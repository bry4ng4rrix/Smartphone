// Assistant du site client (§ demande) — bulle en bas à droite.
//
// Une seule route pour deux usages :
//  * question sur le fonctionnement du site → réponse à partir du GUIDE
//    ci-dessous (voir app/api/assistant/route.ts § promptGuide) ;
//  * article(s) dicté(s) ("2 coques iPhone 13 noires") → extraction par le
//    modèle, puis résolution déterministe dans le catalogue public
//    (lib/assistant-actions.ts) → proposition d'ajout au panier, à confirmer
//    par le client. Rien n'est écrit côté serveur : le panier est local au
//    navigateur (providers/cart-provider.tsx), la bulle l'alimente elle-même
//    une fois la proposition confirmée.
//
// Catalogue public : aucune authentification nécessaire, un visiteur non
// connecté peut donc aussi bien poser une question que préparer un panier.
//
// Ollama local (voir lib/ollama.ts) : rien ne part vers un service tiers.

import { ollamaGenerate, ollamaJson, ollamaErrorHint } from "@/lib/ollama";
import { preparerAjoutPanier, type ArticleExtrait } from "@/lib/assistant-actions";
import type { ReponseAssistant } from "@/lib/assistant-types";

/**
 * Mode d'emploi du site, injecté à chaque question.
 *
 * C'est la SEULE source de l'assistant : il lui est demandé de ne rien
 * inventer au-delà. Tenez-le à jour quand une règle change côté site ou API
 * — sinon l'assistant donnera des consignes périmées avec aplomb.
 */
const GUIDE = `
CATALOGUE
- Le bouton "Catalogue" (ou une catégorie du menu) liste les produits d'une boutique : housses, cache-écrans, chargeurs, etc. On peut filtrer par catégorie, marque, couleur, prix, et faire une recherche par mot-clé.
- Les catégories "Housse" et "Cache-écran" demandent d'abord la marque puis le modèle du téléphone : le site ne montre alors que les produits compatibles avec ce téléphone.
- Une fiche produit affiche le prix, les couleurs disponibles (grisées si épuisées) et un bouton "Ajouter au panier". Le cœur sur une fiche l'ajoute aux favoris.

PAS DE COMPTE
- Le site ne demande NI inscription NI connexion. Il n'y a pas de profil, pas de mot de passe, pas d'historique de commandes en ligne.
- Si on vous demande où vous connecter : il n'y a rien à connecter, on commande directement.

PANIER
- Le panier est local à cet appareil. Il ne peut contenir que des articles d'UNE seule boutique à la fois.
- Depuis le panier : changer la quantité, retirer un article, le vider, puis "Passer commande".

PASSER COMMANDE — QUATRE ÉTAPES
1. Vos coordonnées : nom, téléphone (format +261XXXXXXXXX), et un second numéro facultatif. C'est sur ce numéro que la boutique rappelle.
2. Livraison : "Livraison" à 3000 Ar avec l'adresse, ou "Retrait sur place" gratuit sans adresse. Une précision facultative peut être ajoutée.
3. Vérification : tout est réaffiché et tout reste modifiable — quantités, nom, numéros, adresse, total.
4. Confirmation : cocher l'attestation, puis confirmer dans la fenêtre qui s'ouvre.
- Après envoi, un numéro de commande s'affiche : c'est la référence à conserver, elle est imprimable.
- Paiement : rien en ligne. On règle à la livraison ou au retrait.

APRÈS LA COMMANDE
- La boutique APPELLE au numéro indiqué pour confirmer, puis lance la préparation.
- Il n'y a pas de page de suivi en ligne et la commande n'est plus modifiable depuis le site : toute correction se fait lors de cet appel, ou en contactant la boutique.

COMMANDE SPÉCIALE (housse ou cache-écran indisponible)
- Si aucun produit compatible n'est en stock pour le téléphone choisi, le site propose une commande spéciale : un formulaire (téléphone, produit souhaité, quantité, contact) envoyé à la boutique, avec un acompte indicatif de 50 % et un délai indicatif de 15 jours. La boutique confirme ensuite le prix et le délai exacts.

L'ASSISTANT (cette bulle) PEUT AUSSI PRÉPARER LE PANIER
- Dites ce que vous voulez en une phrase, par exemple "je veux 2 coques iPhone 13 noires et un chargeur 20W" : l'assistant retrouve les articles dans le catalogue et vous montre un récapitulatif avant de les ajouter au panier. Rien n'est ajouté sans votre confirmation.
`.trim();

interface Payload {
  question?: string;
  /** Boutique du panier en cours (null si vide) — évite de mélanger deux boutiques. */
  boutiqueId?: number | null;
}

interface Intention {
  intention: "ajouter_panier" | "question" | "autre";
  articles: { produit: string; couleur: string; quantite: number }[];
}

const SCHEMA_INTENTION = {
  type: "object",
  properties: {
    intention: { type: "string", enum: ["ajouter_panier", "question", "autre"] },
    articles: {
      type: "array",
      items: {
        type: "object",
        properties: {
          produit: { type: "string" },
          couleur: { type: "string" },
          quantite: { type: "integer" },
        },
        required: ["produit", "couleur", "quantite"],
      },
    },
  },
  required: ["intention", "articles"],
};

function promptIntention(message: string): string {
  return `Tu analyses un message envoyé à l'assistant du site "Smartphone.Mg", une boutique en ligne d'accessoires pour téléphones à Madagascar.

Détermine l'intention :
- "ajouter_panier" : le client demande un ou plusieurs articles à ajouter au panier ou à commander. Exemple : "je veux 2 coques iPhone 13 noires", "ajoute un chargeur 20W".
- "question" : il pose une question sur le fonctionnement du site (catalogue, panier, commande, livraison, paiement, commande spéciale...).
- "autre" : tout le reste (salutations, hors sujet).

Si l'intention est "ajouter_panier", remplis "articles" avec ce qui est dit, SANS rien inventer (chaîne vide ou 0 si absent) :
- produit : le nom du produit tel qu'écrit (marque et modèle), sans la couleur ni la quantité.
- couleur : la couleur si précisée, sinon "".
- quantite : le nombre demandé (1 si non précisé).

Message : """${message}"""`;
}

function promptGuide(question: string): string {
  return `Tu es l'assistant du site "Smartphone.Mg", une boutique en ligne d'accessoires pour téléphones à Madagascar (housses, cache-écrans, chargeurs...).

Voici le mode d'emploi complet du site :
${GUIDE}

Question du client : ${question}

Réponds UNIQUEMENT à partir du mode d'emploi ci-dessus. Si la réponse ne s'y trouve pas, dis simplement que tu ne sais pas et suggère de contacter la boutique — n'invente jamais une règle ou un écran qui n'existe pas.
Réponds en français, en texte brut, sans markdown (pas de gras, pas d'astérisques, pas de titres). Sois bref, concret et chaleureux : explique où cliquer et dans quel ordre.`;
}

// La détection d'intention coûte quelques secondes de modèle : on ne la
// lance que si le message peut raisonnablement être une demande d'article.
const PEUT_ETRE_UNE_DEMANDE = /veux|voudrais|command|ajout|achet|prend|mets|panier/i;

async function traiterMessage(question: string, boutiqueId: number | null): Promise<ReponseAssistant> {
  const analyse = PEUT_ETRE_UNE_DEMANDE.test(question) ? await ollamaJson<Intention>(promptIntention(question), SCHEMA_INTENTION) : null;

  if (analyse?.intention === "ajouter_panier") {
    try {
      return await preparerAjoutPanier(analyse.articles as ArticleExtrait[], boutiqueId);
    } catch (error) {
      console.error("Erreur assistant (préparation panier) :", error);
      return { reponse: "Je n'ai pas pu vérifier le catalogue pour le moment. Réessayez dans un instant." };
    }
  }

  return { reponse: await ollamaGenerate(promptGuide(question)) };
}

export async function POST(req: Request) {
  try {
    const data: Payload = await req.json();
    const question = (data.question || "").trim();
    if (!question) {
      return Response.json({ reponse: "Posez-moi une question, ou dites-moi ce que vous voulez commander." });
    }
    return Response.json(await traiterMessage(question, data.boutiqueId ?? null));
  } catch (error: unknown) {
    console.error("Erreur assistant (Ollama) :", error);
    return Response.json({ reponse: `Désolé, je n'ai pas pu répondre. ${ollamaErrorHint(error)}` }, { status: 500 });
  }
}
