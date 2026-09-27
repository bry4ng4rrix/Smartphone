// Accès à Ollama (local sur le VPS, pas d'API cloud), utilisé par
// app/api/assistant/route.ts pour l'assistant client (bulle en bas à droite).
//
// Même service Ollama que l'application de gestion (frontend/lib/ollama.ts) :
// un seul modèle résident sur le VPS (8 Go, CPU seul), partagé entre les deux
// apps. Voir .env.example § « Analyse IA » pour la configuration complète.

export const OLLAMA_BASE_URL = process.env.OLLAMA_BASE_URL || "http://localhost:11434";
export const OLLAMA_MODEL = process.env.OLLAMA_MODEL_FAST || "qwen3:4b-instruct";

const KEEP_ALIVE = "24h";
const TIMEOUT_MS = 180_000;

function stripThinking(text: string): string {
  const end = text.lastIndexOf("</think>");
  return (end === -1 ? text : text.slice(end + "</think>".length)).trim();
}

async function generate(prompt: string, format?: object): Promise<string> {
  const response = await fetch(`${OLLAMA_BASE_URL}/api/generate`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      model: OLLAMA_MODEL,
      prompt,
      // Streaming obligatoire : en mode non-stream, Ollama n'envoie les
      // en-têtes qu'à la fin de la génération, et fetch (undici) coupe la
      // connexion après 300 s sans en-tête.
      stream: true,
      think: true,
      keep_alive: KEEP_ALIVE,
      ...(format ? { format } : {}),
    }),
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });

  if (!response.ok || !response.body) {
    const detail = await response.text().catch(() => "");
    throw new Error(`Ollama (${OLLAMA_MODEL}) a répondu ${response.status} : ${detail.slice(0, 300)}`);
  }

  let text = "";
  let buffer = "";
  const decoder = new TextDecoder();
  for await (const chunk of response.body as unknown as AsyncIterable<Uint8Array>) {
    buffer += decoder.decode(chunk, { stream: true });
    const lines = buffer.split("\n");
    buffer = lines.pop() ?? "";
    for (const line of lines) {
      if (!line.trim()) continue;
      const part = JSON.parse(line);
      if (part.error) throw new Error(`Ollama (${OLLAMA_MODEL}) : ${part.error}`);
      text += part.response ?? "";
    }
  }
  if (buffer.trim()) text += JSON.parse(buffer).response ?? "";

  return stripThinking(text);
}

/** Génère une réponse et renvoie uniquement le texte final (sans raisonnement). */
export function ollamaGenerate(prompt: string): Promise<string> {
  return generate(prompt);
}

/**
 * Génère une réponse contrainte à un schéma JSON (Ollama garantit la forme,
 * pas le contenu : valider les valeurs avant de s'en servir).
 */
export async function ollamaJson<T>(prompt: string, schema: object): Promise<T> {
  const text = await generate(prompt, schema);
  return JSON.parse(text) as T;
}

export function ollamaErrorHint(error: unknown): string {
  return (error as { name?: string })?.name === "TimeoutError"
    ? "Le modèle a mis trop de temps à répondre."
    : "Impossible de contacter l'assistant pour le moment.";
}
