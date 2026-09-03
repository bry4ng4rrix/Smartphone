'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { djangoClient } from '@/lib/django-client';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { RadioGroup, RadioGroupItem } from '@/components/ui/radio-group';
import { Label } from '@/components/ui/label';
import { toast } from 'sonner';
import { Loader2, Mail, Lock, User, Eye, EyeOff, Building2 } from 'lucide-react';

const ERRORS: Record<string, string> = {
  'User already registered':       'Un compte existe déjà avec cet email.',
  'Password should be at least':   'Le mot de passe doit contenir au moins 6 caractères.',
  'Unable to validate email':      'Adresse email invalide.',
  'Too many requests':             'Trop de tentatives. Attendez quelques minutes.',
};

function friendlyError(msg: string) {
  for (const [key, val] of Object.entries(ERRORS)) {
    if (msg.includes(key)) return val;
  }
  return msg;
}

export function RegisterForm() {
  const router = useRouter();
  const [fullName, setFullName] = useState('');
  const [username, setUsername] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [companyName, setCompanyName] = useState('');
  const [shopName, setShopName] = useState('');
  const [adminEmail, setAdminEmail] = useState('');
  const [position, setPosition] = useState('');
  const [showPw, setShowPw] = useState(false);
  const [loading, setLoading] = useState(false);
  const [role, setRole] = useState<'admin' | 'store_manager' | 'employee'>('employee');

  const handleRegister = async (e: React.FormEvent) => {
    e.preventDefault();

    if (!fullName.trim()) {
      toast.error('Le nom complet est requis.');
      return;
    }

    if (password.length < 6) {
      toast.error('Le mot de passe doit contenir au moins 6 caractères.');
      return;
    }

    if (role === 'admin' && !companyName.trim()) {
      toast.error("Le nom de l'entreprise est requis.");
      return;
    }

    if (role === 'store_manager') {
      if (!shopName.trim()) {
        toast.error('Le nom du magasin est requis.');
        return;
      }
      if (!adminEmail.trim()) {
        toast.error("L'email de l'administrateur est requis.");
        return;
      }
    }

    if (role === 'employee') {
      if (!adminEmail.trim()) {
        toast.error("L'email du responsable est requis.");
        return;
      }
      if (!position.trim()) {
        toast.error('Le poste / fonction est requis.');
        return;
      }
    }

    setLoading(true);

    try {
      await djangoClient.auth.register(email, username || email.split('@')[0], password, role, {
        full_name: fullName,
        company_name: role === 'admin' ? companyName : undefined,
        shop_name: role === 'store_manager' ? shopName : undefined,
        admin_email: (role === 'store_manager' || role === 'employee') ? adminEmail : undefined,
        position: role === 'employee' ? position : undefined,
      });

      const msg =
        role === 'admin'
          ? 'Compte créé ! En attente d\'approbation.'
          : 'Compte créé ! En attente d\'approbation par un administrateur.';
      toast.success(msg);
      router.push('/auth/pending-approval');
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : 'Erreur lors de l\'inscription';
      toast.error(friendlyError(errorMsg));
    } finally {
      setLoading(false);
    }
  };

  return (
    <Card className="w-full max-w-md shadow-xl border-t-4 border-t-primary">
      <CardHeader className="space-y-1 pb-4">
        <CardTitle className="text-2xl font-bold">Créer un compte</CardTitle>
        <CardDescription>Rejoignez E-kajy Entana</CardDescription>
      </CardHeader>

      <CardContent>
        <form onSubmit={handleRegister} className="space-y-4" noValidate>
          {/* Role Selection */}
          <div className="space-y-2">
            <Label className="text-sm font-medium">Type de compte</Label>
            <RadioGroup
              value={role}
              onValueChange={(v) => setRole(v as 'admin' | 'store_manager' | 'employee')}
              className="grid grid-cols-3 gap-2"
            >
              <div
                className={`flex items-center space-x-2 border rounded-lg p-2 cursor-pointer transition-colors ${
                  role === 'admin' ? 'border-blue-500 bg-blue-50 dark:bg-blue-950/30' : 'hover:bg-muted/50'
                }`}
              >
                <RadioGroupItem value="admin" id="admin" />
                <Label htmlFor="admin" className="cursor-pointer text-xs font-semibold">
                  Admin
                </Label>
              </div>
              <div
                className={`flex items-center space-x-2 border rounded-lg p-2 cursor-pointer transition-colors ${
                  role === 'store_manager' ? 'border-cyan-500 bg-cyan-50 dark:bg-cyan-950/30' : 'hover:bg-muted/50'
                }`}
              >
                <RadioGroupItem value="store_manager" id="store_manager" />
                <Label htmlFor="store_manager" className="cursor-pointer text-xs font-semibold">
                  Manager
                </Label>
              </div>
              <div
                className={`flex items-center space-x-2 border rounded-lg p-2 cursor-pointer transition-colors ${
                  role === 'employee' ? 'border-green-500 bg-green-50 dark:bg-green-950/30' : 'hover:bg-muted/50'
                }`}
              >
                <RadioGroupItem value="employee" id="employee" />
                <Label htmlFor="employee" className="cursor-pointer text-xs font-semibold">
                  Employé
                </Label>
              </div>
            </RadioGroup>
          </div>

          {/* Full Name */}
          <div className="space-y-1.5">
            <label htmlFor="reg-fullname" className="text-sm font-medium">
              Nom complet <span className="text-destructive">*</span>
            </label>
            <div className="relative">
              <User className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground pointer-events-none" />
              <Input
                id="reg-fullname"
                type="text"
                placeholder="Jean Dupont"
                value={fullName}
                onChange={(e) => setFullName(e.target.value)}
                disabled={loading}
                className="pl-10"
                required
              />
            </div>
          </div>

          {/* Dynamic Role Fields */}
          {role === 'admin' && (
            <div className="space-y-1.5 animate-in fade-in duration-200">
              <label htmlFor="reg-companyname" className="text-sm font-medium">
                Nom de l&apos;entreprise <span className="text-destructive">*</span>
              </label>
              <div className="relative">
                <Building2 className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground pointer-events-none" />
                <Input
                  id="reg-companyname"
                  type="text"
                  placeholder="Ma Super Entreprise"
                  value={companyName}
                  onChange={(e) => setCompanyName(e.target.value)}
                  disabled={loading}
                  className="pl-10"
                  required
                />
              </div>
            </div>
          )}

          {role === 'store_manager' && (
            <div className="space-y-4 animate-in fade-in duration-200">
              <div className="space-y-1.5">
                <label htmlFor="reg-shopname" className="text-sm font-medium">
                  Nom du magasin <span className="text-destructive">*</span>
                </label>
                <div className="relative">
                  <Building2 className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground pointer-events-none" />
                  <Input
                    id="reg-shopname"
                    type="text"
                    placeholder="Boutique Centre-Ville"
                    value={shopName}
                    onChange={(e) => setShopName(e.target.value)}
                    disabled={loading}
                    className="pl-10"
                    required
                  />
                </div>
              </div>
              <div className="space-y-1.5">
                <label htmlFor="reg-adminemail" className="text-sm font-medium">
                  Email de l&apos;administrateur <span className="text-destructive">*</span>
                </label>
                <div className="relative">
                  <Mail className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground pointer-events-none" />
                  <Input
                    id="reg-adminemail"
                    type="email"
                    placeholder="admin@boutique.com"
                    value={adminEmail}
                    onChange={(e) => setAdminEmail(e.target.value)}
                    disabled={loading}
                    className="pl-10"
                    required
                  />
                </div>
              </div>
            </div>
          )}

          {role === 'employee' && (
            <div className="space-y-4 animate-in fade-in duration-200">
              <div className="space-y-1.5">
                <label htmlFor="reg-manageremail" className="text-sm font-medium">
                  Email du responsable (Admin ou Gérant) <span className="text-destructive">*</span>
                </label>
                <div className="relative">
                  <Mail className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground pointer-events-none" />
                  <Input
                    id="reg-manageremail"
                    type="email"
                    placeholder="gerant@boutique.com"
                    value={adminEmail}
                    onChange={(e) => setAdminEmail(e.target.value)}
                    disabled={loading}
                    className="pl-10"
                    required
                  />
                </div>
              </div>
              <div className="space-y-1.5">
                <label htmlFor="reg-position" className="text-sm font-medium">
                  Poste / Fonction <span className="text-destructive">*</span>
                </label>
                <div className="relative">
                  <User className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground pointer-events-none" />
                  <Input
                    id="reg-position"
                    type="text"
                    placeholder="Caissier, Vendeur..."
                    value={position}
                    onChange={(e) => setPosition(e.target.value)}
                    disabled={loading}
                    className="pl-10"
                    required
                  />
                </div>
              </div>
            </div>
          )}

          {/* Username */}
          <div className="space-y-1.5">
            <label htmlFor="reg-username" className="text-sm font-medium">
              Nom d&apos;utilisateur <span className="text-muted-foreground text-xs">(Optionnel)</span>
            </label>
            <div className="relative">
              <User className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground pointer-events-none" />
              <Input
                id="reg-username"
                type="text"
                autoComplete="username"
                placeholder="jean_dupont"
                value={username}
                onChange={(e) => setUsername(e.target.value)}
                disabled={loading}
                className="pl-10"
              />
            </div>
          </div>

          {/* Email */}
          <div className="space-y-1.5">
            <label htmlFor="reg-email" className="text-sm font-medium">
              Email <span className="text-destructive">*</span>
            </label>
            <div className="relative">
              <Mail className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground pointer-events-none" />
              <Input
                id="reg-email"
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
            <label htmlFor="reg-password" className="text-sm font-medium">
              Mot de passe <span className="text-destructive">*</span>
            </label>
            <div className="relative">
              <Lock className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground pointer-events-none" />
              <Input
                id="reg-password"
                type={showPw ? 'text' : 'password'}
                autoComplete="new-password"
                placeholder="••••••••"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                disabled={loading}
                className="pl-10 pr-10"
                required
                minLength={6}
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
            <p className="text-xs text-muted-foreground">Minimum 6 caractères</p>
          </div>

          <Button type="submit" className="w-full mt-2" disabled={loading}>
            {loading ? (
              <>
                <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                Création du compte…
              </>
            ) : (
              "S'inscrire"
            )}
          </Button>
        </form>

        <p className="mt-5 text-center text-sm text-muted-foreground">
          Déjà un compte?{' '}
          <Link href="/login" className="text-primary font-medium hover:underline">
            Se connecter
          </Link>
        </p>
      </CardContent>
    </Card>
  );
}
