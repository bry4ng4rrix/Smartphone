'use client';

import { useEffect, useRef, useState } from 'react';
import { djangoClient } from '@/lib/django-client';
import { useCurrentUser } from '@/lib/auth/useCurrentUser';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Bot, FileBarChart, Loader2, Send, Sparkles, X } from 'lucide-react';
import { appToday } from '@/lib/timezone';

type Message = { role: 'user' | 'assistant'; texte: string };

const SUGGESTIONS = [
  'Comment créer une commande ?',
  'À quelle heure le livreur peut-il livrer ?',
  'Comment valider une dépense de livreur ?',
  'Que se passe-t-il si le client refuse un article ?',
];

/**
 * Assistant de l'application (§ demande) — bulle flottante en bas à droite.
 *
 * Deux usages :
 *  * répondre aux questions sur le fonctionnement de l'app, à partir du mode
 *    d'emploi tenu dans app/api/ai/assistant/route.ts ;
 *  * rédiger un rapport commenté à partir des chiffres de la période, que le
 *    gérant seul peut demander (les rapports lui sont réservés).
 *
 * Le modèle tourne en local (Ollama) : rien ne part vers un service tiers.
 */
export function AssistantBubble() {
  const { isGerant } = useCurrentUser();
  const [ouvert, setOuvert] = useState(false);
  const [messages, setMessages] = useState<Message[]>([]);
  const [question, setQuestion] = useState('');
  const [enCours, setEnCours] = useState(false);
  const finRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    finRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages, enCours]);

  const demander = async (texte: string) => {
    if (!texte.trim() || enCours) return;
    setMessages((m) => [...m, { role: 'user', texte }]);
    setQuestion('');
    setEnCours(true);
    try {
      const res = await fetch('/api/ai/assistant', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ mode: 'guide', question: texte }),
      });
      const data = await res.json();
      setMessages((m) => [...m, { role: 'assistant', texte: data.reponse }]);
    } catch {
      setMessages((m) => [
        ...m,
        { role: 'assistant', texte: "Je n'ai pas pu répondre. Réessayez." },
      ]);
    } finally {
      setEnCours(false);
    }
  };

  /**
   * Rapport commenté : on récupère d'abord les chiffres du mois auprès de
   * l'API, puis on les donne au modèle. C'est le serveur qui les agrège —
   * le navigateur ne fait que les transmettre.
   */
  const genererRapport = async () => {
    if (enCours) return;
    setMessages((m) => [
      ...m,
      { role: 'user', texte: 'Génère le rapport des 30 derniers jours.' },
    ]);
    setEnCours(true);
    try {
      const fin = appToday();
      const debutDate = new Date(`${fin}T12:00:00+03:00`);
      debutDate.setDate(debutDate.getDate() - 29);
      const rapport = await djangoClient.reports.get(
        debutDate.toISOString().slice(0, 10),
        fin,
      );
      const res = await fetch('/api/ai/assistant', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ mode: 'rapport', rapport }),
      });
      const data = await res.json();
      setMessages((m) => [...m, { role: 'assistant', texte: data.reponse }]);
    } catch {
      setMessages((m) => [
        ...m,
        {
          role: 'assistant',
          texte: "Je n'ai pas pu récupérer les chiffres de la période.",
        },
      ]);
    } finally {
      setEnCours(false);
    }
  };

  // Pas d'assistant pour un visiteur non connecté : il n'a ni page ni données.
  if (!djangoClient.isAuthenticated()) return null;

  if (!ouvert) {
    return (
      <Button
        onClick={() => setOuvert(true)}
        className="fixed bottom-5 right-5 z-40 h-14 w-14 rounded-full shadow-lg"
        aria-label="Ouvrir l'assistant"
      >
        <Bot className="h-6 w-6" />
      </Button>
    );
  }

  return (
    <div className="fixed bottom-5 right-5 z-40 w-[min(380px,calc(100vw-2.5rem))] max-h-[min(560px,calc(100dvh-6rem))] flex flex-col rounded-2xl border bg-card shadow-2xl overflow-hidden">
      <div className="flex items-center justify-between gap-2 border-b px-4 py-3 shrink-0">
        <div className="flex items-center gap-2">
          <div className="p-1.5 rounded-lg bg-primary/10 text-primary">
            <Bot className="h-4 w-4" />
          </div>
          <div>
            <p className="text-sm font-semibold leading-none">Assistant</p>
            <p className="text-[10px] text-muted-foreground mt-0.5">
              Guide de l&apos;application
            </p>
          </div>
        </div>
        <Button
          variant="ghost"
          size="icon"
          className="h-8 w-8"
          onClick={() => setOuvert(false)}
          aria-label="Fermer l'assistant"
        >
          <X className="h-4 w-4" />
        </Button>
      </div>

      <div className="flex-1 min-h-0 overflow-y-auto overscroll-contain p-3 space-y-3">
        {messages.length === 0 && (
          <div className="space-y-3">
            <p className="text-sm text-muted-foreground">
              Posez-moi une question sur l&apos;application — les rôles, le
              parcours d&apos;une commande, les dépenses, les bilans…
            </p>
            <div className="flex flex-col gap-1.5">
              {SUGGESTIONS.map((s) => (
                <button
                  key={s}
                  onClick={() => demander(s)}
                  className="text-left text-xs rounded-lg border px-2.5 py-1.5 hover:bg-muted transition-colors"
                >
                  {s}
                </button>
              ))}
            </div>
          </div>
        )}

        {messages.map((m, i) => (
          <div
            key={i}
            className={`flex ${m.role === 'user' ? 'justify-end' : 'justify-start'}`}
          >
            <div
              className={`max-w-[85%] rounded-2xl px-3 py-2 text-sm whitespace-pre-wrap leading-relaxed ${
                m.role === 'user'
                  ? 'bg-primary text-primary-foreground'
                  : 'bg-muted'
              }`}
            >
              {m.texte}
            </div>
          </div>
        ))}

        {enCours && (
          <div className="flex items-center gap-2 text-xs text-muted-foreground">
            <Loader2 className="h-3.5 w-3.5 animate-spin" />
            Le modèle rédige sa réponse…
          </div>
        )}
        <div ref={finRef} />
      </div>

      <div className="border-t p-3 space-y-2 shrink-0">
        {isGerant && (
          <Button
            variant="outline"
            size="sm"
            className="w-full"
            disabled={enCours}
            onClick={genererRapport}
          >
            <FileBarChart className="h-4 w-4 mr-2" />
            Générer le rapport du mois
          </Button>
        )}
        <form
          className="flex gap-2"
          onSubmit={(e) => {
            e.preventDefault();
            demander(question);
          }}
        >
          <Input
            value={question}
            onChange={(e) => setQuestion(e.target.value)}
            placeholder="Votre question…"
            disabled={enCours}
            className="flex-1 rounded-xl"
          />
          <Button
            type="submit"
            size="icon"
            className="rounded-xl shrink-0"
            disabled={enCours || !question.trim()}
            aria-label="Envoyer"
          >
            {enCours ? (
              <Loader2 className="h-4 w-4 animate-spin" />
            ) : (
              <Send className="h-4 w-4" />
            )}
          </Button>
        </form>
        <p className="text-[10px] text-muted-foreground flex items-center gap-1">
          <Sparkles className="h-3 w-3" />
          Modèle local — aucune donnée ne quitte votre serveur.
        </p>
      </div>
    </div>
  );
}
