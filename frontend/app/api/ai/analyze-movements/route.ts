import { google } from "@ai-sdk/google";
import { generateText } from "ai";

export async function POST(req: Request) {
  try {
    const { fastest, slowest, expiring } = await req.json();
    

    const { text } = await generateText({
      model: google("gemini-1.5-flash"),
      prompt: `Tu es un expert en gestion de stock et logistique.
Voici les données récentes de l'inventaire :
- Produits les plus vendus (avec quantité de sorties) : ${JSON.stringify(fastest)}
- Produits sans mouvement (stock mort) : ${JSON.stringify(slowest)}
- Produits bientôt périmés (ou déjà périmés) : ${JSON.stringify(expiring)}

Analyse ces données et donne-moi :
1. Une brève observation sur les produits qui se vendent le mieux.
2. Une observation sur les produits qui ne bougent pas.
3. Une analyse sur les produits proches de la date de péremption (urgences, pertes potentielles).
4. Des conseils actionnables pour optimiser le cash-flow (par ex. promotions sur le stock mort ou presque périmé, réapprovisionnement des best-sellers).

Formate la réponse en texte brut avec des sauts de ligne, sans utiliser la syntaxe markdown (pas de gras, pas d'italique, pas d'astérisques). Fais des paragraphes clairs. Sois concis et professionnel.`,
    });

    return Response.json({ analysis: text });
  } catch (error) {
    console.error("Erreur lors de l'analyse IA :", error);
    return Response.json({ analysis: "Erreur lors de la génération de l'analyse. Veuillez vérifier vos clés API et réessayer." }, { status: 500 });
  }
}
