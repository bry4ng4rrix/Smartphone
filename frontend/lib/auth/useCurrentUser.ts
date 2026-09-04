'use client';

import { useEffect, useState } from 'react';
import { djangoClient } from '@/lib/django-client';

export interface CurrentUser {
  id: number;
  email: string;
  role: 'admin' | 'magasin' | 'employer' | 'platform_admin';
  full_name: string;
  is_confirmed: boolean;
  phone?: string;
  adresse?: string;
  photo?: string | null;
  company_name?: string;
  logo?: string | null;
  shop_name?: string;
  shop_logo?: string | null;
  magasin_id?: number;
  position?: string;
  // Sous-rôle module Commande (§4/§5 Smartreadme.md) — uniquement pour role="employer".
  commande_role?: 'PREPARATEUR' | 'LIVREUR' | null;
  store_id?: number | null;
  store_name?: string | null;
  store_logo?: string | null;
  is_company_owner?: boolean;
}

export function useCurrentUser() {
  const [user, setUser] = useState<CurrentUser | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const fetchUser = async () => {
      try {
        if (!djangoClient.isAuthenticated()) {
          setUser(null);
          setLoading(false);
          return;
        }
        const data = await djangoClient.get<any>('/users/me/');
        setUser({
          id: data.id,
          email: data.email,
          role: data.role,
          full_name: data.full_name || data.username || '',
          is_confirmed: data.is_confirmed,
          phone: data.phone || undefined,
          adresse: data.adresse || undefined,
          photo: data.photo ?? null,
          company_name: data.company_name || undefined,
          logo: data.logo ?? null,
          shop_name: data.shop_name || undefined,
          shop_logo: data.shop_logo ?? null,
          magasin_id: data.magasin_id || undefined,
          position: data.position || undefined,
          commande_role: data.commande_role ?? null,
          store_id: data.magasin_id ?? null,
          // Admin: affiche le nom/logo de la société. Magasin/employé: nom/logo du magasin.
          store_name: data.role === 'admin' ? (data.company_name ?? null) : (data.shop_name ?? null),
          store_logo: data.role === 'admin' ? (data.logo ?? null) : (data.shop_logo ?? null),
          is_company_owner: !!data.is_company_owner,
        });
      } catch (err) {
        console.error('Error fetching current user:', err);
        setUser(null);
      } finally {
        setLoading(false);
      }
    };

    fetchUser();
  }, []);

  const role = user?.role;
  return {
    user,
    loading,
    isAdmin: role === 'admin',
    isMagasin: role === 'magasin',
    isEmployer: role === 'employer',
    isSuperAdmin: role === 'admin',
    isAdminOrSuperAdmin: role === 'admin' || role === 'magasin',
    isManager: role === 'admin' || role === 'magasin',
    isPlatformOwner: role === 'platform_admin',
    // Module Commande (§4 Smartreadme.md) : Gérant = admin/magasin,
    // Préparateur/Livreur = sous-rôle porté par l'employer.
    isGerant: role === 'admin' || role === 'magasin',
    isPreparateur: role === 'employer' && user?.commande_role === 'PREPARATEUR',
    isLivreur: role === 'employer' && user?.commande_role === 'LIVREUR',
    // The admin who actually owns the company (has an AdminProfile) — as
    // opposed to a co-admin added via "Ajouter un administrateur", who
    // shares full data access but not company-ownership actions (managing
    // other admins, subscription, devices). False for co-admins.
    isCompanyOwner: role === 'admin' && !!user?.is_company_owner,
  };
}
