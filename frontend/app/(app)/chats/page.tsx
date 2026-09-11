'use client';

import { useCallback, useState, useEffect, useRef } from 'react';
import { useCurrentUser } from '@/lib/auth/useCurrentUser';
import { djangoClient } from '@/lib/django-client';
import { useDebouncedValue } from '@/lib/hooks/useDebouncedValue';
import {
  Send,
  Search,
  Users,
  Hash,
  MessageSquare,
  Circle,
  Store,
  Shield,
  Loader2,
  Image as ImageIcon,
  Camera,
  AlertCircle,
  ArrowLeft,
  Plus,
  MoreVertical,
  Pencil,
  Trash2,
  Check,
  CheckCheck,
  X,
  Package,
} from 'lucide-react';
import { Card, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { ScrollArea } from '@/components/ui/scroll-area';
import { Avatar, AvatarFallback } from '@/components/ui/avatar';
import { Badge } from '@/components/ui/badge';
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { toast } from 'sonner';

interface ChatUser {
  /** Messages reçus de ce contact et pas encore lus — badge de la liste. */
  unread_count?: number;
  /** Dernier message échangé, quel qu'en soit l'auteur — sert au classement. */
  last_message_at?: string | null;
  id: number;
  full_name: string;
  email: string;
  role: 'admin' | 'magasin' | 'employer';
  shop_name?: string;
  is_online?: boolean;
  last_seen_at?: string | null;
}

interface ChatProductSnapshot {
  id: number;
  name: string;
  reference: string;
  category: string;
  unit_price: string;
}

interface ChatMessage {
  id: number;
  sender: number;
  sender_name: string;
  sender_email: string;
  sender_role: string;
  recipient: number | null;
  recipient_name: string | null;
  recipient_email: string | null;
  room_name: string;
  content: string;
  /** URL absolue de l'image jointe, si le message en porte une. */
  image?: string | null;
  product?: ChatProductSnapshot | null;
  is_edited?: boolean;
  edited_at?: string | null;
  is_deleted?: boolean;
  timestamp: string;
  read_at?: string | null;
}

export default function ChatsPage() {
  const { user: currentUser, loading: authLoading } = useCurrentUser();
  const [users, setUsers] = useState<ChatUser[]>([]);
  const [loadingUsers, setLoadingUsers] = useState(true);
  
  // Chat Room state
  // Le salon « Général » a été retiré (§ demande) : la messagerie ne
  // comporte plus que des conversations directes. `activeTab` est conservé
  // parce que de nombreuses conditions s'en servent pour distinguer un DM
  // (statut « vu », destinataire...) — il vaut désormais toujours 'direct'.
  const [activeTab] = useState<'general' | 'direct'>('direct');
  const [activeRecipient, setActiveRecipient] = useState<ChatUser | null>(null);
  
  // Message state
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [newMessage, setNewMessage] = useState('');
  const [loadingHistory, setLoadingHistory] = useState(false);

  // Edit message state
  const [editingId, setEditingId] = useState<number | null>(null);
  const [editingContent, setEditingContent] = useState('');

  // Bouton "+" : envoi d'image / photo (§ demande)
  const [attachOpen, setAttachOpen] = useState(false);

  // Search & Filter
  const [searchQuery, setSearchQuery] = useState('');
  const [mobileShowChat, setMobileShowChat] = useState(false);

  // WebSocket state
  const [socketStatus, setSocketStatus] = useState<'connecting' | 'connected' | 'disconnected'>('disconnected');
  const socketRef = useRef<WebSocket | null>(null);
  const reconnectTimeoutRef = useRef<NodeJS.Timeout | null>(null);
  const pingIntervalRef = useRef<NodeJS.Timeout | null>(null);

  // ScrollRef
  const messagesEndRef = useRef<HTMLDivElement | null>(null);

  // 1. Fetch chat users list — reinterrogé périodiquement pour rafraîchir le
  // statut "En ligne" de chacun (calculé côté serveur à partir de
  // last_seen_at, voir ChatUsersListView).
  const fetchUsers = useCallback(
    async (silent = false) => {
      if (!currentUser) return;
      try {
        if (!silent) setLoadingUsers(true);
        const data = await djangoClient.chat.users();
        setUsers(data);
      } catch (err) {
        console.error('Error fetching chat users:', err);
        if (!silent) toast.error('Impossible de charger la liste des collaborateurs.');
      } finally {
        if (!silent) setLoadingUsers(false);
      }
    },
    [currentUser],
  );

  useEffect(() => {
    if (!currentUser) return;
    fetchUsers();
    const interval = setInterval(() => fetchUsers(true), 20000);
    return () => clearInterval(interval);
  }, [currentUser, fetchUsers]);

  // Ouvrir une conversation la marque comme lue côté serveur : on relit la
  // liste tout de suite pour que le badge de non-lus retombe sans attendre
  // le prochain rafraîchissement périodique.
  useEffect(() => {
    if (activeRecipient) fetchUsers(true);
  }, [activeRecipient, fetchUsers]);

  // 2. Fetch message history & connect WebSocket when active recipient or room tab changes
  useEffect(() => {
    if (!currentUser) return;

    // Disconnect old socket
    disconnectWebSocket();
    setMessages([]);

    const loadHistoryAndConnect = async () => {
      setLoadingHistory(true);
      try {
        // Load message history via REST API
        if (activeTab === 'general') {
          const history = await djangoClient.chat.history({ room_name: 'general' });
          setMessages(history);
        } else if (activeTab === 'direct' && activeRecipient) {
          const history = await djangoClient.chat.history({ recipient_id: activeRecipient.id });
          setMessages(history);
        }
        
        // Connect WebSocket
        connectWebSocket();
      } catch (err) {
        console.error('Error loading chat history:', err);
        toast.error('Erreur lors du chargement de l\'historique.');
      } finally {
        setLoadingHistory(false);
      }
    };

    loadHistoryAndConnect();

    return () => {
      disconnectWebSocket();
    };
  }, [currentUser, activeTab, activeRecipient]);

  // 3. Auto scroll to bottom
  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages, loadingHistory]);

  // WebSocket Connection Logic
  const connectWebSocket = () => {
    if (typeof window === 'undefined') return;

    const token = djangoClient.getAccessToken();
    if (!token) return;

    setSocketStatus('connecting');

    // Build WS URL dynamically from current backend URL
    const wsProto = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const apiURL = process.env.NEXT_PUBLIC_DJANGO_API_URL || 'http://localhost:8010/api';
    const host = apiURL.replace(/^https?:\/\//, '').split('/')[0];
    
    let wsUrl = `${wsProto}//${host}/ws/chat/?token=${token}`;
    if (activeTab === 'direct' && activeRecipient) {
      wsUrl += `&recipient_id=${activeRecipient.id}`;
    } else {
      wsUrl += `&room=general`;
    }

    try {
      const ws = new WebSocket(wsUrl);
      socketRef.current = ws;

      ws.onopen = () => {
        setSocketStatus('connected');
        console.log('WebSocket Connected to', wsUrl);

        // Ouvrir une conversation directe = la consulter -> marquer les
        // messages reçus non lus comme "vu" côté serveur.
        if (activeTab === 'direct' && activeRecipient) {
          ws.send(JSON.stringify({ action: 'read' }));
        }

        // Heartbeat de présence — toute trame reçue par le serveur met à
        // jour last_seen_at (voir ChatConsumer.receive()) ; un simple ping
        // sans contenu suffit et n'est jamais traité comme un message.
        if (pingIntervalRef.current) clearInterval(pingIntervalRef.current);
        pingIntervalRef.current = setInterval(() => {
          if (ws.readyState === WebSocket.OPEN) {
            ws.send(JSON.stringify({ action: 'ping' }));
          }
        }, 20000);
      };

      ws.onmessage = (event) => {
        try {
          const data = JSON.parse(event.data);

          if (data.type === 'message_edited') {
            setMessages((prev) =>
              prev.map((m) =>
                m.id === data.id
                  ? { ...m, content: data.content, is_edited: data.is_edited, edited_at: data.edited_at }
                  : m
              )
            );
            return;
          }

          if (data.type === 'message_deleted') {
            setMessages((prev) =>
              prev.map((m) => (m.id === data.id ? { ...m, is_deleted: true, content: '' } : m))
            );
            return;
          }

          if (data.type === 'message_read') {
            const ids: number[] = data.ids || [];
            setMessages((prev) =>
              prev.map((m) => (ids.includes(m.id) ? { ...m, read_at: data.read_at } : m))
            );
            return;
          }

          const receivedData: ChatMessage = data;
          setMessages((prev) => {
            // Avoid duplicates
            if (prev.some((m) => m.id === receivedData.id)) return prev;
            return [...prev, receivedData];
          });

          // Message reçu (pas le nôtre) pendant que la conversation est
          // ouverte -> le marquer "vu" immédiatement.
          if (
            activeTab === 'direct' &&
            activeRecipient &&
            currentUser &&
            receivedData.sender !== currentUser.id &&
            ws.readyState === WebSocket.OPEN
          ) {
            ws.send(JSON.stringify({ action: 'read' }));
          }
        } catch (e) {
          console.error('Error parsing incoming WS message:', e);
        }
      };

      ws.onclose = (event) => {
        setSocketStatus('disconnected');
        console.log('WebSocket Disconnected', event.reason);

        if (pingIntervalRef.current) {
          clearInterval(pingIntervalRef.current);
          pingIntervalRef.current = null;
        }

        // Auto-reconnect if not explicitly disconnected by us
        if (socketRef.current === ws) {
          reconnectTimeoutRef.current = setTimeout(() => {
            console.log('Attempting auto-reconnect...');
            connectWebSocket();
          }, 3000);
        }
      };

      ws.onerror = (err) => {
        console.error('WebSocket Error:', err);
        setSocketStatus('disconnected');
      };
    } catch (error) {
      console.error('Error establishing WebSocket connection:', error);
      setSocketStatus('disconnected');
    }
  };

  const disconnectWebSocket = () => {
    // Clear timeouts
    if (reconnectTimeoutRef.current) {
      clearTimeout(reconnectTimeoutRef.current);
      reconnectTimeoutRef.current = null;
    }
    if (pingIntervalRef.current) {
      clearInterval(pingIntervalRef.current);
      pingIntervalRef.current = null;
    }

    if (socketRef.current) {
      socketRef.current.close();
      socketRef.current = null;
    }
    setSocketStatus('disconnected');
  };

  // Send Message logic
  const handleSendMessage = (e?: React.FormEvent) => {
    if (e) e.preventDefault();

    if (!newMessage.trim() || !socketRef.current || socketStatus !== 'connected') {
      return;
    }

    const payload = {
      content: newMessage.trim()
    };

    socketRef.current.send(JSON.stringify(payload));
    setNewMessage('');
  };

  // Edit message logic
  const startEditMessage = (msg: ChatMessage) => {
    setEditingId(msg.id);
    setEditingContent(msg.content);
  };

  const cancelEditMessage = () => {
    setEditingId(null);
    setEditingContent('');
  };

  const saveEditMessage = () => {
    if (!editingId || !editingContent.trim() || !socketRef.current || socketStatus !== 'connected') return;
    socketRef.current.send(JSON.stringify({
      action: 'edit',
      message_id: editingId,
      content: editingContent.trim(),
    }));
    setEditingId(null);
    setEditingContent('');
  };

  // Delete message logic
  const handleDeleteMessage = (messageId: number) => {
    if (!socketRef.current || socketStatus !== 'connected') return;
    if (!confirm('Supprimer ce message ?')) return;
    socketRef.current.send(JSON.stringify({ action: 'delete', message_id: messageId }));
  };

  // Product picker ("+" button) logic
  // Bouton "+" du chat : envoi d'une image (§ demande). Le WebSocket ne
  // transporte que du JSON, l'image passe donc par HTTP
  // (users/views.py::ChatImageUploadView) qui la diffuse ensuite au même
  // groupe temps réel — le message arrive donc par le socket comme un
  // message texte, sans traitement particulier ici.
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [sendingImage, setSendingImage] = useState(false);

  const pickImage = (fromCamera: boolean) => {
    const input = fileInputRef.current;
    if (!input) return;
    // `capture` ouvre directement l'appareil photo sur mobile ; sur desktop
    // l'attribut est ignoré et la boîte de dialogue habituelle s'affiche.
    if (fromCamera) input.setAttribute('capture', 'environment');
    else input.removeAttribute('capture');
    input.value = '';
    input.click();
    setAttachOpen(false);
  };

  const handleImageSelected = async (file?: File) => {
    if (!file) return;
    setSendingImage(true);
    try {
      await djangoClient.chat.sendImage(
        file,
        newMessage.trim(),
        activeTab === 'direct' ? activeRecipient?.id : undefined,
      );
      setNewMessage('');
    } catch (err: any) {
      toast.error(err?.message || "Impossible d'envoyer l'image.");
    } finally {
      setSendingImage(false);
    }
  };

  // Suggestions list
  const quickSuggestions = [
    "Bonjour !",
    "Est-ce que le stock est à jour ?",
    "La commande est en cours.",
    "Merci pour votre aide !",
    "Je m'en occupe tout de suite."
  ];

  // Helper formats
  const formatTime = (isoString: string) => {
    try {
      const d = new Date(isoString);
      return d.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });
    } catch (e) {
      return '';
    }
  };

  const formatLastSeen = (isoString?: string | null) => {
    if (!isoString) return null;
    try {
      const d = new Date(isoString);
      const diffMin = (Date.now() - d.getTime()) / 60000;
      if (diffMin < 1) return "à l'instant";
      if (diffMin < 60) return `il y a ${Math.floor(diffMin)} min`;
      return `à ${d.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' })}`;
    } catch (e) {
      return null;
    }
  };

  const getRoleLabel = (role: string) => {
    switch (role) {
      case 'admin':
        return 'Admin';
      case 'magasin':
        return 'Gérant';
      case 'employer':
        return 'Employé';
      default:
        return role;
    }
  };

  const getRoleBadgeColor = (role: string) => {
    switch (role) {
      case 'admin':
        return 'bg-rose-500/10 text-rose-700 dark:text-rose-400 hover:bg-rose-500/20 border-rose-500/20';
      case 'magasin':
        return 'bg-blue-500/10 text-blue-700 dark:text-blue-400 hover:bg-blue-500/20 border-blue-500/20';
      case 'employer':
        return 'bg-emerald-500/10 text-emerald-700 dark:text-emerald-400 hover:bg-emerald-500/20 border-emerald-500/20';
      default:
        return 'bg-muted text-muted-foreground';
    }
  };

  const getInitials = (name: string) => {
    if (!name) return 'U';
    return name
      .split(' ')
      .map((part) => part[0])
      .slice(0, 2)
      .join('')
      .toUpperCase();
  };

  // Filter users based on query
  const debouncedSearchQuery = useDebouncedValue(searchQuery);
  /**
   * Liste des contacts, classée comme une messagerie (§ demande) :
   *
   * 1. les conversations avec des messages NON LUS d'abord — elles se voient
   *    en premier, sans avoir à faire défiler ;
   * 2. à l'intérieur de chaque groupe, la plus récemment active en tête ;
   * 3. les contacts avec qui on n'a jamais échangé ferment la marche, par
   *    ordre alphabétique.
   */
  const filteredUsers = users
    .filter((u) => {
      const term = debouncedSearchQuery.toLowerCase();
      return (
        u.full_name.toLowerCase().includes(term) ||
        u.email.toLowerCase().includes(term) ||
        (u.shop_name && u.shop_name.toLowerCase().includes(term))
      );
    })
    .sort((a, b) => {
      const rang = (u: ChatUser) => (u.unread_count ? 0 : 1);
      const quand = (u: ChatUser) =>
        u.last_message_at ? new Date(u.last_message_at).getTime() : 0;
      const parRang = rang(a) - rang(b);
      if (parRang !== 0) return parRang;
      const parDate = quand(b) - quand(a);
      if (parDate !== 0) return parDate;
      return a.full_name.localeCompare(b.full_name, 'fr');
    });

  // Statut de présence toujours à jour (le polling rafraîchit `users`, pas
  // l'objet figé au moment du clic dans `activeRecipient`).
  const liveActiveRecipient = activeRecipient
    ? users.find((u) => u.id === activeRecipient.id) || activeRecipient
    : null;

  const openChatView = () => setMobileShowChat(true);

  const handleSelectGeneral = () => {
    setActiveRecipient(null);
    openChatView();
  };

  const handleSelectUser = (u: ChatUser) => {
    setActiveRecipient(u);
    openChatView();
  };

  if (authLoading) {
    return (
      <div className="flex flex-col items-center justify-center min-h-[60vh] gap-3">
        <Loader2 className="h-10 w-10 animate-spin text-primary" />
        <p className="text-muted-foreground animate-pulse">Chargement de votre profil...</p>
      </div>
    );
  }

  if (!currentUser) {
    return (
      <div className="flex flex-col items-center justify-center min-h-[60vh] p-6 text-center">
        <AlertCircle className="h-12 w-12 text-destructive mb-4" />
        <h3 className="text-xl font-semibold mb-2">Non Authentifié</h3>
        <p className="text-muted-foreground max-w-sm">
          Vous devez être connecté pour accéder à la messagerie interne.
        </p>
      </div>
    );
  }

  return (
    // `h-full` et non un calcul en vh : le <main> du gabarit applicatif
    // (app/(app)/layout.tsx) fait déjà « hauteur d'écran moins la barre du
    // haut ». Recalculer cette hauteur ICI, puis y ajouter les marges
    // verticales, rendait la page plus haute que son conteneur : c'était la
    // PAGE qui défilait, et la liste des collaborateurs se retrouvait coupée
    // sans ascenseur. En pourcentage, les marges sont comprises dans la
    // hauteur (box-border) et rien ne déborde.
    <div className="mx-auto px-3 sm:px-6 lg:px-8 py-4 sm:py-6 h-full min-h-0 flex flex-col">
      
      {/* Le titre, le sous-titre et la carte du compte connecté ont été
          retirés (§ demande) : ils mangeaient de la hauteur au détriment de
          la conversation, et l'identité du compte figure déjà dans la barre
          supérieure. */}

      {/* Main chat box container */}
      <div className="flex-1 min-h-0 bg-card border rounded-2xl sm:rounded-3xl overflow-hidden shadow-md flex">
        
        {/* Left Side: Sidebar */}
        <div className={`${mobileShowChat ? 'hidden md:flex' : 'flex'} w-full md:w-80 min-h-0 border-r flex-col bg-muted/30 shrink-0 select-none`}>
          
          {/* En-tête de la liste — le sélecteur Général/Direct a disparu
              avec le salon Général (§ demande) : il ne reste qu'une seule
              destination possible. */}
          <div className="p-3 sm:p-4 border-b flex items-center gap-2">
            <Users className="h-4 w-4 text-muted-foreground" />
            <span className="text-sm font-semibold">Conversations</span>
          </div>

          {/* Search box for Direct Messages */}
          {activeTab === 'direct' && (
            <div className="px-4 pb-3 pt-1 border-b">
              <div className="relative">
                <Search className="absolute left-3 top-2.5 h-4 w-4 text-muted-foreground" />
                <Input
                  placeholder="Rechercher un collaborateur..."
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                  className="pl-9 h-9 rounded-xl text-xs bg-background"
                />
              </div>
            </div>
          )}

          {/* Users/Rooms List */}
          {/* Défilement natif plutôt que le composant ScrollArea : il ne
              dépend d'aucune chaîne de hauteurs en pourcentage, et
              fonctionne au doigt comme à la molette. `min-h-0` est
              indispensable EN PLUS de `flex-1` — un élément flex garde
              `min-height: auto`, ce qui l'empêche de se réduire sous la
              hauteur de son contenu : sans lui la liste grandissait au
              lieu de défiler. */}
          <div className="flex-1 min-h-0 overflow-y-auto overscroll-contain">
            <div className="p-2 space-y-1">
              {(
                // Direct Messaging Users List
                <>
                  {loadingUsers ? (
                    <div className="flex flex-col items-center justify-center p-8 gap-2">
                      <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
                      <span className="text-xs text-muted-foreground">Chargement des collaborateurs...</span>
                    </div>
                  ) : filteredUsers.length === 0 ? (
                    <div className="text-center p-8">
                      <p className="text-xs text-muted-foreground">Aucun collaborateur trouvé</p>
                    </div>
                  ) : (
                    filteredUsers.map((u) => (
                      <button
                        key={u.id}
                        onClick={() => handleSelectUser(u)}
                        className={`w-full text-left p-3 rounded-2xl flex items-center gap-3 transition-all ${
                          activeRecipient?.id === u.id
                            ? 'bg-primary text-primary-foreground shadow-sm shadow-primary/20'
                            : 'hover:bg-accent/60'
                        }`}
                      >
                        <div className="relative shrink-0">
                          <Avatar className="h-10 w-10 border">
                            <AvatarFallback className={`font-semibold text-xs ${
                              activeRecipient?.id === u.id
                                ? 'bg-primary-foreground/20 text-primary-foreground'
                                : 'bg-muted text-muted-foreground'
                            }`}>
                              {getInitials(u.full_name)}
                            </AvatarFallback>
                          </Avatar>
                          {u.is_online && (
                            <span
                              className={`absolute bottom-0 right-0 h-2.5 w-2.5 rounded-full bg-emerald-500 ${
                                activeRecipient?.id === u.id ? 'ring-2 ring-primary' : 'ring-2 ring-background'
                              }`}
                            />
                          )}
                        </div>

                        <div className="flex-1 min-w-0">
                          <div className="flex justify-between items-center">
                            <div className="flex items-center gap-1.5 min-w-0">
                              <h4 className="font-semibold text-xs truncate max-w-[110px]">{u.full_name}</h4>
                              {/* Messages reçus de ce contact et pas encore
                                  lus (§ demande) — même compteur que le badge
                                  du menu, mais détaillé par expéditeur. */}
                              {!!u.unread_count && u.unread_count > 0 && (
                                <span
                                  className={`min-w-4 h-4 px-1 inline-flex items-center justify-center rounded-full text-[9px] font-bold tabular-nums shrink-0 ${
                                    activeRecipient?.id === u.id
                                      ? 'bg-primary-foreground text-primary'
                                      : 'bg-red-500 text-white'
                                  }`}
                                  aria-label={`${u.unread_count} message${u.unread_count > 1 ? 's' : ''} non lu${u.unread_count > 1 ? 's' : ''}`}
                                >
                                  {u.unread_count > 99 ? '99+' : u.unread_count}
                                </span>
                              )}
                            </div>
                            <Badge className={`text-[8px] py-0 px-1 border uppercase font-bold scale-90 ${
                              activeRecipient?.id === u.id
                                ? 'bg-primary-foreground/20 text-primary-foreground border-transparent'
                                : getRoleBadgeColor(u.role)
                            }`}>
                              {getRoleLabel(u.role)}
                            </Badge>
                          </div>
                          <div className="flex items-center gap-1.5 mt-0.5">
                            {u.shop_name ? (
                              <div className={`flex items-center text-[10px] truncate ${
                                activeRecipient?.id === u.id ? 'text-primary-foreground/80' : 'text-muted-foreground'
                              }`}>
                                <Store className="h-3 w-3 mr-0.5 shrink-0" />
                                {u.shop_name}
                              </div>
                            ) : (
                              <div className={`flex items-center text-[10px] truncate ${
                                activeRecipient?.id === u.id ? 'text-primary-foreground/80' : 'text-muted-foreground'
                              }`}>
                                <Shield className="h-3 w-3 mr-0.5 shrink-0" />
                                Administration
                              </div>
                            )}
                          </div>
                          <div className={`text-[10px] mt-0.5 truncate ${
                            activeRecipient?.id === u.id ? 'text-primary-foreground/70' : u.is_online ? 'text-emerald-600 dark:text-emerald-400' : 'text-muted-foreground/70'
                          }`}>
                            {u.is_online ? 'En ligne' : formatLastSeen(u.last_seen_at) ? `Vu ${formatLastSeen(u.last_seen_at)}` : 'Hors ligne'}
                          </div>
                        </div>
                      </button>
                    ))
                  )}
                </>
              )}
            </div>
          </div>
        </div>

        {/* Right Side: Conversation window */}
        <div className={`${!mobileShowChat ? 'hidden md:flex' : 'flex'} flex-1 flex-col bg-background relative min-w-0 min-h-0`}>
          
          {/* Main conversation Header */}
          <div className="p-3 sm:p-4 border-b flex justify-between items-center shadow-sm shrink-0 bg-card select-none gap-2">
            <div className="flex items-center gap-2 sm:gap-3 min-w-0">
              <Button
                type="button"
                variant="ghost"
                size="icon"
                className="md:hidden shrink-0 h-8 w-8"
                onClick={() => setMobileShowChat(false)}
              >
                <ArrowLeft className="h-4 w-4" />
              </Button>
              {liveActiveRecipient ? (
                <>
                  <div className="relative shrink-0">
                    <Avatar className="h-10 w-10 border">
                      <AvatarFallback className="bg-primary/15 text-primary text-xs font-bold">
                        {getInitials(liveActiveRecipient.full_name)}
                      </AvatarFallback>
                    </Avatar>
                    {liveActiveRecipient.is_online && (
                      <span className="absolute bottom-0 right-0 h-2.5 w-2.5 rounded-full bg-emerald-500 ring-2 ring-card" />
                    )}
                  </div>
                  <div className="min-w-0">
                    <h3 className="font-bold text-sm truncate">{liveActiveRecipient.full_name}</h3>
                    <div className="flex items-center gap-1.5 mt-0.5">
                      <span className={`text-[10px] ${liveActiveRecipient.is_online ? 'text-emerald-600 dark:text-emerald-400 font-medium' : 'text-muted-foreground'}`}>
                        {liveActiveRecipient.is_online
                          ? 'En ligne'
                          : formatLastSeen(liveActiveRecipient.last_seen_at)
                            ? `Vu ${formatLastSeen(liveActiveRecipient.last_seen_at)}`
                            : 'Hors ligne'}
                      </span>
                      <span className="text-muted-foreground/30">•</span>
                      <span className="text-[10px] font-semibold text-primary">
                        {getRoleLabel(liveActiveRecipient.role)}
                      </span>
                    </div>
                  </div>
                </>
              ) : null}
            </div>

            {/* Socket connection indicator */}
            <div className="flex items-center gap-2 shrink-0">
              {socketStatus === 'connected' ? (
                <Badge variant="outline" className="bg-emerald-500/10 text-emerald-700 dark:text-emerald-400 border-emerald-500/20 text-[10px] flex items-center gap-1.5 rounded-full py-0.5 px-2.5">
                  <span className="relative flex h-2 w-2">
                    <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75"></span>
                    <span className="relative inline-flex rounded-full h-2 w-2 bg-emerald-500"></span>
                  </span>
                  En ligne
                </Badge>
              ) : socketStatus === 'connecting' ? (
                <Badge variant="outline" className="bg-amber-500/10 text-amber-700 dark:text-amber-400 border-amber-500/20 text-[10px] flex items-center gap-1.5 rounded-full py-0.5 px-2.5">
                  <Loader2 className="h-3 w-3 animate-spin text-amber-500" />
                  Connexion...
                </Badge>
              ) : (
                <Badge variant="outline" className="bg-rose-500/10 text-rose-700 dark:text-rose-400 border-rose-500/20 text-[10px] flex items-center gap-1.5 rounded-full py-0.5 px-2.5">
                  <Circle className="h-2 w-2 fill-rose-500 text-rose-500" />
                  Hors ligne
                </Badge>
              )}
            </div>
          </div>

          {/* Messages Scroll Area */}
          <div className="flex-1 min-h-0 relative bg-muted/20">
            {loadingHistory ? (
              <div className="absolute inset-0 flex flex-col items-center justify-center gap-2">
                <Loader2 className="h-8 w-8 animate-spin text-primary" />
                <span className="text-xs text-muted-foreground">Chargement des messages...</span>
              </div>
            ) : messages.length === 0 ? (
              <div className="absolute inset-0 flex flex-col items-center justify-center p-8 text-center select-none">
                <div className="p-4 rounded-full bg-primary/5 text-primary/30 mb-3">
                  <MessageSquare className="h-10 w-10" />
                </div>
                <h4 className="font-semibold text-sm mb-1">Aucun message pour le moment</h4>
                <p className="text-xs text-muted-foreground max-w-[280px]">
                  Envoyez un message pour commencer la conversation en temps réel.
                </p>
              </div>
            ) : (
              <ScrollArea className="h-full">
                <div className="p-3 sm:p-4 space-y-3 sm:space-y-4">
                  {messages.map((msg, index) => {
                    const isOwnMessage = msg.sender === currentUser.id;
                    const showSenderName = !isOwnMessage && (index === 0 || messages[index - 1].sender !== msg.sender);
                    const isEditing = editingId === msg.id;

                    return (
                      <div
                        key={msg.id || index}
                        className={`flex flex-col group ${isOwnMessage ? 'items-end' : 'items-start'}`}
                      >
                        {/* Sender info */}
                        {showSenderName && (
                          <span className="text-[10px] font-semibold text-muted-foreground ml-2 mb-1">
                            {msg.sender_name}
                            <span className="text-[9px] font-normal text-muted-foreground/60 border border-muted-foreground/20 rounded px-1 ml-1 text-xs">
                              {getRoleLabel(msg.sender_role)}
                            </span>
                          </span>
                        )}

                        {/* Bubble */}
                        <div className="max-w-[85%] sm:max-w-[75%] md:max-w-[65%] flex flex-col">
                          <div className="flex items-end gap-1">
                            {isOwnMessage && !msg.is_deleted && !isEditing && (
                              <DropdownMenu>
                                <DropdownMenuTrigger asChild>
                                  <button
                                    type="button"
                                    className="opacity-0 group-hover:opacity-100 transition-opacity p-1 rounded-md hover:bg-muted shrink-0 order-first"
                                  >
                                    <MoreVertical className="h-3.5 w-3.5 text-muted-foreground" />
                                  </button>
                                </DropdownMenuTrigger>
                                <DropdownMenuContent align="end">
                                  <DropdownMenuItem onClick={() => startEditMessage(msg)}>
                                    <Pencil className="h-3.5 w-3.5 mr-2" />
                                    Modifier
                                  </DropdownMenuItem>
                                  <DropdownMenuItem
                                    className="text-red-600 focus:text-red-600"
                                    onClick={() => handleDeleteMessage(msg.id)}
                                  >
                                    <Trash2 className="h-3.5 w-3.5 mr-2" />
                                    Supprimer
                                  </DropdownMenuItem>
                                </DropdownMenuContent>
                              </DropdownMenu>
                            )}

                            {isEditing ? (
                              <div className="flex items-center gap-1.5 min-w-[220px]">
                                <Input
                                  autoFocus
                                  value={editingContent}
                                  onChange={(e) => setEditingContent(e.target.value)}
                                  onKeyDown={(e) => {
                                    if (e.key === 'Enter') saveEditMessage();
                                    if (e.key === 'Escape') cancelEditMessage();
                                  }}
                                  className="h-8 text-xs rounded-xl bg-background"
                                />
                                <button
                                  type="button"
                                  onClick={saveEditMessage}
                                  className="p-1.5 rounded-md bg-primary text-primary-foreground shrink-0"
                                >
                                  <Check className="h-3.5 w-3.5" />
                                </button>
                                <button
                                  type="button"
                                  onClick={cancelEditMessage}
                                  className="p-1.5 rounded-md hover:bg-muted shrink-0"
                                >
                                  <X className="h-3.5 w-3.5" />
                                </button>
                              </div>
                            ) : (
                              <div className={`p-2.5 sm:p-3 text-xs sm:text-sm shadow-sm rounded-2xl ${
                                msg.is_deleted
                                  ? 'bg-transparent border border-dashed text-muted-foreground italic'
                                  : isOwnMessage
                                    ? 'bg-primary text-primary-foreground rounded-tr-sm'
                                    : 'bg-muted text-foreground rounded-tl-sm'
                              }`}>
                                {msg.is_deleted ? (
                                  <p className="flex items-center gap-1.5">
                                    <Trash2 className="h-3 w-3" />
                                    Message supprimé
                                  </p>
                                ) : (
                                  <>
                                    {msg.product && (
                                      <div className={`flex items-center gap-2 rounded-xl p-2 mb-1.5 ${
                                        isOwnMessage ? 'bg-primary-foreground/10' : 'bg-background'
                                      }`}>
                                        <div className={`p-1.5 rounded-lg shrink-0 ${
                                          isOwnMessage ? 'bg-primary-foreground/10' : 'bg-primary/10'
                                        }`}>
                                          <Package className={`h-4 w-4 ${isOwnMessage ? 'text-primary-foreground' : 'text-primary'}`} />
                                        </div>
                                        <div className="min-w-0">
                                          <p className="font-semibold text-xs truncate">{msg.product.name}</p>
                                          <p className={`text-[10px] truncate ${
                                            isOwnMessage ? 'text-primary-foreground/70' : 'text-muted-foreground'
                                          }`}>
                                            Réf. {msg.product.reference} · {msg.product.unit_price} Ar
                                          </p>
                                        </div>
                                      </div>
                                    )}
                                    {msg.image && (
                                      <a
                                        href={msg.image}
                                        target="_blank"
                                        rel="noopener noreferrer"
                                        className="block mb-1"
                                      >
                                        <img
                                          src={msg.image}
                                          alt="Image envoyée"
                                          className="max-h-60 w-auto max-w-full rounded-lg border object-cover"
                                        />
                                      </a>
                                    )}
                                    {msg.content && (
                                      <p className="whitespace-pre-wrap leading-relaxed">{msg.content}</p>
                                    )}
                                  </>
                                )}
                              </div>
                            )}
                          </div>

                          {/* Timestamp */}
                          {!isEditing && (
                            <span className={`flex items-center gap-1 text-[9px] text-muted-foreground/70 mt-1 select-none px-1 ${
                              isOwnMessage ? 'justify-end text-right' : 'text-left'
                            }`}>
                              {formatTime(msg.timestamp)}
                              {msg.is_edited && !msg.is_deleted ? ' · modifié' : ''}
                              {isOwnMessage && !msg.is_deleted && activeTab === 'direct' && (
                                msg.read_at ? (
                                  <CheckCheck className="h-3 w-3 text-primary" />
                                ) : (
                                  <Check className="h-3 w-3" />
                                )
                              )}
                            </span>
                          )}
                        </div>
                      </div>
                    );
                  })}
                  <div ref={messagesEndRef} />
                </div>
              </ScrollArea>
            )}
          </div>

          {/* Quick Suggestions & Input form */}
          <div className="p-3 sm:p-4 border-t bg-card shrink-0 select-none safe-area-pb">
            {/* Quick Suggestions */}
            {messages.length === 0 && (
              <div className="flex flex-wrap gap-1.5 mb-2 sm:mb-3">
                {quickSuggestions.map((suggestion) => (
                  <button
                    key={suggestion}
                    type="button"
                    onClick={() => setNewMessage(suggestion)}
                    className="text-[10px] sm:text-xs px-2 sm:px-2.5 py-1 bg-secondary hover:bg-primary hover:text-primary-foreground rounded-full transition-all duration-200 border cursor-pointer"
                  >
                    {suggestion}
                  </button>
                ))}
              </div>
            )}

            {/* Input message form */}
            <form onSubmit={handleSendMessage} className="flex gap-2 items-end">
              {/* Input fichier masqué, piloté par les deux entrées du "+".
                  `accept="image/*"` limite aux images ; `capture` est posé à
                  la volée pour ouvrir l'appareil photo (voir pickImage). */}
              <input
                ref={fileInputRef}
                type="file"
                accept="image/*"
                className="hidden"
                onChange={(e) => handleImageSelected(e.target.files?.[0])}
              />
              <Popover open={attachOpen} onOpenChange={setAttachOpen}>
                <PopoverTrigger asChild>
                  <Button
                    type="button"
                    variant="outline"
                    size="icon"
                    disabled={socketStatus !== 'connected' || sendingImage}
                    className="rounded-2xl h-10 w-10 sm:h-11 sm:w-11 shrink-0"
                  >
                    {sendingImage ? (
                      <Loader2 className="h-4 w-4 animate-spin" />
                    ) : (
                      <Plus className="h-4 w-4" />
                    )}
                  </Button>
                </PopoverTrigger>
                <PopoverContent align="start" side="top" className="w-56 p-1">
                  <button
                    type="button"
                    onClick={() => pickImage(false)}
                    className="w-full flex items-center gap-2.5 p-2 rounded-lg hover:bg-muted text-left transition-colors"
                  >
                    <div className="p-1.5 rounded-lg bg-primary/10 shrink-0">
                      <ImageIcon className="h-4 w-4 text-primary" />
                    </div>
                    <div className="min-w-0">
                      <p className="text-xs font-medium">Envoyer une image</p>
                      <p className="text-[10px] text-muted-foreground">Depuis vos fichiers</p>
                    </div>
                  </button>
                  <button
                    type="button"
                    onClick={() => pickImage(true)}
                    className="w-full flex items-center gap-2.5 p-2 rounded-lg hover:bg-muted text-left transition-colors"
                  >
                    <div className="p-1.5 rounded-lg bg-primary/10 shrink-0">
                      <Camera className="h-4 w-4 text-primary" />
                    </div>
                    <div className="min-w-0">
                      <p className="text-xs font-medium">Prendre une photo</p>
                      <p className="text-[10px] text-muted-foreground">Avec l&apos;appareil photo</p>
                    </div>
                  </button>
                </PopoverContent>
              </Popover>
              <Input
                placeholder="Rédiger votre message..."
                value={newMessage}
                onChange={(e) => setNewMessage(e.target.value)}
                disabled={socketStatus !== 'connected'}
                className="flex-1 rounded-2xl min-h-10 h-10 sm:h-11 text-sm bg-background border-input"
              />
              <Button
                type="submit"
                disabled={!newMessage.trim() || socketStatus !== 'connected'}
                className="rounded-2xl h-10 sm:h-11 w-10 sm:w-auto sm:px-4 flex items-center justify-center shrink-0 active:scale-95 transition-transform"
              >
                <Send className="h-4 w-4" />
                <span className="hidden sm:inline ml-2">Envoyer</span>
              </Button>
            </form>
          </div>

        </div>

      </div>
    </div>
  );
}
