'use client';

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useRef,
  useState,
  type ReactNode,
} from 'react';
import { djangoClient } from '@/lib/django-client';
import { buildWebSocketUrl } from '@/lib/ws-utils';

export type DataModel =
  | 'product_variant'
  | 'stock_movement'
  | 'order'
  | 'order_status_history'
  | 'supplier_order'
  | 'caisse_session'
  | 'caisse_movement';
export type DataAction = 'created' | 'updated' | 'deleted';

export interface DataSyncEvent {
  model: DataModel;
  action: DataAction;
  id: number | null;
  magasin_id: number | null;
}

type DataSyncListener = (event: DataSyncEvent) => void;

interface DataSyncContextValue {
  socketStatus: 'connecting' | 'connected' | 'disconnected';
  subscribe: (listener: DataSyncListener) => () => void;
}

const DataSyncContext = createContext<DataSyncContextValue | null>(null);

export function DataSyncProvider({ children }: { children: ReactNode }) {
  const [socketStatus, setSocketStatus] = useState<'connecting' | 'connected' | 'disconnected'>('disconnected');
  const socketRef = useRef<WebSocket | null>(null);
  const reconnectTimeoutRef = useRef<NodeJS.Timeout | null>(null);
  const listenersRef = useRef<Set<DataSyncListener>>(new Set());

  const subscribe = useCallback((listener: DataSyncListener) => {
    listenersRef.current.add(listener);
    return () => listenersRef.current.delete(listener);
  }, []);

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

    const wsUrl = buildWebSocketUrl('/ws/data/', token);

    try {
      const ws = new WebSocket(wsUrl);
      socketRef.current = ws;

      ws.onopen = () => setSocketStatus('connected');

      ws.onmessage = (event) => {
        try {
          const data = JSON.parse(event.data) as DataSyncEvent;
          listenersRef.current.forEach((listener) => listener(data));
        } catch (e) {
          console.error('Error parsing data sync event:', e);
        }
      };

      ws.onclose = (event) => {
        setSocketStatus('disconnected');
        if (socketRef.current === ws && event.code !== 1000) {
          reconnectTimeoutRef.current = setTimeout(connectWebSocket, 3000);
        }
      };

      ws.onerror = () => setSocketStatus('disconnected');
    } catch (error) {
      console.error('Error connecting to data sync socket:', error);
      setSocketStatus('disconnected');
    }
  }, [disconnectWebSocket]);

  useEffect(() => {
    if (!djangoClient.isAuthenticated()) return;
    connectWebSocket();
    return () => disconnectWebSocket();
  }, [connectWebSocket, disconnectWebSocket]);

  return (
    <DataSyncContext.Provider value={{ socketStatus, subscribe }}>
      {children}
    </DataSyncContext.Provider>
  );
}

export function useDataSync() {
  const ctx = useContext(DataSyncContext);
  if (!ctx) {
    throw new Error('useDataSync must be used within a DataSyncProvider');
  }
  return ctx;
}
