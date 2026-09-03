'use client';

import { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { useCurrentUser } from '@/lib/auth/useCurrentUser';
import { LabelSidebar } from '@/components/layout/label-sidebar';
import { Loader2 } from 'lucide-react';

export default function LabelLayout({ children }: { children: React.ReactNode }) {
  const { user, loading, isPlatformOwner } = useCurrentUser();
  const router = useRouter();

  useEffect(() => {
    if (loading) return;
    if (!user) {
      router.replace('/login');
      return;
    }
    if (!isPlatformOwner) {
      router.replace('/dashboard');
    }
  }, [loading, user, isPlatformOwner, router]);

  if (loading || !isPlatformOwner) {
    return (
      <div className="flex items-center justify-center h-screen">
        <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
      </div>
    );
  }

  return (
    <div className="flex min-h-screen bg-background">
      <LabelSidebar />
      <main className="flex-1 overflow-y-auto">{children}</main>
    </div>
  );
}
