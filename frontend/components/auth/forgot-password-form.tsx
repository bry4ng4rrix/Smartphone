'use client';

import { useState } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { djangoClient } from '@/lib/django-client';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { toast } from 'sonner';
import { KeyRound, Loader2, ArrowLeft, Clock, CheckCircle2, XCircle } from 'lucide-react';

type Status = 'none' | 'pending' | 'approved' | 'rejected';

export function ForgotPasswordForm() {
  const router = useRouter();
  const [step, setStep] = useState<'request' | 'check'>('request');
  const [email, setEmail] = useState('');
  const [loading, setLoading] = useState(false);
  const [queue, setQueue] = useState<'label' | 'admin' | null>(null);
  const [status, setStatus] = useState<Status | null>(null);
  const [newPassword, setNewPassword] = useState('');
  const [confirm, setConfirm] = useState('');

  const handleRequest = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    try {
      const res = await djangoClient.auth.forgotPasswordRequest(email);
      setQueue(res.queue);
      setStatus('pending');
      setStep('check');
      toast.success(res.message);
    } catch (err: any) {
      toast.error(err.message || "Erreur lors de l'envoi de la demande");
    } finally {
      setLoading(false);
    }
  };

  const handleCheckStatus = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    try {
      const res = await djangoClient.auth.forgotPasswordStatus(email);
      setStatus(res.status);
      if (res.status === 'none') {
        toast.error('Aucune demande trouvée pour cet email.');
      }
    } catch (err: any) {
      toast.error(err.message || 'Erreur lors de la vérification');
    } finally {
      setLoading(false);
    }
  };

  const handleSetPassword = async (e: React.FormEvent) => {
    e.preventDefault();
    if (newPassword !== confirm) {
      toast.error('Les mots de passe ne correspondent pas');
      return;
    }
    setLoading(true);
    try {
      await djangoClient.auth.forgotPasswordConfirm(email, newPassword);
      toast.success('Mot de passe défini avec succès. Vous pouvez vous connecter.');
      router.push('/login');
    } catch (err: any) {
      toast.error(err.message || 'Erreur lors de la définition du mot de passe');
    } finally {
      setLoading(false);
    }
  };

  return (
    <Card className="w-full max-w-md shadow-xl">
      <CardHeader className="space-y-1 pb-4">
        <CardTitle className="flex items-center gap-2 text-2xl font-bold">
          <KeyRound className="h-5 w-5" />
          Mot de passe oublié
        </CardTitle>
        <CardDescription>
          {step === 'request'
            ? "Entrez votre email : votre demande sera transmise pour validation."
            : "Vérifiez si votre demande a été validée."}
        </CardDescription>
      </CardHeader>

      <CardContent className="space-y-4">
        {step === 'request' ? (
          <form onSubmit={handleRequest} className="space-y-4">
            <div className="space-y-1.5">
              <Label htmlFor="fp-email">Email</Label>
              <Input
                id="fp-email"
                type="email"
                placeholder="vous@example.com"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                disabled={loading}
                required
              />
            </div>
            <Button type="submit" className="w-full" disabled={loading}>
              {loading ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : null}
              Envoyer la demande
            </Button>
            <p className="text-center text-sm text-muted-foreground">
              Demande déjà envoyée ?{' '}
              <button
                type="button"
                className="text-primary font-medium hover:underline"
                onClick={() => setStep('check')}
              >
                Vérifier le statut
              </button>
            </p>
          </form>
        ) : (
          <div className="space-y-4">
            <form onSubmit={handleCheckStatus} className="space-y-4">
              <div className="space-y-1.5">
                <Label htmlFor="fp-check-email">Email</Label>
                <Input
                  id="fp-check-email"
                  type="email"
                  placeholder="vous@example.com"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  disabled={loading}
                  required
                />
              </div>
              <Button type="submit" variant="outline" className="w-full" disabled={loading}>
                {loading ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : null}
                Vérifier le statut
              </Button>
            </form>

            {status && status !== 'none' && (
              <div
                className={`flex items-center gap-2 rounded-lg border p-3 text-sm ${
                  status === 'approved'
                    ? 'border-green-200 bg-green-50 text-green-700 dark:bg-green-950/20 dark:text-green-400'
                    : status === 'rejected'
                    ? 'border-red-200 bg-red-50 text-red-700 dark:bg-red-950/20 dark:text-red-400'
                    : 'border-orange-200 bg-orange-50 text-orange-700 dark:bg-orange-950/20 dark:text-orange-400'
                }`}
              >
                {status === 'approved' ? (
                  <CheckCircle2 className="h-4 w-4 shrink-0" />
                ) : status === 'rejected' ? (
                  <XCircle className="h-4 w-4 shrink-0" />
                ) : (
                  <Clock className="h-4 w-4 shrink-0" />
                )}
                <span>
                  {status === 'approved' && 'Demande validée : vous pouvez définir votre nouveau mot de passe.'}
                  {status === 'pending' &&
                    (queue === 'label'
                      ? 'En attente de validation par Label Technology.'
                      : 'En attente de validation par votre administrateur.')}
                  {status === 'rejected' && 'Votre demande a été rejetée. Contactez votre administrateur.'}
                </span>
              </div>
            )}

            {status === 'approved' && (
              <form onSubmit={handleSetPassword} className="space-y-4 border-t pt-4">
                <div className="space-y-1.5">
                  <Label htmlFor="fp-new">Nouveau mot de passe</Label>
                  <Input
                    id="fp-new"
                    type="password"
                    value={newPassword}
                    onChange={(e) => setNewPassword(e.target.value)}
                    minLength={6}
                    disabled={loading}
                    required
                  />
                </div>
                <div className="space-y-1.5">
                  <Label htmlFor="fp-confirm">Confirmer</Label>
                  <Input
                    id="fp-confirm"
                    type="password"
                    value={confirm}
                    onChange={(e) => setConfirm(e.target.value)}
                    disabled={loading}
                    required
                  />
                </div>
                <Button type="submit" className="w-full" disabled={loading}>
                  {loading ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : null}
                  Définir le mot de passe
                </Button>
              </form>
            )}

            <button
              type="button"
              className="flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground"
              onClick={() => { setStep('request'); setStatus(null); }}
            >
              <ArrowLeft className="h-3.5 w-3.5" />
              Faire une nouvelle demande
            </button>
          </div>
        )}

        <p className="text-center text-sm text-muted-foreground">
          <Link href="/login" className="text-primary font-medium hover:underline">
            Retour à la connexion
          </Link>
        </p>
      </CardContent>
    </Card>
  );
}
