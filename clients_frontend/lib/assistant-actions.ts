// Résolution des articles dictés à l'assistant (bulle en bas à droite) dans
// le catalogue public — appelé côté serveur par app/api/assistant/route.ts.
//
// Principe (comme pour l'assistant de l'app de gestion) : le modèle ne fait
// qu'EXTRAIRE ce que le client a dit (voir la route) ; retrouver les produits
// dans le catalogue et vérifier leur disponibilité est déterministe et se
// fait ici. Rien n'est écrit côté serveur : le résultat est un panier
// proposé, ajouté au panier local du navigateur seulement si le client
// confirme (voir components/layout/chat-bubble.tsx).

import { catalogue } from "./endpoints";
import { formatAr, normalize } from "./utils";
import type { Produit, Variante } from "./types";
import type { ArticlePropose, ReponseAssistant } from "./assistant-types";

function mots(s: string): string[] {
  return normalize(s)
    // "7Pro" / "iphone13" → "7 pro" / "iphone 13" : le catalogue et les
    // clients ne sont pas cohérents sur les espaces.
    .replace(/(\d)([a-z])/g, "$1 $2")
    .replace(/([a-z])(\d)/g, "$1 $2")
    .replace(/[^a-z0-9]+/g, " ")
    .trim()
    .split(" ")
    .filter(Boolean);
}

function scoreProduit(recherche: string[], p: Produit): number {
  const meule = mots(`${p.marque.nom} ${p.sous_type.nom} ${p.nom} ${p.categorie.nom}`);
  let score = 0;
  for (const q of recherche) {
    if (meule.includes(q)) score += 2;
    else if (q.length >= 3 && meule.some((m) => m.length >= 3 && (m.startsWith(q) || q.startsWith(m)))) score += 1;
  }
  return score;
}

type Resolution = { ok: true; produit: Produit; variante: Variante } | { ok: false; probleme: string };

/**
 * Retrouve le produit et la variante du catalogue désignés par un libellé
 * libre ("coque iphone 13", couleur "noire"). Refuse de deviner en cas de
 * doute : mieux vaut redemander que proposer le mauvais produit.
 */
export async function resoudreArticle(produitTexte: string, couleurTexte: string, boutiqueId: number | null): Promise<Resolution> {
  const recherche = mots(produitTexte);
  if (!recherche.length) return { ok: false, probleme: "un article sans nom" };

  let page;
  try {
    page = await catalogue.produits({ search: produitTexte, boutique: boutiqueId ?? undefined, page_size: 30 });
  } catch {
    return { ok: false, probleme: `"${produitTexte}" : catalogue injoignable pour le moment` };
  }

  const notes = page.results
    .map((p) => ({ p, score: scoreProduit(recherche, p) }))
    .filter((x) => x.score >= recherche.length) // au moins la moitié des mots
    .sort((a, b) => b.score - a.score);

  if (!notes.length) return { ok: false, probleme: `"${produitTexte}" : introuvable dans le catalogue` };

  const meilleur = notes[0].score;
  let candidats = notes.filter((x) => x.score === meilleur).map((x) => x.p);
  if (candidats.length > 1) {
    // À score égal, le nom le plus court est le plus spécifique
    // ("iPhone 13" plutôt que "iPhone 13 Pro" pour "iphone 13").
    const longueur = (p: Produit) => mots(`${p.marque.nom} ${p.nom}`).length;
    const min = Math.min(...candidats.map(longueur));
    candidats = candidats.filter((p) => longueur(p) === min);
  }
  if (candidats.length > 1) {
    const options = candidats.slice(0, 5).map((p) => p.nom_complet).join(", ");
    return { ok: false, probleme: `"${produitTexte}" : plusieurs produits correspondent (${options}) — précisez` };
  }

  const produit = candidats[0];
  const variantes = produit.variantes.filter((v) => v.disponible);
  if (!variantes.length) return { ok: false, probleme: `"${produit.nom_complet}" : plus aucune couleur en stock` };

  const c = normalize(couleurTexte);
  if (!c) {
    if (variantes.length === 1) return { ok: true, produit, variante: variantes[0] };
    const couleurs = variantes.map((v) => v.couleur).join(", ");
    return { ok: false, probleme: `"${produit.nom_complet}" : précisez la couleur (${couleurs})` };
  }
  const exacte = variantes.find((v) => normalize(v.couleur) === c);
  if (exacte) return { ok: true, produit, variante: exacte };
  const racine = c.slice(0, 4);
  const proches = variantes.filter((v) => {
    const vc = normalize(v.couleur);
    return vc.startsWith(racine) || c.startsWith(vc.slice(0, 4));
  });
  if (proches.length === 1) return { ok: true, produit, variante: proches[0] };
  if (variantes.length === 1) return { ok: true, produit, variante: variantes[0] };
  const couleurs = variantes.map((v) => v.couleur).join(", ");
  return { ok: false, probleme: `"${produit.nom_complet}" : couleur "${couleurTexte}" indisponible (${couleurs})` };
}

/** Ce que le modèle a extrait du message — tout est optionnel et non fiable. */
export interface ArticleExtrait {
  produit?: string;
  couleur?: string;
  quantite?: number;
}

const libelleVariante = (p: Produit, v: Variante) => (v.couleur && v.couleur !== "Standard" ? `${p.nom_complet} (${v.couleur})` : p.nom_complet);

/**
 * Résout une liste d'articles dictés et prépare la proposition d'ajout au
 * panier. `boutiqueActuelleId` est la boutique du panier en cours (`null`
 * s'il est vide) : un panier ne peut contenir que les articles d'une seule
 * boutique, exactement comme la règle appliquée par le panier lui-même
 * (providers/cart-provider.tsx).
 */
export async function preparerAjoutPanier(articlesExtraits: ArticleExtrait[], boutiqueActuelleId: number | null): Promise<ReponseAssistant> {
  const articles = (articlesExtraits || []).filter((a) => (a.produit || "").trim());
  if (!articles.length) {
    return { reponse: "Dites-moi quel(s) article(s) vous voulez, par exemple : « 2 coques iPhone 13 noires »." };
  }

  const manques: string[] = [];
  const resume: string[] = [];
  const resolus: ArticlePropose[] = [];
  let boutiqueId = boutiqueActuelleId;
  let boutiqueNom = "";

  for (const a of articles) {
    const quantite = Math.max(1, Math.floor(Number(a.quantite) || 1));
    const res = await resoudreArticle(a.produit || "", a.couleur || "", boutiqueId);
    if (!res.ok) {
      manques.push(res.probleme);
      continue;
    }
    if (boutiqueId !== null && res.produit.boutique.id !== boutiqueId) {
      manques.push(
        `"${res.produit.nom_complet}" vient d'une autre boutique (${res.produit.boutique.nom}) que le reste de votre panier (${boutiqueNom}) — une commande ne peut venir que d'une seule boutique`,
      );
      continue;
    }
    boutiqueId = res.produit.boutique.id;
    boutiqueNom = res.produit.boutique.nom;
    resolus.push({
      varianteId: res.variante.id,
      produitId: res.produit.id,
      nom: res.produit.nom,
      nomComplet: res.produit.nom_complet,
      couleur: res.variante.couleur,
      prix: res.produit.prix_vente,
      photo: res.produit.photo,
      boutiqueId: res.produit.boutique.id,
      boutiqueNom: res.produit.boutique.nom,
      quantite,
    });
    resume.push(`${quantite} × ${libelleVariante(res.produit, res.variante)} — ${formatAr(res.produit.prix_vente * quantite)}`);
  }

  if (!resolus.length) {
    return { reponse: `Je n'ai trouvé aucun de ces articles dans le catalogue :\n- ${manques.join("\n- ")}` };
  }

  const avertissement = manques.length ? `\n\nJe n'ai en revanche pas pu ajouter :\n- ${manques.join("\n- ")}` : "";

  return {
    reponse: `Voici ce que je peux ajouter à votre panier${boutiqueNom ? ` (${boutiqueNom})` : ""}. Vérifiez puis confirmez.${avertissement}`,
    proposition: { type: "ajouter_panier", resume, articles: resolus },
  };
}
