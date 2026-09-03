import { Suspense } from 'react';
import { SubscriptionExpiredContent } from '@/components/auth/subscription-expired-content';

export const metadata = {
  title: 'Abonnement expiré - E-kajy Entana',
};

export default function SubscriptionExpiredPage() {
  return (
    <Suspense fallback={null}>
      <SubscriptionExpiredContent />
    </Suspense>
  );
}
