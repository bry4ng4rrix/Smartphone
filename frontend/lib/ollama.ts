// Accès à Ollama (local sur le VPS, pas d'API cloud) partagé par les routes
// app/api/ai/*. Deux profils, choisis selon l'usage :
//
//  * fast    : réponses courtes (assistant "guide", extraction d'une commande,
//              revue de doublons) — timeout court.
//  * analyse : rapports et analyses de chiffres — timeout long.
//
// Par défaut les deux profils utilisent le MÊME modèle, qwen3:4b-instruct
// (variante Instruct-2507 : pas de phase de réflexion, bon en français et en
// JSON structuré, ~7 s pour une question sur le guide, ~1-2 min pour un
// rapport). Un seul modèle résident : le VPS (8 Go, CPU seul) ne peut pas
// en garder deux en RAM (OOM), et chaque bascule coûte 10-20 s de
// rechargement. Si on configure deux modèles différents, l'autre est
// déchargé avant chaque appel pour rester dans la mémoire disponible.

export const OLLAMA_BASE_URL = process.env.OLLAMA_BASE_URL || 'http://localhost:11434';
export const OLLAMA_MODEL_FAST = process.env.OLLAMA_MODEL_FAST || 'qwen3:4b-instruct';
export const OLLAMA_MODEL_ANALYSE = process.env.OLLAMA_MODEL_ANALYSE || 'qwen3:4b-instruct';

export type OllamaUsage = 'fast' | 'analyse';

const PROFILES: Record<OllamaUsage, { model: string; keepAlive: string; timeoutMs: number }> = {
  fast: { model: OLLAMA_MODEL_FAST, keepAlive: '24h', timeoutMs: 180_000 },
  analyse: { model: OLLAMA_MODEL_ANALYSE, keepAlive: '24h', timeoutMs: 900_000 },
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

async function generate(usage: OllamaUsage, prompt: string, format?: object): Promise<string> {
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
      // Les variantes "thinking" de qwen3 ignorent think:false et renvoient
      // alors leur raisonnement dans `response` ; avec think:true Ollama
      // l'isole dans `thinking`. Sans effet sur un modèle instruct.
      think: true,
      keep_alive: p.keepAlive,
      ...(format ? { format } : {}),
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

/** Génère une réponse et renvoie uniquement le texte final (sans raisonnement). */
export function ollamaGenerate(usage: OllamaUsage, prompt: string): Promise<string> {
  return generate(usage, prompt);
}

/**
 * Génère une réponse contrainte à un schéma JSON (Ollama garantit la forme,
 * pas le contenu : valider les valeurs avant de s'en servir).
 */
export async function ollamaJson<T>(usage: OllamaUsage, prompt: string, schema: object): Promise<T> {
  const text = await generate(usage, prompt, schema);
  return JSON.parse(text) as T;
}

export function ollamaErrorHint(error: unknown): string {
  return (error as { name?: string })?.name === 'TimeoutError'
    ? 'Le modèle a mis trop de temps à répondre (délai dépassé).'
    : `Impossible de contacter Ollama sur ${OLLAMA_BASE_URL}. Vérifiez qu'Ollama tourne sur le VPS et que OLLAMA_BASE_URL est bien configuré (voir roadmap.md).`;
}
