'use client';

import { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { Sidebar } from '@/components/layout/sidebar';
import { TopBar } from '@/components/layout/topbar';
import { djangoClient } from '@/lib/django-client';
import { DataSyncProvider } from '@/lib/contexts/DataSyncContext';

export default function AppLayout({ children }: { children: React.ReactNode }) {
  const router = useRouter();

  useEffect(() => {
    if (!djangoClient.isAuthenticated()) {
      router.replace('/login');
    }
  }, [router]);

  return (
    <DataSyncProvider>
      <div className="flex h-screen bg-background">
        <Sidebar />
        <div className="flex-1 flex flex-col overflow-hidden">
          <TopBar />
          <main className="flex-1 overflow-auto">
            {children}
          </main>
        </div>
      </div>
    </DataSyncProvider>
  );
}
