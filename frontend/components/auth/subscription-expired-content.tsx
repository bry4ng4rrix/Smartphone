'use client';

import { useEffect, useState } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import Link from 'next/link';
import { djangoClient } from '@/lib/django-client';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { RadioGroup, RadioGroupItem } from '@/components/ui/radio-group';
import { Skeleton } from '@/components/ui/skeleton';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { toast } from 'sonner';
import {
  AlertTriangle,
  Mail,
  Wallet,
  ArrowLeft,
  ArrowRight,
  Loader2,
  CheckCircle2,
  Smartphone,
  CreditCard,
  Globe,
  Building2,
  UserRound,
  Clock,
} from 'lucide-react';

const SUPPORT_EMAIL = 'contact@labeltechnology.mg';

const PAYMENT_METHODS: { value: 'mvola' | 'paypal' | 'visa' | 'mastercard'; label: string; icon: any }[] = [
  { value: 'mvola', label: 'MVola', icon: Smartphone },
  { value: 'paypal', label: 'PayPal', icon: Globe },
  { value: 'visa', label: 'Visa', icon: CreditCard },
  { value: 'mastercard', label: 'Mastercard', icon: CreditCard },
];

// Each payment method asks for its own reference — never a full card number
// or CVV, since there is no real PCI-compliant gateway behind this yet.
const REFERENCE_FIELD: Record<string, { label: string; type: string; placeholder: string }> = {
  mvola: { label: 'Numéro de téléphone MVola', type: 'tel', placeholder: '034 XX XXX XX' },
  paypal: { label: 'Email PayPal', type: 'email', placeholder: 'vous@paypal.com' },
  visa: { label: 'Nom du titulaire de la carte', type: 'text', placeholder: 'NOM Prénom' },
  mastercard: { label: 'Nom du titulaire de la carte', type: 'text', placeholder: 'NOM Prénom' },
};

// Minimum time the "processing" screen stays visible, so the simulated
// confirmation feels real instead of flashing instantly.
const MIN_PROCESSING_MS = 1800;
const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

type Step = 'offer' | 'login' | 'method' | 'processing' | 'success';

type Identity = {
  email: string;
  full_name: string;
  role: string;
  is_admin: boolean;
  company_name: string;
};

export function SubscriptionExpiredContent() {
  const router = useRouter();
  const searchParams = useSearchParams();

  const [dialogOpen, setDialogOpen] = useState(false);
  const [step, setStep] = useState<Step>('offer');

  const [offers, setOffers] = useState<any[]>([]);
  const [offersLoading, setOffersLoading] = useState(false);
  const [selectedOfferId, setSelectedOfferId] = useState<string>('');

  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [verifying, setVerifying] = useState(false);
  const [identity, setIdentity] = useState<Identity | null>(null);

  const [paymentMethod, setPaymentMethod] = useState<string>('');
  const [paymentReference, setPaymentReference] = useState('');
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    const prefill = searchParams.get('email');
    if (prefill) setEmail(prefill);
  }, [searchParams]);

  const openDialog = async () => {
    setStep('offer');
    setIdentity(null);
    setPassword('');
    setPaymentMethod('');
    setPaymentReference('');
    setDialogOpen(true);
    if (offers.length === 0) {
      setOffersLoading(true);
      try {
        const data = await djangoClient.public.listOffers();
        setOffers(data);
      } catch (err) {
        console.error(err);
        toast.error('Erreur lors du chargement des offres');
      } finally {
        setOffersLoading(false);
      }
    }
  };

  const handleVerify = async () => {
    if (!email.trim() || !password) {
      toast.error('Veuillez indiquer votre email et votre mot de passe.');
      return;
    }
    setVerifying(true);
    try {
      const data = await djangoClient.public.verifyAccount({ email: email.trim(), password });
      setIdentity(data);
      setStep('method');
    } catch (err: any) {
      toast.error(err.message || 'Erreur lors de la vérification du compte');
    } finally {
      setVerifying(false);
    }
  };

  const handleSubmit = async () => {
    if (!identity) return;
    if (!paymentMethod) {
      toast.error('Veuillez choisir un moyen de paiement.');
      return;
    }
    if (!paymentReference.trim()) {
      toast.error(`Veuillez indiquer : ${REFERENCE_FIELD[paymentMethod].label.toLowerCase()}`);
      return;
    }

    setSubmitting(true);
    setStep('processing');
    try {
      await Promise.all([
        djangoClient.public.createPaymentRequest({
          email: email.trim(),
          password,
          offer_id: Number(selectedOfferId),
          payment_method: paymentMethod as any,
          payment_reference: paymentReference.trim(),
        }),
        sleep(MIN_PROCESSING_MS),
      ]);

      setStep('success');
      setTimeout(() => {
        router.push(`/login?email=${encodeURIComponent(email.trim())}`);
      }, 1800);
    } catch (err: any) {
      toast.error(err.message || "Erreur lors de l'envoi de la demande");
      setStep('method');
    } finally {
      setSubmitting(false);
    }
  };

  const selectedOffer = offers.find((o) => String(o.id) === selectedOfferId);

  return (
    <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-background to-muted p-4">
      <Card className="w-full max-w-md shadow-xl border-orange-200">
        <CardHeader className="text-center space-y-3">
          <div className="mx-auto w-14 h-14 rounded-full bg-orange-100 flex items-center justify-center">
            <AlertTriangle className="h-7 w-7 text-orange-600" />
          </div>
          <CardTitle className="text-2xl">Votre abonnement a expiré</CardTitle>
          <CardDescription>
            L'accès à votre espace est temporairement suspendu. Contactez Label Technology pour
            réactiver votre abonnement, ou réglez directement votre facture ci-dessous.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <a
            href={`mailto:${SUPPORT_EMAIL}`}
            className="flex items-center gap-3 p-3 border rounded-lg hover:bg-muted transition-colors"
          >
            <Mail className="h-5 w-5 text-blue-600 shrink-0" />
            <div>
              <p className="text-sm font-medium">Contacter Label Technology</p>
              <p className="text-sm text-muted-foreground">{SUPPORT_EMAIL}</p>
            </div>
          </a>

          <button
            type="button"
            onClick={openDialog}
            className="w-full flex items-start gap-3 p-3 border rounded-lg hover:bg-muted transition-colors text-left"
          >
            <Wallet className="h-5 w-5 text-green-600 shrink-0 mt-0.5" />
            <div>
              <p className="text-sm font-medium">Paiement direct</p>
              <p className="text-sm text-muted-foreground">
                Choisissez une offre et payez par MVola, PayPal, Visa ou Mastercard.
              </p>
            </div>
          </button>

          <Button asChild variant="outline" className="w-full">
            <Link href="/login">
              <ArrowLeft className="h-4 w-4 mr-2" />
              Retour à la connexion
            </Link>
          </Button>
        </CardContent>
      </Card>

      <Dialog
        open={dialogOpen}
        onOpenChange={(open) => {
          if (step === 'processing' || step === 'success') return;
          setDialogOpen(open);
        }}
      >
        <DialogContent className="sm:max-w-md">
          {step === 'offer' && (
            <>
              <DialogHeader>
                <DialogTitle>Choisissez une offre</DialogTitle>
                <DialogDescription>
                  Sélectionnez l'abonnement que vous souhaitez activer.
                </DialogDescription>
              </DialogHeader>
              {offersLoading ? (
                <div className="space-y-2">
                  {Array.from({ length: 3 }).map((_, i) => (
                    <Skeleton key={i} className="h-16 w-full" />
                  ))}
                </div>
              ) : offers.length === 0 ? (
                <p className="text-sm text-muted-foreground py-6 text-center">
                  Aucune offre disponible pour le moment. Contactez {SUPPORT_EMAIL}.
                </p>
              ) : (
                <RadioGroup value={selectedOfferId} onValueChange={setSelectedOfferId} className="space-y-2">
                  {offers.map((o) => (
                    <label
                      key={o.id}
                      htmlFor={`offer-${o.id}`}
                      className="flex items-center justify-between gap-3 border rounded-lg p-3 cursor-pointer hover:bg-muted has-[[data-state=checked]]:border-blue-500 has-[[data-state=checked]]:bg-blue-50/50"
                    >
                      <div className="flex items-center gap-3">
                        <RadioGroupItem value={String(o.id)} id={`offer-${o.id}`} />
                        <div>
                          <p className="text-sm font-medium">{o.name}</p>
                          <p className="text-xs text-muted-foreground">
                            {o.max_devices} appareil(s) connecté(s) · {o.duration_months} mois
                          </p>
                        </div>
                      </div>
                      <span className="text-sm font-semibold whitespace-nowrap">{o.price}</span>
                    </label>
                  ))}
                </RadioGroup>
              )}
              <DialogFooter>
                <Button variant="outline" onClick={() => setDialogOpen(false)}>
                  Annuler
                </Button>
                <Button disabled={!selectedOfferId} onClick={() => setStep('login')}>
                  Continuer
                  <ArrowRight className="h-4 w-4 ml-2" />
                </Button>
              </DialogFooter>
            </>
          )}

          {step === 'login' && (
            <>
              <DialogHeader>
                <DialogTitle>Identifiez votre compte</DialogTitle>
                <DialogDescription>
                  {selectedOffer ? `Offre sélectionnée : ${selectedOffer.name} (${selectedOffer.price})` : ''}
                  {' '}Connectez-vous pour continuer le paiement.
                </DialogDescription>
              </DialogHeader>
              <div className="space-y-3">
                <div className="space-y-1.5">
                  <Label>Email</Label>
                  <Input
                    type="email"
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    placeholder="vous@example.com"
                    onKeyDown={(e) => e.key === 'Enter' && handleVerify()}
                  />
                </div>
                <div className="space-y-1.5">
                  <Label>Mot de passe</Label>
                  <Input
                    type="password"
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    placeholder="••••••••"
                    onKeyDown={(e) => e.key === 'Enter' && handleVerify()}
                  />
                </div>
              </div>
              <DialogFooter>
                <Button variant="outline" onClick={() => setStep('offer')}>
                  <ArrowLeft className="h-4 w-4 mr-2" />
                  Retour
                </Button>
                <Button onClick={handleVerify} disabled={verifying}>
                  {verifying ? 'Vérification...' : 'Continuer'}
                </Button>
              </DialogFooter>
            </>
          )}

          {step === 'method' && identity && (
            <>
              <DialogHeader>
                <DialogTitle>Moyen de paiement</DialogTitle>
                <DialogDescription>
                  {selectedOffer ? `Offre sélectionnée : ${selectedOffer.name} (${selectedOffer.price})` : ''}
                </DialogDescription>
              </DialogHeader>

              <div className="flex items-center gap-3 border rounded-lg p-3 bg-muted/40">
                <div className="w-9 h-9 rounded-full bg-blue-100 flex items-center justify-center shrink-0">
                  <UserRound className="h-4 w-4 text-blue-600" />
                </div>
                <div className="min-w-0">
                  <p className="text-sm font-medium truncate">{identity.full_name}</p>
                  <p className="text-xs text-muted-foreground flex items-center gap-1 truncate">
                    <Building2 className="h-3 w-3 shrink-0" />
                    {identity.company_name}
                  </p>
                </div>
              </div>

              {identity.is_admin ? (
                <div className="space-y-3">
                  <div className="space-y-1.5">
                    <Label>Payer avec</Label>
                    <RadioGroup
                      value={paymentMethod}
                      onValueChange={(v) => {
                        setPaymentMethod(v);
                        setPaymentReference('');
                      }}
                      className="grid grid-cols-2 gap-2"
                    >
                      {PAYMENT_METHODS.map(({ value, label, icon: Icon }) => (
                        <label
                          key={value}
                          htmlFor={`pm-${value}`}
                          className="flex items-center gap-2 border rounded-lg p-3 cursor-pointer hover:bg-muted has-[[data-state=checked]]:border-blue-500 has-[[data-state=checked]]:bg-blue-50/50"
                        >
                          <RadioGroupItem value={value} id={`pm-${value}`} />
                          <Icon className="h-4 w-4 text-muted-foreground" />
                          <span className="text-sm">{label}</span>
                        </label>
                      ))}
                    </RadioGroup>
                  </div>

                  {paymentMethod && (
                    <div className="space-y-1.5">
                      <Label>{REFERENCE_FIELD[paymentMethod].label}</Label>
                      <Input
                        type={REFERENCE_FIELD[paymentMethod].type}
                        value={paymentReference}
                        onChange={(e) => setPaymentReference(e.target.value)}
                        placeholder={REFERENCE_FIELD[paymentMethod].placeholder}
                      />
                    </div>
                  )}
                </div>
              ) : (
                <div className="flex items-start gap-3 border border-orange-200 bg-orange-50/60 rounded-lg p-3">
                  <Clock className="h-5 w-5 text-orange-600 shrink-0 mt-0.5" />
                  <div>
                    <p className="text-sm font-medium text-orange-800">En attente d'un administrateur</p>
                    <p className="text-sm text-orange-700">
                      Seul un administrateur de {identity.company_name} peut effectuer ce paiement.
                      Merci de le contacter pour continuer.
                    </p>
                  </div>
                </div>
              )}

              <DialogFooter>
                <Button variant="outline" onClick={() => setStep('login')}>
                  <ArrowLeft className="h-4 w-4 mr-2" />
                  Retour
                </Button>
                {identity.is_admin && (
                  <Button onClick={handleSubmit} disabled={submitting || !paymentMethod || !paymentReference.trim()}>
                    Envoyer la demande de paiement
                  </Button>
                )}
              </DialogFooter>
            </>
          )}

          {step === 'processing' && (
            <div className="py-10 flex flex-col items-center text-center gap-3">
              <Loader2 className="h-10 w-10 text-blue-600 animate-spin" />
              <p className="font-medium">En attente de la confirmation de votre paiement…</p>
              <p className="text-sm text-muted-foreground">
                Validation automatique ou par Label Technology — merci de ne pas fermer cette fenêtre.
              </p>
            </div>
          )}

          {step === 'success' && (
            <div className="py-10 flex flex-col items-center text-center gap-3">
              <CheckCircle2 className="h-10 w-10 text-green-600" />
              <p className="font-medium">Paiement confirmé, votre abonnement a été réactivé !</p>
              <p className="text-sm text-muted-foreground">Redirection vers la connexion…</p>
            </div>
          )}
        </DialogContent>
      </Dialog>
    </div>
  );
}
