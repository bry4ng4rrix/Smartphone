// Revue IA (Ollama local) des références nouvellement créées par un import
// Excel — la correspondance exacte/insensible à la casse est déjà gérée
// côté serveur (catalog/views.py::import_excel::_match_ci), donc jamais de
// doublon strict ; ce endpoint sert uniquement à repérer les quasi-doublons
// que seule une lecture "humaine" attrape (faute de frappe, variante
// d'écriture — ex: "Samsung A05S" vs "Samsung A05" déjà en catalogue).
// Best-effort : si Ollama ne répond pas, l'import reste valide, on perd
// juste cette vérification supplémentaire (voir handleImportExcel).
//
// Pour changer le PROMPT : voir frontend/app/api/ai/analyze/route.ts, même
// principe (éditer PROMPT_TEMPLATE-like ci-dessous puis rebuild frontend).

import { ollamaGenerate } from '@/lib/ollama';

interface CheckPayload {
  newNames: string[];
  existingNames: string[];
}

function buildPrompt({ newNames, existingNames }: CheckPayload): string {
  return `Tu vérifies un catalogue de références de téléphones/accessoires pour un revendeur à Madagascar, après un import Excel.

Références déjà existantes dans le catalogue (liste, peut être longue) :
${JSON.stringify(existingNames)}

Références qui viennent d'être créées par cet import (nouvelles) :
${JSON.stringify(newNames)}

Pour chaque référence nouvellement créée, dis si elle ressemble fortement à une référence déjà existante (faute de frappe, variante d'écriture, espace/tiret en trop, modèle très proche type "A05" vs "A05S" qui pourrait être une erreur de saisie plutôt qu'un vrai modèle différent). Ignore les différences de casse (déjà gérées ailleurs).

Réponds STRICTEMENT en JSON, un tableau d'objets, un seul objet par référence nouvelle qui te semble suspecte (n'inclus PAS celles qui sont clairement légitimes/différentes) :
[{"nouvelle": "nom exact de la référence créée", "ressemble_a": "nom exact de la référence existante la plus proche", "raison": "courte explication en français"}]

Si aucune ne te semble suspecte, réponds exactement : []
Ne réponds RIEN d'autre que ce JSON (pas de texte avant/après, pas de balises markdown).`;
}

export async function POST(req: Request) {
  try {
    const data: CheckPayload = await req.json();
    if (!data.newNames?.length) {
      return Response.json({ warnings: [] });
    }

    // Modèle rapide : cette revue tourne pendant l'import, elle ne doit pas
    // bloquer l'utilisateur plusieurs minutes.
    let text = await ollamaGenerate('fast', buildPrompt(data));
    // Au cas où le modèle encadre quand même sa réponse de ```json ... ``` malgré la consigne.
    text = text.replace(/^```(?:json)?\s*/i, '').replace(/```\s*$/i, '').trim();

    let warnings: { nouvelle: string; ressemble_a: string; raison: string }[] = [];
    try {
      const parsed = JSON.parse(text);
      if (Array.isArray(parsed)) warnings = parsed;
    } catch {
      // Réponse non-JSON malgré la consigne — best-effort, on renvoie vide
      // plutôt que de casser l'UI sur un import par ailleurs déjà réussi.
      warnings = [];
    }

    return Response.json({ warnings });
  } catch (error: any) {
    console.error('Erreur lors de la revue IA des doublons (Ollama) :', error);
    // Best-effort : ne fait jamais échouer l'import lui-même.
    return Response.json({ warnings: [], error: error?.message || 'Ollama indisponible' }, { status: 200 });
  }
}
