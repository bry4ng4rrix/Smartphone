// Actions que l'assistant peut exécuter pour l'utilisateur (côté serveur,
// appelé par app/api/ai/assistant/route.ts) :
//
//  * créer une commande à partir d'une demande en langage naturel ;
//  * mettre à jour les stocks à partir d'un fichier Excel.
//
// Principe : le modèle ne fait qu'EXTRAIRE ce que l'utilisateur a dit
// (voir la route). Tout le reste — retrouver les produits dans le catalogue,
// la zone, le téléphone, calculer les écarts de stock, appeler l'API Django
// — est déterministe et se fait ici, puis l'utilisateur confirme avant
// que quoi que ce soit ne soit écrit. L'API Django est appelée avec le
// token de l'utilisateur : ses droits (gérant / préparateur) s'appliquent
// exactement comme depuis les écrans habituels.

import * as XLSX from 'xlsx';
import type { AjustementStock, CommandePayload, ReponseAssistant } from './assistant-types';

const API_BASE_URL = process.env.NEXT_PUBLIC_DJANGO_API_URL || 'http://127.0.0.1:8010/api';

export class ApiError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

function messageErreurApi(body: string): string {
  try {
    const data = JSON.parse(body);
    if (typeof data === 'string') return data;
    if (Array.isArray(data)) return data.map(String).join(' ');
    if (data && typeof data === 'object') {
      if (typeof data.detail === 'string') return data.detail;
      return Object.entries(data)
        .map(([k, v]) => `${k} : ${Array.isArray(v) ? v.join(' ') : String(v)}`)
        .join(' ; ');
    }
  } catch {
    /* corps non JSON */
  }
  return body.slice(0, 200);
}

async function api<T>(token: string, path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(`${API_BASE_URL}${path}`, {
    ...init,
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}`, ...(init?.headers || {}) },
    signal: AbortSignal.timeout(30_000),
  });
  if (!res.ok) {
    const body = await res.text().catch(() => '');
    throw new ApiError(res.status, messageErreurApi(body) || `HTTP ${res.status}`);
  }
  return res.json();
}

export function messageErreur(error: unknown): string {
  if (error instanceof ApiError) {
    if (error.status === 401) return 'Votre session a expiré : rechargez la page puis réessayez.';
    if (error.status === 403) return `Vous n'avez pas le droit de faire cela (${error.message}).`;
    return `L'application a refusé l'opération : ${error.message}`;
  }
  return "Je n'ai pas pu joindre l'application. Réessayez dans un instant.";
}

// ---------------------------------------------------------------------------
// Normalisation
// ---------------------------------------------------------------------------

export function normaliser(s: string): string {
  return (
    s
      .normalize('NFD')
      .replace(/[̀-ͯ]/g, '')
      .toLowerCase()
      // "7Pro" / "iphone13" → "7 pro" / "iphone 13" : le catalogue et les
      // utilisateurs ne sont pas cohérents sur les espaces.
      .replace(/(\d)([a-z])/g, '$1 $2')
      .replace(/([a-z])(\d)/g, '$1 $2')
      .replace(/[^a-z0-9]+/g, ' ')
      .trim()
  );
}

const mots = (s: string) => normaliser(s).split(' ').filter(Boolean);

export function normaliserTelephone(brut: string): string | null {
  const d = brut.replace(/\D/g, '');
  if (d.length === 12 && d.startsWith('261')) return `+${d}`;
  if (d.length === 10 && d.startsWith('0')) return `+261${d.slice(1)}`;
  if (d.length === 9) return `+261${d}`;
  return null;
}

// ---------------------------------------------------------------------------
// Catalogue
// ---------------------------------------------------------------------------

interface Variante {
  id: number;
  couleur: string;
  stock_actuel: number;
}

interface Reference {
  id: number;
  type_name: string;
  brand_name: string;
  reference_name: string;
  actif: boolean;
  variants: Variante[];
}

interface Zone {
  code: string;
  nom: string;
  prix: string;
  actif: boolean;
}

const libelleRef = (r: Reference) => `${r.type_name} ${r.brand_name} ${r.reference_name}`.trim();
const libelleVariante = (r: Reference, v: Variante) =>
  v.couleur && v.couleur !== 'Standard' ? `${libelleRef(r)} (${v.couleur})` : libelleRef(r);

function scoreReference(recherche: string[], ref: Reference): number {
  const meule = mots(`${ref.type_name} ${ref.brand_name} ${ref.reference_name}`);
  let score = 0;
  for (const q of recherche) {
    if (meule.includes(q)) score += 2;
    else if (q.length >= 3 && meule.some((m) => m.length >= 3 && (m.startsWith(q) || q.startsWith(m)))) score += 1;
  }
  return score;
}

type Resolution =
  | { ok: true; reference: Reference; variante: Variante }
  | { ok: false; probleme: string };

/**
 * Retrouve la variante du catalogue désignée par un libellé libre
 * ("coque iphone 13", couleur "noire"). Refuse de deviner en cas de doute :
 * mieux vaut redemander que créer une commande sur le mauvais produit.
 */
export function resoudreArticle(produit: string, couleur: string, references: Reference[]): Resolution {
  const recherche = mots(produit);
  if (!recherche.length) return { ok: false, probleme: 'un article sans nom' };

  const notes = references
    .filter((r) => r.actif && r.variants.length)
    .map((r) => ({ r, score: scoreReference(recherche, r) }))
    .filter((x) => x.score >= recherche.length) // au moins la moitié des mots
    .sort((a, b) => b.score - a.score);

  if (!notes.length) return { ok: false, probleme: `"${produit}" : introuvable dans le catalogue` };

  const meilleur = notes[0].score;
  let candidats = notes.filter((x) => x.score === meilleur).map((x) => x.r);
  if (candidats.length > 1) {
    // À score égal, la référence la plus courte est la plus spécifique
    // ("iPhone 13" plutôt que "iPhone 13 Pro" pour "iphone 13").
    const longueur = (r: Reference) => mots(`${r.brand_name} ${r.reference_name}`).length;
    const min = Math.min(...candidats.map(longueur));
    candidats = candidats.filter((r) => longueur(r) === min);
  }
  if (candidats.length > 1) {
    const options = candidats.slice(0, 5).map(libelleRef).join(', ');
    return { ok: false, probleme: `"${produit}" : plusieurs produits correspondent (${options}) — précisez` };
  }

  const reference = candidats[0];
  const variantes = reference.variants;
  const c = normaliser(couleur);
  if (!c) {
    if (variantes.length === 1) return { ok: true, reference, variante: variantes[0] };
    const couleurs = variantes.map((v) => v.couleur).join(', ');
    return { ok: false, probleme: `"${libelleRef(reference)}" : précisez la couleur (${couleurs})` };
  }
  const exacte = variantes.find((v) => normaliser(v.couleur) === c);
  if (exacte) return { ok: true, reference, variante: exacte };
  const racine = c.slice(0, 4);
  const proches = variantes.filter((v) => {
    const vc = normaliser(v.couleur);
    return vc.startsWith(racine) || c.startsWith(vc.slice(0, 4));
  });
  if (proches.length === 1) return { ok: true, reference, variante: proches[0] };
  if (variantes.length === 1) return { ok: true, reference, variante: variantes[0] };
  const couleurs = variantes.map((v) => v.couleur).join(', ');
  return { ok: false, probleme: `"${libelleRef(reference)}" : couleur "${couleur}" inconnue (${couleurs})` };
}

export function resoudreZone(texte: string, zones: Zone[]): { code: string; libelle: string } | null {
  const n = normaliser(texte);
  if (!n) return null;
  if (/recup|sur place|comptoir|retrait|magasin|boutique/.test(n)) {
    return { code: 'RECUPERATION', libelle: 'Récupération sur place' };
  }
  const actives = zones.filter((z) => z.actif);
  const libelle = (z: Zone) => `${z.nom} (${Number(z.prix).toLocaleString('fr-FR')} Ar)`;

  const exacte = actives.find((z) => normaliser(z.nom) === n || normaliser(z.code) === n);
  if (exacte) return { code: exacte.code, libelle: libelle(exacte) };

  const numero = n.match(/\d+/)?.[0];
  if (numero) {
    const parNumero = actives.filter((z) => normaliser(z.nom).match(/\d+/)?.[0] === numero);
    if (parNumero.length === 1) return { code: parNumero[0].code, libelle: libelle(parNumero[0]) };
  }
  const partielles = actives.filter((z) => normaliser(z.nom).includes(n) || n.includes(normaliser(z.nom)));
  if (partielles.length === 1) return { code: partielles[0].code, libelle: libelle(partielles[0]) };
  return null;
}

// ---------------------------------------------------------------------------
// Créer une commande
// ---------------------------------------------------------------------------

/** Ce que le modèle a extrait du message — tout est optionnel et non fiable. */
export interface CommandeExtraite {
  client_nom?: string;
  telephone?: string;
  zone?: string;
  adresse?: string;
  mode_paiement?: string;
  note?: string;
  articles?: { produit?: string; couleur?: string; quantite?: number }[];
}

export async function preparerCommande(extrait: CommandeExtraite, token: string): Promise<ReponseAssistant> {
  const [zones, references] = await Promise.all([
    api<Zone[]>(token, '/orders/delivery-zones/'),
    api<Reference[]>(token, '/catalog/references/'),
  ]);

  const manques: string[] = [];
  const resume: string[] = [];
  const items: CommandePayload['items'] = [];

  const client_nom = (extrait.client_nom || '').trim();
  if (!client_nom) manques.push('le nom du client');

  const telephone = normaliserTelephone(extrait.telephone || '');
  if (!telephone) manques.push('un numéro de téléphone valide (ex : 034 12 345 67)');

  const zone = resoudreZone(extrait.zone || '', zones);
  if (!zone) {
    const noms = zones.filter((z) => z.actif).map((z) => z.nom).join(', ');
    manques.push(`la zone de livraison (${noms}) ou "récupération sur place"`);
  }

  const articles = (extrait.articles || []).filter((a) => (a.produit || '').trim());
  if (!articles.length) manques.push('au moins un article');
  for (const a of articles) {
    const quantite = Math.max(1, Math.floor(Number(a.quantite) || 1));
    const res = resoudreArticle(a.produit || '', a.couleur || '', references);
    if (!res.ok) {
      manques.push(res.probleme);
      continue;
    }
    items.push({ product_variant: res.variante.id, quantite });
    const stock = res.variante.stock_actuel;
    resume.push(
      `${quantite} × ${libelleVariante(res.reference, res.variante)}` +
        (stock < quantite ? ` — attention, stock ${stock}` : ''),
    );
  }

  if (manques.length) {
    return {
      reponse:
        `Pour créer cette commande, il me manque :\n- ${manques.join('\n- ')}\n\n` +
        'Renvoyez-moi la demande complète avec ces précisions.',
    };
  }

  const mode_paiement: CommandePayload['mode_paiement'] = extrait.mode_paiement === 'AVANT' ? 'AVANT' : 'LIVRAISON';
  const adresse_livraison = zone!.code === 'RECUPERATION' ? '' : (extrait.adresse || '').trim().slice(0, 255);
  const note_preparateur = (extrait.note || '').trim();

  const payload: CommandePayload = {
    client_nom: client_nom.slice(0, 255),
    telephone: telephone!,
    livraison_zone: zone!.code,
    adresse_livraison,
    mode_paiement,
    note_preparateur,
    items,
  };

  const lignes = [
    `Client : ${payload.client_nom} — ${payload.telephone}`,
    `Livraison : ${zone!.libelle}${adresse_livraison ? ` — ${adresse_livraison}` : ''}`,
    `Paiement : ${mode_paiement === 'AVANT' ? "payé d'avance" : 'à la livraison'}`,
    ...resume.map((l) => `• ${l}`),
    ...(note_preparateur ? [`Note : ${note_preparateur}`] : []),
  ];

  return {
    reponse: 'Voici la commande que je vais créer. Vérifiez puis confirmez.',
    proposition: { type: 'creer_commande', resume: lignes, payload },
  };
}

export async function executerCommande(payload: CommandePayload, token: string): Promise<string> {
  const order = await api<{ numero?: string; id: number; total_a_payer?: string; frais_livraison?: string }>(
    token,
    '/orders/',
    { method: 'POST', body: JSON.stringify(payload) },
  );
  const total = order.total_a_payer ? ` Total à payer : ${Number(order.total_a_payer).toLocaleString('fr-FR')} Ar.` : '';
  return `Commande ${order.numero || `#${order.id}`} créée pour ${payload.client_nom}.${total} Vous pouvez l'ouvrir dans la page Commandes pour assigner un préparateur et un livreur.`;
}

// ---------------------------------------------------------------------------
// Mettre à jour les stocks depuis un fichier Excel
// ---------------------------------------------------------------------------

function trouverColonne(entetes: string[], motifs: RegExp[]): number {
  for (const motif of motifs) {
    const i = entetes.findIndex((e) => motif.test(e));
    if (i !== -1) return i;
  }
  return -1;
}

const MAX_LIGNES_RESUME = 15;

/**
 * Lit un fichier Excel et prépare les ajustements de stock à appliquer.
 * Colonnes reconnues (peu importe l'ordre, en-têtes en 1re ligne) :
 * Référence (ou Produit/Article), Couleur, Stock (ou Quantité) — et en
 * option Marque, Sous-type pour lever les ambiguïtés. Le fichier d'export
 * du catalogue ("Catégorie | Sous-type | Marque | Référence | Couleur | …
 * Stock actuel …") est accepté tel quel.
 */
export async function preparerStock(contenu: ArrayBuffer, nomFichier: string, token: string): Promise<ReponseAssistant> {
  const classeur = XLSX.read(new Uint8Array(contenu), { type: 'array' });
  const feuille = classeur.Sheets[classeur.SheetNames[0]];
  if (!feuille) return { reponse: 'Le fichier ne contient aucune feuille.' };
  const lignes = XLSX.utils.sheet_to_json<unknown[]>(feuille, { header: 1, defval: '' });

  const iEntete = lignes.findIndex((l) => l.filter((c) => String(c).trim()).length >= 2);
  if (iEntete === -1) return { reponse: 'Le fichier est vide.' };
  const entetes = lignes[iEntete].map((c) => normaliser(String(c)));

  const colRef = trouverColonne(entetes, [/^reference/, /reference/, /produit|article|modele|designation|^nom/]);
  const colStock = trouverColonne(entetes, [/nouveau stock|stock actuel|^stock$|^stock /, /quantit|^qte|^qty/]);
  const colCouleur = trouverColonne(entetes, [/couleur|color/]);
  const colMarque = trouverColonne(entetes, [/^marque/]);
  const colType = trouverColonne(entetes, [/sous type/, /^type/]);
  if (colRef === -1 || colStock === -1) {
    return {
      reponse:
        `Je n'ai pas reconnu les colonnes du fichier (trouvées : ${entetes.filter(Boolean).join(', ')}). ` +
        'Il me faut au moins une colonne "Référence" (ou "Produit") et une colonne "Stock" (ou "Quantité"), avec en option "Couleur", "Marque" et "Sous-type".',
    };
  }

  const references = await api<Reference[]>(token, '/catalog/references/');
  const ajustements: AjustementStock[] = [];
  const problemes: string[] = [];
  let inchanges = 0;
  const vus = new Set<number>();

  for (let i = iEntete + 1; i < lignes.length; i++) {
    const l = lignes[i];
    const cell = (j: number) => (j === -1 ? '' : String(l[j] ?? '').trim());
    const ref = cell(colRef);
    if (!ref) continue;
    const numLigne = i + 1;
    const stockBrut = cell(colStock);
    const nouveau = Number(stockBrut.replace(/\s/g, '').replace(',', '.'));
    if (stockBrut === '' || !Number.isFinite(nouveau) || nouveau < 0 || !Number.isInteger(nouveau)) {
      problemes.push(`ligne ${numLigne} (${ref}) : stock "${stockBrut}" invalide`);
      continue;
    }
    const libelle = [cell(colType), cell(colMarque), ref].filter(Boolean).join(' ');
    const res = resoudreArticle(libelle, cell(colCouleur), references);
    if (!res.ok) {
      problemes.push(`ligne ${numLigne} : ${res.probleme}`);
      continue;
    }
    if (vus.has(res.variante.id)) {
      problemes.push(`ligne ${numLigne} : ${libelleVariante(res.reference, res.variante)} apparaît plusieurs fois, seule la première ligne compte`);
      continue;
    }
    vus.add(res.variante.id);
    if (res.variante.stock_actuel === nouveau) {
      inchanges++;
      continue;
    }
    ajustements.push({
      variant_id: res.variante.id,
      libelle: libelleVariante(res.reference, res.variante),
      stock_actuel: res.variante.stock_actuel,
      nouveau,
    });
  }

  const bilanProblemes = problemes.length
    ? `\n\n${problemes.length} ligne(s) ignorée(s) :\n- ${problemes.slice(0, MAX_LIGNES_RESUME).join('\n- ')}` +
      (problemes.length > MAX_LIGNES_RESUME ? `\n- … et ${problemes.length - MAX_LIGNES_RESUME} autres` : '')
    : '';

  if (!ajustements.length) {
    return {
      reponse:
        (inchanges ? `Les ${inchanges} produit(s) du fichier sont déjà au bon stock, rien à changer.` : 'Aucun produit du fichier n’a pu être traité.') +
        bilanProblemes,
    };
  }

  const resume = ajustements
    .slice(0, MAX_LIGNES_RESUME)
    .map((a) => `${a.libelle} : ${a.stock_actuel} → ${a.nouveau} (${a.nouveau > a.stock_actuel ? '+' : ''}${a.nouveau - a.stock_actuel})`);
  if (ajustements.length > MAX_LIGNES_RESUME) resume.push(`… et ${ajustements.length - MAX_LIGNES_RESUME} autres produits`);
  if (inchanges) resume.push(`${inchanges} produit(s) déjà à jour, non modifiés`);

  return {
    reponse:
      `Fichier "${nomFichier}" : ${ajustements.length} stock(s) à mettre à jour. Chaque changement sera enregistré comme un mouvement d'ajustement. Vérifiez puis confirmez.` +
      bilanProblemes,
    proposition: { type: 'maj_stock', resume, fichier: nomFichier, ajustements },
  };
}

export async function executerStock(ajustements: AjustementStock[], fichier: string, token: string): Promise<string> {
  const echecs: string[] = [];
  let faits = 0;
  for (const a of ajustements) {
    const diff = a.nouveau - a.stock_actuel;
    if (!diff) continue;
    try {
      await api(token, `/catalog/variants/${a.variant_id}/adjust/`, {
        method: 'POST',
        body: JSON.stringify({
          type: diff > 0 ? 'ENTREE' : 'SORTIE',
          quantite: Math.abs(diff),
          note: `Assistant IA — ${fichier}`.slice(0, 255),
        }),
      });
      faits++;
    } catch (e) {
      echecs.push(`${a.libelle} : ${e instanceof ApiError ? e.message : 'erreur réseau'}`);
    }
  }
  let texte = `${faits} stock(s) mis à jour à partir de "${fichier}". Le détail est visible dans la page Mouvements.`;
  if (echecs.length) texte += `\n\n${echecs.length} échec(s) :\n- ${echecs.join('\n- ')}`;
  return texte;
}
