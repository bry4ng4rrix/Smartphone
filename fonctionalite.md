# Fonctionnalités de l'Application Stock

## 🎯 Vue d'ensemble

Application de gestion de stock multi-rôles avec système d'authentification JWT et gestion des produits.

---

## 👥 Gestion des Utilisateurs

### Inscription (Register)
- **Création de comptes** pour 3 rôles différents :
  - **Admin**: Création automatique du profil AdminProfile avec nom de l'entreprise
  - **Magasin**: Création du profil MagasinProfile lié à un admin, compte non confirmé par défaut
  - **Employer**: Création du profil EmployerProfile lié à un admin ou un magasin, compte non confirmé par défaut
- **Champs requis**: full_name, email, password, role
- **Champs optionnels**: phone, company_name (admin), shop_name (magasin), position (employer), admin_email (magasin/employer)
- **Validation**: Email unique, mot de passe sécurisé

### Connexion (Login)
- **Authentification JWT** avec email et mot de passe
- **Vérification**: Le compte doit être confirmé (`is_confirmed=True`)
- **Response**: Access token et refresh token
- **Sécurité**: Token personnalisé qui bloque les comptes non approuvés

### Rafraîchissement de Token (Refresh)
- **Renouvellement** du access token expiré
- **Utilisation**: Envoi du refresh token pour obtenir un nouveau access token

### Profil Utilisateur (My Profile)
- **Consultation** du profil de l'utilisateur connecté
- **Informations retournées**: id, username, email, role, is_confirmed
- **Authentification requise**: Nécessite un JWT token valide

### Approbation de Compte (Approve User)
- **Validation** des comptes magasin et employer par admin ou magasin
- **Permission**: Réservée aux rôles admin et magasin uniquement
- **Action**: Change `is_confirmed` de False à True
- **Endpoint**: PUT avec user_id en paramètre

### Gestion des Rôles (Role Management)
- **Modification** du rôle de n'importe quel utilisateur par les admins
- **Permission**: Réservée au rôle admin uniquement
- **Action**: Change le rôle d'un utilisateur (admin, magasin, employer)
- **Endpoint**: PUT avec user_id en paramètre
- **Champs**: `role` (nouveau rôle à assigner)
- **Validation**: Vérifie que le rôle est valide (admin, magasin, employer)
- **Response**: Message de confirmation avec l'ancien et le nouveau rôle

### Liste des Utilisateurs par Magasin (Users by Magasin)
- **Consultation groupée** : Permet de lister tous les utilisateurs (gérants et employés) en les regroupant par magasin.
- **Accès restreint** :
  - **Admin**: Voit l'ensemble des magasins avec tous leurs utilisateurs.
  - **Magasin**: Ne voit que son propre magasin et ses employés.
  - **Employer**: Ne voit que son propre magasin et ses collègues/gérant.
- **Endpoint**: GET `/api/users/magasins/users/`

---

## 📦 Gestion des Produits

### Liste des Produits (List)
- **Affichage** des produits selon le rôle de l'utilisateur :
  - **Admin**: Voit tous les produits de tous les magasins
  - **Magasin**: Voit uniquement les produits de son magasin
  - **Employer**: Voit uniquement les produits du magasin où il travaille
- **Filtrage automatique** basé sur les permissions

### Création de Produit (Create)
- **Ajout** de nouveaux produits au stock
- **Permission**: Réservée aux rôles admin et magasin
- **Champs du produit**:
  - **Identification**: name, reference (unique), brand, category, description
  - **Prix**: unit_price, shell_price
  - **Stock**: initial_quantity, alert_threshold
  - **Dates**: expiry_date
  - **Images**: image1, image2, image3, qr_code
  - **Relation**: magasin (automatique pour magasin, optionnel pour admin)
- **Validation**: Référence unique

### Détails d'un Produit (Retrieve)
- **Consultation** des détails d'un produit spécifique
- **Permission**: Authentification requise
- **Accès**: Selon le rôle (même filtrage que la liste)

### Mise à jour de Produit (Update)
- **Modification complète** d'un produit
- **Permission**: Réservée au rôle admin uniquement
- **Champs**: Tous les champs modifiables

### Mise à jour Partielle (Partial Update)
- **Modification partielle** d'un produit
- **Permission**: Réservée au rôle admin uniquement
- **Flexibilité**: Seuls les champs fournis sont modifiés

### Suppression de Produit (Delete)
- **Retrait** d'un produit du stock
- **Permission**: Réservée au rôle admin uniquement
- **Action**: Suppression définitive du produit

---

## 📈 Ventes et Analyses Financières

### Historique des Ventes (Sale Management)
- **Enregistrement des ventes** : Permet de vendre des produits tout en conservant un historique complet.
- **Stock automatique** : Lors de la création d'une vente, le stock disponible du produit (`initial_quantity`) est automatiquement déduit du nombre d'articles vendus.
- **Traçabilité complète** : Lors de la vente, le système enregistre automatiquement :
  - L'**identifiant du magasin** (`magasin_id` / `shop_name`) où le produit est stocké.
  - Le **nom de l'employé** (`seller_name`) ou gérant qui réalise la vente (lié au profil connecté).
- **Détails de transaction** : Stockage du produit, de la quantité, du prix unitaire de vente (`sale_price`), du total calculé automatiquement (`total_price`), de la date de vente (`sold_at`), du vendeur (`seller`) et du magasin (`magasin`).
- **Filtrage par rôle** :
  - **Admin**: Accès à tout l'historique des ventes.
  - **Magasin**: Accès aux ventes de sa boutique uniquement.
  - **Employer**: Accès aux ventes de sa boutique uniquement.

### Totaux de Prix (Totals)
- **Calcul global** : Fournit instantanément la somme globale de tous les `unit_price` (prix d'achat) et de tous les `shell_price` (prix de vente conseillé) de tous les produits enregistrés dans le système.
- **Endpoint dédié** : GET `/api/users/sales/totals/`

### Calcul du Bénéfice (Profit Analytics)
- **Calcul en temps réel** : Analyse financière des profits réels de l'entreprise/magasin selon la formule :
  $$\text{Bénéfice} = \text{Revenu Total} - \text{Coût Total}$$
  Soit : $\sum (\text{sale\_price} \times \text{quantity}) - \sum (\text{product.unit\_price} \times \text{quantity})$.
- **Endpoint dédié** : GET `/api/users/sales/profit/`

### Tableaux de Bord Unifiés (Dashboard API)
- **Visualisation par Rôle** : Fournit un tableau de bord analytique ultra-complet, performant et automatisé qui s'adapte dynamiquement au profil de l'utilisateur connecté via un seul endpoint : `GET /api/users/dashboard/`.
- **Indicateurs Clés de Performance (KPIs) calculés** :
  - **Admin** : Chiffre d'affaires total, bénéfices totaux, valeur totale du stock (prix d'achat), nombre de magasins/employés/produits/ventes, ventes et bénéfices du jour, alertes stock faible, et décompte des produits expirés ou arrivant à expiration (sous 30 jours).
  - **Magasin (Gérant)** : Nombre de ventes de sa boutique, chiffre d'affaires et bénéfices du jour de sa boutique, valeur totale de son propre stock, produits en rupture/stock faible, et produits expirés de sa boutique.
  - **Employer (Vendeur)** : Mes ventes du jour (compteur), montant total de mes transactions de ventes, nombre de produits vendus, et liste de mes dernières transactions.
- **Sécurité et Isolation des Données (Cloisonnement SaaS)** :
  - Les gérants de magasin et employés ne peuvent en aucun cas consulter les bénéfices globaux de la société ou les données de magasins tiers.
  - Les prix d'achat individuels (`unit_price`) sont strictement exclus des listes pour les profils non-admins.

---

## 🔐 Sécurité et Permissions

### Système de Rôles
- **Admin**: Accès total, peut tout voir et modifier
- **Magasin**: Gère son magasin, peut créer des produits et approuver des comptes
- **Employer**: Consultation uniquement des produits de son magasin

### Permissions Personnalisées
- **IsAdmin**: Vérifie que l'utilisateur a le rôle admin
- **IsMagasin**: Vérifie que l'utilisateur a le rôle magasin
- **IsEmployer**: Vérifie que l'utilisateur a le rôle employer
- **IsAuthenticated**: Vérifie que l'utilisateur est connecté

### Authentification JWT
- **Tokens**: Access token (court terme) et Refresh token (long terme)
- **Validation**: Vérification de la confirmation du compte à la connexion
- **Sécurité**: Les tokens sont requis pour les endpoints protégés

---

## 🏢 Structure Organisationnelle

### Hiérarchie des Utilisateurs
- **Admin** (niveau supérieur)
  - Gère plusieurs **Magasins**
    - Chaque Magasin gère ses **Employers**
      - Les Employers travaillent dans un Magasin

### Relations entre Profils
- **AdminProfile**: Lié à un CustomUser (admin)
- **MagasinProfile**: Lié à un CustomUser (magasin) et à un Admin
- **EmployerProfile**: Lié à un CustomUser (employer), à un Magasin et/ou un Admin

---

## 📊 Caractéristiques des Produits

### Informations de Base
- Nom, référence unique, marque, catégorie, description

### Gestion des Prix
- **Prix unitaire (unit_price)** : Prix d'achat d'origine. **Sécurité critique** : Masqué automatiquement via l'API pour les gérants de magasin et les employés (seul l'Admin peut le consulter).
- **Prix de vente (shell_price)** : Prix de vente au détail, visible par tous les rôles.

### Gestion du Stock
- **Quantité initiale** : Stock total disponible.
- **Sécurité et intégrité** : Vérification stricte lors de chaque vente; si la quantité demandée excède le stock disponible, la vente est bloquée avec une erreur explicite.
- **Seuil d'alerte** : Seuil critique pour le réapprovisionnement automatique.

### Dates et Validité
- Date d'expiration des produits
- Dates de création et de mise à jour automatiques

### Médias
- Jusqu'à 3 images par produit (image1, image2, image3)
- Code QR pour identification (qr_code)

### Association
- Chaque produit est lié à un magasin spécifique

---

## 🔄 Workflow d'Utilisation

### Pour un Admin
1. Créer son compte (auto-confirmé)
2. Créer des comptes pour les gérants de magasin
3. Approuver les comptes magasin
4. Gérer tous les produits (CRUD complet)
5. Modifier les rôles des utilisateurs (admin, magasin, employer)
6. Superviser l'ensemble du système

### Pour un Magasin
1. S'inscrire avec l'email de son admin
2. Attendre l'approbation de l'admin
3. Se connecter une fois approuvé
4. Créer des produits pour son magasin
5. Approuver les comptes de ses employés
6. Voir et gérer ses produits

### Pour un Employer
1. S'inscrire avec l'email de son admin ou magasin
2. Attendre l'approbation
3. Se connecter une fois approuvé
4. Consulter les produits de son magasin
5. Pas de droits de modification

---

## 🚀 Points Forts

- **Sécurité**: Authentification JWT robuste
- **Flexibilité**: Système multi-rôles adapté
- **Organisation**: Hiérarchie claire admin → magasin → employer
- **Contrôle**: Permissions granulaires par rôle
- **Traçabilité**: Dates automatiques de création et modification
- **Médias**: Support d'images et QR codes pour les produits
- **Validation**: Comptes non confirmés bloqués jusqu'à approbation
