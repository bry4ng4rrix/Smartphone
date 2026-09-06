'use client';

import { useEffect, useState, useCallback } from 'react';
import { djangoClient } from '@/lib/django-client';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import {
  Table, TableBody, TableCell, TableHead, TableHeader, TableRow,
} from '@/components/ui/table';
import {
  Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle, DialogTrigger,
} from '@/components/ui/dialog';
import { Label } from '@/components/ui/label';
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/ui/select';
import { Badge } from '@/components/ui/badge';
import { Skeleton } from '@/components/ui/skeleton';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { toast } from 'sonner';
import { Check, X, ShieldAlert, Users as UsersIcon, Shield, Briefcase, Plus, Loader2, KeyRound, RefreshCw } from 'lucide-react';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { useCurrentUser } from '@/lib/auth/useCurrentUser';
import { ConfirmDeleteDialog } from '@/components/confirm-delete-dialog';
import { useDebouncedValue } from '@/lib/hooks/useDebouncedValue';

export default function UsersPage() {
  const { user: currentUser, loading: currentUserLoading, isAdmin, isManager, isCompanyOwner } = useCurrentUser();

  const [allUsers, setAllUsers] = useState<any[]>([]);
  const [pendingUsers, setPendingUsers] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchTerm, setSearchTerm] = useState('');

  // Password reset requests (magasin/employer -> admin)
  const [passwordRequests, setPasswordRequests] = useState<any[]>([]);
  const [passwordRequestsLoading, setPasswordRequestsLoading] = useState(true);
  const [passwordRequestsFilter, setPasswordRequestsFilter] = useState('pending');
  const [resolvingRequestId, setResolvingRequestId] = useState<number | null>(null);

  // Add user dialog
  const [isDialogOpen, setIsDialogOpen] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [newUser, setNewUser] = useState({
    full_name: '',
    email: '',
    password: '',
    role: 'employer' as string,
    position: '',
    shop_name: '',
    company_name: '',
  });

  // Edit role dialog
  const [editRoleDialogOpen, setEditRoleDialogOpen] = useState(false);
  const [editingUserRole, setEditingUserRole] = useState<any>(null);
  const [newRoleValue, setNewRoleValue] = useState('');
  const [editRoleLoading, setEditRoleLoading] = useState(false);

  // Delete user confirmation
  const [deleteTarget, setDeleteTarget] = useState<{ id: number; name: string } | null>(null);

  // Ticks every 10 minutes so the "Actif il y a ..." column refreshes without a page reload
  const [now, setNow] = useState(() => new Date());
  useEffect(() => {
    const interval = setInterval(() => setNow(new Date()), 10 * 60 * 1000);
    return () => clearInterval(interval);
  }, []);

  const formatRelativeTime = (dateStr?: string | null) => {
    if (!dateStr) return null;
    const diffMin = Math.max(0, Math.round((now.getTime() - new Date(dateStr).getTime()) / 60000));
    if (diffMin < 1) return "à l'instant";
    if (diffMin < 60) return `il y a ${diffMin} minute${diffMin > 1 ? 's' : ''}`;
    const diffH = Math.round(diffMin / 60);
    if (diffH < 24) return `il y a ${diffH} heure${diffH > 1 ? 's' : ''}`;
    const diffD = Math.round(diffH / 24);
    return `il y a ${diffD} jour${diffD > 1 ? 's' : ''}`;
  };

  const isCurrentlyOnline = (u: any) =>
    !!u.last_login_at && (!u.last_logout_at || new Date(u.last_logout_at) < new Date(u.last_login_at));

  const fetchUsers = useCallback(async () => {
    setLoading(true);
    try {
      const [storeData, pending] = await Promise.all([
        djangoClient.get<any[]>('/users/magasins/users/'),
        djangoClient.auth.getPendingUsers().catch(() => [] as any[]),
      ]);

      const flat: any[] = [];
      const seenUserIds = new Set<number>();

      const addUser = (user: any, shopName?: string, magasinId?: number) => {
        if (!user || seenUserIds.has(user.id)) return;
        seenUserIds.add(user.id);
        flat.push({ ...user, shop_name: shopName || user.shop_name || '-', magasin_id: magasinId ?? user.magasin_id ?? null });
      };

      for (const store of storeData) {
        if (store.manager) addUser(store.manager, store.shop_name, store.magasin_id);
        for (const emp of store.employers || []) addUser(emp, store.shop_name, store.magasin_id);
        for (const companyUser of store.company_users || []) addUser(companyUser, companyUser.shop_name || store.shop_name, companyUser.magasin_id ?? store.magasin_id);
      }
      setAllUsers(flat);
      setPendingUsers(pending);
    } catch (err: any) {
      toast.error('Erreur de chargement: ' + err.message);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (!currentUserLoading) fetchUsers();
  }, [currentUserLoading, fetchUsers]);

  const fetchPasswordRequests = useCallback(async () => {
    setPasswordRequestsLoading(true);
    try {
      const data = await djangoClient.passwordResetRequests.list(
        passwordRequestsFilter === 'all' ? undefined : passwordRequestsFilter
      );
      setPasswordRequests(data);
    } catch (err: any) {
      toast.error('Erreur lors du chargement des demandes: ' + err.message);
    } finally {
      setPasswordRequestsLoading(false);
    }
  }, [passwordRequestsFilter]);

  useEffect(() => {
    if (!currentUserLoading && isAdmin) fetchPasswordRequests();
  }, [currentUserLoading, isAdmin, fetchPasswordRequests]);

  const handleResolvePasswordRequest = async (id: number, action: 'approve' | 'reject') => {
    setResolvingRequestId(id);
    try {
      await djangoClient.passwordResetRequests.resolve(id, action);
      toast.success(action === 'approve' ? 'Demande approuvée' : 'Demande rejetée');
      await fetchPasswordRequests();
    } catch (err: any) {
      toast.error(err.message || 'Erreur lors du traitement');
    } finally {
      setResolvingRequestId(null);
    }
  };


  const handleApprove = async (userId: number) => {
    try {
      await djangoClient.auth.approveUser(userId);
      toast.success('Utilisateur approuvé');
      await fetchUsers();
    } catch (err: any) {
      toast.error(err.message);
    }
  };

  const handleReject = async (userId: number) => {
    if (!confirm('Rejeter et supprimer cet utilisateur ?')) return;
    try {
      await djangoClient.auth.rejectUser(userId);
      toast.success('Utilisateur rejeté');
      await fetchUsers();
    } catch (err: any) {
      toast.error(err.message);
    }
  };

  const handleConfirmDelete = async (password: string) => {
    if (!deleteTarget) return;
    await djangoClient.users.delete(deleteTarget.id, password);
    toast.success('Utilisateur supprimé');
    await fetchUsers();
  };

  const handleUpdateRole = async () => {
    if (!editingUserRole || !newRoleValue) return;
    setEditRoleLoading(true);
    try {
      await djangoClient.put(`/users/role/${editingUserRole.id}/`, { role: newRoleValue });
      toast.success(`Rôle mis à jour : ${newRoleValue}`);
      setEditRoleDialogOpen(false);
      setEditingUserRole(null);
      setNewRoleValue('');
      await fetchUsers();
    } catch (err: any) {
      toast.error(err.message);
    } finally {
      setEditRoleLoading(false);
    }
  };

  const handleAddUser = async (e: React.FormEvent) => {
    e.preventDefault();
    if (newUser.password.length < 6) {
      toast.error('Le mot de passe doit contenir au moins 6 caractères');
      return;
    }

    setIsSubmitting(true);
    try {
      const extraData: any = {};
      if (newUser.role === 'employer') {
        extraData.position = newUser.position;
        extraData.admin_email = currentUser?.email || '';
      } else if (newUser.role === 'magasin') {
        extraData.shop_name = newUser.shop_name;
        extraData.admin_email = currentUser?.email || '';
      }

      let createdUser: any = null;

      if (newUser.role === 'admin') {
        createdUser = await djangoClient.post<any>('/users/add-admin/', {
          email: newUser.email,
          username: newUser.email,
          password: newUser.password,
          role: newUser.role,
          full_name: newUser.full_name,
        });
      } else {
        createdUser = await djangoClient.auth.register(
          newUser.email,
          newUser.email,
          newUser.password,
          newUser.role,
          { full_name: newUser.full_name, ...extraData }
        );
      }

      if (newUser.role !== 'admin') {
        toast.info('Utilisateur créé en attente d\'approbation');
      } else {
        toast.success('Administrateur créé avec succès');
      }

      if (createdUser?.id && newUser.role === 'admin') {
        setAllUsers(prev => [
          {
            id: createdUser.id,
            full_name: newUser.full_name,
            email: newUser.email,
            role: 'admin',
            shop_name: currentUser?.company_name || 'Société',
            magasin_id: null,
            position: '',
            is_confirmed: true,
          },
          ...prev,
        ]);
      }

      setIsDialogOpen(false);
      setNewUser({ full_name: '', email: '', password: '', role: 'employer', position: '', shop_name: '', company_name: '' });
      await fetchUsers();
    } catch (err: any) {
      const errorData = err?.response?.data;
      const usernameError = Array.isArray(errorData?.username) ? errorData.username.join(' ') : '';
      const emailError = Array.isArray(errorData?.email) ? errorData.email.join(' ') : '';

      if (usernameError.toLowerCase().includes('already exists') || emailError.toLowerCase().includes('already exists')) {
        toast.error('Un utilisateur avec ce nom d\'utilisateur ou cet email existe déjà.');
      } else {
        toast.error(err?.message || 'Une erreur est survenue pendant la création du compte.');
      }
    } finally {
      setIsSubmitting(false);
    }
  };

  const debouncedSearchTerm = useDebouncedValue(searchTerm);

  const filteredAll = allUsers.filter(u =>
    (u.full_name || '').toLowerCase().includes(debouncedSearchTerm.toLowerCase()) ||
    (u.email || '').toLowerCase().includes(debouncedSearchTerm.toLowerCase())
  );

  const filteredPending = pendingUsers.filter(u =>
    (u.full_name || '').toLowerCase().includes(debouncedSearchTerm.toLowerCase()) ||
    (u.email || '').toLowerCase().includes(debouncedSearchTerm.toLowerCase())
  );

  const getRoleIcon = (role: string) => {
    if (role === 'admin') return <Shield className="h-4 w-4 text-purple-500" />;
    if (role === 'magasin') return <Briefcase className="h-4 w-4 text-blue-500" />;
    return <UsersIcon className="h-4 w-4 text-green-500" />;
  };

  const getRoleLabel = (role: string) => ({
    admin: 'Administrateur', magasin: 'Gérant', employer: 'Employé',
  }[role] ?? role);

  const PR_STATUS_LABEL: Record<string, string> = {
    pending: 'En attente', approved: 'Approuvée', rejected: 'Rejetée',
  };

  const getPrStatusBadgeClass = (status: string) => {
    switch (status) {
      case 'approved': return 'bg-green-50 text-green-800 border-green-200';
      case 'rejected': return 'bg-red-50 text-red-800 border-red-200';
      default: return 'bg-orange-50 text-orange-800 border-orange-200';
    }
  };

  if (!isManager && !currentUserLoading) {
    return (
      <div className="p-6">
        <Card>
          <CardContent className="flex flex-col items-center justify-center py-20 text-center">
            <ShieldAlert className="h-12 w-12 text-red-500 mb-4" />
            <h2 className="text-xl font-bold">Accès Refusé</h2>
            <p className="text-muted-foreground mt-2">Vous n'avez pas les permissions pour gérer les utilisateurs.</p>
          </CardContent>
        </Card>
      </div>
    );
  }

  return (
    <div className="p-6 space-y-6">
      <div className="flex flex-col md:flex-row justify-between items-start md:items-center gap-4">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Super Administration
          </h1>
          <p className="text-muted-foreground mt-1">Gérez les accès de votre équipe.</p>
        </div>
        <div className="flex items-center gap-2">
          <Input
            placeholder="Rechercher..."
            value={searchTerm}
            onChange={e => setSearchTerm(e.target.value)}
            className="max-w-xs"
          />
          {isManager && (
            <Dialog open={isDialogOpen} onOpenChange={setIsDialogOpen}>
              <DialogTrigger asChild>
                <Button>
                  <Plus className="h-4 w-4 mr-2" />Ajouter
                </Button>
              </DialogTrigger>
              <DialogContent className="sm:max-w-lg">
                <DialogHeader>
                  <DialogTitle>Créer un utilisateur</DialogTitle>
                  <DialogDescription>Le compte sera créé et en attente d'approbation.</DialogDescription>
                </DialogHeader>
                <form onSubmit={handleAddUser} className="space-y-4 pt-2">
                  <div className="space-y-2">
                    <Label>Nom complet *</Label>
                    <Input value={newUser.full_name} onChange={e => setNewUser({ ...newUser, full_name: e.target.value })} placeholder="Jean Dupont" required />
                  </div>
                  <div className="space-y-2">
                    <Label>Email *</Label>
                    <Input type="email" value={newUser.email} onChange={e => setNewUser({ ...newUser, email: e.target.value })} placeholder="jean@exemple.com" required />
                  </div>
                  <div className="space-y-2">
                    <Label>Mot de passe *</Label>
                    <Input type="password" value={newUser.password} onChange={e => setNewUser({ ...newUser, password: e.target.value })} placeholder="••••••••" minLength={6} required />
                  </div>
                  <div className="space-y-2">
                    <Label>Rôle *</Label>
                    <Select value={newUser.role} onValueChange={v => setNewUser({ ...newUser, role: v })}>
                      <SelectTrigger><SelectValue /></SelectTrigger>
                      <SelectContent>
                        <SelectItem value="employer">Employé / Commercial</SelectItem>
                        {isAdmin && <SelectItem value="magasin">Gérant de magasin</SelectItem>}
                        {isCompanyOwner && <SelectItem value="admin">Administrateur</SelectItem>}
                      </SelectContent>
                    </Select>
                  </div>
                  {newUser.role === 'employer' && (
                    <div className="space-y-2">
                      <Label>Poste / Fonction</Label>
                      <Input value={newUser.position} onChange={e => setNewUser({ ...newUser, position: e.target.value })} placeholder="Ex: Vendeur" />
                    </div>
                  )}
                  {newUser.role === 'magasin' && (
                    <div className="space-y-2">
                      <Label>Nom du magasin *</Label>
                      <Input value={newUser.shop_name} onChange={e => setNewUser({ ...newUser, shop_name: e.target.value })} placeholder="Ex: Boutique Ivandry" required />
                    </div>
                  )}

                  <Button type="submit" className="w-full" disabled={isSubmitting}>
                    {isSubmitting ? <><Loader2 className="mr-2 h-4 w-4 animate-spin" />Création...</> : 'Créer l\'utilisateur'}
                  </Button>
                </form>
              </DialogContent>
            </Dialog>
          )}
        </div>
      </div>

      <Tabs defaultValue="actifs">
        <TabsList>
          <TabsTrigger value="actifs">
            Utilisateurs actifs
            {allUsers.length > 0 && <Badge variant="secondary" className="ml-2">{allUsers.length}</Badge>}
          </TabsTrigger>
          <TabsTrigger value="pending">
            En attente
            {pendingUsers.length > 0 && <Badge className="ml-2 bg-orange-100 text-orange-800">{pendingUsers.length}</Badge>}
          </TabsTrigger>
          {isAdmin && (
            <TabsTrigger value="password-resets">
              Réinit. mots de passe
              {passwordRequests.filter(r => r.status === 'pending').length > 0 && (
                <Badge className="ml-2 bg-orange-100 text-orange-800">
                  {passwordRequests.filter(r => r.status === 'pending').length}
                </Badge>
              )}
            </TabsTrigger>
          )}
        </TabsList>

        {/* Active users */}
        <TabsContent value="actifs">
          <Card>
            <CardHeader>
              <CardTitle>Équipe active</CardTitle>
              <CardDescription>Utilisateurs confirmés groupés par magasin</CardDescription>
            </CardHeader>
            <CardContent>
              {loading ? (
                <div className="space-y-2">{Array.from({ length: 4 }).map((_, i) => <Skeleton key={i} className="h-10 w-full" />)}</div>
              ) : (
                <div className="overflow-x-auto">
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>Utilisateur</TableHead>
                        <TableHead>Rôle</TableHead>
                        <TableHead>Magasin</TableHead>
                        <TableHead>Poste</TableHead>
                        <TableHead>Connexion / Déconnexion</TableHead>
                        <TableHead>Actif</TableHead>
                        <TableHead className="text-right">Actions</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {filteredAll.length === 0 ? (
                        <TableRow><TableCell colSpan={8} className="text-center py-8 text-muted-foreground">Aucun utilisateur trouvé</TableCell></TableRow>
                      ) : filteredAll.map(u => (
                        <TableRow key={u.id}>
                          <TableCell>
                            <div className="flex items-center gap-3">
                              {u.photo ? (
                                <img src={u.photo} alt={u.full_name} className="h-8 w-8 rounded-full object-cover border shrink-0" />
                              ) : (
                                <div className="h-8 w-8 rounded-full border bg-muted flex items-center justify-center text-xs font-medium shrink-0">
                                  {(u.full_name || u.email || '?')[0]?.toUpperCase()}
                                </div>
                              )}
                              <div>
                                <div className="font-medium">{u.full_name || 'Sans nom'}</div>
                                <div className="text-xs text-muted-foreground">{u.email}</div>
                                {(u.phone || u.adresse) && (
                                  <div className="text-xs text-muted-foreground">
                                    {[u.phone, u.adresse].filter(Boolean).join(' · ')}
                                  </div>
                                )}
                              </div>
                            </div>
                          </TableCell>
                          <TableCell>
                            <div className="flex items-center gap-2">
                              {getRoleIcon(u.role)}
                              {getRoleLabel(u.role)}
                            </div>
                          </TableCell>
                          <TableCell className="text-sm text-muted-foreground">{u.shop_name || '-'}</TableCell>
                          <TableCell className="text-sm text-muted-foreground">{u.position || '-'}</TableCell>
                          <TableCell className="text-xs text-muted-foreground">
                            {u.last_login_at ? (
                              <div className="space-y-0.5">
                                <div>Connexion : {format(new Date(u.last_login_at), 'dd MMM yyyy HH:mm', { locale: fr })}</div>
                                <div>
                                  Déconnexion :{' '}
                                  {isCurrentlyOnline(u)
                                    ? 'En ligne'
                                    : format(new Date(u.last_logout_at), 'dd MMM yyyy HH:mm', { locale: fr })}
                                </div>
                              </div>
                            ) : '-'}
                          </TableCell>
                          <TableCell className="text-sm">
                            {u.last_login_at ? (
                              isCurrentlyOnline(u) ? (
                                <span className="text-green-700 flex items-center gap-1.5">
                                  <span className="h-1.5 w-1.5 rounded-full bg-green-500 inline-block shrink-0" />
                                  Actif {formatRelativeTime(u.last_login_at)}
                                </span>
                              ) : (
                                <span className="text-muted-foreground flex items-center gap-1.5">
                                  <span className="h-1.5 w-1.5 rounded-full bg-slate-300 inline-block shrink-0" />
                                  Hors ligne {formatRelativeTime(u.last_logout_at)}
                                </span>
                              )
                            ) : (
                              <span className="text-xs text-muted-foreground">Jamais connecté</span>
                            )}
                          </TableCell>
                          <TableCell className="text-right">
                            <div className="flex justify-end gap-2">
                              {/* Managing an admin account (founder or co-admin) is
                                  ownership territory: only the founder gets these
                                  buttons on an "admin" row. Gérant/employé rows stay
                                  manageable by any admin, founder or co-admin. */}
                              {(u.role === 'admin' ? isCompanyOwner : isAdmin) && currentUser && u.id !== currentUser.id && (
                                <Button
                                  variant="outline" size="sm"
                                  className="text-blue-600 hover:text-blue-700 hover:bg-blue-50"
                                  onClick={() => { setEditingUserRole(u); setNewRoleValue(u.role); setEditRoleDialogOpen(true); }}
                                >
                                  Modifier rôle
                                </Button>
                              )}
                              {(u.role === 'admin' ? isCompanyOwner : isAdmin) && currentUser && u.id !== currentUser.id && (
                                <Button
                                  variant="ghost" size="sm"
                                  className="text-red-600 hover:text-red-700 hover:bg-red-50"
                                  onClick={() => setDeleteTarget({ id: u.id, name: u.full_name || u.email })}
                                >
                                  Supprimer
                                </Button>
                              )}
                            </div>
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </div>
              )}
            </CardContent>
          </Card>
        </TabsContent>

        {/* Pending users */}
        <TabsContent value="pending">
          <Card>
            <CardHeader>
              <CardTitle>En attente d'approbation</CardTitle>
              <CardDescription>Comptes créés mais non encore approuvés</CardDescription>
            </CardHeader>
            <CardContent>
              {loading ? (
                <div className="space-y-2">{Array.from({ length: 3 }).map((_, i) => <Skeleton key={i} className="h-10 w-full" />)}</div>
              ) : filteredPending.length === 0 ? (
                <div className="text-center py-12 text-muted-foreground">
                  <p className="text-lg font-medium">Aucune demande en attente</p>
                  <p className="text-sm mt-1">Tous les utilisateurs ont été traités.</p>
                </div>
              ) : (
                <div className="overflow-x-auto">
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>Utilisateur</TableHead>
                        <TableHead>Rôle</TableHead>
                        <TableHead>Magasin / Poste</TableHead>
                        <TableHead>Date inscription</TableHead>
                        <TableHead className="text-right">Actions</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {filteredPending.map(u => (
                        <TableRow key={u.id}>
                          <TableCell>
                            <div className="flex items-center gap-3">
                              {u.photo ? (
                                <img src={u.photo} alt={u.full_name} className="h-8 w-8 rounded-full object-cover border shrink-0" />
                              ) : (
                                <div className="h-8 w-8 rounded-full border bg-muted flex items-center justify-center text-xs font-medium shrink-0">
                                  {(u.full_name || u.email || '?')[0]?.toUpperCase()}
                                </div>
                              )}
                              <div>
                                <div className="font-medium">{u.full_name || 'Sans nom'}</div>
                                <div className="text-xs text-muted-foreground">{u.email}</div>
                                {(u.phone || u.adresse) && (
                                  <div className="text-xs text-muted-foreground">
                                    {[u.phone, u.adresse].filter(Boolean).join(' · ')}
                                  </div>
                                )}
                              </div>
                            </div>
                          </TableCell>
                          <TableCell>
                            <div className="flex items-center gap-2">
                              {getRoleIcon(u.role)}
                              {getRoleLabel(u.role)}
                            </div>
                          </TableCell>
                          <TableCell className="text-sm text-muted-foreground">
                            {u.shop_name || u.position || '-'}
                          </TableCell>
                          <TableCell className="text-xs">
                            {u.created_at ? format(new Date(u.created_at), 'dd MMM yyyy', { locale: fr }) : '-'}
                          </TableCell>
                          <TableCell className="text-right">
                            <div className="flex justify-end gap-2">
                              <Button
                                variant="outline" size="sm"
                                className="text-green-600 hover:text-green-700 hover:bg-green-50"
                                onClick={() => handleApprove(u.id)}
                              >
                                <Check className="h-4 w-4 mr-1" />Approuver
                              </Button>
                              <Button
                                variant="outline" size="sm"
                                className="text-red-600 hover:text-red-700 hover:bg-red-50"
                                onClick={() => handleReject(u.id)}
                              >
                                <X className="h-4 w-4 mr-1" />Rejeter
                              </Button>
                            </div>
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </div>
              )}
            </CardContent>
          </Card>
        </TabsContent>

        {/* Employee/magasin password reset requests */}
        {isAdmin && (
          <TabsContent value="password-resets">
            <Card>
              <CardHeader className="flex flex-row items-center justify-between space-y-0">
                <div>
                  <CardTitle className="flex items-center gap-2">
                    <KeyRound className="h-5 w-5" />
                    Réinitialisations de mot de passe
                  </CardTitle>
                  <CardDescription>
                    Demandes de vos gérants de magasin et commerciaux ayant oublié leur mot de passe
                  </CardDescription>
                </div>
                <div className="flex items-center gap-2">
                  <Select value={passwordRequestsFilter} onValueChange={setPasswordRequestsFilter}>
                    <SelectTrigger className="w-40"><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="pending">En attente</SelectItem>
                      <SelectItem value="approved">Approuvées</SelectItem>
                      <SelectItem value="rejected">Rejetées</SelectItem>
                      <SelectItem value="all">Toutes</SelectItem>
                    </SelectContent>
                  </Select>
                  <Button variant="outline" size="sm" onClick={fetchPasswordRequests} disabled={passwordRequestsLoading}>
                    <RefreshCw className={`h-4 w-4 ${passwordRequestsLoading ? 'animate-spin' : ''}`} />
                  </Button>
                </div>
              </CardHeader>
              <CardContent>
                {passwordRequestsLoading ? (
                  <div className="space-y-2">{Array.from({ length: 3 }).map((_, i) => <Skeleton key={i} className="h-16 w-full" />)}</div>
                ) : passwordRequests.length === 0 ? (
                  <div className="text-center py-12 text-muted-foreground">
                    Aucune demande {passwordRequestsFilter !== 'all' ? PR_STATUS_LABEL[passwordRequestsFilter]?.toLowerCase() : ''}
                  </div>
                ) : (
                  <div className="space-y-3">
                    {passwordRequests.map((r) => (
                      <div key={r.id} className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 rounded-lg border p-4">
                        <div className="flex items-start gap-3">
                          <KeyRound className="h-5 w-5 text-violet-500 mt-0.5 shrink-0" />
                          <div>
                            <p className="font-medium text-sm">
                              {r.user_name} — <span className="text-blue-700">{r.user_email}</span>
                            </p>
                            <p className="text-xs text-muted-foreground">
                              {getRoleLabel(r.user_role)}
                              {r.magasin_name ? ` · Magasin : ${r.magasin_name}` : ''}
                            </p>
                            <p className="text-xs text-muted-foreground mt-1">
                              {new Date(r.created_at).toLocaleString('fr-FR')}
                            </p>
                          </div>
                        </div>
                        <div className="flex items-center gap-2 shrink-0">
                          <Badge variant="outline" className={getPrStatusBadgeClass(r.status)}>
                            {PR_STATUS_LABEL[r.status]}
                          </Badge>
                          {r.status === 'pending' && (
                            <>
                              <Button
                                size="sm" variant="outline"
                                className="text-green-700 border-green-200"
                                disabled={resolvingRequestId === r.id}
                                onClick={() => handleResolvePasswordRequest(r.id, 'approve')}
                              >
                                <Check className="h-4 w-4 mr-1" />Approuver
                              </Button>
                              <Button
                                size="sm" variant="outline"
                                className="text-red-700 border-red-200"
                                disabled={resolvingRequestId === r.id}
                                onClick={() => handleResolvePasswordRequest(r.id, 'reject')}
                              >
                                <X className="h-4 w-4 mr-1" />Rejeter
                              </Button>
                            </>
                          )}
                        </div>
                      </div>
                    ))}
                  </div>
                )}
              </CardContent>
            </Card>
          </TabsContent>
        )}

      </Tabs>

      {/* Edit Role Dialog */}
      <Dialog open={editRoleDialogOpen} onOpenChange={setEditRoleDialogOpen}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>Modifier le rôle</DialogTitle>
            <DialogDescription>Changer le rôle de {editingUserRole?.full_name || editingUserRole?.email}</DialogDescription>
          </DialogHeader>
          <div className="space-y-4 pt-4">
            <div className="space-y-2">
              <Label>Nouveau rôle</Label>
              <Select value={newRoleValue} onValueChange={setNewRoleValue}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  {isCompanyOwner && <SelectItem value="admin">Administrateur</SelectItem>}
                  <SelectItem value="magasin">Gérant de magasin</SelectItem>
                  <SelectItem value="employer">Employé / Commercial</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="flex gap-2 justify-end">
              <Button variant="outline" onClick={() => setEditRoleDialogOpen(false)}>Annuler</Button>
              <Button onClick={handleUpdateRole} disabled={!newRoleValue || newRoleValue === editingUserRole?.role || editRoleLoading}>
                {editRoleLoading ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : null}
                Enregistrer
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>

      <ConfirmDeleteDialog
        open={!!deleteTarget}
        onOpenChange={(open) => !open && setDeleteTarget(null)}
        title="Supprimer cet utilisateur"
        description={
          <>
            Vous êtes sur le point de supprimer définitivement{' '}
            <span className="font-medium text-foreground">{deleteTarget?.name}</span>.
            Cette action est irréversible. Entrez votre mot de passe pour confirmer.
          </>
        }
        onConfirm={handleConfirmDelete}
      />
    </div>
  );
}

