// Accès à Ollama (local sur le VPS, pas d'API cloud) partagé par les routes
// app/api/ai/*. Deux modèles, choisis selon l'usage :
//
//  * FAST    : réponses courtes et immédiates (assistant "guide", revue de
//              doublons). Petit modèle gardé chaud en RAM : ~2-5 s par réponse.
//  * ANALYSE : rapports et analyses de chiffres. Modèle plus gros qui
//              raisonne avant de répondre (variante "thinking") : plusieurs
//              minutes sur CPU, mais une lecture des données bien meilleure.
//
// Le VPS (8 Go, CPU seul) ne peut PAS garder les deux modèles en RAM à la
// fois (1,9 + 3,2 Go + le reste = OOM, Ollama redémarre). Avant chaque appel,
// on décharge donc l'autre modèle. Le modèle d'analyse se décharge aussi
// tout seul peu après usage (keep_alive court) ; le modèle rapide reste
// chargé pour répondre sans délai.

export const OLLAMA_BASE_URL = process.env.OLLAMA_BASE_URL || 'http://localhost:11434';
export const OLLAMA_MODEL_FAST = process.env.OLLAMA_MODEL_FAST || 'qwen3:1.7b';
export const OLLAMA_MODEL_ANALYSE = process.env.OLLAMA_MODEL_ANALYSE || 'qwen3:4b';

export type OllamaUsage = 'fast' | 'analyse';

const PROFILES: Record<OllamaUsage, { model: string; think: boolean; keepAlive: string; timeoutMs: number }> = {
  fast: { model: OLLAMA_MODEL_FAST, think: false, keepAlive: '24h', timeoutMs: 120_000 },
  // think:true — les variantes "thinking" de qwen3 ignorent think:false et
  // renvoient alors leur raisonnement dans `response` (sans balise <think>
  // ouvrante). Avec think:true, Ollama l'isole dans `thinking` et `response`
  // ne contient que la réponse finale.
  analyse: { model: OLLAMA_MODEL_ANALYSE, think: true, keepAlive: '2m', timeoutMs: 900_000 },
};

function stripThinking(text: string): string {
  const end = text.lastIndexOf('</think>');
  return (end === -1 ? text : text.slice(end + '</think>'.length)).trim();
}

// Prompt vide + keep_alive 0 = "décharge ce modèle s'il est en mémoire",
// sans le charger sinon. Best-effort : un échec ici ne doit pas bloquer.
async function unload(model: string): Promise<void> {
  await fetch(`${OLLAMA_BASE_URL}/api/generate`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ model, keep_alive: 0 }),
    signal: AbortSignal.timeout(10_000),
  }).catch(() => undefined);
}

/** Génère une réponse et renvoie uniquement le texte final (sans raisonnement). */
export async function ollamaGenerate(usage: OllamaUsage, prompt: string): Promise<string> {
  const p = PROFILES[usage];
  const other = PROFILES[usage === 'fast' ? 'analyse' : 'fast'];
  if (other.model !== p.model) await unload(other.model);

  const response = await fetch(`${OLLAMA_BASE_URL}/api/generate`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: p.model,
      prompt,
      // Streaming obligatoire : en mode non-stream, Ollama n'envoie les
      // en-têtes qu'à la fin de la génération, et fetch (undici) coupe la
      // connexion après 300 s sans en-tête — une analyse longue échouait
      // systématiquement à 5 min quel que soit le timeout ci-dessous.
      stream: true,
      think: p.think,
      keep_alive: p.keepAlive,
    }),
    signal: AbortSignal.timeout(p.timeoutMs),
  });

  if (!response.ok || !response.body) {
    const detail = await response.text().catch(() => '');
    throw new Error(`Ollama (${p.model}) a répondu ${response.status} : ${detail.slice(0, 300)}`);
  }

  let text = '';
  let buffer = '';
  const decoder = new TextDecoder();
  for await (const chunk of response.body as unknown as AsyncIterable<Uint8Array>) {
    buffer += decoder.decode(chunk, { stream: true });
    const lines = buffer.split('\n');
    buffer = lines.pop() ?? '';
    for (const line of lines) {
      if (!line.trim()) continue;
      const part = JSON.parse(line);
      if (part.error) throw new Error(`Ollama (${p.model}) : ${part.error}`);
      text += part.response ?? '';
    }
  }
  if (buffer.trim()) text += JSON.parse(buffer).response ?? '';

  return stripThinking(text);
}

export function ollamaErrorHint(error: unknown): string {
  return (error as { name?: string })?.name === 'TimeoutError'
    ? 'Le modèle a mis trop de temps à répondre (délai dépassé).'
    : `Impossible de contacter Ollama sur ${OLLAMA_BASE_URL}. Vérifiez qu'Ollama tourne sur le VPS et que OLLAMA_BASE_URL est bien configuré (voir roadmap.md).`;
}
