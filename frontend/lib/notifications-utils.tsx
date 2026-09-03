import { Bell, Mail, Package, User, MessageSquare, ArrowLeftRight, ArrowUpDown } from 'lucide-react';

export const typeIcon = (type: string) => {
  switch (type) {
    case 'sale': return <Package className="h-4 w-4" />;
    case 'user': return <User className="h-4 w-4" />;
    case 'product': return <Mail className="h-4 w-4" />;
    case 'chat': return <MessageSquare className="h-4 w-4" />;
    case 'transfer': return <ArrowLeftRight className="h-4 w-4" />;
    case 'movement': return <ArrowUpDown className="h-4 w-4" />;
    default: return <Bell className="h-4 w-4" />;
  }
};

export const typeLabel = (type: string) => {
  switch (type) {
    case 'sale': return 'Vente';
    case 'product': return 'Produit';
    case 'user': return 'Utilisateur';
    case 'chat': return 'Chat';
    case 'transfer': return 'Transfert';
    case 'movement': return 'Mouvement';
    default: return 'Autre';
  }
};

export const formatNotificationDate = (value: string) =>
  new Date(value).toLocaleString('fr-FR', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });

export const getTypeBadgeClass = (type: string) => {
  switch (type) {
    case 'sale':
      return 'bg-green-500/10 text-green-700 dark:text-green-400 border-green-500/20';
    case 'product':
      return 'bg-blue-500/10 text-blue-700 dark:text-blue-400 border-blue-500/20';
    case 'user':
      return 'bg-violet-500/10 text-violet-700 dark:text-violet-400 border-violet-500/20';
    case 'chat':
      return 'bg-amber-500/10 text-amber-700 dark:text-amber-400 border-amber-500/20';
    case 'transfer':
      return 'bg-cyan-500/10 text-cyan-700 dark:text-cyan-400 border-cyan-500/20';
    case 'movement':
      return 'bg-orange-500/10 text-orange-700 dark:text-orange-400 border-orange-500/20';
    default:
      return 'bg-muted text-muted-foreground border-border';
  }
};

export const getNotificationCardClass = (isRead: boolean) =>
  isRead
    ? 'bg-muted/40 border-border'
    : 'bg-primary/5 border-primary/30 shadow-sm';

export const getSocketStatusBadgeClass = (status: 'connecting' | 'connected' | 'disconnected') => {
  switch (status) {
    case 'connected':
      return 'bg-emerald-500/10 text-emerald-700 dark:text-emerald-400 border-emerald-500/20';
    case 'connecting':
      return 'bg-amber-500/10 text-amber-700 dark:text-amber-400 border-amber-500/20';
    default:
      return 'bg-rose-500/10 text-rose-700 dark:text-rose-400 border-rose-500/20';
  }
};
