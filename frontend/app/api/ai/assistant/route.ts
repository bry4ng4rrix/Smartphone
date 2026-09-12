// Assistant de l'application (§ demande) — bulle en bas à droite.
//
// Usages dans une même route :
//  * "guide"    : le message de l'utilisateur. Le modèle détermine d'abord
//                 s'il s'agit d'une question (réponse à partir du GUIDE
//                 ci-dessous) ou d'un ordre de créer une commande (extraction
//                 → proposition à confirmer, voir lib/assistant-actions.ts).
//                 Avec un fichier Excel joint (multipart) : proposition de
//                 mise à jour des stocks, sans passer par le modèle.
//  * "executer" : l'utilisateur a confirmé une proposition ; on l'applique
//                 telle quelle via l'API Django (aucun appel au modèle).
//  * "rapport"  : rédiger un commentaire des chiffres de la page Rapports,
//                 fournis par l'appelant.
//
// Les actions appellent l'API Django avec le token de l'utilisateur
// (en-tête Authorization transmis par la bulle) : ses droits s'appliquent.
//
// Ollama local (voir lib/ollama.ts). Pour changer le ton ou le contenu,
// éditez GUIDE ou les fonctions de prompt ci-dessous, puis relancez le
// conteneur frontend.

import { ollamaGenerate, ollamaJson, ollamaErrorHint } from '@/lib/ollama';
import {
  executerCommande,
  executerStock,
  messageErreur,
  preparerCommande,
  preparerStock,
  type CommandeExtraite,
} from '@/lib/assistant-actions';
import type { Proposition, ReponseAssistant } from '@/lib/assistant-types';

/**
 * Mode d'emploi de l'application, injecté à chaque question.
 *
 * C'est la SEULE source de l'assistant : il lui est demandé de ne rien
 * inventer au-delà. Tenez-le à jour quand une règle métier change — sinon
 * l'assistant donnera des consignes périmées avec aplomb.
 */
const GUIDE = `
RÔLES
- Gérant (admin ou magasin) : accès complet. Crée et modifie les commandes, assigne préparateur et livreur, valide les dépenses, consulte les rapports et les bilans de tous les livreurs.
- Préparateur : voit les commandes qui lui sont assignées. Les prépare et les passe en "Prête".
- Livreur : voit sa tournée. Récupère les colis, puis marque "Livré" ou "Retour".

WORKFLOW D'UNE COMMANDE (6 statuts, sens unique)
Nouvelle -> En préparation -> Prête -> En livraison -> Livré (ou Retour). Annulée possible tant que la commande n'est pas terminée.
- Le stock sort du magasin au passage "En préparation", et y revient en cas de Retour ou d'Annulation.
- "Livré" ne touche plus au stock : il est déjà sorti.
- Une fois Livré ou Retour, seul le gérant peut corriger l'état (bouton "Corriger l'état"), ce qui rétablit le stock.

RÈGLE DU JOUR J
- Préparateur : peut agir 5 heures AVANT le jour de livraison, soit à partir de 19h00 la veille (heure de Madagascar).
- Livreur : ne peut agir qu'à partir de minuit, le jour de livraison. Sa tournée n'affiche les commandes qu'à partir de 19h00 la veille.
- Gérant : aucune contrainte d'horaire.

LIVRAISON PARTIELLE
Au moment de confirmer "Livré" : si la commande a un seul article, on répond Oui ou Non. Si elle en a plusieurs, on coche ceux qui ont été remis. Les articles décochés repartent en stock et sortent du total à payer. Si rien n'est remis, la commande devient un Retour.

PAIEMENT
"Payé" (d'avance) ou "Paiement à la livraison". Une commande payée d'avance affiche 0 Ar dans le bilan du livreur : il n'a rien à encaisser. Le mode de paiement, la zone et l'adresse restent modifiables même pendant la livraison ; changer la zone met à jour les frais et le bilan.

BILAN DU JOUR
- Livreur : ses livraisons et retours du jour, avec un ticket récapitulatif. Les retours ne sont jamais additionnés aux livraisons.
- Gérant : la liste des livreurs avec leurs totaux ; un clic ouvre le détail d'un livreur.

DÉPENSES DES LIVREURS
Le livreur déclare ses frais de tournée (repas, carburant, enveloppes...) depuis son bilan, avec un motif. Le gérant est notifié et accepte ou rejette. Seules les dépenses acceptées sont déduites de l'argent à remettre. Les types de dépense se configurent dans Paramètres > Dépenses.

AUTRES PAGES
- Commandes : la liste des commandes. Bouton "Nouvelle commande" (gérant, préparateur) pour en saisir une : client, téléphone, zone, adresse, mode de paiement, articles ; puis assigner un préparateur et un livreur.
- Produits : catalogue Catégorie > Sous-type > Marque > Référence > Couleur, avec le stock par variante.
- Mouvements : historique de toutes les entrées et sorties de stock.
- Alertes : produits en rupture ou sous le seuil.
- Récupération : commandes à retirer au comptoir (zone "Récupération", sans livreur ni frais).
- Caisse : sessions d'ouverture/fermeture et mouvements d'espèces.
- Tableau de bord : centre de rapports en 8 sections (vue d'ensemble, ventes, finances, dépenses, stock, commandes, livraisons, marketing), filtres de période, impression PDF. La page Rapports n'existe plus : tout est dans le Tableau de bord.
- Discussions : messagerie interne entre collaborateurs. Deux livreurs ne peuvent pas se contacter entre eux.
- Paramètres : profil, sécurité, catégories de dépenses, types de dépense des livreurs, zones de livraison (nom + prix).

L'ASSISTANT (cette bulle) PEUT AUSSI AGIR
- Créer une commande : écrire la demande en une phrase, par exemple "Crée une commande pour Rakoto 034 12 345 67, 2 coques iPhone 13 noires et 1 chargeur 20W, zone 2, lot II B 45 Ivandry, paiement à la livraison". L'assistant retrouve les produits dans le catalogue, affiche un récapitulatif, et ne crée la commande qu'après confirmation. Réservé au gérant et au préparateur (le préparateur uniquement en récupération sur place).
- Mettre à jour les stocks depuis un fichier Excel : joindre le fichier avec le bouton trombone. Colonnes attendues : Référence (ou Produit), Couleur, Stock (ou Quantité), et en option Marque et Sous-type ; le fichier d'export du catalogue convient tel quel. L'assistant affiche les écarts, et n'applique les ajustements qu'après confirmation. Réservé au gérant.
`.trim();

interface Payload {
  mode?: 'guide' | 'rapport' | 'executer';
  question?: string;
  /** Chiffres de la page Rapports, pour le mode "rapport". */
  rapport?: unknown;
  /** Proposition confirmée par l'utilisateur, pour le mode "executer". */
  proposition?: Proposition;
}

interface Intention {
  intention: 'question' | 'creer_commande' | 'autre';
  commande: Required<Omit<CommandeExtraite, 'articles'>> & {
    articles: { produit: string; couleur: string; quantite: number }[];
  };
}

const SCHEMA_INTENTION = {
  type: 'object',
  properties: {
    intention: { type: 'string', enum: ['question', 'creer_commande', 'autre'] },
    commande: {
      type: 'object',
      properties: {
        client_nom: { type: 'string' },
        telephone: { type: 'string' },
        zone: { type: 'string' },
        adresse: { type: 'string' },
        mode_paiement: { type: 'string', enum: ['AVANT', 'LIVRAISON', ''] },
        note: { type: 'string' },
        articles: {
          type: 'array',
          items: {
            type: 'object',
            properties: {
              produit: { type: 'string' },
              couleur: { type: 'string' },
              quantite: { type: 'integer' },
            },
            required: ['produit', 'couleur', 'quantite'],
          },
        },
      },
      required: ['client_nom', 'telephone', 'zone', 'adresse', 'mode_paiement', 'note', 'articles'],
    },
  },
  required: ['intention', 'commande'],
};

function promptIntention(message: string): string {
  return `Tu analyses un message envoyé à l'assistant d'une application de gestion de commandes et de stock (revendeur d'accessoires pour téléphones à Madagascar).

Détermine l'intention :
- "creer_commande" : l'utilisateur ORDONNE de créer une commande et donne des éléments concrets (un client, des articles, une zone...). Exemple : "crée une commande pour Rakoto 034 12 345 67, 2 coques iPhone 13 noires, zone 2".
- "question" : il pose une question ou demande une explication sur le fonctionnement de l'application — y compris "comment créer une commande ?" ou "comment mettre à jour le stock ?".
- "autre" : tout le reste (salutations, hors sujet).

Si l'intention est "creer_commande", remplis "commande" avec ce qui est dit, SANS rien inventer (chaîne vide ou 0 si absent) :
- client_nom : le nom du client.
- telephone : le numéro tel qu'écrit.
- zone : la zone de livraison telle qu'écrite (ex : "zone 2", "Ivandry"), ou "récupération" si le client vient chercher sur place.
- adresse : l'adresse de livraison.
- mode_paiement : "AVANT" si déjà payé / payé d'avance, "LIVRAISON" si paiement à la livraison, "" si rien n'est dit.
- note : consigne éventuelle pour le préparateur ou le livreur.
- articles : un élément par produit. "produit" = le nom du produit tel qu'écrit (marque et modèle), sans la couleur ni la quantité. "couleur" = la couleur si précisée, sinon "". "quantite" = le nombre demandé (1 si non précisé).

Message : """${message}"""`;
}

function promptGuide(question: string): string {
  return `Tu es l'assistant de "Smart kajy", une application de gestion de commandes, stock et livraisons utilisée par un revendeur d'accessoires pour téléphones à Madagascar.

Voici le mode d'emploi complet de l'application :
${GUIDE}

Question de l'utilisateur : ${question}

Réponds UNIQUEMENT à partir du mode d'emploi ci-dessus. Si la réponse ne s'y trouve pas, dis simplement que tu ne sais pas et suggère de demander au gérant — n'invente jamais une règle ou un écran qui n'existe pas.
Réponds en français, en texte brut, sans markdown (pas de gras, pas d'astérisques, pas de titres). Sois bref et concret : explique où cliquer et dans quel ordre.`;
}

function promptRapport(rapport: unknown, question: string): string {
  return `Tu es un conseiller en gestion pour un revendeur d'accessoires pour téléphones à Madagascar.

Voici les chiffres de la période, issus de la page Rapports de l'application :
${JSON.stringify(rapport)}

${question ? `Demande particulière de l'utilisateur : ${question}` : ''}

Rédige un rapport court et utile :
1. La santé financière de la période (chiffre d'affaires, marge, dépenses, résultat).
2. Ce qui se vend et ce qui ne se vend pas.
3. La performance des livreurs et des préparateurs : qui tient le rythme, où sont les retours.
4. Deux ou trois actions concrètes à mener.

Appuie-toi uniquement sur les chiffres fournis, ne les invente pas et ne les arrondis pas à la hausse. Les montants sont en ariary (Ar).
Réponds en français, en texte brut, sans markdown (pas de gras, pas d'astérisques, pas de titres). Paragraphes courts.`;
}

function tokenDepuis(req: Request): string | null {
  const auth = req.headers.get('authorization') || '';
  return auth.startsWith('Bearer ') ? auth.slice(7).trim() || null : null;
}

const CONNEXION_REQUISE: ReponseAssistant = {
  reponse: 'Votre session a expiré : rechargez la page puis réessayez.',
};

/** Message + fichier Excel joint (multipart) : mise à jour des stocks. */
async function traiterFichier(req: Request): Promise<ReponseAssistant> {
  const token = tokenDepuis(req);
  if (!token) return CONNEXION_REQUISE;
  const form = await req.formData();
  const fichier = form.get('file');
  if (!(fichier instanceof File)) return { reponse: 'Aucun fichier reçu.' };
  if (!/\.xlsx?$/i.test(fichier.name)) return { reponse: 'Joignez un fichier Excel (.xlsx).' };
  if (fichier.size > 5 * 1024 * 1024) return { reponse: 'Le fichier dépasse 5 Mo.' };
  try {
    return await preparerStock(await fichier.arrayBuffer(), fichier.name, token);
  } catch (error) {
    console.error('Erreur assistant (fichier stock) :', error);
    return { reponse: messageErreur(error) };
  }
}

/** Proposition confirmée : on l'applique telle quelle, sans le modèle. */
async function executer(req: Request, proposition: Proposition | undefined): Promise<ReponseAssistant> {
  const token = tokenDepuis(req);
  if (!token) return CONNEXION_REQUISE;
  try {
    if (proposition?.type === 'creer_commande' && proposition.payload?.items?.length) {
      return { reponse: await executerCommande(proposition.payload, token) };
    }
    if (proposition?.type === 'maj_stock' && proposition.ajustements?.length) {
      return { reponse: await executerStock(proposition.ajustements, proposition.fichier || 'fichier', token) };
    }
    return { reponse: "Je n'ai rien à exécuter." };
  } catch (error) {
    console.error('Erreur assistant (exécution) :', error);
    return { reponse: messageErreur(error) };
  }
}

// La détection d'intention coûte ~5 s de modèle : on ne la lance que si le
// message peut raisonnablement être un ordre de commande.
const PEUT_ETRE_UN_ORDRE = /cr[eé]{1,2}|commande|ajout|enregistr|nouvel|client|livr/i;

/** Message texte : question sur le guide, ou ordre de créer une commande. */
async function traiterMessage(req: Request, question: string): Promise<ReponseAssistant> {
  const analyse = PEUT_ETRE_UN_ORDRE.test(question)
    ? await ollamaJson<Intention>('fast', promptIntention(question), SCHEMA_INTENTION)
    : null;

  if (analyse?.intention === 'creer_commande') {
    const token = tokenDepuis(req);
    if (!token) return CONNEXION_REQUISE;
    try {
      return await preparerCommande(analyse.commande, token);
    } catch (error) {
      console.error('Erreur assistant (préparation commande) :', error);
      return { reponse: messageErreur(error) };
    }
  }

  return { reponse: await ollamaGenerate('fast', promptGuide(question)) };
}

export async function POST(req: Request) {
  try {
    if ((req.headers.get('content-type') || '').includes('multipart/form-data')) {
      return Response.json(await traiterFichier(req));
    }

    const data: Payload = await req.json();
    const question = (data.question || '').trim();

    if (data.mode === 'executer') {
      return Response.json(await executer(req, data.proposition));
    }
    if (data.mode === 'rapport') {
      return Response.json({ reponse: await ollamaGenerate('analyse', promptRapport(data.rapport, question)) });
    }
    if (!question) {
      return Response.json({ reponse: 'Posez-moi une question sur l’application.' });
    }
    return Response.json(await traiterMessage(req, question));
  } catch (error: unknown) {
    console.error('Erreur assistant (Ollama) :', error);
    return Response.json({ reponse: `Désolé, je n'ai pas pu répondre. ${ollamaErrorHint(error)}` }, { status: 500 });
  }
}
