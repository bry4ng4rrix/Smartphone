superadmin ------> admin (magasin ) -----> -employer , magasinier

je veux un autre page special pour les super admin superadmin  :
-qui peuvent geree tous les fonctionalites des app 
-peuvent gere un ou plusieurs admin qui gere un ou plusieurs produits 
-qui peuvent voir les statistique d'un ou plusieurs magasins 
-voire les liste des magasin 
-cree un magasin (un admin )
-voir les stat a chaquin magasin(admin) : total des prix de stock , vendue , ajouter , alerts , rapport

================================================================================
ANALYSE APPROFONDIE - DÉVELOPPEUR SENIOR & CHEF DE PROJET
================================================================================

📊 ANALYSE D'IMPACT ARCHITECTURAL:
=================================

1. SÉCURITÉ & RLS (Row Level Security):
   ⚠️  CRITIQUE: Le rôle 'superadmin' doit avoir accès GLOBAL à toutes les données
   - Les RLS policies actuelles filtrent par store_id pour admin/magasinier
   - Le superadmin doit BYPASS ces filtres pour voir TOUT
   - Solution: Ajouter OR get_user_role(auth.uid()) = 'superadmin' dans TOUTES les policies

2. IMPACT SUR LE SYSTÈME D'AUTHENTIFICATION:
   - Le formulaire d'inscription actuel permet de choisir admin/magasinier/employer
   - ⚠️  SÉCURITÉ: Le rôle 'superadmin' NE doit PAS être visible dans le formulaire public
   - Les superadmins doivent être créés MANUELLEMENT par un autre superadmin ou via SQL direct
   - Le trigger handle_new_user() doit rejeter explicitement role='superadmin' depuis l'inscription publique

3. PERFORMANCE & SCALABILITÉ:
   - Le superadmin va récupérer TOUTES les données de TOUS les magasins
   - ⚠️  RISQUE: Si 100+ magasins avec 10k+ produits, les requêtes seront lentes
   - Solution: Implémenter la pagination, lazy loading, et filtres par date
   - Ajouter des indexes sur store_id, created_at pour optimiser les requêtes globales

4. MAINTENABILITÉ:
   - Éviter la duplication de code entre /users et /superadmin
   - Créer des composants réutilisables (UserTable, StoreTable, StatsCard)
   - Extraire la logique métier dans des hooks personnalisés (useGlobalStats, useAllUsers, useAllStores)

================================================================================
FICHIERS À MODIFIER (ANALYSE DÉTAILLÉE):
================================================================================

1. supabase/migrations/20240015_fix_role_constraint.sql
   ⚠️  ATTENTION: Cette migration a déjà été exécutée en production
   - Mieux: Créer une NOUVELLE migration (20240026) au lieu de modifier l'existante
   - DROP CONSTRAINT users_role_check
   - ADD CONSTRAINT avec 'superadmin' inclus

2. lib/auth/useCurrentUser.ts
   - Ajouter isSuperAdmin: boolean dans le return
   - Pas besoin de modifier l'interface (utilise déjà role: string)
   - Impact: Minimal, backward compatible

3. components/auth/register-form.tsx
   ⚠️  SÉCURITÉ CRITIQUE:
   - Ajouter validation: if (role === 'superadmin') return error
   - Le rôle superadmin ne doit JAMAIS être sélectionnable dans le formulaire public
   - Ajouter un commentaire expliquant pourquoi

4. components/layout/sidebar.tsx
   - Ajouter l'item SuperAdmin avec condition superAdminOnly
   - Récupérer isSuperAdmin depuis useCurrentUser()
   - Impact: UI uniquement, pas de breaking changes

5. app/(app)/users/page.tsx
   - Optionnel: Ajouter un lien vers /superadmin si isSuperAdmin
   - Permettre aux superadmins d'accéder à la gestion users depuis leur dashboard

================================================================================
FICHIERS À CRÉER (SPÉCIFICATIONS TECHNIQUES):
================================================================================

1. supabase/migrations/20240026_add_superadmin_role.sql
   (Nouveau numéro pour éviter conflits avec migration existante)

   -- DROP et recréer la contrainte
   ALTER TABLE users DROP CONSTRAINT IF EXISTS users_role_check;
   ALTER TABLE users ADD CONSTRAINT users_role_check
     CHECK (role IN ('superadmin', 'admin', 'magasinier', 'employer'));

   -- Update get_user_role function
   CREATE OR REPLACE FUNCTION get_user_role(p_user_id uuid)
   RETURNS TEXT AS $$
   DECLARE
     v_role TEXT;
   BEGIN
     SELECT role INTO v_role FROM users WHERE id = p_user_id;
     RETURN COALESCE(v_role, 'employer');
   END;
   $$ LANGUAGE plpgsql SECURITY DEFINER;

   -- Update RLS policies pour TOUS les tables concernés
   -- Pattern: OR get_user_role(auth.uid()) = 'superadmin'
   -- Tables à modifier: users, products, stores, stock_movements, suppliers, categories, notifications, stock_alerts

   -- Update handle_new_user trigger
   -- Ajouter: IF v_role = 'superadmin' THEN RAISE EXCEPTION 'Superadmin must be created manually'; END IF;

   -- Documentation
   COMMENT ON TABLE users IS 'Rôles: superadmin (accès global), admin (1 magasin), magasinier (manager), employer (employé)';

2. components/auth/superadmin-guard.tsx
   - Structure identique à admin-guard.tsx
   - Import: useCurrentUser, isSuperAdmin
   - Redirection: /dashboard si pas superadmin
   - Message: "Accès réservé aux super administrateurs"

3. app/(app)/superadmin/page.tsx
   ⚠️  PERFORMANCE: Cette page peut devenir très lourde

   STRUCTURE RECOMMANDÉE:
   ┌─────────────────────────────────────────┐
   │ Header: Super Admin Dashboard           │
   ├─────────────────────────────────────────┤
   │ Section 1: KPIs Globaux (6 cartes)      │
   │ - Total magasins, admins, produits     │
   │ - Valeur stock totale, employés         │
   ├─────────────────────────────────────────┤
   │ Section 2: Liste des Magasins           │
   │ - Table avec pagination                 │
   │ - Filtre par magasin                    │
   │ - Actions: Voir détails, désactiver    │
   ├─────────────────────────────────────────┤
   │ Section 3: Gestion Utilisateurs (Tabs)  │
   │ - Tab 1: Tous les utilisateurs         │
   │ - Tab 2: Admins uniquement             │
   │ - Tab 3: Employés/Magasiniers          │
   │ - Actions: Créer, Modifier, Supprimer  │
   ├─────────────────────────────────────────┤
   │ Section 4: Statistiques par Magasin     │
   │ - Sélecteur de magasin                  │
   │ - Graphiques: stock, ventes, alertes   │
   └─────────────────────────────────────────┘

   DONNÉES À RÉCUPÉRER (avec optimisations):
   - SELECT * FROM stores (avec count produits, employés)
   - SELECT * FROM users WHERE role IN ('admin', 'superadmin', 'magasinier', 'employer')
   - SELECT store_id, COUNT(*), SUM(quantity), SUM(quantity * unit_price) FROM products GROUP BY store_id
   - SELECT store_id, COUNT(*) FROM users WHERE status='approved' GROUP BY store_id
   - SELECT store_id, COUNT(*) FROM stock_alerts GROUP BY store_id

4. hooks/useGlobalStats.ts (NOUVEAU - pour la performance)
   - Hook personnalisé pour récupérer les statistiques globales
   - UtiliseuseEffect avec debounce pour éviter trop de requêtes
   - Cache les résultats avec useState
   - Exporte: { globalStats, loading, error, refetch }

5. hooks/useAllUsers.ts (NOUVEAU - pour la réutilisabilité)
   - Hook pour récupérer tous les utilisateurs avec filtres
   - Paramètres: role, status, storeId, searchTerm
   - Pagination incluse
   - Exporte: { users, loading, error, refetch, pagination }

================================================================================
RISQUES & MITIGATIONS:
================================================================================

🚨 RISQUE 1: Performance dégradée avec beaucoup de données
   MITIGATION:
   - Pagination côté serveur (LIMIT/OFFSET dans SQL)
   - Indexes sur les colonnes fréquemment filtrées
   - Lazy loading pour les tableaux
   - Cache React Query pour éviter les requêtes répétées

🚨 RISQUE 2: Sécurité - Accès non autorisé aux données globales
   MITIGATION:
   - SuperAdminGuard sur TOUTES les routes superadmin
   - Vérification côté serveur dans les API endpoints
   - Logs d'audit pour toutes les actions superadmin
   - RLS policies strictes avec superadmin explicitement autorisé

🚨 RISQUE 3: Erreur humaine - Suppression accidentelle de données
   MITIGATION:
   - Confirmation dialog avec détails avant suppression
   - Soft delete au lieu de hard delete (colonne deleted_at)
   - Restaurer les données supprimées (undo functionality)
   - Backup automatique avant actions destructrices

🚨 RISQUE 4: Création de superadmin via formulaire public
   MITIGATION:
   - Validation côté client: rejeter role='superadmin'
   - Validation côté serveur: trigger handle_new_user
   - Supprimer 'superadmin' des options du RadioGroup
   - Log d'alerte si tentative détectée

================================================================================
ORDRE D'EXÉCUTION RECOMMANDÉ (AVECT TESTS):
================================================================================

PHASE 1: PRÉPARATION & DATABASE
─────────────────────────────────
1. Créer migration 20240026_add_superadmin_role.sql
2. Exécuter: pnpm db:migrate
3. Vérifier dans Supabase Dashboard: la contrainte est mise à jour
4. Tester: INSERT INTO users avec role='superadmin' via SQL direct

PHASE 2: AUTHENTIFICATION & SÉCURITÉ
────────────────────────────────────
5. Modifier lib/auth/useCurrentUser.ts
6. Modifier components/auth/register-form.tsx (sécurité)
7. Créer components/auth/superadmin-guard.tsx
8. Tester: Tenter de s'inscrire avec role='superadmin' → doit échouer

PHASE 3: UI & NAVIGATION
─────────────────────────
9. Modifier components/layout/sidebar.tsx
10. Créer hooks personnalisés (useGlobalStats, useAllUsers)
11. Tester: Le lien SuperAdmin n'apparaît que pour les superadmins

PHASE 4: PAGE SUPERADMIN
────────────────────────
12. Créer app/(app)/superadmin/page.tsx
13. Implémenter Section 1: KPIs Globaux
14. Implémenter Section 2: Liste des Magasins
15. Implémenter Section 3: Gestion Utilisateurs
16. Implémenter Section 4: Stats par Magasin
17. Tester avec données de test (10 magasins, 50 utilisateurs)

PHASE 5: TESTS & VALIDATION
───────────────────────────
18. Tests E2E: Créer superadmin, créer admin, créer magasin
19. Tests de performance: Avec 100+ magasins
20. Tests de sécurité: Tentative d'accès non autorisé
21. Review code avec équipe
22. Déploiement en staging

================================================================================
ESTIMATION TEMPS:
================================================================================

- Migration SQL: 1h
- Auth & Guards: 2h
- Sidebar & Navigation: 1h
- Hooks personnalisés: 3h
- Page SuperAdmin (MVP): 8h
- Tests & Debug: 4h
- Review & Documentation: 2h

TOTAL ESTIMÉ: 21 heures (~3 jours de développement)

================================================================================
RECOMMANDATIONS ADDITIONNELLES:
================================================================================

✅ BONNES PRATIQUES:
- Utiliser TypeScript strict pour éviter les erreurs
- Ajouter des commentaires JSDoc pour les fonctions complexes
- Implémenter l'accessibilité (ARIA labels, keyboard navigation)
- Ajouter des tests unitaires pour les hooks
- Documenter l'API superadmin dans API_README.md

✅ AMÉLIORATIONS FUTURES:
- Ajouter un système de permissions granulaires (RBAC avancé)
- Implémenter l'audit trail complet pour les actions superadmin
- Ajouter des notifications en temps réel pour les superadmins
- Créer des rapports automatisés (PDF/Excel) par magasin
- Implémenter le multi-langue (i18n)

✅ MONITORING:
- Ajouter des logs Sentry pour les erreurs superadmin
- Monitorer les temps de réponse des requêtes globales
- Alertes si un superadmin effectue des actions suspectes
- Analytics sur l'utilisation des fonctionnalités superadmin

================================================================================
DÉTAILS D'IMPLÉMENTATION
================================================================================

🔧 MIGRATION SQL (20240025_add_superadmin_role.sql):
----------------------------------------------------
- ALTER TABLE users DROP CONSTRAINT users_role_check
- ALTER TABLE users ADD CONSTRAINT users_role_check CHECK (role IN ('superadmin', 'admin', 'magasinier', 'employer'))
- UPDATE get_user_role() function pour retourner 'employer' par défaut si pas trouvé
- UPDATE toutes les RLS policies pour inclure superadmin dans les permissions
- UPDATE handle_new_user() trigger pour gérer le rôle superadmin (auto-approved)
- COMMENT pour documenter la hiérarchie

🔧 USECURRENTUSER.TS:
---------------------
- Ajouter dans l'interface: isSuperAdmin?: boolean
- Ajouter dans le return: isSuperAdmin: user?.role === 'superadmin'

🔧 SIDEBAR.TSX:
--------------
- Import: Shield de lucide-react
- Ajouter dans navigationItems:
  {
    label: 'Super Admin',
    href: '/superadmin',
    icon: Shield,
    superAdminOnly: true,
  }
- Modifier le filtre: !item.superAdminOnly || isSuperAdmin
- Récupérer isSuperAdmin depuis useCurrentUser()

🔧 SUPERADMIN-GUARD.TSX:
-------------------------
- Copier la structure de admin-guard.tsx
- Remplacer isAdmin par isSuperAdmin
- Message: "Cette page est réservée aux super administrateurs"

🔧 SUPERADMIN/PAGE.TSX:
-----------------------
Structure de la page:
1. Header avec titre "Super Admin Dashboard"
2. Section Statistiques Globales (6 cartes)
3. Section Liste des Magasins (tableau avec filtre)
4. Section Gestion des Administrateurs et employer (tableau + formulaire création)
5. Section Statistiques par Magasin (détails pour chaque magasin)

Données à récupérer:
- SELECT * FROM stores (tous les magasins)
- SELECT * FROM users WHERE role IN ('admin', 'superadmin') (tous les admins)
- SELECT * FROM products (tous les produits de tous les magasins)
- SELECT * FROM users WHERE role IN ('employer', 'magasinier') (tous les employés)
- SELECT * FROM stock_movements (tous les mouvements)
- SELECT * FROM stock_alerts (toutes les alertes)

================================================================================
ORDRE D'EXÉCUTION RECOMMANDÉ:
===============================
1. Créer la migration SQL
2. Exécuter la migration (pnpm db:migrate)
3. Modifier lib/auth/useCurrentUser.ts
4. Créer components/auth/superadmin-guard.tsx
5. Créer app/(app)/superadmin/page.tsx
6. Modifier components/layout/sidebar.tsx
7. Tester la page superadmin avec un utilisateur superadmin
8. Modifier la page register 
================================================================================ 


