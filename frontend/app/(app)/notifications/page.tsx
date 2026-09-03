'use client';

import { useCallback, useEffect, useState } from 'react';
import { Trash2, Mail, CheckCheck, Loader2, AlertCircle } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Skeleton } from '@/components/ui/skeleton';
import { toast } from 'sonner';
import { djangoClient } from '@/lib/django-client';
import { useNotificationsWebSocket } from '@/lib/hooks/useNotificationsWebSocket';
import {
  typeIcon,
  typeLabel,
  formatNotificationDate,
  getTypeBadgeClass,
  getNotificationCardClass,
  getSocketStatusBadgeClass,
} from '@/lib/notifications-utils';

export default function NotificationsPage() {
  const [notifications, setNotifications] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [actionLoading, setActionLoading] = useState(false);

  const fetchNotifications = useCallback(async () => {
    try {
      setLoading(true);
      const data = (await djangoClient.notifications.list()) as any;
      setNotifications(Array.isArray(data) ? data : data.results || []);
    } catch (error: any) {
      console.error('Notifications error:', error);
      toast.error('Impossible de charger les notifications.');
    } finally {
      setLoading(false);
    }
  }, []);

  const handleNewNotification = useCallback((newNotif: any) => {
    setNotifications((prev) => {
      if (prev.some((n) => n.id === newNotif.id)) return prev;
      toast.info(newNotif.message, {
        description: `Type : ${typeLabel(newNotif.notif_type)}`,
        duration: 5000,
      });
      return [newNotif, ...prev];
    });
  }, []);

  const { socketStatus } = useNotificationsWebSocket({
    onNotification: handleNewNotification,
    showToast: false,
  });

  useEffect(() => {
    fetchNotifications();
  }, [fetchNotifications]);

  const toggleRead = async (notification: any) => {
    try {
      setActionLoading(true);
      await djangoClient.notifications.markRead(notification.id, !notification.is_read);
      toast.success(notification.is_read ? 'Notification marquée non lue' : 'Notification marquée lue');
      await fetchNotifications();
    } catch {
      toast.error('Impossible de mettre à jour la notification.');
    } finally {
      setActionLoading(false);
    }
  };

  const markAllRead = async () => {
    try {
      setActionLoading(true);
      await djangoClient.notifications.markAllRead();
      toast.success('Toutes les notifications ont été marquées comme lues.');
      await fetchNotifications();
    } catch {
      toast.error('Impossible de marquer toutes les notifications comme lues.');
    } finally {
      setActionLoading(false);
    }
  };

  const clearAll = async () => {
    try {
      setActionLoading(true);
      await djangoClient.notifications.deleteAll();
      toast.success('Toutes les notifications ont été supprimées.');
      setNotifications([]);
    } catch {
      toast.error('Impossible de supprimer les notifications.');
    } finally {
      setActionLoading(false);
    }
  };

  const deleteNotification = async (id: number) => {
    try {
      setActionLoading(true);
      await djangoClient.notifications.delete(id);
      setNotifications((prev) => prev.filter((n) => n.id !== id));
      toast.success('Notification supprimée.');
    } catch {
      toast.error('Impossible de supprimer la notification.');
    } finally {
      setActionLoading(false);
    }
  };

  return (
    <div className="p-4 sm:p-6 space-y-6">
      <div className="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
        <div>
          <h1 className="text-2xl sm:text-3xl font-bold tracking-tight">Notifications</h1>
          <div className="flex flex-wrap items-center gap-2 mt-1">
            <p className="text-muted-foreground text-sm">
              Toutes les alertes et mouvements enregistrés de l&apos;application.
            </p>
            <Badge variant="outline" className={`text-[10px] flex items-center gap-1.5 rounded-full py-0.5 px-2.5 ${getSocketStatusBadgeClass(socketStatus)}`}>
              {socketStatus === 'connected' ? (
                <>
                  <span className="relative flex h-2 w-2">
                    <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75" />
                    <span className="relative inline-flex rounded-full h-2 w-2 bg-emerald-500" />
                  </span>
                  Temps réel
                </>
              ) : socketStatus === 'connecting' ? (
                <>
                  <Loader2 className="h-3 w-3 animate-spin" />
                  Connexion...
                </>
              ) : (
                <>
                  <AlertCircle className="h-3 w-3" />
                  Déconnecté
                </>
              )}
            </Badge>
          </div>
        </div>

        <div className="flex flex-wrap gap-2">
          <Button variant="outline" size="sm" onClick={fetchNotifications} disabled={loading || actionLoading}>
            Actualiser
          </Button>
          <Button variant="secondary" size="sm" onClick={markAllRead} disabled={loading || actionLoading || notifications.length === 0}>
            Marquer tout lu
          </Button>
          <Button variant="destructive" size="sm" onClick={clearAll} disabled={loading || actionLoading || notifications.length === 0}>
            Supprimer tout
          </Button>
        </div>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Historique des notifications</CardTitle>
        </CardHeader>
        <CardContent>
          {loading ? (
            <div className="space-y-3">
              {Array.from({ length: 5 }).map((_, index) => (
                <Skeleton key={index} className="h-20 w-full rounded-lg" />
              ))}
            </div>
          ) : notifications.length === 0 ? (
            <div className="py-16 text-center text-muted-foreground">
              Aucune notification pour le moment.
            </div>
          ) : (
            <div className="space-y-3">
              {notifications.map((notification) => (
                <div
                  key={notification.id}
                  className={`rounded-xl border p-4 transition-all duration-300 ${getNotificationCardClass(notification.is_read)}`}
                >
                  <div className="flex flex-col gap-3 md:flex-row md:items-start md:justify-between">
                    <div className="flex items-start gap-3 min-w-0">
                      <div className="mt-1 flex h-9 w-9 items-center justify-center rounded-full bg-primary/10 text-primary shrink-0">
                        {typeIcon(notification.notif_type)}
                      </div>
                      <div className="min-w-0">
                        <div className="flex flex-wrap items-center gap-2 text-sm font-medium">
                          <span className="break-words">{notification.message}</span>
                          <Badge variant="outline" className={getTypeBadgeClass(notification.notif_type)}>
                            {typeLabel(notification.notif_type)}
                          </Badge>
                          {!notification.is_read && (
                            <Badge className="bg-primary/15 text-primary hover:bg-primary/20">
                              Nouveau
                            </Badge>
                          )}
                        </div>
                        <p className="text-xs text-muted-foreground mt-2 break-words">
                          {notification.product_name ? `Produit : ${notification.product_name}` : notification.sale_id ? `Vente #${notification.sale_id}` : notification.user_name ? `Utilisateur : ${notification.user_name}` : ''}
                          {notification.magasin_name ? ` · Magasin : ${notification.magasin_name}` : ''}
                          {notification.created_at ? ` · ${formatNotificationDate(notification.created_at)}` : ''}
                        </p>
                      </div>
                    </div>
                    <div className="flex flex-wrap gap-2 shrink-0">
                      <Button
                        size="icon"
                        variant="outline"
                        onClick={() => toggleRead(notification)}
                        disabled={actionLoading}
                      >
                        {notification.is_read ? (
                          <Mail className="h-4 w-4" />
                        ) : (
                          <CheckCheck className="h-4 w-4" />
                        )}
                      </Button>

                      <Button
                        size="icon"
                        variant="destructive"
                        onClick={() => deleteNotification(notification.id)}
                        disabled={actionLoading}
                      >
                        <Trash2 className="h-4 w-4" />
                      </Button>
                    </div>
                  </div>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
