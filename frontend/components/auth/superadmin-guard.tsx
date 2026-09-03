'use client';

import { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { useCurrentUser } from '@/lib/auth/useCurrentUser';
import { Loader2, ShieldAlert } from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';

export function SuperAdminGuard({ children }: { children: React.ReactNode }) {
  const { user, loading, isSuperAdmin } = useCurrentUser();
  const router = useRouter();

  useEffect(() => {
    if (!loading && !isSuperAdmin) {
      router.push('/dashboard');
    }
  }, [loading, isSuperAdmin, router]);

  if (loading) {
    return (
      <div className="flex items-center justify-center h-screen">
        <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
      </div>
    );
  }

  if (!isSuperAdmin) {
    return (
      <div className="flex items-center justify-center h-screen p-6">
        <Card className="w-full max-w-md">
          <CardHeader className="text-center">
            <ShieldAlert className="h-12 w-12 mx-auto text-red-500 mb-2" />
            <CardTitle>Accès refusé</CardTitle>
          </CardHeader>
          <CardContent className="text-center text-muted-foreground">
            <p>Cette page est réservée au Super Administrateur.</p>
            <p className="text-sm mt-2">Redirection en cours…</p>
          </CardContent>
        </Card>
      </div>
    );
  }

  return <>{children}</>;
}
