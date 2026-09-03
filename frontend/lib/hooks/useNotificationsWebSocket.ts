'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { djangoClient } from '@/lib/django-client';
import { toast } from 'sonner';
import { typeLabel } from '@/lib/notifications-utils';

export type SocketStatus = 'connecting' | 'connected' | 'disconnected';

interface UseNotificationsWebSocketOptions {
  onNotification?: (notification: any) => void;
  showToast?: boolean;
}

export function useNotificationsWebSocket(options: UseNotificationsWebSocketOptions = {}) {
  const { onNotification, showToast = false } = options;
  const [socketStatus, setSocketStatus] = useState<SocketStatus>('disconnected');
  const socketRef = useRef<WebSocket | null>(null);
  const reconnectTimeoutRef = useRef<NodeJS.Timeout | null>(null);
  const onNotificationRef = useRef(onNotification);
  const showToastRef = useRef(showToast);

  useEffect(() => {
    onNotificationRef.current = onNotification;
    showToastRef.current = showToast;
  }, [onNotification, showToast]);

  const disconnectWebSocket = useCallback(() => {
    if (reconnectTimeoutRef.current) {
      clearTimeout(reconnectTimeoutRef.current);
      reconnectTimeoutRef.current = null;
    }
    if (socketRef.current) {
      socketRef.current.close(1000);
      socketRef.current = null;
    }
    setSocketStatus('disconnected');
  }, []);

  const connectWebSocket = useCallback(() => {
    if (typeof window === 'undefined') return;

    const token = djangoClient.getAccessToken();
    if (!token) return;

    disconnectWebSocket();
    setSocketStatus('connecting');

    const wsProto = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const apiURL = process.env.NEXT_PUBLIC_DJANGO_API_URL || 'http://localhost:8000/api';
    const host = apiURL.replace(/^https?:\/\//, '').split('/')[0];
    const wsUrl = `${wsProto}//${host}/ws/notifications/?token=${token}`;

    try {
      const ws = new WebSocket(wsUrl);
      socketRef.current = ws;

      ws.onopen = () => {
        setSocketStatus('connected');
      };

      ws.onmessage = (event) => {
        try {
          const newNotif = JSON.parse(event.data);
          if (showToastRef.current) {
            toast.info(newNotif.message, {
              description: `Type : ${typeLabel(newNotif.notif_type)}`,
              duration: 5000,
            });
          }
          onNotificationRef.current?.(newNotif);
        } catch (e) {
          console.error('Error parsing WS notification:', e);
        }
      };

      ws.onclose = (event) => {
        setSocketStatus('disconnected');
        if (socketRef.current === ws && event.code !== 1000) {
          reconnectTimeoutRef.current = setTimeout(() => {
            connectWebSocket();
          }, 3000);
        }
      };

      ws.onerror = () => {
        setSocketStatus('disconnected');
      };
    } catch (error) {
      console.error('Error connecting to notifications socket:', error);
      setSocketStatus('disconnected');
    }
  }, [disconnectWebSocket]);

  useEffect(() => {
    if (!djangoClient.isAuthenticated()) return;
    connectWebSocket();
    return () => disconnectWebSocket();
  }, [connectWebSocket, disconnectWebSocket]);

  return { socketStatus, connectWebSocket, disconnectWebSocket };
}
