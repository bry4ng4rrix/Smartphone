'use client';

import { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { djangoClient } from '@/lib/django-client';

export default function LogoutPage() {
  const router = useRouter();

  useEffect(() => {
    djangoClient.auth.logout();
    router.push('/login');
    router.refresh();
  }, [router]);

  return (
    <div className="flex items-center justify-center min-h-screen">
      <p className="text-muted-foreground">Déconnexion...</p>
    </div>
  );
}
