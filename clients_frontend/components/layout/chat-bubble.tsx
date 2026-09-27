"use client";

import { useEffect, useRef, useState } from "react";
import { Bot, Check, Loader2, MessageCircle, Send, ShoppingBag, X } from "lucide-react";
import { Button, ButtonLink } from "@/components/ui/button";
import { Input } from "@/components/ui/field";
import { useCart } from "@/providers/cart-provider";
import type { LignePanier } from "@/providers/cart-provider";
import type { Proposition, ReponseAssistant } from "@/lib/assistant-types";

type Message = {
  role: "client" | "assistant";
  texte: string;
  /** Panier proposé, joint à un message de l'assistant, à confirmer. */
  proposition?: Proposition;
  decision?: "confirmee" | "annulee";
};

const SUGGESTIONS = [
  "Comment passer une commande ?",
  "Quels sont les statuts d'une commande ?",
  "Comment annuler ou modifier ma commande ?",
  "Comment marche le paiement ?",
];

const EXEMPLE_ARTICLE = "Je veux 2 coques iPhone 13 noires";

/**
 * Assistant du site client (§ demande) — bulle flottante en bas à droite.
 *
 * Deux usages :
 *  * répondre aux questions sur le fonctionnement du site, à partir du mode
 *    d'emploi tenu dans app/api/assistant/route.ts ;
 *  * préparer un panier à partir d'une demande en une phrase — l'assistant
 *    retrouve les articles dans le catalogue et montre un récapitulatif ;
 *    rien n'est ajouté avant que le client ne clique "Confirmer".
 *
 * Ouverte à tout visiteur, même non connecté : le catalogue est public et le
 * panier est local au navigateur (voir providers/cart-provider.tsx) — seule
 * la validation finale de la commande demande une connexion.
 */
export function ChatBubble() {
  const { boutiqueId, ajouterLignes } = useCart();
  const [ouvert, setOuvert] = useState(false);
  const [messages, setMessages] = useState<Message[]>([]);
  const [question, setQuestion] = useState("");
  const [enCours, setEnCours] = useState(false);
  const finRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (ouvert) finRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages, enCours, ouvert]);

  const ajouter = (m: Message) => setMessages((prev) => [...prev, m]);

  const envoyer = async (texte: string) => {
    if (!texte.trim() || enCours) return;
    ajouter({ role: "client", texte: texte.trim() });
    setQuestion("");
    setEnCours(true);
    try {
      const res = await fetch("/api/assistant", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ question: texte, boutiqueId }),
      });
      const data: ReponseAssistant = await res.json();
      ajouter({ role: "assistant", texte: data.reponse, proposition: data.proposition });
    } catch {
      ajouter({ role: "assistant", texte: "Je n'ai pas pu répondre. Vérifiez votre connexion puis réessayez." });
    } finally {
      setEnCours(false);
    }
  };

  const decider = (index: number, decision: "confirmee" | "annulee") => {
    const proposition = messages[index]?.proposition;
    if (!proposition) return;
    setMessages((prev) => prev.map((m, i) => (i === index ? { ...m, decision } : m)));
    if (decision === "annulee") {
      ajouter({ role: "assistant", texte: "D'accord, je n'ajoute rien." });
      return;
    }
    const ajoutees = ajouterLignes(proposition.articles as LignePanier[]);
    if (ajoutees === proposition.articles.length) {
      ajouter({ role: "assistant", texte: "C'est ajouté à votre panier. Vous pouvez continuer vos achats ou passer commande." });
    } else if (ajoutees > 0) {
      ajouter({
        role: "assistant",
        texte: `J'ai ajouté ${ajoutees} sur ${proposition.articles.length} article(s) — les autres viennent d'une boutique différente de votre panier actuel.`,
      });
    } else {
      ajouter({ role: "assistant", texte: "Je n'ai rien pu ajouter : ces articles viennent d'une autre boutique que votre panier actuel. Videz-le d'abord si vous voulez changer de boutique." });
    }
  };

  if (!ouvert) {
    return (
      <Button
        onClick={() => setOuvert(true)}
        variant="accent"
        className="fixed right-5 bottom-5 z-40 h-14 w-14 rounded-full p-0 shadow-lg"
        aria-label="Ouvrir l'assistant"
      >
        <MessageCircle className="size-6" aria-hidden />
      </Button>
    );
  }

  return (
    <div className="glass-strong fixed right-5 bottom-5 z-40 flex max-h-[min(600px,calc(100dvh-6rem))] w-[min(380px,calc(100vw-2.5rem))] flex-col overflow-hidden rounded-2xl shadow-2xl">
      <div className="flex shrink-0 items-center justify-between gap-2 border-b border-[var(--glass-border)] px-4 py-3">
        <div className="flex items-center gap-2">
          <div className="rounded-lg bg-accent/10 p-1.5 text-accent">
            <Bot className="size-4" aria-hidden />
          </div>
          <div>
            <p className="text-sm leading-none font-semibold">Assistant Smartphone.Mg</p>
            <p className="mt-0.5 text-[10px] text-muted">Questions et commandes</p>
          </div>
        </div>
        <Button variant="fantome" size="icone_sm" onClick={() => setOuvert(false)} aria-label="Fermer l'assistant">
          <X className="size-4" aria-hidden />
        </Button>
      </div>

      <div className="min-h-0 flex-1 space-y-3 overflow-y-auto overscroll-contain p-3">
        {messages.length === 0 && (
          <div className="space-y-3">
            <p className="text-sm text-muted">
              Posez-moi une question sur le site — catalogue, commande, livraison, paiement — ou dites-moi directement ce que vous voulez.
            </p>
            <div className="flex flex-col gap-1.5">
              {SUGGESTIONS.map((s) => (
                <button
                  key={s}
                  onClick={() => envoyer(s)}
                  className="hairline rounded-lg px-2.5 py-1.5 text-left text-xs transition-colors hover:bg-foreground/[0.05]"
                >
                  {s}
                </button>
              ))}
            </div>
            <div className="space-y-1.5">
              <p className="text-xs text-muted">Je peux aussi préparer votre panier. Je vous montre toujours un récapitulatif avant d&apos;ajouter quoi que ce soit.</p>
              <button
                onClick={() => setQuestion(EXEMPLE_ARTICLE)}
                className="rounded-lg border border-dashed border-border px-2.5 py-1.5 text-left text-xs text-muted transition-colors hover:bg-foreground/[0.05]"
              >
                Exemple : {EXEMPLE_ARTICLE}
              </button>
            </div>
          </div>
        )}

        {messages.map((m, i) => (
          <div key={i} className={`flex ${m.role === "client" ? "justify-end" : "justify-start"}`}>
            <div
              className={`max-w-[85%] rounded-2xl px-3 py-2 text-sm leading-relaxed whitespace-pre-wrap ${
                m.role === "client" ? "bg-accent text-accent-foreground" : "bg-foreground/[0.05]"
              }`}
            >
              {m.texte}
              {m.proposition && (
                <div className="mt-2 space-y-2 rounded-xl border border-border bg-surface px-3 py-2 text-foreground">
                  <p className="flex items-center gap-1.5 text-xs font-semibold">
                    <ShoppingBag className="size-3.5" aria-hidden />
                    Articles à ajouter
                  </p>
                  <ul className="space-y-0.5 text-xs">
                    {m.proposition.resume.map((ligne, j) => (
                      <li key={j}>{ligne}</li>
                    ))}
                  </ul>
                  {m.decision ? (
                    <p className="text-xs text-muted italic">{m.decision === "confirmee" ? "Ajouté au panier" : "Annulé"}</p>
                  ) : (
                    <div className="flex gap-2 pt-1">
                      <Button size="sm" className="h-7 text-xs" onClick={() => decider(i, "confirmee")}>
                        <Check className="size-3.5" aria-hidden />
                        Confirmer
                      </Button>
                      <Button variant="contour" size="sm" className="h-7 text-xs" onClick={() => decider(i, "annulee")}>
                        Annuler
                      </Button>
                    </div>
                  )}
                  {m.decision === "confirmee" ? (
                    <div className="flex gap-2 pt-1">
                      <ButtonLink href="/panier" variant="contour" size="sm" className="h-7 text-xs">
                        Voir le panier
                      </ButtonLink>
                      <ButtonLink href="/checkout" variant="accent" size="sm" className="h-7 text-xs">
                        Passer commande
                      </ButtonLink>
                    </div>
                  ) : null}
                </div>
              )}
            </div>
          </div>
        ))}

        {enCours && (
          <div className="flex items-center gap-2 text-xs text-muted">
            <Loader2 className="size-3.5 animate-spin" aria-hidden />
            Un instant…
          </div>
        )}
        <div ref={finRef} />
      </div>

      <form
        className="flex shrink-0 gap-2 border-t border-[var(--glass-border)] p-3"
        onSubmit={(e) => {
          e.preventDefault();
          envoyer(question);
        }}
      >
        <label htmlFor="assistant-question" className="sr-only">
          Votre question ou votre commande
        </label>
        <Input
          id="assistant-question"
          value={question}
          onChange={(e) => setQuestion(e.target.value)}
          placeholder="Question ou article à commander…"
          disabled={enCours}
          className="flex-1 rounded-xl"
        />
        <Button type="submit" size="icone" className="shrink-0 rounded-xl" disabled={enCours || !question.trim()} aria-label="Envoyer">
          {enCours ? <Loader2 className="size-4 animate-spin" aria-hidden /> : <Send className="size-4" aria-hidden />}
        </Button>
      </form>
    </div>
  );
}
