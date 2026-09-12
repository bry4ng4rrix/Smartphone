// Assistant de l'application (§ demande) — bulle en bas à droite.
//
// Deux usages dans une même route :
//  * "guide"   : répondre aux questions sur le fonctionnement de l'app, à
//                partir du GUIDE ci-dessous (aucune donnée métier envoyée) ;
//  * "rapport" : rédiger un commentaire des chiffres de la page Rapports,
//                fournis par l'appelant.
//
// Même modèle Ollama local que app/api/ai/analyze/route.ts : pas d'API cloud,
// pas de clé. Pour changer le ton ou le contenu, éditez GUIDE ou les deux
// fonctions de prompt ci-dessous, puis relancez le conteneur frontend.

const OLLAMA_BASE_URL = process.env.OLLAMA_BASE_URL || 'http://localhost:11434';
const OLLAMA_MODEL = process.env.OLLAMA_MODEL || 'qwen3:4b';

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
- Produits : catalogue Catégorie > Sous-type > Marque > Référence > Couleur, avec le stock par variante.
- Mouvements : historique de toutes les entrées et sorties de stock.
- Alertes : produits en rupture ou sous le seuil.
- Récupération : commandes à retirer au comptoir (zone "Récupération", sans livreur ni frais).
- Caisse : sessions d'ouverture/fermeture et mouvements d'espèces.
- Rapports : chiffre d'affaires, dépenses, résultat, produits les plus et moins vendus, performance des livreurs et des préparateurs.
- Discussions : messagerie interne entre collaborateurs. Deux livreurs ne peuvent pas se contacter entre eux.
- Paramètres : profil, sécurité, catégories de dépenses, types de dépense des livreurs, zones de livraison (nom + prix).
`.trim();

interface Payload {
  mode?: 'guide' | 'rapport';
  question?: string;
  /** Chiffres de la page Rapports, pour le mode "rapport". */
  rapport?: unknown;
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

export async function POST(req: Request) {
  try {
    const data: Payload = await req.json();
    const question = (data.question || '').trim();

    if (data.mode !== 'rapport' && !question) {
      return Response.json({ reponse: 'Posez-moi une question sur l’application.' });
    }

    const prompt =
      data.mode === 'rapport'
        ? promptRapport(data.rapport, question)
        : promptGuide(question);

    const response = await fetch(`${OLLAMA_BASE_URL}/api/generate`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: OLLAMA_MODEL,
        prompt,
        stream: false,
        // qwen3 raisonne longuement en interne avant de répondre : désactiver
        // ce mode accélère nettement (ignoré si le modèle ne le supporte pas).
        think: false,
      }),
      // Sur CPU, un rapport complet peut demander plusieurs minutes ; une
      // question sur le guide répond en général en quelques secondes.
      signal: AbortSignal.timeout(600_000),
    });

    if (!response.ok) {
      const detail = await response.text().catch(() => '');
      throw new Error(`Ollama a répondu ${response.status} : ${detail.slice(0, 300)}`);
    }

    const result = await response.json();
    const texte: string = result.response ?? '';
    // On ne garde que la réponse finale, pas le raisonnement interne.
    const reponse = texte.replace(/<think>[\s\S]*?<\/think>/gi, '').trim();

    return Response.json({ reponse });
  } catch (error: any) {
    console.error('Erreur assistant (Ollama) :', error);
    const indice =
      error?.name === 'TimeoutError'
        ? 'Le modèle a mis trop de temps à répondre.'
        : `Impossible de contacter Ollama sur ${OLLAMA_BASE_URL}. Vérifiez qu'Ollama tourne et que OLLAMA_BASE_URL est configuré.`;
    return Response.json({ reponse: `Désolé, je n'ai pas pu répondre. ${indice}` }, { status: 500 });
  }
}
