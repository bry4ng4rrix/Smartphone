import { Suspense } from 'react';
import { ResetPasswordForm } from '@/components/auth/reset-password-form';
import { Loader2 } from 'lucide-react';

export const metadata = {
  title: 'Réinitialiser le mot de passe - E-kajy Entana',
};

function ResetPasswordFallback() {
  return (
    <div className="w-full max-w-md p-8 text-center bg-card rounded-lg shadow-xl border">
      <Loader2 className="mx-auto h-8 w-8 animate-spin text-primary mb-4" />
      <p className="text-muted-foreground">Chargement...</p>
    </div>
  );
}

export default function ResetPasswordPage() {
  return (
    <div className="min-h-screen flex items-center justify-center bg-linear-to-br from-background to-muted p-4">
      <Suspense fallback={<ResetPasswordFallback />}>
        <ResetPasswordForm />
      </Suspense>
    </div>
  );
}
