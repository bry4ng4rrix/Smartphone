'use client';

import { useState, useEffect } from 'react';
import { 
  Bell, CheckCheck, Trash2, Eye, EyeOff, 
  UserPlus, Package, ShoppingCart, Info, Loader2 
} from 'lucide-react';
import { toast } from 'sonner';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

// Simulation du client API (à adapter selon votre implémentation django-client.ts)
const API_BASE = process.env.NEXT_PUBLIC_DJANGO_API_URL || 'http://localhost:8000/api/users';

export default function NotificationsPage() {
  const [notifications, setNotifications] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [selectedIds, setSelectedIds] = useState<number[]>([]);

  const fetchNotifications = async () => {
    try {
      const token = localStorage.getItem('access_token');
      const res = await fetch(`${API_BASE}/notifications/`, {
        headers: { 'Authorization': `Bearer ${token}` }
      });
      const data = await res.json();
      setNotifications(Array.isArray(data) ? data : data.results || []);
    } catch (error) {
      toast.error("Erreur lors du chargement des notifications");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { fetchNotifications(); }, []);

  const handleBulkAction = async (action: string) => {
    if (selectedIds.length === 0 && !action.includes('all')) return;
    
    const endpoint = action === 'read' ? 'bulk-read' : 'bulk-delete';
    const body = action.includes('all') ? {} : { ids: selectedIds };
    const finalEndpoint = action.includes('all') 
      ? (action.includes('read') ? 'mark-all-read' : 'delete-all') 
      : endpoint;

    try {
      const token = localStorage.getItem('access_token');
      await fetch(`${API_BASE}/notifications/${finalEndpoint}/`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
        body: JSON.stringify(body)
      });
      toast.success("Action effectuée");
      setSelectedIds([]);
      fetchNotifications();
    } catch (error) {
      toast.error("Échec de l'opération");
    }
  };

  const toggleSelectAll = () => {
    if (selectedIds.length === notifications.length) setSelectedIds([]);
    else setSelectedIds(notifications.map(n => n.id));
  };

  const getIcon = (type: string) => {
    switch(type) {
      case 'sale': return <ShoppingCart className="w-5 h-5 text-green-500" />;
      case 'product': return <Package className="w-5 h-5 text-blue-500" />;
      case 'user': return <UserPlus className="w-5 h-5 text-purple-500" />;
      default: return <Info className="w-5 h-5 text-gray-500" />;
    }
  };

  if (loading) return <div className="flex justify-center p-10"><Loader2 className="animate-spin" /></div>;

  return (
    <div className="p-6 max-w-4xl mx-auto">
      <div className="flex justify-between items-center mb-6">
        <h1 className="text-2xl font-bold flex items-center gap-2">
          <Bell className="w-6 h-6" /> Notifications
        </h1>
        <div className="flex gap-2">
          <button 
            onClick={() => handleBulkAction('read-all')}
            className="px-3 py-1 text-sm bg-blue-50 text-blue-600 rounded hover:bg-blue-100 flex items-center gap-1"
          >
            <CheckCheck className="w-4 h-4" /> Tout lire
          </button>
          <button 
            onClick={() => handleBulkAction('delete-all')}
            className="px-3 py-1 text-sm bg-red-50 text-red-600 rounded hover:bg-red-100 flex items-center gap-1"
          >
            <Trash2 className="w-4 h-4" /> Tout supprimer
          </button>
        </div>
      </div>

      {selectedIds.length > 0 && (
        <div className="bg-gray-100 p-3 rounded-lg mb-4 flex justify-between items-center animate-in fade-in">
          <span className="text-sm font-medium">{selectedIds.length} sélectionné(s)</span>
          <div className="flex gap-2">
            <button onClick={() => handleBulkAction('read')} className="p-2 text-blue-600 hover:bg-white rounded shadow-sm"><Eye className="w-4 h-4"/></button>
            <button onClick={() => handleBulkAction('delete')} className="p-2 text-red-600 hover:bg-white rounded shadow-sm"><Trash2 className="w-4 h-4"/></button>
          </div>
        </div>
      )}

      <div className="bg-white rounded-xl shadow-sm border border-gray-200 overflow-hidden">
        <div className="p-3 border-b bg-gray-50 flex items-center gap-3">
          <input 
            type="checkbox" 
            checked={selectedIds.length === notifications.length && notifications.length > 0}
            onChange={toggleSelectAll}
            className="w-4 h-4 rounded border-gray-300"
          />
          <span className="text-xs font-semibold text-gray-500 uppercase">Tout sélectionner</span>
        </div>

        {notifications.length === 0 ? (
          <div className="p-10 text-center text-gray-400">Aucune notification</div>
        ) : (
          <div className="divide-y divide-gray-100">
            {notifications.map((notif) => (
              <div 
                key={notif.id} 
                className={`p-4 flex items-start gap-4 transition-colors hover:bg-gray-50 ${!notif.is_read ? 'bg-blue-50/30' : ''}`}
              >
                <input 
                  type="checkbox"
                  checked={selectedIds.includes(notif.id)}
                  onChange={() => {
                    setSelectedIds(prev => 
                      prev.includes(notif.id) ? prev.filter(id => id !== notif.id) : [...prev, notif.id]
                    );
                  }}
                  className="mt-1 w-4 h-4 rounded border-gray-300"
                />
                <div className="mt-1">{getIcon(notif.notif_type)}</div>
                <div className="flex-1 min-w-0">
                  <p className={`text-sm ${!notif.is_read ? 'font-bold text-gray-900' : 'text-gray-600'}`}>
                    {notif.message}
                  </p>
                  <div className="flex items-center gap-2 mt-1">
                    <span className="text-xs text-gray-400">
                      {format(new Date(notif.created_at), "d MMMM 'à' HH:mm", { locale: fr })}
                    </span>
                    {notif.magasin_name && (
                      <span className="text-[10px] px-1.5 py-0.5 bg-gray-100 text-gray-500 rounded uppercase font-bold">
                        {notif.magasin_name}
                      </span>
                    )}
                  </div>
                </div>
                <div className="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                   {/* Actions individuelles optionnelles ici */}
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}