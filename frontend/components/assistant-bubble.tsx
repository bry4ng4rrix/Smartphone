'use client';

import { useEffect, useRef, useState } from 'react';
import { djangoClient } from '@/lib/django-client';
import { useCurrentUser } from '@/lib/auth/useCurrentUser';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Bot, Check, FileBarChart, FileSpreadsheet, Loader2, Paperclip, Send, X } from 'lucide-react';
import { appToday } from '@/lib/timezone';
import type { Proposition, ReponseAssistant } from '@/lib/assistant-types';

type Message = {
  role: 'user' | 'assistant';
  texte: string;
  /** Action à confirmer, jointe à un message de l'assistant. */
  proposition?: Proposition;
  decision?: 'confirmee' | 'annulee';
};

const SUGGESTIONS = [
  'Comment créer une commande ?',
  'À quelle heure le livreur peut-il livrer ?',
  'Comment valider une dépense de livreur ?',
  'Que se passe-t-il si le client refuse un article ?',
];

const EXEMPLE_COMMANDE =
  'Crée une commande pour Rakoto 034 12 345 67, 2 coques iPhone 13 noires, zone 2, lot II B 45 Ivandry, paiement à la livraison';

/**
 * Assistant de l'application (§ demande) — bulle flottante en bas à droite.
 *
 * Usages :
 *  * répondre aux questions sur le fonctionnement de l'app, à partir du mode
 *    d'emploi tenu dans app/api/ai/assistant/route.ts ;
 *  * créer une commande dictée en une phrase (gérant, préparateur) ;
 *  * mettre à jour les stocks depuis un fichier Excel joint (gérant) ;
 *  * rédiger un rapport commenté à partir des chiffres de la période (gérant).
 *
 * Toute action est d'abord présentée sous forme de récapitulatif : rien n'est
 * écrit avant que l'utilisateur ne clique "Confirmer". Le modèle tourne en
 * local (Ollama) : rien ne part vers un service tiers.
 */
export function AssistantBubble() {
  const { isGerant, isPreparateur } = useCurrentUser();
  const [ouvert, setOuvert] = useState(false);
  const [messages, setMessages] = useState<Message[]>([]);
  const [question, setQuestion] = useState('');
  const [fichier, setFichier] = useState<File | null>(null);
  const [enCours, setEnCours] = useState(false);
  const finRef = useRef<HTMLDivElement>(null);
  const fichierRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    finRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages, enCours]);

  const ajouter = (m: Message) => setMessages((prev) => [...prev, m]);

  /**
   * Le token d'accès n'est valable que quelques minutes : on force son
   * rafraîchissement (appel léger) avant de le transmettre à la route, qui
   * s'en sert pour agir auprès de l'API au nom de l'utilisateur.
   */
  const entetesAuth = async (): Promise<Record<string, string>> => {
    await djangoClient.auth.getCurrentUser().catch(() => null);
    const token = djangoClient.getAccessToken();
    return token ? { Authorization: `Bearer ${token}` } : {};
  };

  const envoyer = async (texte: string, piece: File | null = null) => {
    if ((!texte.trim() && !piece) || enCours) return;
    ajouter({ role: 'user', texte: piece ? `${texte.trim() ? `${texte.trim()}\n` : ''}📎 ${piece.name}` : texte });
    setQuestion('');
    setFichier(null);
    if (fichierRef.current) fichierRef.current.value = '';
    setEnCours(true);
    try {
      const auth = await entetesAuth();
      let res: Response;
      if (piece) {
        const form = new FormData();
        form.append('file', piece);
        form.append('question', texte);
        res = await fetch('/api/ai/assistant', { method: 'POST', headers: auth, body: form });
      } else {
        res = await fetch('/api/ai/assistant', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', ...auth },
          body: JSON.stringify({ mode: 'guide', question: texte }),
        });
      }
      const data: ReponseAssistant = await res.json();
      ajouter({ role: 'assistant', texte: data.reponse, proposition: data.proposition });
    } catch {
      ajouter({ role: 'assistant', texte: "Je n'ai pas pu répondre. Réessayez." });
    } finally {
      setEnCours(false);
    }
  };

  const decider = async (index: number, decision: 'confirmee' | 'annulee') => {
    if (enCours) return;
    const proposition = messages[index]?.proposition;
    if (!proposition) return;
    setMessages((prev) => prev.map((m, i) => (i === index ? { ...m, decision } : m)));
    if (decision === 'annulee') {
      ajouter({ role: 'assistant', texte: "D'accord, j'annule. Rien n'a été modifié." });
      return;
    }
    setEnCours(true);
    try {
      const auth = await entetesAuth();
      const res = await fetch('/api/ai/assistant', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', ...auth },
        body: JSON.stringify({ mode: 'executer', proposition }),
      });
      const data: ReponseAssistant = await res.json();
      ajouter({ role: 'assistant', texte: data.reponse });
    } catch {
      ajouter({ role: 'assistant', texte: "Je n'ai pas pu exécuter l'action. Vérifiez dans l'application avant de réessayer." });
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
    ajouter({ role: 'user', texte: 'Génère le rapport des 30 derniers jours.' });
    setEnCours(true);
    try {
      const fin = appToday();
      const debutDate = new Date(`${fin}T12:00:00+03:00`);
      debutDate.setDate(debutDate.getDate() - 29);
      const rapport = await djangoClient.reports.get(debutDate.toISOString().slice(0, 10), fin);
      const res = await fetch('/api/ai/assistant', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ mode: 'rapport', rapport }),
      });
      const data = await res.json();
      ajouter({ role: 'assistant', texte: data.reponse });
    } catch {
      ajouter({ role: 'assistant', texte: "Je n'ai pas pu récupérer les chiffres de la période." });
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

  const peutCommander = isGerant || isPreparateur;

  return (
    <div className="fixed bottom-5 right-5 z-40 w-[min(380px,calc(100vw-2.5rem))] max-h-[min(600px,calc(100dvh-6rem))] flex flex-col rounded-2xl border bg-card shadow-2xl overflow-hidden">
      <div className="flex items-center justify-between gap-2 border-b px-4 py-3 shrink-0">
        <div className="flex items-center gap-2">
          <div className="p-1.5 rounded-lg bg-primary/10 text-primary">
            <Bot className="h-4 w-4" />
          </div>
          <div>
            <p className="text-sm font-semibold leading-none">Assistant</p>
            <p className="text-[10px] text-muted-foreground mt-0.5">
              {peutCommander ? 'Guide et actions' : "Guide de l'application"}
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
                  onClick={() => envoyer(s)}
                  className="text-left text-xs rounded-lg border px-2.5 py-1.5 hover:bg-muted transition-colors"
                >
                  {s}
                </button>
              ))}
            </div>
            {peutCommander && (
              <div className="space-y-1.5">
                <p className="text-xs text-muted-foreground">
                  Je peux aussi créer une commande que vous me dictez
                  {isGerant ? ', ou mettre à jour les stocks depuis un fichier Excel (trombone)' : ''}.
                  Je vous montre toujours un récapitulatif avant d&apos;agir.
                </p>
                <button
                  onClick={() => setQuestion(EXEMPLE_COMMANDE)}
                  className="text-left text-xs rounded-lg border border-dashed px-2.5 py-1.5 hover:bg-muted transition-colors text-muted-foreground"
                >
                  Exemple : {EXEMPLE_COMMANDE}
                </button>
              </div>
            )}
          </div>
        )}

        {messages.map((m, i) => (
          <div key={i} className={`flex ${m.role === 'user' ? 'justify-end' : 'justify-start'}`}>
            <div
              className={`max-w-[85%] rounded-2xl px-3 py-2 text-sm whitespace-pre-wrap leading-relaxed ${
                m.role === 'user' ? 'bg-primary text-primary-foreground' : 'bg-muted'
              }`}
            >
              {m.texte}
              {m.proposition && (
                <div className="mt-2 rounded-xl border bg-card px-3 py-2 space-y-2">
                  <p className="text-xs font-semibold flex items-center gap-1.5">
                    {m.proposition.type === 'creer_commande' ? (
                      <Check className="h-3.5 w-3.5" />
                    ) : (
                      <FileSpreadsheet className="h-3.5 w-3.5" />
                    )}
                    {m.proposition.type === 'creer_commande' ? 'Nouvelle commande' : 'Mise à jour des stocks'}
                  </p>
                  <ul className="text-xs space-y-0.5">
                    {m.proposition.resume.map((ligne, j) => (
                      <li key={j}>{ligne}</li>
                    ))}
                  </ul>
                  {m.decision ? (
                    <p className="text-xs text-muted-foreground italic">
                      {m.decision === 'confirmee' ? 'Confirmé' : 'Annulé'}
                    </p>
                  ) : (
                    <div className="flex gap-2 pt-1">
                      <Button size="sm" className="h-7 text-xs" disabled={enCours} onClick={() => decider(i, 'confirmee')}>
                        Confirmer
                      </Button>
                      <Button
                        size="sm"
                        variant="outline"
                        className="h-7 text-xs"
                        disabled={enCours}
                        onClick={() => decider(i, 'annulee')}
                      >
                        Annuler
                      </Button>
                    </div>
                  )}
                </div>
              )}
            </div>
          </div>
        ))}

        {enCours && (
          <div className="flex items-center gap-2 text-xs text-muted-foreground">
            <Loader2 className="h-3.5 w-3.5 animate-spin" />
            Un instant…
          </div>
        )}
        <div ref={finRef} />
      </div>

      <div className="border-t p-3 space-y-2 shrink-0">
        {isGerant && (
          <Button variant="outline" size="sm" className="w-full" disabled={enCours} onClick={genererRapport}>
            <FileBarChart className="h-4 w-4 mr-2" />
            Générer le rapport du mois
          </Button>
        )}
        {fichier && (
          <div className="flex items-center gap-2 text-xs rounded-lg bg-muted px-2.5 py-1.5">
            <FileSpreadsheet className="h-3.5 w-3.5 shrink-0" />
            <span className="truncate flex-1">{fichier.name}</span>
            <button
              type="button"
              onClick={() => {
                setFichier(null);
                if (fichierRef.current) fichierRef.current.value = '';
              }}
              aria-label="Retirer le fichier"
            >
              <X className="h-3.5 w-3.5" />
            </button>
          </div>
        )}
        <form
          className="flex gap-2"
          onSubmit={(e) => {
            e.preventDefault();
            envoyer(question, fichier);
          }}
        >
          {isGerant && (
            <>
              <input
                ref={fichierRef}
                type="file"
                accept=".xlsx,.xls"
                className="hidden"
                onChange={(e) => setFichier(e.target.files?.[0] ?? null)}
              />
              <Button
                type="button"
                size="icon"
                variant="outline"
                className="rounded-xl shrink-0"
                disabled={enCours}
                onClick={() => fichierRef.current?.click()}
                aria-label="Joindre un fichier Excel de stocks"
              >
                <Paperclip className="h-4 w-4" />
              </Button>
            </>
          )}
          <Input
            value={question}
            onChange={(e) => setQuestion(e.target.value)}
            placeholder={fichier ? 'Message (facultatif)…' : peutCommander ? 'Question ou commande à créer…' : 'Votre question…'}
            disabled={enCours}
            className="flex-1 rounded-xl"
          />
          <Button
            type="submit"
            size="icon"
            className="rounded-xl shrink-0"
            disabled={enCours || (!question.trim() && !fichier)}
            aria-label="Envoyer"
          >
            {enCours ? <Loader2 className="h-4 w-4 animate-spin" /> : <Send className="h-4 w-4" />}
          </Button>
        </form>
      </div>
    </div>
  );
}
