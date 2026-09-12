// Analyse IA stratégique — appelle un modèle Ollama local (pas d'API cloud,
// pas de clé à gérer) installé sur le VPS. Voir roadmap.md § Analyse IA
// pour l'installation d'Ollama et les variables d'environnement.
//
// Pour changer le PROMPT (ton, contenu, longueur...) : éditez PROMPT_TEMPLATE
// ci-dessous. Sur le VPS, le plus simple est de demander directement à
// Claude Code, par ex. :
//   "dans frontend/app/api/ai/analyze/route.ts, modifie PROMPT_TEMPLATE
//    pour qu'il insiste davantage sur les ruptures de stock"
// puis de relancer le conteneur frontend (`docker compose -f
// docker-compose.prod.yml up -d --build frontend`) pour que le changement
// soit pris en compte.

import { ollamaGenerate, ollamaErrorHint } from '@/lib/ollama';

interface AnalyzePayload {
  periode?: string;
  ca?: number;
  beneficeNet?: number;
  valeurStock?: number;
  beneficeEstimeStock?: number;
  ventesImpayeesCount?: number;
  topProduits?: { name: string; qty: number; revenue?: number; profit?: number }[];
  produitsSansMouvement?: { name: string }[];
  rupturesStock?: { name: string; stock?: number }[];
  stockBas?: { name: string; stock?: number; seuil?: number }[];
  repartitionMouvements?: Record<string, number>;
  topVendeurs?: { name: string; revenue: number }[];
  topMagasins?: { name: string; revenue: number }[];
}

// Modifiable librement — voir le commentaire en haut du fichier.
function buildPrompt(data: AnalyzePayload): string {
  return `Tu es un expert en gestion de commerce et logistique, conseiller d'un revendeur d'accessoires pour téléphones à Madagascar.

Voici les données de l'entreprise${data.periode ? ` (période : ${data.periode})` : ''} :

Chiffres clés :
- Chiffre d'affaires (CA) : ${data.ca ?? 'non disponible'} Ar
- Bénéfice net : ${data.beneficeNet ?? 'non disponible'} Ar
- Valeur du stock actuel : ${data.valeurStock ?? 'non disponible'} Ar
- Bénéfice potentiel si tout le stock actuel est vendu : ${data.beneficeEstimeStock ?? 'non disponible'} Ar
- Ventes impayées en cours : ${data.ventesImpayeesCount ?? 0}

Produits les plus vendus (quantité, CA, bénéfice) : ${JSON.stringify(data.topProduits ?? [])}
Produits sans aucune vente récente (stock mort) : ${JSON.stringify(data.produitsSansMouvement ?? [])}
Produits en rupture de stock : ${JSON.stringify(data.rupturesStock ?? [])}
Produits à stock bas (sous le seuil d'alerte) : ${JSON.stringify(data.stockBas ?? [])}
Répartition des mouvements de stock (entrées/sorties/transferts) : ${JSON.stringify(data.repartitionMouvements ?? {})}
Meilleurs vendeurs : ${JSON.stringify(data.topVendeurs ?? [])}
Meilleurs magasins : ${JSON.stringify(data.topMagasins ?? [])}

Analyse ces données et donne-moi :
1. Un résumé de la santé financière (CA, bénéfice, marge).
2. Une observation sur les produits qui se vendent le mieux, et ceux qui ne bougent pas.
3. Une alerte sur les ruptures de stock et stocks bas — quoi réapprovisionner en priorité.
4. Des conseils actionnables concrets pour améliorer les ventes et le cash-flow.

Réponds en français, en texte brut avec des sauts de ligne, sans markdown (pas de gras, pas d'astérisques, pas de titres avec #). Fais des paragraphes courts et clairs. Sois concis et professionnel.`;
}

export async function POST(req: Request) {
  try {
    const data: AnalyzePayload = await req.json();
    const analysis = await ollamaGenerate('analyse', buildPrompt(data));

    return Response.json({ analysis });
  } catch (error: unknown) {
    console.error("Erreur lors de l'analyse IA (Ollama) :", error);
    return Response.json({ analysis: `Erreur lors de la génération de l'analyse. ${ollamaErrorHint(error)}` }, { status: 500 });
  }
}
