'use client';

import { useState, useEffect, useRef } from 'react';
import { useCurrentUser } from '@/lib/auth/useCurrentUser';
import { djangoClient } from '@/lib/django-client';
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
  AlertCircle,
  ArrowLeft,
  Plus,
  MoreVertical,
  Pencil,
  Trash2,
  Check,
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
  id: number;
  full_name: string;
  email: string;
  role: 'admin' | 'magasin' | 'employer';
  shop_name?: string;
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
  product?: ChatProductSnapshot | null;
  is_edited?: boolean;
  edited_at?: string | null;
  is_deleted?: boolean;
  timestamp: string;
}

export default function ChatsPage() {
  const { user: currentUser, loading: authLoading } = useCurrentUser();
  const [users, setUsers] = useState<ChatUser[]>([]);
  const [loadingUsers, setLoadingUsers] = useState(true);
  
  // Chat Room state
  const [activeTab, setActiveTab] = useState<'general' | 'direct'>('general');
  const [activeRecipient, setActiveRecipient] = useState<ChatUser | null>(null);
  
  // Message state
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [newMessage, setNewMessage] = useState('');
  const [loadingHistory, setLoadingHistory] = useState(false);

  // Edit message state
  const [editingId, setEditingId] = useState<number | null>(null);
  const [editingContent, setEditingContent] = useState('');

  // Product picker state ("+" button)
  const [productPickerOpen, setProductPickerOpen] = useState(false);
  const [productSearch, setProductSearch] = useState('');
  const [allProducts, setAllProducts] = useState<any[]>([]);
  const [loadingProducts, setLoadingProducts] = useState(false);

  // Search & Filter
  const [searchQuery, setSearchQuery] = useState('');
  const [mobileShowChat, setMobileShowChat] = useState(false);

  // WebSocket state
  const [socketStatus, setSocketStatus] = useState<'connecting' | 'connected' | 'disconnected'>('disconnected');
  const socketRef = useRef<WebSocket | null>(null);
  const reconnectTimeoutRef = useRef<NodeJS.Timeout | null>(null);
  
  // ScrollRef
  const messagesEndRef = useRef<HTMLDivElement | null>(null);

  // 1. Fetch chat users list
  useEffect(() => {
    if (!currentUser) return;
    
    const fetchUsers = async () => {
      try {
        setLoadingUsers(true);
        const data = await djangoClient.chat.users();
        setUsers(data);
      } catch (err) {
        console.error('Error fetching chat users:', err);
        toast.error('Impossible de charger la liste des collaborateurs.');
      } finally {
        setLoadingUsers(false);
      }
    };
    
    fetchUsers();
  }, [currentUser]);

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

          const receivedData: ChatMessage = data;
          setMessages((prev) => {
            // Avoid duplicates
            if (prev.some((m) => m.id === receivedData.id)) return prev;
            return [...prev, receivedData];
          });
        } catch (e) {
          console.error('Error parsing incoming WS message:', e);
        }
      };

      ws.onclose = (event) => {
        setSocketStatus('disconnected');
        console.log('WebSocket Disconnected', event.reason);
        
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
  const openProductPicker = async () => {
    setProductPickerOpen(true);
    if (allProducts.length === 0) {
      setLoadingProducts(true);
      try {
        const data = await djangoClient.products.list();
        setAllProducts(data);
      } catch (err) {
        console.error('Error fetching products:', err);
        toast.error('Impossible de charger les produits.');
      } finally {
        setLoadingProducts(false);
      }
    }
  };

  const handlePickProduct = (product: any) => {
    if (!socketRef.current || socketStatus !== 'connected') return;
    socketRef.current.send(JSON.stringify({
      content: newMessage.trim(),
      product_id: product.id,
    }));
    setNewMessage('');
    setProductPickerOpen(false);
    setProductSearch('');
  };

  const filteredProducts = allProducts.filter((p) => {
    const term = productSearch.toLowerCase();
    return (
      !term ||
      p.name?.toLowerCase().includes(term) ||
      p.reference?.toLowerCase().includes(term)
    );
  });

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
  const filteredUsers = users.filter((u) => {
    const term = searchQuery.toLowerCase();
    return (
      u.full_name.toLowerCase().includes(term) ||
      u.email.toLowerCase().includes(term) ||
      (u.shop_name && u.shop_name.toLowerCase().includes(term))
    );
  });

  const openChatView = () => setMobileShowChat(true);

  const handleSelectGeneral = () => {
    setActiveRecipient(null);
    openChatView();
  };

  const handleSelectUser = (u: ChatUser) => {
    setActiveRecipient(u);
    openChatView();
  };

  const handleTabChange = (val: string) => {
    setActiveTab(val as 'general' | 'direct');
    setMobileShowChat(false);
    if (val === 'general') {
      setActiveRecipient(null);
    } else if (filteredUsers.length > 0) {
      setActiveRecipient(filteredUsers[0]);
    }
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
    <div className="mx-auto px-3 sm:px-6 lg:px-8 py-4 sm:py-6 h-[calc(100dvh-4rem)] sm:h-[calc(100vh-100px)] flex flex-col">
      
      {/* Title & Info */}
      <div className={`flex flex-col md:flex-row justify-between items-start md:items-center mb-4 sm:mb-6 gap-3 sm:gap-4 ${mobileShowChat ? 'hidden md:flex' : ''}`}>
        <div>
          <h1 className="text-2xl sm:text-3xl font-extrabold tracking-tight text-foreground">
            Messagerie Interne
          </h1>
          <p className="text-xs sm:text-sm text-muted-foreground mt-1">
            Collaborez en temps réel avec toute l&apos;équipe de l&apos;entreprise et de vos magasins.
          </p>
        </div>

        {/* Current user micro card */}
        <div className="flex items-center gap-2 sm:gap-3 px-3 sm:px-4 py-2 bg-card border rounded-2xl shadow-sm w-full md:w-auto">
          <Avatar className="h-9 w-9 border-2 border-primary/20">
            <AvatarFallback className="bg-primary/10 text-primary text-xs font-bold">
              {getInitials(currentUser.full_name)}
            </AvatarFallback>
          </Avatar>
          <div className="text-left">
            <p className="text-xs font-semibold leading-none">{currentUser.full_name}</p>
            <p className="text-[10px] text-muted-foreground mt-0.5 max-w-[150px] truncate">{currentUser.email}</p>
          </div>
          <Badge className={`text-[10px] py-0 px-2 font-semibold border ${getRoleBadgeColor(currentUser.role)}`}>
            {getRoleLabel(currentUser.role)}
          </Badge>
        </div>
      </div>

      {/* Main chat box container */}
      <div className="flex-1 min-h-0 bg-card border rounded-2xl sm:rounded-3xl overflow-hidden shadow-md flex">
        
        {/* Left Side: Sidebar */}
        <div className={`${mobileShowChat ? 'hidden md:flex' : 'flex'} w-full md:w-80 border-r flex-col bg-muted/30 shrink-0 select-none`}>
          
          {/* Tab Switcher */}
          <div className="p-3 sm:p-4 border-b">
            <Tabs 
              value={activeTab} 
              onValueChange={handleTabChange}
              className="w-full"
            >
              <TabsList className="grid grid-cols-2 rounded-2xl p-1 bg-muted/80">
                <TabsTrigger value="general" className="rounded-xl py-2 text-xs font-semibold">
                  <Hash className="h-3.5 w-3.5 mr-1.5" />
                  Général
                </TabsTrigger>
                <TabsTrigger value="direct" className="rounded-xl py-2 text-xs font-semibold">
                  <Users className="h-3.5 w-3.5 mr-1.5" />
                  Direct
                </TabsTrigger>
              </TabsList>
            </Tabs>
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
          <ScrollArea className="flex-1">
            <div className="p-2 space-y-1">
              {activeTab === 'general' ? (
                // General Chat Channel Row
                <button
                  onClick={handleSelectGeneral}
                  className={`w-full text-left p-3 rounded-2xl flex items-center gap-3 transition-all ${
                    activeRecipient === null
                      ? 'bg-primary text-primary-foreground shadow-sm shadow-primary/20'
                      : 'hover:bg-accent/60'
                  }`}
                >
                  <div className={`p-2.5 rounded-xl ${
                    activeRecipient === null ? 'bg-primary-foreground/10 text-primary-foreground' : 'bg-primary/10 text-primary'
                  }`}>
                    <Hash className="h-5 w-5" />
                  </div>
                  <div>
                    <h4 className="font-semibold text-sm">Discussion Générale</h4>
                    <p className={`text-xs mt-0.5 ${
                      activeRecipient === null ? 'text-primary-foreground/70' : 'text-muted-foreground'
                    }`}>
                      Canal de diffusion global
                    </p>
                  </div>
                </button>
              ) : (
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
                        <Avatar className="h-10 w-10 border">
                          <AvatarFallback className={`font-semibold text-xs ${
                            activeRecipient?.id === u.id 
                              ? 'bg-primary-foreground/20 text-primary-foreground'
                              : 'bg-muted text-muted-foreground'
                          }`}>
                            {getInitials(u.full_name)}
                          </AvatarFallback>
                        </Avatar>
                        
                        <div className="flex-1 min-w-0">
                          <div className="flex justify-between items-center">
                            <h4 className="font-semibold text-xs truncate max-w-[120px]">{u.full_name}</h4>
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
                        </div>
                      </button>
                    ))
                  )}
                </>
              )}
            </div>
          </ScrollArea>
        </div>

        {/* Right Side: Conversation window */}
        <div className={`${!mobileShowChat ? 'hidden md:flex' : 'flex'} flex-1 flex-col bg-background relative min-w-0`}>
          
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
              {activeTab === 'general' ? (
                <>
                  <div className="p-2.5 rounded-xl bg-primary/10 text-primary shrink-0">
                    <Hash className="h-5 w-5" />
                  </div>
                  <div>
                    <h3 className="font-bold text-sm">Discussion Générale</h3>
                    <p className="text-[10px] text-muted-foreground">Tout le personnel de l'entreprise</p>
                  </div>
                </>
              ) : activeRecipient ? (
                <>
                  <Avatar className="h-10 w-10 shrink-0 border">
                    <AvatarFallback className="bg-primary/15 text-primary text-xs font-bold">
                      {getInitials(activeRecipient.full_name)}
                    </AvatarFallback>
                  </Avatar>
                  <div className="min-w-0">
                    <h3 className="font-bold text-sm truncate">{activeRecipient.full_name}</h3>
                    <div className="flex items-center gap-1.5 mt-0.5">
                      <span className="text-[10px] text-muted-foreground max-w-[150px] truncate">
                        {activeRecipient.email}
                      </span>
                      <span className="text-muted-foreground/30">•</span>
                      <span className="text-[10px] font-semibold text-primary">
                        {getRoleLabel(activeRecipient.role)}
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
                            <span className={`text-[9px] text-muted-foreground/70 mt-1 select-none px-1 ${
                              isOwnMessage ? 'text-right' : 'text-left'
                            }`}>
                              {formatTime(msg.timestamp)}
                              {msg.is_edited && !msg.is_deleted ? ' · modifié' : ''}
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
              <Popover open={productPickerOpen} onOpenChange={setProductPickerOpen}>
                <PopoverTrigger asChild>
                  <Button
                    type="button"
                    variant="outline"
                    size="icon"
                    disabled={socketStatus !== 'connected'}
                    onClick={openProductPicker}
                    className="rounded-2xl h-10 w-10 sm:h-11 sm:w-11 shrink-0"
                  >
                    <Plus className="h-4 w-4" />
                  </Button>
                </PopoverTrigger>
                <PopoverContent align="start" side="top" className="w-80 p-0">
                  <div className="p-2 border-b">
                    <div className="relative">
                      <Search className="absolute left-2.5 top-2.5 h-3.5 w-3.5 text-muted-foreground" />
                      <Input
                        autoFocus
                        placeholder="Rechercher un produit..."
                        value={productSearch}
                        onChange={(e) => setProductSearch(e.target.value)}
                        className="pl-8 h-9 rounded-xl text-xs"
                      />
                    </div>
                  </div>
                  <div className="max-h-64 overflow-y-auto p-1">
                    {loadingProducts ? (
                      <div className="flex items-center justify-center p-6">
                        <Loader2 className="h-4 w-4 animate-spin text-muted-foreground" />
                      </div>
                    ) : filteredProducts.length === 0 ? (
                      <p className="text-xs text-muted-foreground text-center p-6">Aucun produit trouvé</p>
                    ) : (
                      filteredProducts.slice(0, 30).map((p) => (
                        <button
                          key={p.id}
                          type="button"
                          onClick={() => handlePickProduct(p)}
                          className="w-full flex items-center gap-2.5 p-2 rounded-lg hover:bg-muted text-left transition-colors"
                        >
                          <div className="p-1.5 rounded-lg bg-primary/10 shrink-0">
                            <Package className="h-4 w-4 text-primary" />
                          </div>
                          <div className="min-w-0 flex-1">
                            <p className="text-xs font-medium truncate">{p.name}</p>
                            <p className="text-[10px] text-muted-foreground truncate">
                              Réf. {p.reference} · {p.unit_price} Ar
                            </p>
                          </div>
                        </button>
                      ))
                    )}
                  </div>
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
