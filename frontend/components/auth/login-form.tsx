'use client';

import { useEffect, useState } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import Link from 'next/link';
import { djangoClient } from '@/lib/django-client';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { toast } from 'sonner';
import { Loader2, Mail, Lock, Eye, EyeOff } from 'lucide-react';

const ERRORS: Record<string, string> = {
  'Invalid login credentials':    'Email ou mot de passe incorrect.',
  'No active account found':      'Email ou mot de passe incorrect.',
  'Email not confirmed':          'Compte non confirmé. Contactez l\'administrateur.',
  'Compte non approuvé':          'Compte en attente d\'approbation. Contactez votre administrateur.',
  'User not found':               'Aucun compte avec cet email.',
  'Too many requests':            'Trop de tentatives. Attendez quelques minutes.',
  'Account pending approval':     'Compte en attente d\'approbation. Contactez votre manager.',
  'Account rejected':             'Compte rejeté. Contactez votre manager.',
  'Authentication failed':        'Email ou mot de passe incorrect.',
};

function friendlyError(msg: string) {
  for (const [key, val] of Object.entries(ERRORS)) {
    if (msg.includes(key)) return val;
  }
  return msg;
}

export function LoginForm() {
  const router = useRouter();
  const searchParams = useSearchParams();

  const [email, setEmail]       = useState('');
  const [password, setPassword] = useState('');
  const [showPw, setShowPw]     = useState(false);
  const [loading, setLoading]   = useState(false);

  useEffect(() => {
    const prefill = searchParams.get('email');
    if (prefill) setEmail(prefill);
  }, [searchParams]);

  const goTo = (path: string) => {
    router.push(path);
  };

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);

    try {
      const response = await djangoClient.auth.login(email, password);

      if (!response.user.is_confirmed) {
        toast.error(ERRORS['Account pending approval']);
        setLoading(false);
        return;
      }

      toast.success('Connexion réussie !');
      const rawRole = (response.user as any).raw_role;
      // Le tableau de bord est réservé au gérant (admin/magasin) — les
      // autres rôles (préparateur/livreur) démarrent sur Commandes, la page
      // qui s'adapte déjà à leur rôle (Dépôt / Ma tournée).
      const isGerant = rawRole === 'admin' || rawRole === 'magasin';
      const destination = rawRole === 'platform_admin' ? '/label' : isGerant ? '/dashboard' : '/orders';

      // L'appareil est enregistré automatiquement côté backend (nouveau ou
      // déjà connu) — seule une limite d'appareils dépassée bloque la
      // connexion (voir le catch ci-dessous), pas besoin de confirmation ici.
      goTo(destination);
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : 'Erreur de connexion';
      if (errorMsg.includes('Limite d\'appareils atteinte')) {
        toast.error(errorMsg, { duration: 8000 });
        setLoading(false);
        return;
      }
      toast.error(friendlyError(errorMsg));
    } finally {
      setLoading(false);
    }
  };

  return (
    <Card className="w-full max-w-md shadow-xl">
      <CardHeader className="space-y-1 pb-4">
        <CardTitle className="text-2xl font-bold">Connexion</CardTitle>
        <CardDescription>Accédez à votre espace E-kajy Entana</CardDescription>
      </CardHeader>

      <CardContent>
        <form onSubmit={handleLogin} className="space-y-4" noValidate>
          {/* Email */}
          <div className="space-y-1.5">
            <label htmlFor="login-email" className="text-sm font-medium">
              Email
            </label>
            <div className="relative">
              <Mail className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground pointer-events-none" />
              <Input
                id="login-email"
                type="email"
                autoComplete="email"
                placeholder="vous@example.com"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                disabled={loading}
                className="pl-10"
                required
              />
            </div>
          </div>

          {/* Password */}
          <div className="space-y-1.5">
            <div className="flex items-center justify-between">
              <label htmlFor="login-password" className="text-sm font-medium">
                Mot de passe
              </label>
              <Link href="/forgot-password" className="text-xs text-primary hover:underline">
                Mot de passe oublié ?
              </Link>
            </div>
            <div className="relative">
              <Lock className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground pointer-events-none" />
              <Input
                id="login-password"
                type={showPw ? 'text' : 'password'}
                autoComplete="current-password"
                placeholder="••••••••"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                disabled={loading}
                className="pl-10 pr-10"
                required
              />
              <button
                type="button"
                onClick={() => setShowPw((v) => !v)}
                className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground"
                tabIndex={-1}
                aria-label={showPw ? 'Masquer le mot de passe' : 'Afficher le mot de passe'}
              >
                {showPw ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
              </button>
            </div>
          </div>

          <Button type="submit" className="w-full" disabled={loading}>
            {loading ? (
              <>
                <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                Connexion…
              </>
            ) : (
              'Se connecter'
            )}
          </Button>
        </form>

        <p className="mt-5 text-center text-sm text-muted-foreground">
          Pas encore de compte?{' '}
          <Link href="/register" className="text-primary font-medium hover:underline">
            Créer un compte
          </Link>
        </p>
      </CardContent>
    </Card>
  );
}
