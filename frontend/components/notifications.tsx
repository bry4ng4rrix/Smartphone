'use client';

import { useCallback, useEffect, useState } from 'react';
import Link from 'next/link';
import { Bell, Check, Trash2, Loader2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { ScrollArea } from '@/components/ui/scroll-area';
import { djangoClient } from '@/lib/django-client';
import { useNotificationsWebSocket } from '@/lib/hooks/useNotificationsWebSocket';
import {
  typeIcon,
  formatNotificationDate,
  getTypeBadgeClass,
  typeLabel,
} from '@/lib/notifications-utils';

// IDs "effacés" localement : la notification reste enregistrée en base,
// elle est seulement retirée de la liste récente du menu déroulant.
const DISMISSED_KEY = 'stockv2_dismissed_notification_ids';

const loadDismissed = (): number[] => {
  if (typeof window === 'undefined') return [];
  try {
    return JSON.parse(window.localStorage.getItem(DISMISSED_KEY) || '[]');
  } catch {
    return [];
  }
};

const saveDismissed = (ids: number[]) => {
  if (typeof window === 'undefined') return;
  window.localStorage.setItem(DISMISSED_KEY, JSON.stringify(ids.slice(-200)));
};

export function Notifications() {
  const [notifications, setNotifications] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [actionLoading, setActionLoading] = useState(false);

  const fetchNotifications = useCallback(async () => {
    try {
      const data = (await djangoClient.notifications.list()) as any;
      const list: any[] = Array.isArray(data) ? data : data.results || [];
      const dismissed = new Set(loadDismissed());
      setNotifications(list.filter((n) => !dismissed.has(n.id)));
    } catch (error) {
      console.error('Notifications error:', error);
    } finally {
      setLoading(false);
    }
  }, []);

  const handleNewNotification = useCallback((newNotif: any) => {
    const dismissed = new Set(loadDismissed());
    if (dismissed.has(newNotif.id)) return;
    setNotifications((prev) => {
      if (prev.some((n) => n.id === newNotif.id)) return prev;
      return [newNotif, ...prev];
    });
  }, []);

  useNotificationsWebSocket({
    onNotification: handleNewNotification,
    showToast: true,
  });

  useEffect(() => {
    fetchNotifications();
  }, [fetchNotifications]);

  const unreadCount = notifications.filter((n) => !n.is_read).length;

  const markAsRead = async (id: number) => {
    try {
      await djangoClient.notifications.markRead(id, true);
      setNotifications((prev) =>
        prev.map((n) => (n.id === id ? { ...n, is_read: true } : n))
      );
    } catch (error) {
      console.error('Mark read error:', error);
    }
  };

  const markAllAsRead = async () => {
    if (unreadCount === 0 || actionLoading) return;
    try {
      setActionLoading(true);
      await djangoClient.notifications.markAllRead();
      setNotifications((prev) => prev.map((n) => ({ ...n, is_read: true })));
    } catch (error) {
      console.error('Mark all read error:', error);
    } finally {
      setActionLoading(false);
    }
  };

  const clearAll = () => {
    if (notifications.length === 0) return;
    // On efface uniquement la liste affichée ici : rien n'est supprimé en base.
    const dismissed = new Set(loadDismissed());
    notifications.forEach((n) => dismissed.add(n.id));
    saveDismissed(Array.from(dismissed));
    setNotifications([]);
  };

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="ghost" size="icon" className="relative">
          <Bell className="h-5 w-5" />
          {unreadCount > 0 && (
            <span className="absolute -top-0.5 -right-0.5 flex h-4 min-w-4 items-center justify-center rounded-full bg-destructive px-1 text-[10px] font-bold text-destructive-foreground">
              {unreadCount > 9 ? '9+' : unreadCount}
            </span>
          )}
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-96 p-0">
        <DropdownMenuLabel className="flex items-center justify-between px-4 py-3">
          <div className="flex items-center gap-2">
            <span className="font-semibold">Notifications</span>
            {unreadCount > 0 && (
              <Badge variant="secondary" className="text-[10px]">
                {unreadCount} non lue{unreadCount > 1 ? 's' : ''}
              </Badge>
            )}
          </div>
        </DropdownMenuLabel>

        {notifications.length > 0 && (
          <div className="flex items-center gap-1 border-b px-2 pb-2">
            <Button
              variant="ghost"
              size="sm"
              className="h-7 flex-1 gap-1.5 text-xs text-muted-foreground hover:text-foreground"
              disabled={unreadCount === 0 || actionLoading}
              onClick={markAllAsRead}
            >
              <Check className="h-3.5 w-3.5" />
              Tout marquer lu
            </Button>
            <Button
              variant="ghost"
              size="sm"
              className="h-7 flex-1 gap-1.5 text-xs text-muted-foreground hover:text-destructive"
              onClick={clearAll}
            >
              <Trash2 className="h-3.5 w-3.5" />
              Tout effacer
            </Button>
          </div>
        )}

        {loading ? (
          <div className="flex items-center justify-center py-8 text-muted-foreground">
            <Loader2 className="h-5 w-5 animate-spin" />
          </div>
        ) : notifications.length === 0 ? (
          <div className="flex flex-col items-center gap-2 px-4 py-10 text-center text-sm text-muted-foreground">
            <Bell className="h-8 w-8 opacity-30" />
            Aucune notification
          </div>
        ) : (
          <ScrollArea className="max-h-96">
            {notifications.slice(0, 8).map((notification) => (
              <DropdownMenuItem
                key={notification.id}
                className="flex items-start gap-3 rounded-none border-b px-4 py-3 cursor-default focus:bg-accent last:border-b-0"
                onSelect={(e) => e.preventDefault()}
              >
                <div
                  className={`mt-0.5 flex h-8 w-8 shrink-0 items-center justify-center rounded-full ${
                    notification.is_read
                      ? 'bg-muted text-muted-foreground'
                      : 'bg-primary/10 text-primary'
                  }`}
                >
                  {typeIcon(notification.notif_type)}
                </div>
                <div className="min-w-0 flex-1 space-y-1.5">
                  <div className="flex items-start justify-between gap-2">
                    <p
                      className={`text-sm leading-snug line-clamp-2 ${
                        notification.is_read ? 'text-muted-foreground' : 'font-medium'
                      }`}
                    >
                      {notification.message}
                    </p>
                    {!notification.is_read && (
                      <span className="mt-1 h-2 w-2 shrink-0 rounded-full bg-primary" />
                    )}
                  </div>
                  <div className="flex flex-wrap items-center gap-1.5">
                    <Badge variant="outline" className={`text-[10px] ${getTypeBadgeClass(notification.notif_type)}`}>
                      {typeLabel(notification.notif_type)}
                    </Badge>
                    {notification.created_at && (
                      <span className="text-[10px] text-muted-foreground">
                        {formatNotificationDate(notification.created_at)}
                      </span>
                    )}
                    {!notification.is_read && (
                      <button
                        type="button"
                        className="ml-auto text-[10px] font-medium text-primary hover:underline"
                        onClick={() => markAsRead(notification.id)}
                      >
                        Marquer lu
                      </button>
                    )}
                  </div>
                </div>
              </DropdownMenuItem>
            ))}
          </ScrollArea>
        )}
        <DropdownMenuSeparator />
        <DropdownMenuItem asChild className="justify-center text-sm font-medium">
          <Link href="/notifications">Voir toutes les notifications</Link>
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
