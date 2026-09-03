'use client';

import { useEffect, useState, useCallback } from 'react';
import { djangoClient } from '@/lib/django-client';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Skeleton } from '@/components/ui/skeleton';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { toast } from 'sonner';
import { Inbox, RefreshCw, Check, X, Smartphone, Zap, Wallet, KeyRound } from 'lucide-react';

const STATUS_LABEL: Record<string, string> = {
  pending: 'En attente',
  approved: 'Approuvée',
  rejected: 'Rejetée',
};

const getStatusBadgeClass = (status: string) => {
  switch (status) {
    case 'approved': return 'bg-green-50 text-green-700';
    case 'rejected': return 'bg-red-50 text-red-700';
    default: return 'bg-orange-50 text-orange-700';
  }
};

const TYPE_LABEL: Record<string, string> = {
  device_deletion: "Suppression d'appareil",
  activation: "Activation d'abonnement",
  payment: "Paiement direct",
  password_reset: "Réinitialisation de mot de passe",
};

export default function LabelRequestsPage() {
  const [requests, setRequests] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [statusFilter, setStatusFilter] = useState('pending');
  const [resolving, setResolving] = useState<number | null>(null);

  const fetchData = useCallback(async () => {
    setLoading(true);
    try {
      const data = await djangoClient.platformAdmin.listRequests(
        statusFilter === 'all' ? undefined : statusFilter
      );
      setRequests(data);
    } catch (err) {
      console.error(err);
      toast.error('Erreur lors du chargement des demandes');
    } finally {
      setLoading(false);
    }
  }, [statusFilter]);

  useEffect(() => { fetchData(); }, [fetchData]);

  const handleResolve = async (id: number, action: 'approve' | 'reject') => {
    setResolving(id);
    try {
      await djangoClient.platformAdmin.resolveRequest(id, action);
      toast.success(action === 'approve' ? 'Demande approuvée' : 'Demande rejetée');
      fetchData();
    } catch (err: any) {
      toast.error(err.message || 'Erreur lors du traitement');
    } finally {
      setResolving(null);
    }
  };

  return (
    <div className="p-6 space-y-6">
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h1 className="text-2xl sm:text-3xl font-bold tracking-tight flex items-center gap-2">
            <Inbox className="h-7 w-7 text-blue-600" />Demandes
          </h1>
          <p className="text-muted-foreground mt-1 text-sm sm:text-base">
            Demandes de suppression d'appareil et d'activation soumises par les sociétés
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          <Select value={statusFilter} onValueChange={setStatusFilter}>
            <SelectTrigger className="w-44">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="pending">En attente</SelectItem>
              <SelectItem value="approved">Approuvées</SelectItem>
              <SelectItem value="rejected">Rejetées</SelectItem>
              <SelectItem value="all">Toutes</SelectItem>
            </SelectContent>
          </Select>
          <Button variant="outline" size="sm" onClick={fetchData} disabled={loading}>
            <RefreshCw className={`h-4 w-4 mr-2 ${loading ? 'animate-spin' : ''}`} />
            Actualiser
          </Button>
        </div>
      </div>

      {loading ? (
        <div className="space-y-2">{Array.from({ length: 4 }).map((_, i) => <Skeleton key={i} className="h-24 w-full" />)}</div>
      ) : requests.length === 0 ? (
        <Card>
          <CardContent className="py-12 text-center text-muted-foreground">
            Aucune demande {statusFilter !== 'all' ? STATUS_LABEL[statusFilter]?.toLowerCase() : ''}
          </CardContent>
        </Card>
      ) : (
        <div className="space-y-3">
          {requests.map((r) => (
            <Card key={r.id}>
              <CardContent className="py-4 flex flex-col sm:flex-row sm:items-center justify-between gap-3">
                <div className="flex items-start gap-3">
                  {r.request_type === 'device_deletion' ? (
                    <Smartphone className="h-5 w-5 text-blue-500 mt-0.5 shrink-0" />
                  ) : r.request_type === 'payment' ? (
                    <Wallet className="h-5 w-5 text-green-500 mt-0.5 shrink-0" />
                  ) : r.request_type === 'password_reset' ? (
                    <KeyRound className="h-5 w-5 text-violet-500 mt-0.5 shrink-0" />
                  ) : (
                    <Zap className="h-5 w-5 text-yellow-500 mt-0.5 shrink-0" />
                  )}
                  <div>
                    <p className="font-medium text-sm">
                      {TYPE_LABEL[r.request_type]} — <span className="text-blue-700">{r.company_name}</span>
                    </p>
                    <p className="text-xs text-muted-foreground">
                      Demandé par {r.requested_by_name} ({r.requested_by_email})
                    </p>
                    {r.device_info && (
                      <p className="text-xs text-muted-foreground font-mono mt-1">
                        {r.device_info.ip_address} — {r.device_info.user_agent}
                      </p>
                    )}
                    {r.request_type === 'payment' && (
                      <p className="text-xs text-muted-foreground mt-1">
                        Offre : {r.offer_name || '—'} · Moyen de paiement : {r.payment_method_label || '—'}
                        {r.payment_reference ? ` (${r.payment_reference})` : ''}
                        {r.contact_email ? ` · ${r.contact_email}` : ''}
                      </p>
                    )}
                    {r.note && <p className="text-xs text-muted-foreground mt-1">Note : {r.note}</p>}
                    <p className="text-xs text-muted-foreground mt-1">
                      {new Date(r.created_at).toLocaleString('fr-FR')}
                    </p>
                  </div>
                </div>
                <div className="flex items-center gap-2 shrink-0">
                  <Badge variant="outline" className={getStatusBadgeClass(r.status)}>
                    {STATUS_LABEL[r.status]}
                  </Badge>
                  {r.status === 'pending' && (
                    <>
                      <Button
                        size="sm"
                        variant="outline"
                        className="text-green-700 border-green-200"
                        disabled={resolving === r.id}
                        onClick={() => handleResolve(r.id, 'approve')}
                      >
                        <Check className="h-4 w-4 mr-1" />Approuver
                      </Button>
                      <Button
                        size="sm"
                        variant="outline"
                        className="text-red-700 border-red-200"
                        disabled={resolving === r.id}
                        onClick={() => handleResolve(r.id, 'reject')}
                      >
                        <X className="h-4 w-4 mr-1" />Rejeter
                      </Button>
                    </>
                  )}
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </div>
  );
}
