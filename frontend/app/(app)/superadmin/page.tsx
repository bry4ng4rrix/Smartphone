'use client';

import { useEffect, useState, useCallback } from 'react';
import { djangoClient } from '@/lib/django-client';
import { useCurrentUser } from '@/lib/auth/useCurrentUser';
import { useRouter } from 'next/navigation';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Skeleton } from '@/components/ui/skeleton';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { toast } from 'sonner';
import { Shield, Users, Store, RefreshCw, Trash2 } from 'lucide-react';
import { ConfirmDeleteDialog } from '@/components/confirm-delete-dialog';

const roleLabel: Record<string, string> = {
  admin: 'Administrateur',
  magasin: 'Gérant',
  employer: 'Commercial',
};

export default function SuperAdminPage() {
  const { isSuperAdmin, loading: userLoading } = useCurrentUser();
  const router = useRouter();
  const [stores, setStores] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [changingRole, setChangingRole] = useState<number | null>(null);
  const [deleteTarget, setDeleteTarget] = useState<{ id: number; name: string } | null>(null);

  useEffect(() => {
    if (!userLoading && !isSuperAdmin) {
      router.replace('/dashboard');
    }
  }, [isSuperAdmin, userLoading, router]);

  const fetchData = useCallback(async () => {
    setLoading(true);
    try {
      const data = await djangoClient.get<any[]>('/users/magasins/users/');
      setStores(data);
    } catch (err) {
      console.error(err);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (isSuperAdmin) fetchData();
  }, [isSuperAdmin, fetchData]);

  const allUsers = stores.flatMap(s => [
    s.manager ? { ...s.manager, shop_name: s.shop_name } : null,
    ...(s.employers || []).map((e: any) => ({ ...e, shop_name: s.shop_name })),
  ]).filter(Boolean);

  const handleChangeRole = async (userId: number, newRole: string) => {
    setChangingRole(userId);
    try {
      await djangoClient.put(`/users/role/${userId}/`, { role: newRole });
      toast.success('Rôle modifié');
      fetchData();
    } catch (err: any) {
      toast.error(err.message || 'Erreur');
    } finally {
      setChangingRole(null);
    }
  };

  const handleConfirmDelete = async (password: string) => {
    if (!deleteTarget) return;
    await djangoClient.delete(`/users/delete/${deleteTarget.id}/`, { password });
    toast.success('Utilisateur supprimé');
    fetchData();
  };

  if (userLoading || loading) {
    return (
      <div className="p-6 space-y-4">
        {Array.from({ length: 3 }).map((_, i) => <Skeleton key={i} className="h-16 w-full" />)}
      </div>
    );
  }

  return (
    <div className="p-6 space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold tracking-tight flex items-center gap-2">
            <Shield className="h-8 w-8 text-blue-600" />Super Administration
          </h1>
          <p className="text-muted-foreground mt-1">Gestion globale des utilisateurs et magasins</p>
        </div>
        <Button variant="outline" size="sm" onClick={fetchData} disabled={loading}>
          <RefreshCw className={`h-4 w-4 mr-2 ${loading ? 'animate-spin' : ''}`} />Actualiser
        </Button>
      </div>

      {/* Stats */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm flex items-center gap-2"><Store className="h-4 w-4 text-blue-500" />Magasins</CardTitle>
          </CardHeader>
          <CardContent><div className="text-2xl font-bold">{stores.length}</div></CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm flex items-center gap-2"><Users className="h-4 w-4 text-green-500" />Utilisateurs total</CardTitle>
          </CardHeader>
          <CardContent><div className="text-2xl font-bold">{allUsers.length}</div></CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm flex items-center gap-2"><Users className="h-4 w-4 text-orange-500" />En attente</CardTitle>
          </CardHeader>
          <CardContent><div className="text-2xl font-bold">{allUsers.filter((u: any) => !u.is_confirmed).length}</div></CardContent>
        </Card>
      </div>

      {/* All teams table */}
      <Card>
        <CardHeader>
          <CardTitle>Toutes les équipes</CardTitle>
          <CardDescription>{stores.length} équipe(s) enregistrée(s)</CardDescription>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Magasin</TableHead>
                <TableHead>Gérant</TableHead>
                <TableHead>Membres</TableHead>
                <TableHead>Statut</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {stores.map((s: any) => {
                const isActive = !!s.manager?.is_confirmed;
                const memberCount = (s.employers?.length || 0) + (s.manager ? 1 : 0);
                return (
                  <TableRow key={s.magasin_id}>
                    <TableCell className="font-medium">{s.shop_name}</TableCell>
                    <TableCell className="text-sm text-muted-foreground">{s.manager?.full_name || '-'}</TableCell>
                    <TableCell className="text-sm">{memberCount}</TableCell>
                    <TableCell>
                      <Badge variant="outline" className={isActive ? 'text-green-700 border-green-200' : 'text-orange-700 border-orange-200'}>
                        {isActive ? 'Actif' : 'Inactif'}
                      </Badge>
                    </TableCell>
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      {/* All users table */}
      <Card>
        <CardHeader>
          <CardTitle>Tous les utilisateurs</CardTitle>
          <CardDescription>{allUsers.length} compte(s) enregistré(s)</CardDescription>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Nom</TableHead>
                <TableHead>Email</TableHead>
                <TableHead>Magasin</TableHead>
                <TableHead>Rôle</TableHead>
                <TableHead>Statut</TableHead>
                <TableHead>Actions</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {allUsers.map((u: any) => (
                <TableRow key={u.id}>
                  <TableCell className="font-medium">{u.full_name}</TableCell>
                  <TableCell className="text-sm text-muted-foreground">{u.email}</TableCell>
                  <TableCell className="text-sm">{u.shop_name || '-'}</TableCell>
                  <TableCell>
                    {/* The "admin" row here is always the société's founder
                        (co-admins aren't listed in this view) — role changes
                        on an admin account are reserved to the founder and
                        can never target the founder themselves, so this is
                        never actionable. Disabled rather than removed, to
                        keep the column layout consistent. */}
                    <Select
                      value={u.role}
                      onValueChange={(v) => handleChangeRole(u.id, v)}
                      disabled={changingRole === u.id || u.role === 'admin'}
                    >
                      <SelectTrigger className="w-32 h-7 text-xs">
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="admin">Admin</SelectItem>
                        <SelectItem value="magasin">Gérant</SelectItem>
                        <SelectItem value="employer">Commercial</SelectItem>
                      </SelectContent>
                    </Select>
                  </TableCell>
                  <TableCell>
                    <Badge variant="outline" className={u.is_confirmed ? 'text-green-700 border-green-200' : 'text-orange-700 border-orange-200'}>
                      {u.is_confirmed ? 'Actif' : 'En attente'}
                    </Badge>
                  </TableCell>
                  <TableCell>
                    {u.role !== 'admin' && (
                      <Button
                        variant="ghost"
                        size="icon"
                        className="h-7 w-7 text-red-500 hover:text-red-700"
                        onClick={() => setDeleteTarget({ id: u.id, name: u.full_name })}
                      >
                        <Trash2 className="h-4 w-4" />
                      </Button>
                    )}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

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
