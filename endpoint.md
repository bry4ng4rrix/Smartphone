# API Smartphone.Mg — référence des endpoints

API REST (Django REST Framework) du back-office Smartphone.Mg : catalogue et stock, commandes clients (préparation / livraison), commandes fournisseur, caisse, utilisateurs, chat et notifications. Ce document est la référence exhaustive des routes ; cette introduction pose les conventions communes, puis chaque application (`users`, `catalog`, `orders`, `suppliers`) fait l'objet d'une section détaillée.

## Base URL

| Environnement | Base URL |
| --- | --- |
| Production | `http://185.215.167.79:8010/api` |
| Local | `http://127.0.0.1:8010/api` |

Les routes sont montées par application (`Stock/urls.py`) :

| Préfixe | Application | Contenu |
| --- | --- | --- |
| `/api/users/` | `users` | Authentification, profil, utilisateurs et rôles, magasins, caisse, notifications, chat, sauvegardes, réinitialisation de mot de passe. |
| `/api/catalog/` | `catalog` | Catégories, types, marques, références, variantes, mouvements de stock. |
| `/api/orders/` | `orders` | Commandes clients, statuts, zones de livraison, dépenses livreurs, campagnes marketing, tableau de bord et rapports. |
| `/api/suppliers/` | `suppliers` | Approvisionnements fournisseur (module indépendant du stock). |

Toutes les routes se terminent par un `/` (routeurs DRF). Les fichiers média (photos, logos) sont servis sous `/media/` et renvoyés en URL absolue dans les réponses.

## Authentification (JWT)

L'API utilise `rest_framework_simplejwt` comme unique classe d'authentification (`REST_FRAMEWORK["DEFAULT_AUTHENTICATION_CLASSES"]` dans `Stock/settings.py`). Il n'y a pas de session ni de cookie : chaque requête protégée porte l'en-tête

```
Authorization: Bearer <access>
```

### Obtenir un jeton — `POST /api/users/login/`

Vue `CustomLoginView` (`users/urls.py`) avec `CustomTokenObtainPairSerializer` (`users/authentication.py`). L'identifiant est le `username` (dans les données existantes, il s'agit de l'adresse e-mail).

Requête :
```json
{ "username": "gerant@smartphone.mg", "password": "motdepasse" }
```

Réponse `200` :
```json
{
  "refresh": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ0b2tlbl90eXBlIjoicmVmcmVzaCIsImV4cCI6MTc4OTM3NzQ0MCwiaWF0IjoxNzg5MjkxMDQwLCJqdGkiOiJhYjEyIiwidXNlcl9pZCI6MTF9.signature",
  "access": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ0b2tlbl90eXBlIjoiYWNjZXNzIiwiZXhwIjoxNzg5MjkxMzQwLCJpYXQiOjE3ODkyOTEwNDAsImp0aSI6ImNkMzQiLCJ1c2VyX2lkIjoxMX0.signature"
}
```

Le corps ne contient que `refresh` et `access` (le serializer ne renvoie pas d'objet `user`) : le profil s'obtient ensuite par `GET /api/users/me/`. Un `LoginEvent` (IP, user-agent) est enregistré à chaque connexion réussie.

Erreurs :
- `401` — `{"detail": "No active account found with the given credentials"}` : identifiants incorrects ou compte inactif.
- `401` — `{"detail": "Compte non approuvé. Contactez votre administrateur.", "code": "account_not_approved"}` : compte créé mais pas encore validé (`is_confirmed = false`).
- `400` — `{"username": ["This field is required."]}` / `{"password": ["This field is required."]}` : champ manquant.

### Durée de vie des jetons

`Stock/settings.py` ne définit pas de bloc `SIMPLE_JWT` : ce sont les valeurs par défaut de simplejwt qui s'appliquent.

| Jeton | Durée | Remarque |
| --- | --- | --- |
| `access` | **5 minutes** | À renouveler via `/api/users/refresh/` dès qu'une réponse `401 token_not_valid` apparaît. |
| `refresh` | **1 jour** | Pas de rotation (`ROTATE_REFRESH_TOKENS = False`), pas de liste noire : le même `refresh` reste valable 24 h. |

Un jeton d'accès expiré produit :
```json
{
  "detail": "Given token not valid for any token type",
  "code": "token_not_valid",
  "messages": [
    { "token_class": "AccessToken", "token_type": "access", "message": "Token is expired" }
  ]
}
```

### Renouveler le jeton — `POST /api/users/refresh/`

Vue `CustomTokenRefreshView` (`CustomTokenRefreshSerializer`, sans surcharge).

Requête :
```json
{ "refresh": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ0b2tlbl90eXBlIjoicmVmcmVzaCIsImV4cCI6MTc4OTM3NzQ0MCwiaWF0IjoxNzg5MjkxMDQwLCJqdGkiOiJhYjEyIiwidXNlcl9pZCI6MTF9.signature" }
```

Réponse `200` :
```json
{ "access": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ0b2tlbl90eXBlIjoiYWNjZXNzIiwiZXhwIjoxNzg5MjkxNjQwLCJpYXQiOjE3ODkyOTEzNDAsImp0aSI6ImVmNTYiLCJ1c2VyX2lkIjoxMX0.signature" }
```

Erreurs :
- `401` — `{"detail": "Token is invalid or expired", "code": "token_not_valid"}` : `refresh` expiré ou altéré ; l'utilisateur doit se reconnecter.
- `400` — `{"refresh": ["This field is required."]}` : champ manquant.

## Format des erreurs

Les erreurs suivent les conventions DRF :

| Code | Forme | Quand |
| --- | --- | --- |
| `400` | `{"champ": ["message"]}` — une clé par champ invalide ; `non_field_errors` pour une règle globale ; pour un champ imbriqué en liste, une liste d'objets indexés (`{"lines": [{}, {"quantite": ["…"]}]}`) | Validation de serializer (`is_valid(raise_exception=True)`). |
| `400` | `["message"]` ou `{"detail": "…"}` | Règle métier levée dans un service (`django.core.exceptions.ValidationError` reconvertie en `DRFValidationError(str(exc))`). Certaines vues répondent `{"error": "…"}`. |
| `401` | `{"detail": "Authentication credentials were not provided."}` ou l'objet `token_not_valid` ci-dessus | Jeton absent, expiré ou invalide. |
| `403` | `{"detail": "You do not have permission to perform this action."}` ou `{"detail": "<message métier>"}` | Rôle insuffisant, magasin non autorisé, action réservée à la personne assignée. |
| `404` | `{"detail": "No <Modèle> matches the given query."}` | Objet inexistant **ou** hors des magasins accessibles (le scoping se fait dans `get_queryset`, un objet d'un autre magasin est invisible). |
| `405` | `{"detail": "Method \"PUT\" not allowed."}` | Méthode HTTP exclue par `http_method_names` de la vue. |

Les messages métier sont en français ; les messages génériques de DRF/simplejwt restent en anglais (`LANGUAGE_CODE = 'en-us'`).

## Conventions

- **Dates et heures** : ISO 8601 avec décalage, en heure d'Antananarivo (`TIME_ZONE = 'Indian/Antananarivo'`, `USE_TZ = True`), par exemple `"2026-09-13T10:05:02.774119+03:00"`. Les dates seules sont au format `"2026-09-13"`. En entrée, tout format ISO 8601 est accepté ; sans décalage, l'heure est interprétée en heure locale d'Antananarivo.
- **Montants** : ariary (Ar), toujours renvoyés sous forme de **chaînes décimales à 2 décimales** (`"30000.00"`) — `COERCE_DECIMAL_TO_STRING` par défaut. En entrée, un nombre JSON ou une chaîne sont acceptés.
- **Pagination** : **aucune**. `REST_FRAMEWORK` ne définit ni `DEFAULT_PAGINATION_CLASS` ni `PAGE_SIZE` : les routes de liste renvoient un tableau JSON complet, filtrable par paramètres de requête (`magasin_id`, statuts, dates selon la route).
- **Identifiants** : entiers auto-incrémentés. Les numéros lisibles (`CMD-<magasin>-<AAAAMMJJ>-<seq>`, `SUP-<magasin>-<AAAAMMJJ>-<seq>`) sont générés côté serveur et non modifiables.
- **Envoi de fichiers** (photos de statut, logos, images de chat, import de sauvegarde) : `multipart/form-data` ; sinon `application/json`.
- **Méthodes** : `PATCH` pour les modifications partielles ; certaines vues n'exposent qu'un sous-ensemble de méthodes (voir chaque section — le reste renvoie `405`).

Méthodes volontairement désactivées (`http_method_names`, réponse `405 {"detail": "Method \"PUT\" not allowed."}`) : `PUT` sur les commandes, zones, types de dépense, dépenses, campagnes et catégories de caisse (utiliser `PATCH`) ; `PUT`/`PATCH` sur les variantes (le stock se modifie via `adjust/`) et `PUT` sur les mouvements de caisse ; `PUT`/`PATCH`/`DELETE` sur les sessions de caisse (utiliser `open/` et `close/`).

## Rôles et permissions

`CustomUser.role` prend trois valeurs : `admin`, `magasin`, `employer`. Le module Commande (`users/permissions.py::user_commande_role`) les projette sur trois rôles fonctionnels :

| `role` | `commande_role` (EmployerProfile) | Rôle Commande | Périmètre |
| --- | --- | --- | --- |
| `admin` | — | `GERANT` | Propriétaire de la société (ou co-admin ajouté via `add-admin/`) : tous les magasins de la société. |
| `magasin` | — | `GERANT` | Gérant d'un seul magasin (le sien). |
| `employer` | `PREPARATEUR` | `PREPARATEUR` | Employé du dépôt : prépare les commandes, peut créer des commandes « récupération sur place ». |
| `employer` | `LIVREUR` | `LIVREUR` | Livre les commandes, déclare ses dépenses. |
| `employer` | `null` | `null` | Aucun droit dans le module Commande. |

Classes de permission (`users/permissions.py`) :

| Classe | Autorise |
| --- | --- |
| `IsAdmin` | `role = admin`. |
| `IsCompanyOwner` | `role = admin` **et** titulaire d'un `AdminProfile` (exclut les co-admins) — gestion des admins, abonnement, appareils. |
| `IsMagasin` | `role = magasin`. |
| `IsEmployer` | `role = employer`. |
| `IsGerant` | rôle Commande `GERANT` (admin ou magasin). |
| `IsGerantOrReadOnly` | lecture (`GET`, `HEAD`, `OPTIONS`) pour tout utilisateur authentifié, écriture réservée au Gérant — catalogue. |
| `IsAuthenticated` (DRF) | tout utilisateur connecté ; le filtrage fin se fait alors dans la vue (`get_permissions` par action, ou contrôle de `user_commande_role` dans le service). |

Les rôles Commande sont aussi renvoyés par `GET /api/users/me/` (`role`, `role_commande`, `commande_role`) pour que les clients adaptent leur interface.

## Multi-magasins

Chaque objet métier (commande, produit, commande fournisseur, session de caisse, notification) est rattaché à un `MagasinProfile`. La visibilité est calculée par `get_accessible_magasins(user)` (`users/permissions.py`) :

- `admin` → tous les magasins dont il est `admin` ou membre de `admins` (co-admin) ;
- `magasin` → son propre magasin ;
- `employer` → le magasin de son affectation.

Conséquences :

- **Lecture** : les listes sont automatiquement restreintes aux magasins accessibles ; le paramètre de requête `?magasin_id=<id>` permet de filtrer davantage (un id non accessible donne une liste vide, jamais une erreur).
- **Création** : `resolve_magasin_for_request(request)` choisit le magasin cible. Le champ `magasin_id` (ou `magasin`) du corps est facultatif quand l'utilisateur n'accède qu'à un seul magasin (cas d'un compte `magasin`/`employer`, ou d'un admin mono-magasin) ; il devient obligatoire dès qu'il y en a plusieurs — erreur `400 {"magasin_id": "Ce champ est requis (plusieurs magasins accessibles)."}` — et doit être accessible — erreur `403 {"detail": "Magasin non autorisé."}`.
- **Détail / actions** : un objet d'un magasin non accessible renvoie `404`.

## Temps réel (WebSockets)

Trois consommateurs Django Channels (`Stock/asgi.py`, `users/consumers.py`), sur le même hôte/port que l'API (`ws://185.215.167.79:8010/…` en production). L'authentification se fait par le jeton d'accès JWT dans la query string (`?token=<access>`) ; une connexion sans jeton valide est fermée immédiatement.

| URL | Rôle |
| --- | --- |
| `/ws/chat/?token=<access>&room=general` ou `&recipient_id=<user_id>` | Messagerie interne : salon général de la société (`general_<company_id>`) ou conversation privée (`dm_<id1>_<id2>`) ; événements `message`, `message_edited`, `message_deleted`, `message_read`. Deux livreurs ne peuvent pas se contacter entre eux. |
| `/ws/notifications/?token=<access>` | Notifications métier (commandes, commandes fournisseur, caisse, utilisateurs, chat) poussées à la création d'une `Notification` — l'admin reçoit celles de tous ses magasins, un employé/gérant celles de son magasin, chacun celles qui lui sont adressées. Chaque message est l'objet notification (`id`, `notif_type`, `message`, `magasin`, `magasin_name`, `is_read`, `created_at`). |
| `/ws/data/?token=<access>` | Synchronisation de données : à chaque sauvegarde d'un modèle suivi (commande, historique de statut, produit, variante, mouvement de stock, commande fournisseur, caisse…) un événement `{"model": "…", "action": "created" | "updated" | "deleted", "id": <id>, "magasin_id": <id>}` invite le client à recharger la ressource via l'API REST. |

## Exemple de session complète

Toutes les requêtes ci-dessous sont en `Content-Type: application/json`. Les valeurs sont fictives.

### 1. Connexion

`POST /api/users/login/`
```json
{ "username": "gerant@smartphone.mg", "password": "motdepasse" }
```

Réponse `200` :
```json
{
  "refresh": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ0b2tlbl90eXBlIjoicmVmcmVzaCIsImV4cCI6MTc4OTM3NzQ0MCwiaWF0IjoxNzg5MjkxMDQwLCJqdGkiOiJhYjEyIiwidXNlcl9pZCI6MTF9.signature",
  "access": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ0b2tlbl90eXBlIjoiYWNjZXNzIiwiZXhwIjoxNzg5MjkxMzQwLCJpYXQiOjE3ODkyOTEwNDAsImp0aSI6ImNkMzQiLCJ1c2VyX2lkIjoxMX0.signature"
}
```

Les requêtes suivantes portent `Authorization: Bearer <access>`.

### 2. Profil courant

`GET /api/users/me/`

Réponse `200` (compte admin propriétaire, mono-magasin) :
```json
{
  "id": 11,
  "username": "gerant@smartphone.mg",
  "email": "gerant@smartphone.mg",
  "full_name": "Gérant Smartphone.Mg",
  "phone": null,
  "adresse": null,
  "photo": null,
  "role": "admin",
  "role_commande": "GERANT",
  "is_confirmed": true,
  "is_company_owner": true,
  "company_name": "Smartphone.Mg",
  "logo": "http://185.215.167.79:8010/media/company_logo/logo.jpg",
  "magasin_id": 2,
  "shop_name": "Smartphone.Mg"
}
```

Un employé reçoit à la place `"role": "employer"`, `"role_commande": "PREPARATEUR"` (ou `"LIVREUR"`), `"commande_role"`, `"position"`, `"magasin_id"`, `"shop_name"`, `"shop_logo"`.

### 3. Création d'une commande client

`POST /api/orders/` (gérant ou préparateur ; `magasin_id` facultatif ici car un seul magasin est accessible)
```json
{
  "client_nom": "Rakoto Hery",
  "telephone": "+261340000001",
  "telephone_2": "",
  "livraison_zone": "ZONE1",
  "adresse_livraison": "Lot II J 45 Ankadifotsy",
  "mode_paiement": "LIVRAISON",
  "note_preparateur": "",
  "note_livreur": "Appeler avant de passer",
  "items": [
    { "product_variant": 727, "quantite": 1 }
  ]
}
```

Réponse `201` (serializer Gérant) :
```json
{
  "id": 19,
  "magasin": 2,
  "numero": "CMD-2-20260913-0001",
  "date_commande": "2026-09-13T13:05:00+03:00",
  "client_nom": "Rakoto Hery",
  "telephone": "+261340000001",
  "telephone_2": "",
  "livraison_zone": "ZONE1",
  "adresse_livraison": "Lot II J 45 Ankadifotsy",
  "mode_paiement": "LIVRAISON",
  "frais_livraison": "3000.00",
  "total_a_payer": "33000.00",
  "remise_total": "0.00",
  "note_preparateur": "",
  "note_livreur": "Appeler avant de passer",
  "statut_courant": "NOUVELLE",
  "preparateur": null,
  "preparateur_name": null,
  "livreur": null,
  "livreur_name": null,
  "campagne": null,
  "campagne_nom": "",
  "campagnes": [],
  "items": [
    {
      "id": 22,
      "product_variant": 727,
      "reference_name": "pixel 10 pro xl",
      "brand_name": "Google Pixel",
      "type_name": "PRIVACY",
      "category_name": "CACHE ÉCRAN",
      "couleur": "Standard",
      "prix_unitaire": "30000.00",
      "prix_catalogue": null,
      "remise_unitaire": "0.00",
      "quantite": 1,
      "retourne": false
    }
  ],
  "status_history": [
    {
      "id": 63,
      "ancien_statut": null,
      "nouveau_statut": "NOUVELLE",
      "changed_by": 11,
      "changed_by_name": "Gérant Smartphone.Mg",
      "note": null,
      "photo": null,
      "timestamp": "2026-09-13T13:05:35.327794+03:00"
    }
  ],
  "created_at": "2026-09-13T13:05:35.316374+03:00",
  "updated_at": "2026-09-13T13:05:35.316374+03:00"
}
```

Le prix, les frais de livraison (d'après la zone) et le total sont calculés côté serveur ; le stock n'est pas encore touché.

### 4. Changement de statut

`POST /api/orders/19/status/` — le gérant lance la préparation et désigne le préparateur (transition `NOUVELLE → EN_PREPARATION`, qui déduit les articles du stock).
```json
{ "statut": "EN_PREPARATION", "preparateur_id": 12, "note": "Priorité du matin" }
```

Réponse `200` (même structure que la commande, extrait des champs modifiés) :
```json
{
  "id": 19,
  "numero": "CMD-2-20260913-0001",
  "statut_courant": "EN_PREPARATION",
  "preparateur": 12,
  "preparateur_name": "Faly Andrianina",
  "status_history": [
    {
      "id": 63,
      "ancien_statut": null,
      "nouveau_statut": "NOUVELLE",
      "changed_by": 11,
      "changed_by_name": "Gérant Smartphone.Mg",
      "note": null,
      "photo": null,
      "timestamp": "2026-09-13T13:05:35.327794+03:00"
    },
    {
      "id": 64,
      "ancien_statut": "NOUVELLE",
      "nouveau_statut": "EN_PREPARATION",
      "changed_by": 11,
      "changed_by_name": "Gérant Smartphone.Mg",
      "note": "Priorité du matin",
      "photo": null,
      "timestamp": "2026-09-13T13:12:08.115220+03:00"
    }
  ],
  "updated_at": "2026-09-13T13:12:08.115220+03:00"
}
```

Le cycle complet est `NOUVELLE → EN_PREPARATION → PRETE → EN_LIVRAISON → LIVRE` (ou `RETOUR`), plus `ANNULEE` via `/cancel/`. Chaque transition est réservée au rôle concerné (le gérant peut toujours forcer), par exemple `403 {"detail": "Seul le rôle LIVREUR (ou le gérant) peut passer une commande à 'EN_LIVRAISON'."}` ou `400 ["Transition impossible : la commande est 'NOUVELLE', 'PRETE' nécessite 'EN_PREPARATION'."]`. Les clients connectés reçoivent en parallèle les événements `/ws/data/` (`order/updated`, `order_status_history/created`, `product_variant/updated`, `stock_movement/created`) et une notification `/ws/notifications/`.

Les sections suivantes détaillent chaque route, application par application.

## Sommaire

- **Users**
  - [Authentification](#authentification)
  - [POST /api/users/login/ — Connexion (obtention des jetons JWT)](#post-apiuserslogin-connexion-obtention-des-jetons-jwt)
  - [POST /api/users/refresh/ — Rafraîchir le jeton d'accès](#post-apiusersrefresh-rafraîchir-le-jeton-daccès)
  - [POST /api/users/register/ — Inscription d'un compte](#post-apiusersregister-inscription-dun-compte)
  - [POST /api/users/logout-event/ — Horodatage de déconnexion](#post-apiuserslogout-event-horodatage-de-déconnexion)
  - [POST /api/users/add-admin/ — Ajouter un co-administrateur](#post-apiusersadd-admin-ajouter-un-co-administrateur)
  - [Profil](#profil)
  - [GET /api/users/me/ — Profil de l'utilisateur connecté](#get-apiusersme-profil-de-lutilisateur-connecté)
  - [PATCH /api/users/me/ — Mettre à jour son profil (JSON ou multipart)](#patch-apiusersme-mettre-à-jour-son-profil-json-ou-multipart)
  - [POST /api/users/change-password/ — Changer son mot de passe](#post-apiuserschange-password-changer-son-mot-de-passe)
  - [Gestion des comptes](#gestion-des-comptes)
  - [PUT /api/users/approve/{user_id}/ — Approuver un compte en attente](#put-apiusersapproveuser_id-approuver-un-compte-en-attente)
  - [POST /api/users/reject/{user_id}/ — Rejeter (supprimer) un compte](#post-apiusersrejectuser_id-rejeter-supprimer-un-compte)
  - [GET /api/users/pending/ — Comptes en attente d'approbation](#get-apiuserspending-comptes-en-attente-dapprobation)
  - [PUT /api/users/role/{user_id}/ — Changer le rôle d'un utilisateur](#put-apiusersroleuser_id-changer-le-rôle-dun-utilisateur)
  - [DELETE /api/users/delete/{user_id}/ — Supprimer un utilisateur (avec mot de passe)](#delete-apiusersdeleteuser_id-supprimer-un-utilisateur-avec-mot-de-passe)
  - [PUT /api/users/employers/{user_id}/commande-role/ — Assigner le sous-rôle Préparateur/Livreur](#put-apiusersemployersuser_idcommande-role-assigner-le-sous-rôle-préparateurlivreur)
  - [Magasins](#magasins)
  - [GET /api/users/magasins/ — Lister les magasins accessibles](#get-apiusersmagasins-lister-les-magasins-accessibles)
  - [POST /api/users/magasins/ — Créer un magasin](#post-apiusersmagasins-créer-un-magasin)
  - [GET /api/users/magasins/{id}/ — Détail d'un magasin](#get-apiusersmagasinsid-détail-dun-magasin)
  - [PUT /api/users/magasins/{id}/ — Remplacer nom/description](#put-apiusersmagasinsid-remplacer-nomdescription)
  - [PATCH /api/users/magasins/{id}/ — Modifier nom, logo ou gérant](#patch-apiusersmagasinsid-modifier-nom-logo-ou-gérant)
  - [DELETE /api/users/magasins/{id}/ — Supprimer un magasin (avec mot de passe)](#delete-apiusersmagasinsid-supprimer-un-magasin-avec-mot-de-passe)
  - [GET /api/users/magasins/overview/ — Synthèse par magasin (cartes admin)](#get-apiusersmagasinsoverview-synthèse-par-magasin-cartes-admin)
  - [GET /api/users/magasins/stats/ — Statistiques de stock et ventes par magasin](#get-apiusersmagasinsstats-statistiques-de-stock-et-ventes-par-magasin)
  - [GET /api/users/magasins/users/ — Utilisateurs regroupés par magasin](#get-apiusersmagasinsusers-utilisateurs-regroupés-par-magasin)
  - [POST /api/users/transfer/products/ — Transférer du stock entre magasins](#post-apiuserstransferproducts-transférer-du-stock-entre-magasins)
  - [Réinitialisation de mot de passe (employés / gérants)](#réinitialisation-de-mot-de-passe-employés-gérants)
  - [GET /api/users/password-reset-requests/ — Lister les demandes reçues](#get-apiuserspassword-reset-requests-lister-les-demandes-reçues)
  - [PATCH /api/users/password-reset-requests/{request_id}/ — Approuver ou rejeter une demande](#patch-apiuserspassword-reset-requestsrequest_id-approuver-ou-rejeter-une-demande)
  - [POST /api/users/public/forgot-password/ — Déposer une demande (public)](#post-apiuserspublicforgot-password-déposer-une-demande-public)
  - [GET /api/users/public/forgot-password/status/ — Consulter l'état de sa demande (public)](#get-apiuserspublicforgot-passwordstatus-consulter-létat-de-sa-demande-public)
  - [POST /api/users/public/forgot-password/confirm/ — Définir le nouveau mot de passe (public)](#post-apiuserspublicforgot-passwordconfirm-définir-le-nouveau-mot-de-passe-public)
  - [Caisse — sessions](#caisse-sessions)
  - [GET /api/users/caisse/sessions/ — Lister les sessions de caisse](#get-apiuserscaissesessions-lister-les-sessions-de-caisse)
  - [POST /api/users/caisse/sessions/ — Création directe (désactivée)](#post-apiuserscaissesessions-création-directe-désactivée)
  - [GET /api/users/caisse/sessions/{id}/ — Détail d'une session](#get-apiuserscaissesessionsid-détail-dune-session)
  - [GET /api/users/caisse/sessions/current/ — Session actuellement ouverte](#get-apiuserscaissesessionscurrent-session-actuellement-ouverte)
  - [POST /api/users/caisse/sessions/open/ — Ouvrir une session de caisse](#post-apiuserscaissesessionsopen-ouvrir-une-session-de-caisse)
  - [POST /api/users/caisse/sessions/{id}/close/ — Fermer une session](#post-apiuserscaissesessionsidclose-fermer-une-session)
  - [Caisse — mouvements](#caisse-mouvements)
  - [GET /api/users/caisse/movements/ — Lister les mouvements](#get-apiuserscaissemovements-lister-les-mouvements)
  - [POST /api/users/caisse/movements/ — Enregistrer un mouvement](#post-apiuserscaissemovements-enregistrer-un-mouvement)
  - [GET /api/users/caisse/movements/{id}/ — Détail d'un mouvement](#get-apiuserscaissemovementsid-détail-dun-mouvement)
  - [DELETE /api/users/caisse/movements/{id}/ — Supprimer un mouvement](#delete-apiuserscaissemovementsid-supprimer-un-mouvement)
  - [Caisse — catégories de dépense](#caisse-catégories-de-dépense)
  - [GET /api/users/caisse/categories/ — Lister les catégories](#get-apiuserscaissecategories-lister-les-catégories)
  - [POST /api/users/caisse/categories/ — Créer une catégorie](#post-apiuserscaissecategories-créer-une-catégorie)
  - [GET /api/users/caisse/categories/{id}/ — Détail d'une catégorie](#get-apiuserscaissecategoriesid-détail-dune-catégorie)
  - [PATCH /api/users/caisse/categories/{id}/ — Renommer une catégorie](#patch-apiuserscaissecategoriesid-renommer-une-catégorie)
  - [DELETE /api/users/caisse/categories/{id}/ — Supprimer une catégorie](#delete-apiuserscaissecategoriesid-supprimer-une-catégorie)
  - [GET /api/users/caisse/summary/ — Résumé caisse et ventes sur une période](#get-apiuserscaissesummary-résumé-caisse-et-ventes-sur-une-période)
  - [Notifications](#notifications)
  - [GET /api/users/notifications/ — Lister les notifications visibles](#get-apiusersnotifications-lister-les-notifications-visibles)
  - [POST /api/users/notifications/ — Créer une notification manuelle](#post-apiusersnotifications-créer-une-notification-manuelle)
  - [GET /api/users/notifications/{id}/ — Détail d'une notification](#get-apiusersnotificationsid-détail-dune-notification)
  - [PUT /api/users/notifications/{id}/ — Remplacer une notification](#put-apiusersnotificationsid-remplacer-une-notification)
  - [PATCH /api/users/notifications/{id}/ — Marquer lue / non lue](#patch-apiusersnotificationsid-marquer-lue-non-lue)
  - [DELETE /api/users/notifications/{id}/ — Supprimer une notification](#delete-apiusersnotificationsid-supprimer-une-notification)
  - [POST /api/users/notifications/mark-all-read/ — Tout marquer comme lu](#post-apiusersnotificationsmark-all-read-tout-marquer-comme-lu)
  - [POST /api/users/notifications/bulk-read/ — Marquer une sélection comme lue](#post-apiusersnotificationsbulk-read-marquer-une-sélection-comme-lue)
  - [POST /api/users/notifications/bulk-delete/ — Supprimer une sélection](#post-apiusersnotificationsbulk-delete-supprimer-une-sélection)
  - [POST /api/users/notifications/delete-all/ — Tout supprimer](#post-apiusersnotificationsdelete-all-tout-supprimer)
  - [Chat](#chat)
  - [GET /api/users/chat/users/ — Contacts joignables](#get-apiuserschatusers-contacts-joignables)
  - [GET /api/users/chat/history/ — Historique d'une conversation](#get-apiuserschathistory-historique-dune-conversation)
  - [GET /api/users/chat/unread-count/ — Compteur de messages non lus](#get-apiuserschatunread-count-compteur-de-messages-non-lus)
  - [POST /api/users/chat/upload/ — Envoyer une image dans le chat (multipart)](#post-apiuserschatupload-envoyer-une-image-dans-le-chat-multipart)
  - [Tableau de bord et divers](#tableau-de-bord-et-divers)
  - [GET /api/users/dashboard/ — Indicateurs du tableau de bord](#get-apiusersdashboard-indicateurs-du-tableau-de-bord)
  - [GET /api/users/endpoints/ — Liste statique des endpoints](#get-apiusersendpoints-liste-statique-des-endpoints)
  - [GET /api/users/backup/export/ — Exporter la base et les médias (zip)](#get-apiusersbackupexport-exporter-la-base-et-les-médias-zip)
  - [POST /api/users/backup/import/ — Restaurer depuis une archive (multipart)](#post-apiusersbackupimport-restaurer-depuis-une-archive-multipart)
- **Temps réel (WebSocket)**
  - [/ws/notifications/?token= — Flux de notifications](#wsnotificationstoken-flux-de-notifications)
  - [/ws/data/?token= — Synchronisation des données](#wsdatatoken-synchronisation-des-données)
  - [/ws/chat/?token=&recipient_id= (ou &room=) — Messagerie](#wschattokenrecipient_id-ou-room-messagerie)
- **Catalog (catalogue produit et stock)**
  - [Catégories — categories/](#catégories-categories)
  - [GET /api/catalog/categories/ — Lister les catégories](#get-apicatalogcategories-lister-les-catégories)
  - [POST /api/catalog/categories/ — Créer une catégorie](#post-apicatalogcategories-créer-une-catégorie)
  - [GET /api/catalog/categories/{id}/ — Détail d'une catégorie](#get-apicatalogcategoriesid-détail-dune-catégorie)
  - [PUT /api/catalog/categories/{id}/ — Remplacer une catégorie](#put-apicatalogcategoriesid-remplacer-une-catégorie)
  - [PATCH /api/catalog/categories/{id}/ — Modifier partiellement une catégorie](#patch-apicatalogcategoriesid-modifier-partiellement-une-catégorie)
  - [DELETE /api/catalog/categories/{id}/ — Supprimer une catégorie](#delete-apicatalogcategoriesid-supprimer-une-catégorie)
  - [Sous-types — types/](#sous-types-types)
  - [GET /api/catalog/types/ — Lister les sous-types](#get-apicatalogtypes-lister-les-sous-types)
  - [POST /api/catalog/types/ — Créer un sous-type](#post-apicatalogtypes-créer-un-sous-type)
  - [GET /api/catalog/types/{id}/ — Détail d'un sous-type](#get-apicatalogtypesid-détail-dun-sous-type)
  - [PUT /api/catalog/types/{id}/ — Remplacer un sous-type](#put-apicatalogtypesid-remplacer-un-sous-type)
  - [PATCH /api/catalog/types/{id}/ — Modifier partiellement un sous-type](#patch-apicatalogtypesid-modifier-partiellement-un-sous-type)
  - [DELETE /api/catalog/types/{id}/ — Supprimer un sous-type](#delete-apicatalogtypesid-supprimer-un-sous-type)
  - [Marques — brands/](#marques-brands)
  - [GET /api/catalog/brands/ — Lister les marques](#get-apicatalogbrands-lister-les-marques)
  - [POST /api/catalog/brands/ — Créer une marque](#post-apicatalogbrands-créer-une-marque)
  - [GET /api/catalog/brands/{id}/ — Détail d'une marque](#get-apicatalogbrandsid-détail-dune-marque)
  - [PUT /api/catalog/brands/{id}/ — Remplacer une marque](#put-apicatalogbrandsid-remplacer-une-marque)
  - [PATCH /api/catalog/brands/{id}/ — Modifier partiellement une marque](#patch-apicatalogbrandsid-modifier-partiellement-une-marque)
  - [DELETE /api/catalog/brands/{id}/ — Supprimer une marque](#delete-apicatalogbrandsid-supprimer-une-marque)
  - [Couleurs — colors/](#couleurs-colors)
  - [GET /api/catalog/colors/ — Lister les couleurs](#get-apicatalogcolors-lister-les-couleurs)
  - [POST /api/catalog/colors/ — Créer une couleur](#post-apicatalogcolors-créer-une-couleur)
  - [GET /api/catalog/colors/{id}/ — Détail d'une couleur](#get-apicatalogcolorsid-détail-dune-couleur)
  - [PUT /api/catalog/colors/{id}/ — Remplacer une couleur](#put-apicatalogcolorsid-remplacer-une-couleur)
  - [PATCH /api/catalog/colors/{id}/ — Modifier partiellement une couleur](#patch-apicatalogcolorsid-modifier-partiellement-une-couleur)
  - [DELETE /api/catalog/colors/{id}/ — Supprimer une couleur](#delete-apicatalogcolorsid-supprimer-une-couleur)
  - [Références produit — references/](#références-produit-references)
  - [GET /api/catalog/references/ — Lister les références](#get-apicatalogreferences-lister-les-références)
  - [POST /api/catalog/references/ — Créer une référence](#post-apicatalogreferences-créer-une-référence)
  - [GET /api/catalog/references/{id}/ — Détail d'une référence](#get-apicatalogreferencesid-détail-dune-référence)
  - [PUT /api/catalog/references/{id}/ — Remplacer une référence](#put-apicatalogreferencesid-remplacer-une-référence)
  - [PATCH /api/catalog/references/{id}/ — Modifier partiellement une référence](#patch-apicatalogreferencesid-modifier-partiellement-une-référence)
  - [DELETE /api/catalog/references/{id}/ — Supprimer une référence](#delete-apicatalogreferencesid-supprimer-une-référence)
  - [GET /api/catalog/references/autocomplete/ — Recherche pour le formulaire Nouvelle commande](#get-apicatalogreferencesautocomplete-recherche-pour-le-formulaire-nouvelle-commande)
  - [POST /api/catalog/references/bulk-update-price/ — Modification groupée des prix d'un sous-type](#post-apicatalogreferencesbulk-update-price-modification-groupée-des-prix-dun-sous-type)
  - [GET /api/catalog/references/export-excel/ — Exporter le catalogue en Excel](#get-apicatalogreferencesexport-excel-exporter-le-catalogue-en-excel)
  - [POST /api/catalog/references/import-excel/ — Importer / actualiser le catalogue depuis Excel](#post-apicatalogreferencesimport-excel-importer-actualiser-le-catalogue-depuis-excel)
  - [Lots d'import — import-batches/](#lots-dimport-import-batches)
  - [POST /api/catalog/import-batches/{id}/cancel/ — Annuler un import Excel](#post-apicatalogimport-batchesidcancel-annuler-un-import-excel)
  - [Variantes (couleurs) — variants/](#variantes-couleurs-variants)
  - [GET /api/catalog/variants/ — Lister les variantes](#get-apicatalogvariants-lister-les-variantes)
  - [POST /api/catalog/variants/ — Créer une variante (couleur)](#post-apicatalogvariants-créer-une-variante-couleur)
  - [GET /api/catalog/variants/{id}/ — Détail d'une variante](#get-apicatalogvariantsid-détail-dune-variante)
  - [DELETE /api/catalog/variants/{id}/ — Supprimer une variante](#delete-apicatalogvariantsid-supprimer-une-variante)
  - [POST /api/catalog/variants/{id}/adjust/ — Ajustement manuel du stock](#post-apicatalogvariantsidadjust-ajustement-manuel-du-stock)
  - [Mouvements de stock — movements/](#mouvements-de-stock-movements)
  - [GET /api/catalog/movements/ — Historique des mouvements](#get-apicatalogmovements-historique-des-mouvements)
  - [GET /api/catalog/movements/{id}/ — Détail d'un mouvement](#get-apicatalogmovementsid-détail-dun-mouvement)
  - [Notes produit (produits à commander) — notes/](#notes-produit-produits-à-commander-notes)
  - [GET /api/catalog/notes/ — Lister les notes produit](#get-apicatalognotes-lister-les-notes-produit)
  - [POST /api/catalog/notes/ — Créer une note produit](#post-apicatalognotes-créer-une-note-produit)
  - [GET /api/catalog/notes/{id}/ — Détail d'une note produit](#get-apicatalognotesid-détail-dune-note-produit)
  - [PUT /api/catalog/notes/{id}/ — Remplacer une note produit](#put-apicatalognotesid-remplacer-une-note-produit)
  - [PATCH /api/catalog/notes/{id}/ — Modifier partiellement une note produit](#patch-apicatalognotesid-modifier-partiellement-une-note-produit)
  - [DELETE /api/catalog/notes/{id}/ — Supprimer une note produit](#delete-apicatalognotesid-supprimer-une-note-produit)
- **Commandes (application `orders`)**
  - [Commandes](#commandes)
  - [GET /api/orders/ — Liste des commandes](#get-apiorders-liste-des-commandes)
  - [POST /api/orders/ — Créer une commande](#post-apiorders-créer-une-commande)
  - [GET /api/orders/{id}/ — Détail d'une commande](#get-apiordersid-détail-dune-commande)
  - [PATCH /api/orders/{id}/ — Modifier une commande](#patch-apiordersid-modifier-une-commande)
  - [DELETE /api/orders/{id}/ — Supprimer une commande](#delete-apiordersid-supprimer-une-commande)
  - [POST /api/orders/{id}/status/ — Changer le statut (workflow)](#post-apiordersidstatus-changer-le-statut-workflow)
  - [POST /api/orders/{id}/cancel/ — Annuler une commande](#post-apiordersidcancel-annuler-une-commande)
  - [POST /api/orders/{id}/assign-preparateur/ — Pré-assigner un préparateur](#post-apiordersidassign-preparateur-pré-assigner-un-préparateur)
  - [POST /api/orders/{id}/assign-livreur/ — Pré-assigner un livreur](#post-apiordersidassign-livreur-pré-assigner-un-livreur)
  - [POST /api/orders/{id}/corriger-statut/ — Corriger un statut final (LIVRE ↔ RETOUR)](#post-apiordersidcorriger-statut-corriger-un-statut-final-livre-retour)
  - [POST /api/orders/{id}/share-chat/ — Partager la commande dans la messagerie](#post-apiordersidshare-chat-partager-la-commande-dans-la-messagerie)
  - [POST /api/orders/{id}/campagne/ — Rattacher / détacher une campagne marketing](#post-apiordersidcampagne-rattacher-détacher-une-campagne-marketing)
  - [GET /api/orders/available-staff/ — Disponibilité des préparateurs / livreurs](#get-apiordersavailable-staff-disponibilité-des-préparateurs-livreurs)
  - [Zones de livraison (delivery-zones/)](#zones-de-livraison-delivery-zones)
  - [GET /api/orders/delivery-zones/ — Liste des zones](#get-apiordersdelivery-zones-liste-des-zones)
  - [POST /api/orders/delivery-zones/ — Créer une zone](#post-apiordersdelivery-zones-créer-une-zone)
  - [GET /api/orders/delivery-zones/{id}/ — Détail d'une zone](#get-apiordersdelivery-zonesid-détail-dune-zone)
  - [PATCH /api/orders/delivery-zones/{id}/ — Modifier une zone](#patch-apiordersdelivery-zonesid-modifier-une-zone)
  - [DELETE /api/orders/delivery-zones/{id}/ — Supprimer (ou désactiver) une zone](#delete-apiordersdelivery-zonesid-supprimer-ou-désactiver-une-zone)
  - [Types de dépense (expense-types/)](#types-de-dépense-expense-types)
  - [GET /api/orders/expense-types/ — Liste des types](#get-apiordersexpense-types-liste-des-types)
  - [POST /api/orders/expense-types/ — Créer un type](#post-apiordersexpense-types-créer-un-type)
  - [GET /api/orders/expense-types/{id}/ — Détail d'un type](#get-apiordersexpense-typesid-détail-dun-type)
  - [PATCH /api/orders/expense-types/{id}/ — Modifier un type](#patch-apiordersexpense-typesid-modifier-un-type)
  - [DELETE /api/orders/expense-types/{id}/ — Supprimer (ou désactiver) un type](#delete-apiordersexpense-typesid-supprimer-ou-désactiver-un-type)
  - [Dépenses des livreurs (expenses/)](#dépenses-des-livreurs-expenses)
  - [GET /api/orders/expenses/ — Liste des dépenses](#get-apiordersexpenses-liste-des-dépenses)
  - [POST /api/orders/expenses/ — Déclarer une dépense](#post-apiordersexpenses-déclarer-une-dépense)
  - [GET /api/orders/expenses/{id}/ — Détail d'une dépense](#get-apiordersexpensesid-détail-dune-dépense)
  - [PATCH /api/orders/expenses/{id}/ — Modifier une dépense en attente](#patch-apiordersexpensesid-modifier-une-dépense-en-attente)
  - [DELETE /api/orders/expenses/{id}/ — Supprimer une dépense en attente](#delete-apiordersexpensesid-supprimer-une-dépense-en-attente)
  - [POST /api/orders/expenses/{id}/resoudre/ — Accepter ou rejeter une dépense](#post-apiordersexpensesidresoudre-accepter-ou-rejeter-une-dépense)
  - [Campagnes marketing (campaigns/)](#campagnes-marketing-campaigns)
  - [GET /api/orders/campaigns/ — Liste des campagnes](#get-apiorderscampaigns-liste-des-campagnes)
  - [POST /api/orders/campaigns/ — Créer une campagne](#post-apiorderscampaigns-créer-une-campagne)
  - [GET /api/orders/campaigns/{id}/ — Détail d'une campagne](#get-apiorderscampaignsid-détail-dune-campagne)
  - [PATCH /api/orders/campaigns/{id}/ — Modifier une campagne](#patch-apiorderscampaignsid-modifier-une-campagne)
  - [DELETE /api/orders/campaigns/{id}/ — Supprimer une campagne](#delete-apiorderscampaignsid-supprimer-une-campagne)
  - [Tableau de bord](#tableau-de-bord)
  - [GET /api/orders/dashboard/ — Dashboard du gérant](#get-apiordersdashboard-dashboard-du-gérant)
  - [Rapports du gérant (agrégé)](#rapports-du-gérant-agrégé)
  - [GET /api/orders/reports/ — Bilan complet de la période](#get-apiordersreports-bilan-complet-de-la-période)
  - [Centre de rapports (reports/<section>/)](#centre-de-rapports-reportssection)
  - [GET /api/orders/reports/overview/ — Vue générale](#get-apiordersreportsoverview-vue-générale)
  - [GET /api/orders/reports/sales/ — Ventes](#get-apiordersreportssales-ventes)
  - [GET /api/orders/reports/financial/ — Financier](#get-apiordersreportsfinancial-financier)
  - [GET /api/orders/reports/expenses/ — Dépenses](#get-apiordersreportsexpenses-dépenses)
  - [GET /api/orders/reports/stock/ — Stock](#get-apiordersreportsstock-stock)
  - [GET /api/orders/reports/orders/ — Commandes](#get-apiordersreportsorders-commandes)
  - [GET /api/orders/reports/deliveries/ — Livraisons](#get-apiordersreportsdeliveries-livraisons)
  - [GET /api/orders/reports/marketing/ — Marketing](#get-apiordersreportsmarketing-marketing)
- **Suppliers (approvisionnements fournisseur)**
- **Fournisseurs**
  - [GET /api/suppliers/suppliers/ — Liste des fournisseurs](#get-apisupplierssuppliers-liste-des-fournisseurs)
  - [POST /api/suppliers/suppliers/ — Créer un fournisseur](#post-apisupplierssuppliers-créer-un-fournisseur)
  - [GET /api/suppliers/suppliers/{id}/ — Fiche fournisseur](#get-apisupplierssuppliersid-fiche-fournisseur)
  - [PATCH /api/suppliers/suppliers/{id}/ — Modifier · DELETE /api/suppliers/suppliers/{id}/ — Supprimer / désactiver](#patch-apisupplierssuppliersid-modifier-delete-apisupplierssuppliersid-supprimer-désactiver)
- **Approvisionnements (1 sous-type, N paiements, Frais + Douane)**
  - [GET /api/suppliers/orders/kpis/ — Indicateurs de la page](#get-apisuppliersorderskpis-indicateurs-de-la-page)
  - [GET /api/suppliers/orders/ — Liste · GET /api/suppliers/orders/{id}/ — Détail](#get-apisuppliersorders-liste-get-apisuppliersordersid-détail)
  - [POST /api/suppliers/orders/ — Créer un approvisionnement](#post-apisuppliersorders-créer-un-approvisionnement)
  - [PATCH /api/suppliers/orders/{id}/ — Modifier · DELETE — Supprimer un brouillon](#patch-apisuppliersordersid-modifier-delete-supprimer-un-brouillon)
  - [POST …/commander/ · …/preparer/ · …/expedier/ · …/transit/ · …/arriver/ — Avancer le cycle](#post-commander-preparer-expedier-transit-arriver-avancer-le-cycle)
  - [POST /api/suppliers/orders/{id}/frais-douane/ — Frais + Douane](#post-apisuppliersordersidfrais-douane-frais-douane)
  - [POST /api/suppliers/orders/{id}/finaliser/ — Finaliser le coût](#post-apisuppliersordersidfinaliser-finaliser-le-coût)
  - [GET|POST /api/suppliers/orders/{id}/payments/ · DELETE …/payments/{pid}/ — Paiements fournisseur](#getpost-apisuppliersordersidpayments-delete-paymentspid-paiements-fournisseur)
  - [GET /api/suppliers/cost-history/ — Historique des envois d'un sous-type](#get-apisupplierscost-history-historique-des-envois-dun-sous-type)
- **Espace client (nouveau — app `clients`)**
  - [Catalogue public](#catalogue-public)
  - [GET /api/boutiques/ — Boutiques](#get-apiboutiques-boutiques)
  - [GET /api/boutiques/{id}/zones/ — Zones de livraison d'une boutique](#get-apiboutiquesidzones-zones-de-livraison-dune-boutique)
  - [GET /api/categories/ — Catégories (alias : GET /api/type/)](#get-apicategories-catégories-alias-get-apitype)
  - [GET /api/sous-type/ — Sous-types](#get-apisous-type-sous-types)
  - [GET /api/marque/ — Marques](#get-apimarque-marques)
  - [GET /api/couleurs/ — Couleurs](#get-apicouleurs-couleurs)
  - [GET /api/produit/ — Produits (liste paginée)](#get-apiproduit-produits-liste-paginée)
  - [GET /api/produit/{id}/ — Détail d'un produit](#get-apiproduitid-détail-dun-produit)
  - [Compte client](#compte-client)
  - [POST /api/client/register/ — Inscription](#post-apiclientregister-inscription)
  - [POST /api/client/login/ — Connexion](#post-apiclientlogin-connexion)
  - [POST /api/client/refresh/ — Renouveler l'access](#post-apiclientrefresh-renouveler-laccess)
  - [GET /api/client/me/ — Profil](#get-apiclientme-profil)
  - [PATCH /api/client/me/ — Modifier le profil](#patch-apiclientme-modifier-le-profil)
  - [POST /api/client/change-password/ — Changer de mot de passe](#post-apiclientchange-password-changer-de-mot-de-passe)
  - [Commandes du client](#commandes-du-client)
  - [GET /api/client/orders/ — Mes commandes](#get-apiclientorders-mes-commandes)
  - [POST /api/client/orders/ — Passer une commande](#post-apiclientorders-passer-une-commande)
  - [GET /api/client/orders/{id}/ — Suivi d'une commande](#get-apiclientordersid-suivi-dune-commande)
  - [PATCH /api/client/orders/{id}/ — Modifier une commande en attente](#patch-apiclientordersid-modifier-une-commande-en-attente)
  - [POST /api/client/orders/{id}/cancel/ — Annuler une commande](#post-apiclientordersidcancel-annuler-une-commande)
  - [Côté gérant (API interne, ajouts)](#côté-gérant-api-interne-ajouts)
  - [POST /api/orders/{id}/approuver/ — Approuver une commande client](#post-apiordersidapprouver-approuver-une-commande-client)
  - [POST /api/orders/{id}/refuser/ — Refuser une commande client](#post-apiordersidrefuser-refuser-une-commande-client)

---

## Users

Application Django `users` : authentification JWT, comptes et rôles, magasins, caisse, notifications, chat, tableau de bord et sauvegarde.

- **Préfixe d'URL** : `/api/users/` (monté dans `Stock/urls.py`). Les routes des viewsets (`caisse/sessions/`, `caisse/movements/`, `caisse/categories/`, `notifications/`, `magasins/`) sont générées par un `DefaultRouter`, donc chaque détail répond aussi à `HEAD`/`OPTIONS`. Aucune pagination n'est configurée : les listes renvoient un tableau JSON brut.
- **Authentification** : `Authorization: Bearer <access>` (SimpleJWT). Durée de vie de l'access : 5 minutes ; du refresh : 24 h ; pas de rotation. Sans jeton : `401 {"detail": "Authentication credentials were not provided."}` ; jeton invalide/expiré : `401 {"detail": "Given token not valid for any token type", "code": "token_not_valid", "messages": [{"token_class": "AccessToken", "token_type": "access", "message": "Token is invalid"}]}`. Une `permission_class` refusée renvoie `403 {"detail": "You do not have permission to perform this action."}` (messages DRF en anglais, `LANGUAGE_CODE = en-us`). Un objet hors périmètre du queryset d'un viewset renvoie `404 {"detail": "No <Modèle> matches the given query."}`.
- **Rôles** (`CustomUser.role`) : `admin` (propriétaire de société ou co-admin), `magasin` (gérant d'un point de vente), `employer` (employé, avec sous-rôle `commande_role` = `PREPARATEUR` | `LIVREUR` | `null`). Le module Commande dérive un rôle synthétique via `user_commande_role()` : `GERANT` pour `admin` et `magasin`, sinon le `commande_role` de l'employé. `IsGerant` = rôle `admin` ou `magasin`. `IsCompanyOwner` = admin possédant un `AdminProfile` (le fondateur ; un co-admin ajouté par `add-admin/` n'en a pas).
- **Périmètre magasin** : un admin voit les magasins dont il est `admin` (FK) ou membre de `admins` (M2M) ; un gérant voit son `magasin_profile` ; un employé voit le magasin de son `employer_profile`.
- **Serializers** : `RegisterSerializer`, `MagasinProfileSerializer`, `CaisseSessionSerializer`, `CaisseMovementSerializer`, `CaisseCategorySerializer`, `NotificationSerializer`, `ChatMessageSerializer`, `EmployeePasswordResetRequestSerializer` (tous dans `users/serializers.py`). Les montants sérialisés (`DecimalField`) sont des chaînes (`"50000.00"`) ; les montants calculés dans les vues (`dashboard/`, `caisse/summary/`, `magasins/stats/`) sont des nombres. Les dates sont en ISO 8601 avec fuseau `Indian/Antananarivo` (`+03:00`).
- **Temps réel** : voir la section « Temps réel (WebSocket) » en fin de document. Les effets « notification » ci-dessous désignent la création d'un objet `Notification` (signal `post_save` → diffusion WebSocket automatique sur `/ws/notifications/`) ; les effets « data_update » désignent une trame sur `/ws/data/`.

Valeurs d'exemple utilisées dans tout le document (fictives) : société « Boutique Demo » ; admin fondateur `id 11` (`Rakoto Andry`, `admin@boutique-demo.mg`) ; magasin `id 2` (« Boutique Centre ») ; employés `id 12` (`Hery Rabe`, préparateur), `id 13` (`Miora Razafy`, préparatrice), `id 15` (`Fetra Rakotobe`, livreur), `id 17` (`Onja Rasolo`, livreur).

---

### Authentification

### `POST /api/users/login/` — Connexion (obtention des jetons JWT)
**Rôle** : public · **Vue** : `CustomLoginView` (urls.py, `TokenViewBase` + `CustomTokenObtainPairSerializer` de authentication.py)

Effet : vérifie les identifiants, refuse les comptes non approuvés (`is_confirmed = False`), puis enregistre un `LoginEvent` (IP, user-agent) utilisé pour l'affichage « dernière connexion » de `magasins/users/`.

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| email | corps | string | oui | Adresse e-mail (`USERNAME_FIELD`). |
| password | corps | string | oui | Mot de passe. |

Requête :
```json
{ "email": "admin@boutique-demo.mg", "password": "MotDePasse123" }
```

Réponse `200` :
```json
{
  "refresh": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ0b2tlbl90eXBlIjoicmVmcmVzaCIsImV4cCI6MTc4OTAwMDAwMCwidXNlcl9pZCI6MTF9.x1y2z3",
  "access": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ0b2tlbl90eXBlIjoiYWNjZXNzIiwiZXhwIjoxNzg4OTAwMzAwLCJ1c2VyX2lkIjoxMX0.a1b2c3"
}
```

Erreurs :
- `400` — `{"email": ["This field is required."]}` ou `{"password": ["This field is required."]}` : champ manquant.
- `401` — `{"detail": "No active account found with the given credentials"}` : e-mail inconnu, mot de passe incorrect ou `is_active = False`.
- `401` — `{"detail": "Compte non approuvé. Contactez votre administrateur."}` : compte existant mais `is_confirmed = False` (en attente d'approbation via `approve/{user_id}/`).

### `POST /api/users/refresh/` — Rafraîchir le jeton d'accès
**Rôle** : public · **Vue** : `CustomTokenRefreshView` (urls.py, `CustomTokenRefreshSerializer`)

Effet : renvoie un nouveau jeton `access` (5 min) à partir d'un `refresh` valide ; le refresh n'est pas renouvelé (pas de rotation).

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| refresh | corps | string | oui | Jeton de rafraîchissement obtenu au login. |

Requête :
```json
{ "refresh": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ0b2tlbl90eXBlIjoicmVmcmVzaCIsImV4cCI6MTc4OTAwMDAwMCwidXNlcl9pZCI6MTF9.x1y2z3" }
```

Réponse `200` :
```json
{ "access": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ0b2tlbl90eXBlIjoiYWNjZXNzIiwiZXhwIjoxNzg4OTAwNjAwLCJ1c2VyX2lkIjoxMX0.d4e5f6" }
```

Erreurs :
- `400` — `{"refresh": ["This field is required."]}` : champ manquant.
- `401` — `{"detail": "Token is invalid", "code": "token_not_valid"}` (ou `"Token is invalid or expired"` selon la version de SimpleJWT) : refresh illisible ou expiré.

### `POST /api/users/register/` — Inscription d'un compte
**Rôle** : public (un admin authentifié peut aussi l'appeler pour créer directement un compte approuvé) · **Vue** : `RegisterView` (views.py, `RegisterSerializer`)

Effet : crée le `CustomUser` et son profil selon `role`. `admin` → `AdminProfile` + magasin par défaut « Stock Local » (auto-approuvé). `magasin` → `MagasinProfile` rattaché à l'admin désigné par `admin_email`, partagé avec tous les admins de la société. `employer` → `EmployerProfile` rattaché à l'admin (ou au gérant) désigné par `admin_email` ; si l'admin n'a qu'un seul magasin, l'employé y est affecté automatiquement. Les comptes `magasin`/`employer` restent `is_confirmed = false` sauf si la requête est faite par l'admin cible lui-même (jeton Bearer présent). Signal : notification `user` « Nouvel utilisateur: … » (magasin de l'employé si connu) diffusée en WebSocket.

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| username | corps | string | oui | Identifiant unique (en pratique, recopier l'e-mail). |
| full_name | corps | string | oui | Nom complet. |
| email | corps | string (e-mail) | oui | Unique. |
| password | corps | string | oui | Écriture seule. |
| phone | corps | string ≤ 20 | non | Téléphone. |
| role | corps | `admin` \| `magasin` \| `employer` | oui | Absent → erreur `Role invalide`. |
| company_name | corps | string | non | Rôle `admin` uniquement ; défaut = `full_name`. |
| admin_email | corps | string (e-mail) | oui pour `magasin`/`employer` | E-mail de l'admin (ou, pour un employé, d'un gérant `magasin`). |
| shop_name | corps | string | oui pour `magasin` (erreur 500 sinon) | Nom du point de vente. |
| position | corps | string | oui pour `employer` (erreur 500 sinon) | Intitulé de poste. |
| commande_role | corps | `PREPARATEUR` \| `LIVREUR` \| null | non | Rôle `employer` uniquement. |

Requête (employé) :
```json
{
  "username": "hery.rabe@boutique-demo.mg",
  "full_name": "Hery Rabe",
  "email": "hery.rabe@boutique-demo.mg",
  "password": "MotDePasse123",
  "phone": "+261340000001",
  "role": "employer",
  "admin_email": "admin@boutique-demo.mg",
  "position": "Préparateur",
  "commande_role": "PREPARATEUR"
}
```

Requête (admin / nouvelle société) :
```json
{
  "username": "admin@boutique-demo.mg",
  "full_name": "Rakoto Andry",
  "email": "admin@boutique-demo.mg",
  "password": "MotDePasse123",
  "role": "admin",
  "company_name": "Boutique Demo"
}
```

Réponse `200` :
```json
{ "message": "Inscription réussie", "id": 12 }
```

Erreurs :
- `400` — `{"username": ["This field is required."], "full_name": ["This field is required."], "email": ["This field is required."], "password": ["This field is required."]}` : champs manquants (chaque champ absent est listé).
- `400` — `{"email": ["user with this email already exists."]}` ou `{"username": ["A user with that username already exists."]}` : doublon.
- `400` — `{"role": ["\"boss\" is not a valid choice."]}` : rôle hors liste ; `{"commande_role": ["\"X\" is not a valid choice."]}`.
- `400` — `["Role invalide"]` : `role` absent du corps.
- `400` — `{"admin_email": "Administrateur introuvable avec cet email."}` : rôle `magasin`, aucun admin avec cet e-mail.
- `400` — `{"admin_email": "Responsable (administrateur ou gérant) introuvable avec cet email."}` : rôle `employer`, ni admin ni gérant avec cet e-mail.

### `POST /api/users/logout-event/` — Horodatage de déconnexion
**Rôle** : tout utilisateur authentifié · **Vue** : `LogoutEventView` (views.py)

Effet : renseigne `logged_out_at` sur le dernier `LoginEvent` de l'utilisateur (au mieux : le JWT n'est pas invalidé côté serveur). Sert à l'affichage `last_logout_at` de `magasins/users/`.

Réponse `200` :
```json
{ "message": "Déconnexion enregistrée" }
```

Erreurs :
- `401` — `{"detail": "Authentication credentials were not provided."}` : sans jeton.

### `POST /api/users/add-admin/` — Ajouter un co-administrateur
**Rôle** : `admin` fondateur uniquement (`IsAuthenticated`, `IsCompanyOwner`) · **Vue** : `AddAdminView` (views.py, `RegisterSerializer`)

Effet : crée un compte `admin` approuvé (`is_confirmed = true`), supprime l'`AdminProfile` créé par le serializer (ce n'est pas une nouvelle société) et ajoute ce compte à `admins` de tous les magasins du demandeur. Le co-admin a le même accès aux données mais n'est pas « propriétaire » (`is_company_owner = false`). Signal : notification `user` « Nouvel utilisateur: … ».

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| username | corps | string | oui | Identifiant unique. |
| full_name | corps | string | oui | Nom complet. |
| email | corps | string (e-mail) | oui | Unique. |
| password | corps | string | oui | Mot de passe. |
| role | corps | string | oui | Envoyer `"admin"` (le rôle est forcé à `admin` après création). |
| phone | corps | string | non | Téléphone. |

Requête :
```json
{
  "username": "coadmin@boutique-demo.mg",
  "full_name": "Sitraka Ravelo",
  "email": "coadmin@boutique-demo.mg",
  "password": "MotDePasse123",
  "role": "admin"
}
```

Réponse `201` :
```json
{ "message": "Admin ajouté", "id": 21 }
```

Erreurs :
- `400` — mêmes erreurs de validation que `register/` (`{"email": ["user with this email already exists."]}`, champs requis…).
- `403` — `{"detail": "You do not have permission to perform this action."}` : non-admin ou co-admin sans `AdminProfile`.

---

### Profil

### `GET /api/users/me/` — Profil de l'utilisateur connecté
**Rôle** : tout utilisateur authentifié · **Vue** : `Myprofile` (views.py)

Effet : lecture seule. Les champs varient selon le rôle : `admin` → `company_name`, `logo`, `is_company_owner` (co-admin : nom/logo du fondateur), plus `magasin_id`/`shop_name` s'il n'a qu'un seul magasin ; `magasin` → `shop_name`, `magasin_id`, `shop_logo` ; `employer` → `position`, `commande_role`, et `magasin_id`/`shop_name`/`shop_logo` si affecté. `role_commande` vaut `GERANT`, `PREPARATEUR`, `LIVREUR` ou `null`.

Réponse `200` (admin) :
```json
{
  "id": 11,
  "username": "admin@boutique-demo.mg",
  "email": "admin@boutique-demo.mg",
  "full_name": "Rakoto Andry",
  "phone": "+261340000000",
  "adresse": "Lot II A 12, Antananarivo",
  "photo": null,
  "role": "admin",
  "role_commande": "GERANT",
  "is_confirmed": true,
  "is_company_owner": true,
  "company_name": "Boutique Demo",
  "logo": "http://localhost:8010/media/company_logo/logo-demo.jpg",
  "magasin_id": 2,
  "shop_name": "Boutique Centre"
}
```

Réponse `200` (employé) :
```json
{
  "id": 13,
  "username": "miora.razafy@boutique-demo.mg",
  "email": "miora.razafy@boutique-demo.mg",
  "full_name": "Miora Razafy",
  "phone": null,
  "adresse": null,
  "photo": null,
  "role": "employer",
  "role_commande": "PREPARATEUR",
  "is_confirmed": true,
  "is_company_owner": false,
  "position": "Préparateur",
  "commande_role": "PREPARATEUR",
  "magasin_id": 2,
  "shop_name": "Boutique Centre",
  "shop_logo": null
}
```

Réponse `200` (gérant) :
```json
{
  "id": 22,
  "username": "gerant.centre@boutique-demo.mg",
  "email": "gerant.centre@boutique-demo.mg",
  "full_name": "Lova Andrian",
  "phone": null,
  "adresse": null,
  "photo": null,
  "role": "magasin",
  "role_commande": "GERANT",
  "is_confirmed": true,
  "is_company_owner": false,
  "shop_name": "Boutique Centre",
  "magasin_id": 2,
  "shop_logo": "http://localhost:8010/media/shop_logo/centre.png"
}
```

Erreurs :
- `401` — `{"detail": "Authentication credentials were not provided."}`.

### `PATCH /api/users/me/` — Mettre à jour son profil (JSON ou multipart)
**Rôle** : `admin` ou `magasin` (un employé reçoit 403) · **Vue** : `Myprofile` (views.py)

Effet : met à jour les champs fournis du `CustomUser` (`full_name`, `phone`, `adresse`, `photo`) puis, pour un admin fondateur, `company_name`/`logo` de l'`AdminProfile` (un co-admin n'a pas de profil : seuls ses champs utilisateur changent) ; pour un gérant, `shop_name`/`shop_logo` du `MagasinProfile`. Les fichiers (`photo`, `logo`, `shop_logo`) ne sont pris en compte qu'en `multipart/form-data` : une valeur texte est ignorée.

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| full_name | corps | string | non | Ignoré si vide. |
| phone | corps | string | non | Peut être `""`. |
| adresse | corps | string | non | Peut être `""`. |
| photo | corps (multipart) | fichier image | non | Photo de profil (`user_photos/`). |
| company_name | corps | string | non | Admin fondateur uniquement. |
| logo | corps (multipart) | fichier image | non | Admin fondateur uniquement (`company_logo/`). |
| shop_name | corps | string | non | Gérant uniquement. |
| shop_logo | corps (multipart) | fichier image | non | Gérant uniquement (`shop_logo/`). |

Requête (JSON) :
```json
{ "full_name": "Rakoto Andry", "phone": "+261340000000", "adresse": "Lot II A 12, Antananarivo", "company_name": "Boutique Demo" }
```

Requête (multipart, champs de formulaire) :
```json
{ "full_name": "Rakoto Andry", "photo": "<fichier image>", "logo": "<fichier image>" }
```

Réponse `200` :
```json
{ "message": "Profil mis à jour" }
```

Erreurs :
- `403` — `{"error": "Seul le gérant peut modifier ces informations. Contactez votre gérant."}` : rôle `employer`.

### `POST /api/users/change-password/` — Changer son mot de passe
**Rôle** : `admin` ou `magasin` · **Vue** : `ChangePasswordView` (views.py)

Effet : vérifie l'ancien mot de passe puis enregistre le nouveau (les jetons JWT existants restent valides jusqu'à expiration).

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| old_password | corps | string | oui | Mot de passe actuel. |
| new_password | corps | string ≥ 6 | oui | Nouveau mot de passe. |

Requête :
```json
{ "old_password": "MotDePasse123", "new_password": "NouveauMdp456" }
```

Réponse `200` :
```json
{ "message": "Mot de passe changé avec succès" }
```

Erreurs :
- `403` — `{"error": "Seul le gérant peut modifier ces informations. Contactez votre gérant."}` : rôle `employer`.
- `400` — `{"detail": "Champs requis manquants"}` : `old_password` ou `new_password` absent/vide.
- `400` — `{"detail": "Mot de passe actuel incorrect"}`.
- `400` — `{"detail": "Le mot de passe doit contenir au moins 6 caractères"}`.

---

### Gestion des comptes

### `PUT /api/users/approve/{user_id}/` — Approuver un compte en attente
**Rôle** : `admin` (tout membre de sa société) ou `magasin` (employés de son magasin seulement) · **Vue** : `ApproveUserView` (views.py)

Effet : passe `is_confirmed` à `true`, ce qui débloque la connexion (`login/`).

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| user_id | chemin | int | oui | Identifiant du compte à approuver. |

Réponse `200` :
```json
{ "message": "Utilisateur approuvé" }
```

Erreurs :
- `403` — `{"error": "Permission refusée"}` : rôle `employer`.
- `403` — `{"error": "Permission refusée : entreprise introuvable."}` : demandeur sans admin résolu.
- `403` — `{"error": "Permission refusée : cet employé n'appartient pas à votre magasin."}` : gérant visant un compte hors de son magasin (ou non employé).
- `403` — `{"error": "Permission refusée : cet utilisateur n'appartient pas à votre entreprise."}` : admin visant un compte d'une autre société (ou inexistant).
- `404` — `{"error": "Magasin introuvable"}` : gérant sans `MagasinProfile`.
- `404` — `{"error": "Utilisateur introuvable"}`.

### `POST /api/users/reject/{user_id}/` — Rejeter (supprimer) un compte
**Rôle** : `admin` (membres de sa société) ou `magasin` (employés de son magasin) · **Vue** : `RejectUserView` (views.py)

Effet : supprime définitivement le `CustomUser` et ses profils (cascade). Aucune vérification de mot de passe.

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| user_id | chemin | int | oui | Identifiant du compte à rejeter. |

Réponse `200` :
```json
{ "message": "Utilisateur rejeté et supprimé" }
```

Erreurs :
- `403` — `{"error": "Permission refusée"}` : rôle `employer`.
- `403` — `{"error": "Permission refusée : entreprise introuvable."}`.
- `403` — `{"error": "Permission refusée : cet employé n'appartient pas à votre magasin."}` : gérant.
- `403` — `{"error": "Permission refusée : cet utilisateur n'appartient pas à votre entreprise."}` : admin.
- `404` — `{"error": "Magasin introuvable"}` ; `{"error": "Utilisateur introuvable"}`.

### `GET /api/users/pending/` — Comptes en attente d'approbation
**Rôle** : `admin` (gérants et employés de sa société) ou `magasin` (employés de son magasin) · **Vue** : `PendingUsersView` (views.py)

Effet : lecture seule des comptes `is_confirmed = false`. `position`/`shop_name` sont ajoutés pour un employé, `shop_name` pour un gérant.

Réponse `200` :
```json
[
  {
    "id": 23,
    "full_name": "Naina Rakoto",
    "email": "naina.rakoto@boutique-demo.mg",
    "role": "employer",
    "created_at": "2026-09-12T09:15:02.113456+03:00",
    "position": "Livreur",
    "shop_name": "Boutique Centre"
  },
  {
    "id": 24,
    "full_name": "Lova Andrian",
    "email": "gerant.centre@boutique-demo.mg",
    "role": "magasin",
    "created_at": "2026-09-12T10:02:45.001122+03:00",
    "shop_name": "Boutique Nord"
  }
]
```

Erreurs :
- `403` — `{"error": "Permission refusée"}` : rôle `employer`.
- `404` — `{"error": "Magasin introuvable"}` : gérant sans profil.

### `PUT /api/users/role/{user_id}/` — Changer le rôle d'un utilisateur
**Rôle** : `admin` (`IsAdmin`) ; toute opération impliquant le rôle `admin` est réservée au fondateur · **Vue** : `RoleManagementView` (views.py)

Effet : remplace `CustomUser.role` (les profils existants ne sont pas convertis). Une promotion vers `admin` ajoute l'utilisateur à `admins` de tous les magasins du demandeur.

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| user_id | chemin | int | oui | Utilisateur ciblé (≠ soi-même). |
| role | corps | `admin` \| `magasin` \| `employer` | oui | Nouveau rôle. |

Requête :
```json
{ "role": "magasin" }
```

Réponse `200` :
```json
{ "message": "Rôle modifié de employer à magasin", "user_id": 13, "email": "miora.razafy@boutique-demo.mg", "new_role": "magasin" }
```

Erreurs :
- `400` — `{"error": "Rôle invalide. Les rôles valides sont: admin, magasin, employer"}`.
- `400` — `{"error": "Vous ne pouvez pas modifier votre propre rôle"}`.
- `403` — `{"error": "Permission refusée : entreprise introuvable."}`.
- `403` — `{"error": "Seul le fondateur de la société peut gérer les administrateurs."}` : co-admin touchant un admin ou promouvant vers `admin`.
- `403` — `{"error": "Action impossible sur le fondateur de la société."}`.
- `403` — `{"error": "Permission refusée : cet utilisateur n'appartient pas à votre entreprise."}`.
- `403` — `{"detail": "You do not have permission to perform this action."}` : non-admin.
- `404` — `{"error": "Utilisateur introuvable"}`.

### `DELETE /api/users/delete/{user_id}/` — Supprimer un utilisateur (avec mot de passe)
**Rôle** : `admin` (membres de sa société ; retirer un admin = fondateur uniquement) ou `magasin` (employés de son magasin) · **Vue** : `DeleteUserView` (views.py)

Effet : supprime le compte et ses profils en cascade après confirmation du mot de passe du demandeur (corps JSON sur une requête DELETE).

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| user_id | chemin | int | oui | Utilisateur ciblé (≠ soi-même). |
| password | corps | string | oui | Mot de passe du demandeur. |

Requête :
```json
{ "password": "MotDePasse123" }
```

Réponse `200` :
```json
{ "message": "Utilisateur supprimé" }
```

Erreurs :
- `403` — `{"error": "Permission refusée"}` : rôle `employer`.
- `400` — `{"error": "Mot de passe requis pour confirmer la suppression."}` ; `{"error": "Mot de passe incorrect."}`.
- `403` — `{"error": "Permission refusée : entreprise introuvable."}`.
- `404` — `{"error": "Utilisateur introuvable"}`.
- `400` — `{"error": "Vous ne pouvez pas vous supprimer vous-même"}`.
- `403` — `{"error": "Permission refusée : cet employé n'appartient pas à votre magasin."}` ; `404 {"error": "Magasin introuvable"}` : gérant.
- `403` — `{"error": "Seul le fondateur de la société peut retirer un administrateur."}` ; `{"error": "Action impossible sur le fondateur de la société."}` ; `{"error": "Permission refusée : cet utilisateur n'appartient pas à votre entreprise."}` : admin.

### `PUT /api/users/employers/{user_id}/commande-role/` — Assigner le sous-rôle Préparateur/Livreur
**Rôle** : `GERANT` (`IsGerant` : admin ou magasin) sur un employé d'un magasin accessible · **Vue** : `EmployerCommandeRoleUpdateView` (views.py)

Effet : met à jour `EmployerProfile.commande_role` (pilote les permissions du module Commande et le blocage du chat entre livreurs).

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| user_id | chemin | int | oui | `CustomUser.id` de l'employé. |
| commande_role | corps | `PREPARATEUR` \| `LIVREUR` \| null | non | Absent, vide ou `null` → retire le sous-rôle. |

Requête :
```json
{ "commande_role": "LIVREUR" }
```

Réponse `200` :
```json
{ "message": "Rôle module Commande mis à jour", "user_id": 15, "commande_role": "LIVREUR" }
```

Erreurs :
- `404` — `{"error": "Employé introuvable"}` : pas d'`EmployerProfile` dans les magasins accessibles.
- `400` — `{"error": "commande_role invalide (PREPARATEUR ou LIVREUR)"}`.
- `403` — `{"detail": "You do not have permission to perform this action."}` : employé.

---

### Magasins

Viewset `MagasinViewSet` (`MagasinProfileSerializer`, champs `id`, `shop_name`, `description`, `shop_logo` (URL absolue ou `null`, lecture seule), `admin`, `user`). Queryset : admin → ses magasins (FK `admin` ou M2M `admins`) ; gérant → le sien ; employé → aucun (liste vide, détail 404).

### `GET /api/users/magasins/` — Lister les magasins accessibles
**Rôle** : tout utilisateur authentifié (`admin`, `magasin` ; vide pour `employer`) · **Vue** : `MagasinViewSet.list` (views.py)

Effet : lecture seule.

Réponse `200` :
```json
[
  {
    "id": 2,
    "shop_name": "Boutique Centre",
    "description": "Housses, cache-écrans et accessoires téléphone",
    "shop_logo": null,
    "admin": 11,
    "user": null
  }
]
```

### `POST /api/users/magasins/` — Créer un magasin
**Rôle** : `admin` uniquement (autres rôles authentifiés → 400) · **Vue** : `MagasinViewSet.create` / `perform_create` (views.py)

Effet : crée le `MagasinProfile` avec `admin = demandeur` et `admins = tous les admins de la société` (fondateur + co-admins). Le logo ne peut pas être envoyé ici (champ lecture seule) : utiliser `PATCH magasins/{id}/` en multipart.

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| shop_name | corps | string ≤ 255 | oui | Nom du point de vente. |
| description | corps | string ≤ 255 | non | Description. |

Requête :
```json
{ "shop_name": "Boutique Nord", "description": "Point de vente Analamahitsy" }
```

Réponse `201` :
```json
{ "id": 3, "shop_name": "Boutique Nord", "description": "Point de vente Analamahitsy", "shop_logo": null, "admin": 11, "user": null }
```

Erreurs :
- `400` — `{"shop_name": ["This field is required."]}`.
- `400` — `["Seul l'admin peut créer un magasin."]` : rôle `magasin` ou `employer`.

### `GET /api/users/magasins/{id}/` — Détail d'un magasin
**Rôle** : `admin` / `magasin` (dans le périmètre) · **Vue** : `MagasinViewSet.retrieve` (views.py)

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| id | chemin | int | oui | `MagasinProfile.id`. |

Réponse `200` :
```json
{ "id": 2, "shop_name": "Boutique Centre", "description": "Housses, cache-écrans et accessoires téléphone", "shop_logo": null, "admin": 11, "user": null }
```

Erreurs :
- `404` — `{"detail": "No MagasinProfile matches the given query."}` : hors périmètre ou inexistant.

### `PUT /api/users/magasins/{id}/` — Remplacer nom/description
**Rôle** : `admin` / `magasin` (dans le périmètre) · **Vue** : `MagasinViewSet.update` (views.py, comportement DRF standard)

Effet : met à jour `shop_name` (obligatoire) et `description` via le serializer ; `admin`, `user`, `shop_logo` sont ignorés.

Requête :
```json
{ "shop_name": "Boutique Centre", "description": "Nouvelle description" }
```

Réponse `200` :
```json
{ "id": 2, "shop_name": "Boutique Centre", "description": "Nouvelle description", "shop_logo": null, "admin": 11, "user": null }
```

Erreurs :
- `400` — `{"shop_name": ["This field is required."]}`.
- `404` — `{"detail": "No MagasinProfile matches the given query."}`.

### `PATCH /api/users/magasins/{id}/` — Modifier nom, logo ou gérant
**Rôle** : `admin` / `magasin` (dans le périmètre) ; `manager_id` réservé à `admin` · **Vue** : `MagasinViewSet.partial_update` (views.py, surchargé)

Effet : met à jour `shop_name`, `shop_logo` (fichier multipart uniquement, une chaîne est ignorée) et/ou affecte un compte `magasin` comme gérant (`MagasinProfile.user`). `description` n'est pas modifiable ici.

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| id | chemin | int | oui | `MagasinProfile.id`. |
| shop_name | corps | string | non | Nouveau nom. |
| shop_logo | corps (multipart) | fichier image | non | Logo (`shop_logo/`). |
| manager_id | corps | int | non | `CustomUser.id` d'un compte `role = magasin` (admin uniquement). |

Requête :
```json
{ "shop_name": "Boutique Centre", "manager_id": 22 }
```

Réponse `200` :
```json
{ "id": 2, "shop_name": "Boutique Centre", "description": "Housses, cache-écrans et accessoires téléphone", "shop_logo": "http://localhost:8010/media/shop_logo/centre.png", "admin": 11, "user": 22 }
```

Erreurs :
- `403` — `{"error": "Seul un administrateur peut modifier le gérant."}` : `manager_id` envoyé par un gérant.
- `404` — `{"manager_id": "Gérant introuvable."}` : aucun compte `magasin` avec cet id.
- `400` — `{"manager_id": "Ce compte est déjà gérant de \"Boutique Nord\"."}` : compte déjà rattaché à un autre magasin.
- `404` — `{"detail": "No MagasinProfile matches the given query."}`.

### `DELETE /api/users/magasins/{id}/` — Supprimer un magasin (avec mot de passe)
**Rôle** : `admin` / `magasin` (dans le périmètre) · **Vue** : `MagasinViewSet.destroy` (views.py)

Effet : supprime le magasin et, en cascade, ses catégories/produits, commandes, sessions de caisse, notifications et profils employés rattachés.

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| id | chemin | int | oui | `MagasinProfile.id`. |
| password | corps | string | oui | Mot de passe du demandeur. |

Requête :
```json
{ "password": "MotDePasse123" }
```

Réponse `204` : corps vide.

Erreurs :
- `400` — `{"error": "Mot de passe requis pour confirmer la suppression."}` ; `{"error": "Mot de passe incorrect."}`.
- `404` — `{"detail": "No MagasinProfile matches the given query."}`.

### `GET /api/users/magasins/overview/` — Synthèse par magasin (cartes admin)
**Rôle** : `admin` (`IsAdmin`) · **Vue** : `AdminMagasinOverviewView` (views.py)

Effet : lecture seule. `total_stock_value` = Σ `stock_actuel × prix_vente` ; `total_profit` = Σ `(prix_unitaire − prix_achat) × quantite` des commandes `LIVRE` ; `number_of_sales_week` = commandes livrées mises à jour depuis 7 jours.

Réponse `200` :
```json
{
  "magasins": [
    {
      "magasin_id": 2,
      "shop_name": "Boutique Centre",
      "total_stock_value": 43315000.0,
      "total_profit": 20000.0,
      "number_of_products": 298,
      "number_of_sales_week": 8,
      "number_of_employees": 8
    }
  ]
}
```

Erreurs :
- `403` — `{"detail": "You do not have permission to perform this action."}`.

### `GET /api/users/magasins/stats/` — Statistiques de stock et ventes par magasin
**Rôle** : tout utilisateur authentifié (périmètre selon rôle) · **Vue** : `MagasinStatsView` (views.py)

Effet : lecture seule ; un employé sans magasin affecté reçoit `[]`.

Réponse `200` :
```json
[
  {
    "magasin_id": 2,
    "shop_name": "Boutique Centre",
    "total_products": 298,
    "total_stock_quantity": 1321,
    "total_stock_value": 43315000.0,
    "total_sold_value": 339000.0,
    "profit": 20000.0
  }
]
```

Erreurs :
- `404` — `{"error": "Employer profile not found"}` : employé sans profil.
- `403` — `{"error": "Role not supported"}`.

### `GET /api/users/magasins/users/` — Utilisateurs regroupés par magasin
**Rôle** : tout utilisateur authentifié (périmètre selon rôle) · **Vue** : `UsersByMagasinView` (views.py)

Effet : lecture seule. Pour chaque magasin : `manager` (admin propriétaire), `employers` (profils employés) et `company_users` (liste cumulée dédupliquée : admin, gérant, employés, co-admins). `last_login_at`/`last_logout_at` proviennent du dernier `LoginEvent`.

Réponse `200` :
```json
[
  {
    "magasin_id": 2,
    "shop_name": "Boutique Centre",
    "shop_logo": null,
    "manager": {
      "id": 11,
      "full_name": "Rakoto Andry",
      "email": "admin@boutique-demo.mg",
      "phone": "+261340000000",
      "adresse": null,
      "photo": null,
      "is_confirmed": true,
      "role": "admin",
      "last_login_at": "2026-09-12T15:38:33.367810Z",
      "last_logout_at": "2026-09-12T18:30:26.050862Z"
    },
    "employers": [
      {
        "id": 12,
        "full_name": "Hery Rabe",
        "email": "hery.rabe@boutique-demo.mg",
        "phone": "+261340000001",
        "adresse": null,
        "photo": null,
        "is_confirmed": true,
        "position": "Préparateur",
        "role": "employer",
        "commande_role": "PREPARATEUR",
        "last_login_at": "2026-09-09T21:12:14.554163Z",
        "last_logout_at": "2026-09-09T21:12:22.825774Z"
      },
      {
        "id": 15,
        "full_name": "Fetra Rakotobe",
        "email": "fetra.rakotobe@boutique-demo.mg",
        "phone": null,
        "adresse": null,
        "photo": null,
        "is_confirmed": true,
        "position": "Livreur",
        "role": "employer",
        "commande_role": "LIVREUR",
        "last_login_at": null,
        "last_logout_at": null
      }
    ],
    "company_users": [
      {
        "id": 11,
        "full_name": "Rakoto Andry",
        "email": "admin@boutique-demo.mg",
        "phone": "+261340000000",
        "adresse": null,
        "photo": null,
        "is_confirmed": true,
        "role": "admin",
        "shop_name": "Boutique Centre",
        "magasin_id": 2,
        "position": null,
        "last_login_at": "2026-09-12T15:38:33.367810Z",
        "last_logout_at": "2026-09-12T18:30:26.050862Z"
      },
      {
        "id": 12,
        "full_name": "Hery Rabe",
        "email": "hery.rabe@boutique-demo.mg",
        "phone": "+261340000001",
        "adresse": null,
        "photo": null,
        "is_confirmed": true,
        "role": "employer",
        "shop_name": "Boutique Centre",
        "magasin_id": 2,
        "position": "Préparateur",
        "last_login_at": "2026-09-09T21:12:14.554163Z",
        "last_logout_at": "2026-09-09T21:12:22.825774Z"
      }
    ]
  }
]
```

Erreurs :
- `404` — `{"error": "Employer profile not found"}` ; `403 {"error": "Role not supported"}`. Un employé sans magasin reçoit `200 []`.

### `POST /api/users/transfer/products/` — Transférer du stock entre magasins
**Rôle** : `admin` (les deux magasins doivent lui appartenir) · **Vue** : `TransferProductsView` (views.py, `catalog.services.apply_stock_movement`)

Effet : pour chaque variante, retrouve ou crée la chaîne Catégorie → Type → Marque → Référence → Variante (même couleur) dans le magasin destination, puis applique un `StockMovement` `SORTIE` (source) et `ENTREE` (destination), origine `AJUSTEMENT`, dans une transaction atomique (tout ou rien). Crée deux notifications `other` (« Transfert sortant vers … » sur la source, « Transfert entrant depuis … » sur la destination). Signaux : `data_update` `stock_movement` (created) et `product_variant` (updated) sur les deux magasins.

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| source_magasin_id | corps | int | oui | Magasin d'origine. |
| destination_magasin_id | corps | int | oui | Magasin de destination (≠ source). |
| items | corps | liste de `{variant_id, quantity}` | oui (ou `variant_ids`) | `quantity` `null`/absent = tout le stock disponible. |
| variant_ids | corps | liste d'int | alternative à `items` | Transfère la totalité du stock de chaque variante. |

Requête :
```json
{
  "source_magasin_id": 2,
  "destination_magasin_id": 3,
  "items": [
    { "variant_id": 410, "quantity": 5 },
    { "variant_id": 412, "quantity": null }
  ]
}
```

Réponse `200` :
```json
{ "message": "Transfert effectué avec succès" }
```

Erreurs :
- `403` — `{"error": "Permission refusée"}` : non-admin.
- `400` — `{"error": "Paramètres manquants ou invalides"}` : id manquant ou aucune ligne.
- `400` — `{"error": "Le magasin source et destination doivent être différents"}`.
- `404` — `{"error": "Magasin source ou destination introuvable ou non autorisé"}`.
- `400` — `{"error": "Identifiant de variante manquant"}` ; `{"error": "Certaines variantes n'appartiennent pas au magasin source"}`.
- `400` — `{"error": "Quantité invalide pour iPhone 13 (Noir)"}` : quantité ≤ 0.
- `400` — `{"error": "Stock insuffisant pour iPhone 13 (Noir). Disponible : 3."}`.

---

### Réinitialisation de mot de passe (employés / gérants)

Flux en trois étapes sans e-mail : (1) le compte `magasin`/`employer` dépose une demande publique, (2) l'admin de la société l'approuve ou la rejette, (3) le demandeur revient définir un nouveau mot de passe. Les comptes `admin` ne sont pas éligibles.

### `GET /api/users/password-reset-requests/` — Lister les demandes reçues
**Rôle** : `admin` (`IsAdmin`), demandes dont il est l'`admin` cible · **Vue** : `EmployeePasswordResetListView` (views.py, `EmployeePasswordResetRequestSerializer`)

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| status | query | `pending` \| `approved` \| `rejected` | non | Filtre sur le statut. |

Réponse `200` :
```json
[
  {
    "id": 4,
    "status": "pending",
    "user_name": "Miora Razafy",
    "user_email": "miora.razafy@boutique-demo.mg",
    "user_role": "employer",
    "magasin_name": "Boutique Centre",
    "created_at": "2026-09-12T08:40:11.120000+03:00",
    "resolved_at": null
  }
]
```

Erreurs :
- `403` — `{"detail": "You do not have permission to perform this action."}`.

### `PATCH /api/users/password-reset-requests/{request_id}/` — Approuver ou rejeter une demande
**Rôle** : `admin` cible de la demande · **Vue** : `EmployeePasswordResetResolveView` (views.py)

Effet : passe le statut à `approved`/`rejected`, renseigne `resolved_by`/`resolved_at`. Une demande approuvée permet l'appel de `public/forgot-password/confirm/`.

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| request_id | chemin | int | oui | Identifiant de la demande. |
| action | corps | `approve` \| `reject` | oui | Décision. |

Requête :
```json
{ "action": "approve" }
```

Réponse `200` :
```json
{
  "id": 4,
  "status": "approved",
  "user_name": "Miora Razafy",
  "user_email": "miora.razafy@boutique-demo.mg",
  "user_role": "employer",
  "magasin_name": "Boutique Centre",
  "created_at": "2026-09-12T08:40:11.120000+03:00",
  "resolved_at": "2026-09-12T09:05:47.330000+03:00"
}
```

Erreurs :
- `404` — `{"error": "Demande introuvable"}` : id inconnu ou demande d'une autre société.
- `400` — `{"error": "Action invalide."}` ; `{"error": "Cette demande a déjà été traitée."}`.

### `POST /api/users/public/forgot-password/` — Déposer une demande (public)
**Rôle** : public (`AllowAny`) · **Vue** : `PublicForgotPasswordRequestView` (views.py)

Effet : crée un `EmployeePasswordResetRequest` (`status = pending`) adressé à l'admin du magasin/de l'employé. Aucun e-mail n'est envoyé ; aucune notification WebSocket n'est créée.

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| email | corps | string | oui | E-mail du compte (insensible à la casse). |

Requête :
```json
{ "email": "miora.razafy@boutique-demo.mg" }
```

Réponse `201` :
```json
{ "queue": "admin", "message": "Votre demande a été transmise à votre administrateur pour validation." }
```

Erreurs :
- `400` — `{"error": "Email requis."}`.
- `404` — `{"error": "Aucun compte avec cet email."}`.
- `400` — `{"error": "La réinitialisation automatique n'est pas disponible pour les comptes administrateur. Contactez le support technique directement."}` : compte `admin`.
- `404` — `{"error": "Aucun administrateur associé à ce compte."}` : profil sans admin résolu.
- `400` — `{"error": "Une demande est déjà en attente."}`.
- `400` — `{"error": "Réinitialisation non disponible pour ce type de compte."}` : rôle inconnu.

### `GET /api/users/public/forgot-password/status/` — Consulter l'état de sa demande (public)
**Rôle** : public · **Vue** : `PublicForgotPasswordStatusView` (views.py)

Effet : lecture seule ; renvoie le statut de la dernière demande non consommée. `none` si aucun compte, compte admin ou aucune demande.

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| email | query | string | oui | E-mail du compte. |

Réponse `200` :
```json
{ "status": "approved" }
```

Valeurs possibles de `status` : `none`, `pending`, `approved`, `rejected`.

### `POST /api/users/public/forgot-password/confirm/` — Définir le nouveau mot de passe (public)
**Rôle** : public · **Vue** : `PublicForgotPasswordConfirmView` (views.py)

Effet : si une demande `approved` non consommée existe, enregistre le nouveau mot de passe et marque la demande `consumed_at` (non rejouable).

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| email | corps | string | oui | E-mail du compte. |
| new_password | corps | string ≥ 6 | oui | Nouveau mot de passe. |

Requête :
```json
{ "email": "miora.razafy@boutique-demo.mg", "new_password": "NouveauMdp456" }
```

Réponse `200` :
```json
{ "message": "Mot de passe mis à jour avec succès." }
```

Erreurs :
- `400` — `{"error": "Le mot de passe doit contenir au moins 6 caractères."}` (vérifié avant l'e-mail).
- `404` — `{"error": "Aucun compte avec cet email."}` : e-mail inconnu ou compte admin.
- `400` — `{"error": "Aucune demande approuvée trouvée pour cet email."}`.

---

### Caisse — sessions

Viewset `CaisseSessionViewSet` (`CaisseSessionSerializer`), méthodes autorisées `GET`/`POST` uniquement (`PUT`/`PATCH`/`DELETE` → `405 {"detail": "Method \"PATCH\" not allowed."}`). Permission `IsAuthenticated` + `IsGerant` (admin ou gérant ; un employé reçoit 403). Queryset limité aux magasins accessibles. Le magasin d'une action est résolu par `_resolve_own_magasin` : celui du gérant ; pour un admin, `magasin_id` (ou `magasin`) dans le corps, ou `magasin_id` en query.

Forme d'une session (sérialisée) :
```json
{
  "id": 7,
  "magasin": 2,
  "magasin_name": "Boutique Centre",
  "status": "open",
  "opened_by": 11,
  "opened_by_name": "Rakoto Andry",
  "closed_by": null,
  "closed_by_name": null,
  "opening_balance": "50000.00",
  "closing_balance": null,
  "expected_balance": null,
  "difference": null,
  "opening_note": "Fond de caisse du matin",
  "closing_note": null,
  "opened_at": "2026-09-13T08:02:10.786286+03:00",
  "closed_at": null,
  "movements": []
}
```

### `GET /api/users/caisse/sessions/` — Lister les sessions de caisse
**Rôle** : `GERANT` · **Vue** : `CaisseSessionViewSet.list` (views.py)

Effet : lecture seule, triée par `-opened_at`, mouvements imbriqués.

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| magasin_id (alias `store_id`) | query | int | non | Filtre par magasin. |
| status | query | `open` \| `closed` | non | Filtre par statut. |

Réponse `200` :
```json
[
  {
    "id": 7,
    "magasin": 2,
    "magasin_name": "Boutique Centre",
    "status": "closed",
    "opened_by": 11,
    "opened_by_name": "Rakoto Andry",
    "closed_by": 11,
    "closed_by_name": "Rakoto Andry",
    "opening_balance": "50000.00",
    "closing_balance": "61500.00",
    "expected_balance": "62000.00",
    "difference": "-500.00",
    "opening_note": "Fond de caisse du matin",
    "closing_note": "Écart de 500 Ar",
    "opened_at": "2026-09-13T08:02:10.786286+03:00",
    "closed_at": "2026-09-13T18:05:41.000000+03:00",
    "movements": [
      {
        "id": 3,
        "session": 7,
        "magasin": 2,
        "magasin_name": "Boutique Centre",
        "movement_type": "out",
        "amount": "12000.00",
        "reason": "Achat cartons",
        "category": 3,
        "category_name": "Commande stock",
        "created_by": 11,
        "created_by_name": "Rakoto Andry",
        "created_at": "2026-09-13T10:15:00.100000+03:00"
      }
    ]
  }
]
```

Erreurs :
- `403` — `{"detail": "You do not have permission to perform this action."}` : employé.

### `POST /api/users/caisse/sessions/` — Création directe (désactivée)
**Rôle** : `GERANT` · **Vue** : `CaisseSessionViewSet.create` (views.py)

Effet : aucun ; renvoie toujours une erreur pour forcer l'usage de `open/`.

Erreurs :
- `405` — `{"error": "Utiliser POST /caisse/sessions/open/ pour ouvrir une session."}`.

### `GET /api/users/caisse/sessions/{id}/` — Détail d'une session
**Rôle** : `GERANT` · **Vue** : `CaisseSessionViewSet.retrieve` (views.py)

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| id | chemin | int | oui | `CaisseSession.id`. |

Réponse `200` : objet session (forme ci-dessus).

Erreurs :
- `404` — `{"detail": "No CaisseSession matches the given query."}`.

### `GET /api/users/caisse/sessions/current/` — Session actuellement ouverte
**Rôle** : `GERANT` · **Vue** : `CaisseSessionViewSet.current` (views.py)

Effet : lecture seule ; renvoie la session `open` la plus récente du magasin du gérant, ou du `magasin_id` demandé (un admin sans `magasin_id` obtient la plus récente de tous ses magasins).

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| magasin_id | query | int | non (recommandé pour un admin) | Magasin ciblé. |

Réponse `200` : objet session. Réponse `204` (corps vide) : aucune session ouverte.

### `POST /api/users/caisse/sessions/open/` — Ouvrir une session de caisse
**Rôle** : `GERANT` · **Vue** : `CaisseSessionViewSet.open` (views.py)

Effet : crée une session `open` (une seule par magasin). Signaux : notification `caisse` « Caisse ouverte (Boutique Centre) par Rakoto Andry — fond: 50000.00 » sur le magasin ; `data_update` `caisse_session` / `created`.

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| magasin_id (ou `magasin`) | corps | int | oui pour `admin` | Magasin ciblé (ignoré pour un gérant). |
| opening_balance | corps | nombre ou chaîne décimale | non (défaut 0) | Fond de caisse. |
| opening_note | corps | string ≤ 255 | non | Note d'ouverture. |
| opened_at | corps | string ISO 8601 | non | Antidatage de l'ouverture (pas dans le futur). |

Requête :
```json
{ "magasin_id": 2, "opening_balance": 50000, "opening_note": "Fond de caisse du matin", "opened_at": "2026-09-13T08:00:00+03:00" }
```

Réponse `201` : objet session (statut `open`).

Erreurs :
- `400` — `{"error": "Magasin introuvable ou non spécifié."}` : admin sans `magasin_id` valide, gérant/employé sans magasin.
- `400` — `{"error": "Une session de caisse est déjà ouverte pour ce magasin."}`.
- `400` — `{"error": "Montant d'ouverture invalide."}`.
- `400` — `{"error": "Heure d'ouverture invalide (format attendu : ISO 8601)."}` ; `{"error": "Heure d'ouverture ne peut pas être dans le futur."}`.

### `POST /api/users/caisse/sessions/{id}/close/` — Fermer une session
**Rôle** : `GERANT` · **Vue** : `CaisseSessionViewSet.close` (views.py)

Effet : calcule `expected_balance = opening_balance + Σ entrées − Σ sorties`, `difference = closing_balance − expected_balance`, passe la session en `closed`. Signaux : notification `caisse` « Caisse fermée (Boutique Centre) par Rakoto Andry — écart: -500.00 » ; `data_update` `caisse_session` / `updated`.

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| id | chemin | int | oui | Session à fermer. |
| closing_balance | corps | nombre ou chaîne décimale | oui | Montant réellement compté. |
| closing_note | corps | string ≤ 255 | non | Note de fermeture. |
| closed_at | corps | string ISO 8601 | non | Antidatage (≥ `opened_at`, pas dans le futur). |

Requête :
```json
{ "closing_balance": "61500.00", "closing_note": "Écart de 500 Ar" }
```

Réponse `200` : objet session (statut `closed`, `expected_balance`/`difference` renseignés).

Erreurs :
- `404` — `{"detail": "No CaisseSession matches the given query."}`.
- `400` — `{"error": "Cette session est déjà fermée."}` ; `{"error": "Montant de fermeture requis."}` ; `{"error": "Montant de fermeture invalide."}`.
- `400` — `{"error": "Heure de fermeture invalide (format attendu : ISO 8601)."}` ; `{"error": "Heure de fermeture ne peut pas être dans le futur."}` ; `{"error": "L'heure de fermeture ne peut pas être avant l'heure d'ouverture."}`.

### Caisse — mouvements

Viewset `CaisseMovementViewSet` (`CaisseMovementSerializer`), méthodes `GET`/`POST`/`DELETE` (pas de `PUT`/`PATCH`). Permission `IsGerant`.

### `GET /api/users/caisse/movements/` — Lister les mouvements
**Rôle** : `GERANT` · **Vue** : `CaisseMovementViewSet.list` (views.py)

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| session_id (alias `session`) | query | int | non | Filtre par session. |
| magasin_id (alias `store_id`) | query | int | non | Filtre par magasin. |
| date_from | query | date `YYYY-MM-DD` | non | `created_at` ≥ date. |
| date_to | query | date `YYYY-MM-DD` | non | `created_at` ≤ date. |

Réponse `200` :
```json
[
  {
    "id": 3,
    "session": 7,
    "magasin": 2,
    "magasin_name": "Boutique Centre",
    "movement_type": "out",
    "amount": "12000.00",
    "reason": "Achat cartons",
    "category": 3,
    "category_name": "Commande stock",
    "created_by": 11,
    "created_by_name": "Rakoto Andry",
    "created_at": "2026-09-13T10:15:00.100000+03:00"
  },
  {
    "id": 2,
    "session": 7,
    "magasin": 2,
    "magasin_name": "Boutique Centre",
    "movement_type": "in",
    "amount": "24000.00",
    "reason": "Encaissement vente comptoir",
    "category": null,
    "category_name": null,
    "created_by": 11,
    "created_by_name": "Rakoto Andry",
    "created_at": "2026-09-13T09:30:12.000000+03:00"
  }
]
```

### `POST /api/users/caisse/movements/` — Enregistrer un mouvement
**Rôle** : `GERANT` · **Vue** : `CaisseMovementViewSet.create` / `perform_create` (views.py)

Effet : rattache le mouvement à la session `session` indiquée (doit être accessible et ouverte) ou, à défaut, à la session ouverte du magasin résolu ; `magasin` et `created_by` sont déduits. Signaux : notification `caisse` « Mouvement de caisse -12000.00 (Achat cartons) — Rakoto Andry » ; `data_update` `caisse_movement` / `created`.

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| movement_type | corps | `in` \| `out` | oui | Entrée ou sortie. |
| amount | corps | décimal (12,2) | oui | Montant. |
| reason | corps | string ≤ 255 | oui | Motif. |
| category | corps | int | non | `CaisseCategory.id`, uniquement pour `out`. |
| session | corps | int | non | Session cible ; sinon session ouverte du magasin. |
| magasin_id | corps | int | non (admin sans `session`) | Magasin dont on prend la session ouverte. |

Requête :
```json
{ "movement_type": "out", "amount": "12000.00", "reason": "Achat cartons", "category": 3, "session": 7 }
```

Réponse `201` :
```json
{
  "id": 3,
  "session": 7,
  "magasin": 2,
  "magasin_name": "Boutique Centre",
  "movement_type": "out",
  "amount": "12000.00",
  "reason": "Achat cartons",
  "category": 3,
  "category_name": "Commande stock",
  "created_by": 11,
  "created_by_name": "Rakoto Andry",
  "created_at": "2026-09-13T10:15:00.100000+03:00"
}
```

Erreurs :
- `400` — `{"movement_type": ["\"x\" is not a valid choice."], "amount": ["A valid number is required."], "reason": ["This field is required."]}` : validation de champ.
- `400` — `{"category": ["Invalid pk \"99\" - object does not exist."]}` : catégorie inconnue.
- `400` — `{"non_field_errors": ["Une catégorie ne s'applique qu'aux sorties."]}` : `category` avec `movement_type = in`.
- `400` — `["Aucune session de caisse ouverte."]` : session introuvable/inaccessible ou aucune session ouverte.
- `400` — `["Cette session de caisse est fermée."]`.

### `GET /api/users/caisse/movements/{id}/` — Détail d'un mouvement
**Rôle** : `GERANT` · **Vue** : `CaisseMovementViewSet.retrieve` (views.py)

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| id | chemin | int | oui | `CaisseMovement.id`. |

Réponse `200` : objet mouvement (forme ci-dessus).

Erreurs :
- `404` — `{"detail": "No CaisseMovement matches the given query."}`.

### `PATCH /api/users/caisse/movements/{id}/` — Corriger un mouvement (session ouverte)
**Rôle** : gérant · **Vue** : `CaisseMovementViewSet.partial_update` (users/views.py)

Effet : modifie le type, le montant, le motif et la catégorie d'un mouvement **tant que sa session est ouverte** ; une entrée perd sa catégorie ; le solde attendu de la session est recalculé.

Requête :
```json
{ "movement_type": "out", "amount": "402000", "reason": "REDOTPAY", "category": 3 }
```

Réponse `200` : le mouvement mis à jour (même forme que la création). Erreurs : `400` — `["Cette session de caisse est fermée : ses mouvements ne peuvent plus être modifiés."]`, `["Une catégorie ne s'applique qu'aux sorties."]` ; `403` hors gérant ; `404`.

### `DELETE /api/users/caisse/movements/{id}/` — Supprimer un mouvement (session ouverte)
**Rôle** : `GERANT` · **Vue** : `CaisseMovementViewSet.destroy` (views.py)

Effet : supprime le mouvement (aucun recalcul d'une session déjà fermée). Signal : `data_update` `caisse_movement` / `deleted`.

Réponse `204` : corps vide.

Erreurs :
- `404` — `{"detail": "No CaisseMovement matches the given query."}`.

### Caisse — catégories de dépense

Viewset `CaisseCategoryViewSet` (`CaisseCategorySerializer`), méthodes `GET`/`POST`/`PATCH`/`DELETE` (pas de `PUT`). Lecture : tout utilisateur authentifié ; écriture (`create`, `partial_update`, `destroy`) : `IsGerant`. Les catégories sont rattachées à l'`AdminProfile` du fondateur (partagées par toute la société). Au premier `GET` d'une société sans catégorie, quatre valeurs par défaut sont créées : `Salaire`, `Pub`, `Commande stock`, `Autre`.

### `GET /api/users/caisse/categories/` — Lister les catégories
**Rôle** : tout utilisateur authentifié · **Vue** : `CaisseCategoryViewSet.list` (views.py)

Effet : lecture (avec création des valeurs par défaut si la société n'en a aucune). Tri par `nom`. Liste vide si la société n'a pas de fondateur résolu.

Réponse `200` :
```json
[
  { "id": 4, "nom": "Autre", "created_at": "2026-09-08T17:30:42.375854+03:00" },
  { "id": 3, "nom": "Commande stock", "created_at": "2026-09-08T17:30:42.375849+03:00" }
]
```

### `POST /api/users/caisse/categories/` — Créer une catégorie
**Rôle** : `GERANT` · **Vue** : `CaisseCategoryViewSet.create` (views.py)

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| nom | corps | string ≤ 100 | oui | Unique par société (`unique_together`). |

Requête :
```json
{ "nom": "Loyer" }
```

Réponse `201` :
```json
{ "id": 5, "nom": "Loyer", "created_at": "2026-09-13T11:00:00.000000+03:00" }
```

Erreurs :
- `400` — `{"nom": ["This field is required."]}`.
- `400` — `["Société introuvable."]` : aucun fondateur avec `AdminProfile`.
- `403` — `{"detail": "You do not have permission to perform this action."}` : employé.
- `500` — doublon de `nom` dans la société (contrainte d'unicité non validée par le serializer).

### `GET /api/users/caisse/categories/{id}/` — Détail d'une catégorie
**Rôle** : tout utilisateur authentifié · **Vue** : `CaisseCategoryViewSet.retrieve` (views.py)

Réponse `200` :
```json
{ "id": 3, "nom": "Commande stock", "created_at": "2026-09-08T17:30:42.375849+03:00" }
```

Erreurs :
- `404` — `{"detail": "No CaisseCategory matches the given query."}`.

### `PATCH /api/users/caisse/categories/{id}/` — Renommer une catégorie
**Rôle** : `GERANT` · **Vue** : `CaisseCategoryViewSet.partial_update` (views.py)

Requête :
```json
{ "nom": "Publicité" }
```

Réponse `200` :
```json
{ "id": 2, "nom": "Publicité", "created_at": "2026-09-08T17:30:42.375843+03:00" }
```

Erreurs :
- `404` — `{"detail": "No CaisseCategory matches the given query."}` ; `403` pour un employé.

### `DELETE /api/users/caisse/categories/{id}/` — Supprimer une catégorie
**Rôle** : `GERANT` · **Vue** : `CaisseCategoryViewSet.destroy` (views.py)

Effet : supprime la catégorie ; les mouvements liés conservent `category = null` (`SET_NULL`).

Réponse `204` : corps vide.

Erreurs :
- `404` — `{"detail": "No CaisseCategory matches the given query."}` ; `403` pour un employé.

### `GET /api/users/caisse/summary/` — Résumé caisse et ventes sur une période
**Rôle** : `GERANT` · **Vue** : `CaisseSummaryView` (views.py)

Effet : lecture seule. Période par défaut : du 1er du mois courant à aujourd'hui. `ca_produits_vendus` = Σ `prix_unitaire × quantite` des commandes `LIVRE` (par `date_commande`) ; `cout_produits_vendus` = Σ `quantite × prix_achat` ; `benefice_produits_vendus` = différence.

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| date_from | query | date `YYYY-MM-DD` | non | Début de période. |
| date_to | query | date `YYYY-MM-DD` | non | Fin de période. |
| magasin_id | query | int | non | Restreint à un magasin accessible. |

Réponse `200` :
```json
{
  "date_from": "2026-09-01",
  "date_to": "2026-09-13",
  "total_entrees": 24000.0,
  "total_sorties": 12000.0,
  "solde": 12000.0,
  "sorties_par_categorie": [
    { "categorie": "Commande stock", "total": 12000.0 }
  ],
  "ca_produits_vendus": 315000.0,
  "cout_produits_vendus": 295000.0,
  "benefice_produits_vendus": 20000.0
}
```

Erreurs :
- `403` — `{"detail": "You do not have permission to perform this action."}` : employé.
- `500` — date mal formée (`ValidationError` Django non interceptée).

---

### Notifications

Viewset `NotificationViewSet` (`NotificationSerializer`), CRUD complet, permission `IsAuthenticated`. Queryset (« notifications visibles ») : admin → notifications des magasins où il est dans `admins` + les siennes (`user = lui`) ; gérant → celles de son magasin + les siennes ; employé → celles de son magasin (si affecté) + les siennes. Types (`notif_type`) : `order`, `supplier_order`, `user`, `chat`, `caisse`, `other`. La plupart des notifications sont créées par les signaux (commandes, caisse, chat, nouvel utilisateur, transferts) ; toute création déclenche une diffusion sur `/ws/notifications/`.

Forme d'une notification :
```json
{
  "id": 128,
  "notif_type": "order",
  "message": "Dépense acceptée : ENVELOPPE — 5000 Ar",
  "magasin": 2,
  "magasin_name": "Boutique Centre",
  "caisse_session": null,
  "user": 15,
  "user_name": "Fetra Rakotobe",
  "is_read": false,
  "created_at": "2026-09-12T19:02:32.619488+03:00"
}
```

### `GET /api/users/notifications/` — Lister les notifications visibles
**Rôle** : tout utilisateur authentifié · **Vue** : `NotificationViewSet.list` (views.py)

Effet : lecture seule, tri `-created_at`, sans pagination ni filtre.

Réponse `200` :
```json
[
  {
    "id": 128,
    "notif_type": "order",
    "message": "Dépense acceptée : ENVELOPPE — 5000 Ar",
    "magasin": 2,
    "magasin_name": "Boutique Centre",
    "caisse_session": null,
    "user": 15,
    "user_name": "Fetra Rakotobe",
    "is_read": false,
    "created_at": "2026-09-12T19:02:32.619488+03:00"
  },
  {
    "id": 113,
    "notif_type": "order",
    "message": "Dépense à valider : ENVELOPPE — 5000 Ar, déclarée par Fetra Rakotobe",
    "magasin": 2,
    "magasin_name": "Boutique Centre",
    "caisse_session": null,
    "user": null,
    "user_name": null,
    "is_read": false,
    "created_at": "2026-09-11T19:01:14.981592+03:00"
  }
]
```

### `POST /api/users/notifications/` — Créer une notification manuelle
**Rôle** : tout utilisateur authentifié (aucun contrôle de périmètre sur `magasin`/`user`) · **Vue** : `NotificationViewSet.create` (views.py)

Effet : crée la notification ; le signal `post_save` la diffuse aux groupes WebSocket de l'admin du magasin, du magasin et de l'utilisateur ciblé.

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| message | corps | string | oui | Texte. |
| notif_type | corps | `order` \| `supplier_order` \| `user` \| `chat` \| `caisse` \| `other` | non (défaut `other`) | Type. |
| magasin | corps | int \| null | non | `MagasinProfile.id`. |
| caisse_session | corps | int \| null | non | `CaisseSession.id`. |
| user | corps | int \| null | non | Destinataire personnel. |
| is_read | corps | bool | non (défaut `false`) | État de lecture. |

Requête :
```json
{ "notif_type": "other", "message": "Inventaire prévu samedi matin", "magasin": 2 }
```

Réponse `201` :
```json
{
  "id": 129,
  "notif_type": "other",
  "message": "Inventaire prévu samedi matin",
  "magasin": 2,
  "magasin_name": "Boutique Centre",
  "caisse_session": null,
  "user": null,
  "user_name": null,
  "is_read": false,
  "created_at": "2026-09-13T11:20:00.000000+03:00"
}
```

Erreurs :
- `400` — `{"message": ["This field is required."]}` ; `{"notif_type": ["\"x\" is not a valid choice."]}` ; `{"magasin": ["Invalid pk \"99\" - object does not exist."]}`.

### `GET /api/users/notifications/{id}/` — Détail d'une notification
**Rôle** : tout utilisateur authentifié (notification visible) · **Vue** : `NotificationViewSet.retrieve` (views.py)

Réponse `200` : objet notification.

Erreurs :
- `404` — `{"detail": "No Notification matches the given query."}`.

### `PUT /api/users/notifications/{id}/` — Remplacer une notification
**Rôle** : tout utilisateur authentifié (notification visible) · **Vue** : `NotificationViewSet.update` (views.py, DRF standard)

Effet : remplace les champs modifiables (`message` obligatoire). Pas de diffusion WebSocket (seule la création est diffusée).

Requête :
```json
{ "notif_type": "other", "message": "Inventaire reporté à dimanche", "magasin": 2, "is_read": true }
```

Réponse `200` : objet notification mis à jour.

Erreurs :
- `400` — `{"message": ["This field is required."]}` ; `404` si non visible.

### `PATCH /api/users/notifications/{id}/` — Marquer lue / non lue
**Rôle** : tout utilisateur authentifié (notification visible) · **Vue** : `NotificationViewSet.partial_update` (views.py, surchargé)

Effet : si `is_read` est présent, applique `bool(is_read)` et renvoie l'objet (attention : la chaîne `"false"` vaut `true` ; envoyer un booléen JSON). Sinon, mise à jour partielle standard des autres champs.

Requête :
```json
{ "is_read": true }
```

Réponse `200` : objet notification (`"is_read": true`).

Erreurs :
- `404` — `{"detail": "No Notification matches the given query."}`.

### `DELETE /api/users/notifications/{id}/` — Supprimer une notification
**Rôle** : `admin` (toute notification visible) ; gérant/employé : leurs notifications personnelles ou celles de leur magasin · **Vue** : `NotificationViewSet.destroy` (views.py)

Réponse `204` : corps vide.

Erreurs :
- `404` — `{"detail": "No Notification matches the given query."}` : non visible.
- `403` — `{"error": "Permission refusée"}` : visible mais ni personnelle ni du magasin de l'utilisateur.

### `POST /api/users/notifications/mark-all-read/` — Tout marquer comme lu
**Rôle** : tout utilisateur authentifié · **Vue** : `NotificationViewSet.mark_all_read` (views.py)

Effet : `is_read = true` sur toutes les notifications visibles.

Réponse `200` :
```json
{ "message": "Toutes les notifications marquées comme lues." }
```

### `POST /api/users/notifications/bulk-read/` — Marquer une sélection comme lue
**Rôle** : tout utilisateur authentifié · **Vue** : `NotificationViewSet.bulk_read` (views.py)

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| ids | corps | liste d'int | non (défaut `[]`) | Identifiants (les ids non visibles sont ignorés). |

Requête :
```json
{ "ids": [128, 127] }
```

Réponse `200` :
```json
{ "message": "Notifications marquées comme lues." }
```

### `POST /api/users/notifications/bulk-delete/` — Supprimer une sélection
**Rôle** : tout utilisateur authentifié · **Vue** : `NotificationViewSet.bulk_delete` (views.py)

Effet : supprime les notifications visibles dont l'id est dans `ids` (sans la règle de propriété de `DELETE /{id}/`).

Requête :
```json
{ "ids": [128, 127] }
```

Réponse `204` : corps vide.

### `POST /api/users/notifications/delete-all/` — Tout supprimer
**Rôle** : tout utilisateur authentifié · **Vue** : `NotificationViewSet.delete_all` (views.py)

Effet : supprime toutes les notifications visibles par l'utilisateur (pour un admin : toutes celles de ses magasins).

Réponse `204` : corps vide.

---

### Chat

Rooms : `general_<company_id>` (salon général de la société ; `company_id` = id de l'admin propriétaire du premier magasin) et `dm_<idMin>_<idMax>` (conversation privée). Règle métier : deux `LIVREUR` ne peuvent pas se contacter (`chat_blocked_between`). L'envoi de texte, l'édition, la suppression et l'accusé de lecture passent par le WebSocket `/ws/chat/` ; seules les images passent par HTTP.

Forme d'un message (`ChatMessageSerializer`) :
```json
{
  "id": 1,
  "sender": 11,
  "sender_name": "Rakoto Andry",
  "sender_email": "admin@boutique-demo.mg",
  "sender_role": "admin",
  "recipient": 17,
  "recipient_name": "Onja Rasolo",
  "recipient_email": "onja.rasolo@boutique-demo.mg",
  "room_name": "dm_11_17",
  "content": "Bonjour, la commande CMD-2-20260912-0002 est prête.",
  "image": null,
  "is_edited": false,
  "edited_at": null,
  "is_deleted": false,
  "timestamp": "2026-09-08T14:53:17.610218+03:00",
  "read_at": null
}
```

### `GET /api/users/chat/users/` — Contacts joignables
**Rôle** : tout utilisateur authentifié · **Vue** : `ChatUsersListView` (views.py)

Effet : lecture seule. Membres approuvés de la société (admins, gérants, employés des mêmes magasins), sans soi-même ni les paires livreur–livreur. `is_online` = `last_seen_at` < 40 s ; `unread_count` = messages privés non lus reçus de ce contact ; `last_message_at` = dernier échange (dans les deux sens). `shop_name` présent pour `magasin`/`employer`.

Réponse `200` :
```json
[
  {
    "id": 17,
    "full_name": "Onja Rasolo",
    "email": "onja.rasolo@boutique-demo.mg",
    "role": "employer",
    "is_online": false,
    "last_seen_at": "2026-09-12T15:40:02.101000+00:00",
    "unread_count": 2,
    "last_message_at": "2026-09-08T11:53:17.610218+00:00",
    "shop_name": "Boutique Centre"
  },
  {
    "id": 13,
    "full_name": "Miora Razafy",
    "email": "miora.razafy@boutique-demo.mg",
    "role": "employer",
    "is_online": true,
    "last_seen_at": "2026-09-13T08:10:44.000000+00:00",
    "unread_count": 0,
    "last_message_at": null,
    "shop_name": "Boutique Centre"
  }
]
```

Réponse `200` `[]` si l'utilisateur n'appartient à aucun magasin.

### `GET /api/users/chat/history/` — Historique d'une conversation
**Rôle** : tout utilisateur authentifié · **Vue** : `ChatMessageHistoryView` (views.py)

Effet : lecture seule ; renvoie les 100 derniers messages (ordre chronologique), messages supprimés inclus (`is_deleted = true`, `content = ""`). Sans `recipient_id`, renvoie le salon général de la société.

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| recipient_id | query | int | non | Conversation privée avec cet utilisateur. |
| room_name | query | string | non | Lu mais sans effet (le salon général est toujours `general_<company_id>`). |

Réponse `200` :
```json
[
  {
    "id": 1,
    "sender": 11,
    "sender_name": "Rakoto Andry",
    "sender_email": "admin@boutique-demo.mg",
    "sender_role": "admin",
    "recipient": 17,
    "recipient_name": "Onja Rasolo",
    "recipient_email": "onja.rasolo@boutique-demo.mg",
    "room_name": "dm_11_17",
    "content": "Bonjour, la commande CMD-2-20260912-0002 est prête.",
    "image": null,
    "is_edited": false,
    "edited_at": null,
    "is_deleted": false,
    "timestamp": "2026-09-08T14:53:17.610218+03:00",
    "read_at": null
  }
]
```

Erreurs :
- `403` — `{"error": "Permission refusée"}` : destinataire d'une autre société.
- `403` — `{"error": "Deux livreurs ne peuvent pas se contacter entre eux"}`.
- `404` — `{"error": "Destinataire introuvable"}`.
- `200 []` — utilisateur sans magasin ou société non résolue.

### `GET /api/users/chat/unread-count/` — Compteur de messages non lus
**Rôle** : tout utilisateur authentifié · **Vue** : `ChatUnreadCountView` (views.py)

Effet : lecture seule ; nombre de messages privés reçus, non lus et non supprimés (le salon général n'a pas de statut « lu »).

Réponse `200` :
```json
{ "count": 2 }
```

### `POST /api/users/chat/upload/` — Envoyer une image dans le chat (multipart)
**Rôle** : tout utilisateur authentifié · **Vue** : `ChatImageUploadView` (views.py, `MultiPartParser`/`FormParser`)

Effet : crée un `ChatMessage` avec pièce jointe (`chat/`) et le diffuse au groupe `chat_<room>` (trame `type: "message"` sur `/ws/chat/`, best-effort). Signal : notification `chat` « Message privé de Rakoto Andry : … » adressée au destinataire (ou « Message de … dans Général : … » sur le magasin de l'expéditeur).

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| image | corps (multipart) | fichier image | oui | Pièce jointe. |
| recipient_id | corps | int | non | Message privé ; absent → salon général. |
| content | corps | string | non | Légende (espaces retirés). |

Requête (champs de formulaire) :
```json
{ "image": "<fichier image>", "recipient_id": 17, "content": "Photo du colis" }
```

Réponse `201` :
```json
{
  "id": 2,
  "sender": 11,
  "sender_name": "Rakoto Andry",
  "sender_email": "admin@boutique-demo.mg",
  "sender_role": "admin",
  "recipient": 17,
  "recipient_name": "Onja Rasolo",
  "recipient_email": "onja.rasolo@boutique-demo.mg",
  "room_name": "dm_11_17",
  "content": "Photo du colis",
  "image": "http://localhost:8010/media/chat/colis-1234.jpg",
  "is_edited": false,
  "edited_at": null,
  "is_deleted": false,
  "timestamp": "2026-09-13T11:32:05.410000+03:00",
  "read_at": null
}
```

Erreurs :
- `400` — `{"error": "Aucune image reçue."}`.
- `403` — `{"error": "Aucun magasin associé."}` ; `{"error": "Permission refusée"}` (autre société) ; `{"error": "Deux livreurs ne peuvent pas se contacter entre eux"}` ; `{"error": "Société introuvable"}`.
- `404` — `{"error": "Destinataire introuvable"}` : id inconnu ou non numérique.

---

### Tableau de bord et divers

### `GET /api/users/dashboard/` — Indicateurs du tableau de bord
**Rôle** : tout utilisateur authentifié ; forme de la réponse selon le rôle · **Vue** : `DashboardView` (views.py)

Effet : lecture seule. `ca` = valeur du stock au prix de vente + Σ entrées de caisse ; `benefice_estime_stock` = Σ `stock_actuel × (prix_vente − prix_achat)` ; `total_revenue`/`total_profit` sur les commandes `LIVRE` ; `low_stock_count` = variantes avec `stock_actuel ≤ seuil_alerte` ; `expired_*`/`unpaid_*` toujours 0 (hors périmètre du catalogue). Pour un employé, l'activité est lue dans `OrderStatusHistory` : statut cible `LIVRE` pour un `LIVREUR`, `PRETE` sinon.

Réponse `200` (admin) :
```json
{
  "role": "admin",
  "kpis": {
    "ca": 43315000.0,
    "benefice_estime_stock": 7035000.0,
    "total_revenue": 315000.0,
    "total_profit": 20000.0,
    "total_stock_value": 43315000.0,
    "total_magasins": 1,
    "total_employers": 8,
    "total_products": 298,
    "total_sales": 8,
    "sales_today": 0,
    "profit_today": 0,
    "low_stock_count": 304,
    "expired_count": 0,
    "expiring_soon_count": 0,
    "unpaid_sales_count": 0,
    "unpaid_sales_value": 0
  },
  "lists": {
    "top_products": [
      { "name": "iPhone 11", "qty_sold": 2 },
      { "name": "Pixel 6 Pro", "qty_sold": 1 }
    ],
    "bottom_products": [
      { "name": "Pixel 7 Pro", "qty_sold": 0 },
      { "name": "Pixel 8 Pro", "qty_sold": 0 }
    ],
    "low_stock_products": [
      { "name": "Pixel 6 Pro (Bleu)", "initial_quantity": 0, "alert_threshold": 2, "magasin__shop_name": "Boutique Centre" }
    ],
    "expired_products": [],
    "expiring_soon_products": [],
    "recent_sales": [
      {
        "product_name": "Pixel 8 Pro x1",
        "quantity": 1,
        "sale_price": null,
        "total_price": 43000.0,
        "seller_name": "Rakoto Andry",
        "shop_name": "Boutique Centre",
        "sold_at": "2026-09-12T07:17:42.595148Z"
      }
    ],
    "best_employees": [
      { "created_by__full_name": "Rakoto Andry", "sales_count": 8, "total_amount": 339000.0 }
    ],
    "best_shops": [
      { "magasin__shop_name": "Boutique Centre", "total_amount": 339000.0, "sales_count": 8, "total_stock": 0 }
    ]
  }
}
```

Réponse `200` (gérant) :
```json
{
  "role": "magasin",
  "kpis": {
    "ca": 43315000.0,
    "benefice_estime_stock": 7035000.0,
    "sales_today": 1,
    "profit_today": 5000.0,
    "total_revenue": 315000.0,
    "total_profit": 20000.0,
    "stock_value": 43315000.0,
    "total_products": 298,
    "total_sales": 8,
    "low_stock_count": 304,
    "expired_count": 0,
    "unpaid_sales_count": 0,
    "unpaid_sales_value": 0
  },
  "lists": {
    "top_products": [ { "name": "iPhone 11", "qty_sold": 2 } ],
    "bottom_products": [ { "name": "Pixel 7 Pro", "qty_sold": 0 } ],
    "low_stock_products": [ { "name": "Pixel 6 Pro (Bleu)", "initial_quantity": 0 } ],
    "recent_sales": [
      { "product_name": "Pixel 8 Pro x1", "quantity": 1, "total_price": 43000.0, "seller_name": "Rakoto Andry", "sold_at": "2026-09-12T07:17:42.595148Z" }
    ],
    "best_sellers": [ { "created_by__full_name": "Rakoto Andry", "sales_count": 8, "total_amount": 339000.0 } ]
  }
}
```

Réponse `200` (employé) :
```json
{
  "role": "employer",
  "commande_role": "PREPARATEUR",
  "kpis": {
    "my_sales_today": 0,
    "total_amount_sold": 0,
    "products_sold_count": 0,
    "clients_count": 0,
    "unpaid_sales_count": 0,
    "unpaid_sales_value": 0
  },
  "lists": {
    "recent_sales": []
  }
}
```

Erreurs :
- `404` — `{"error": "Magasin profile not found"}` (gérant) ; `{"error": "Employer profile not found"}` (employé).
- `403` — `{"error": "Role not supported"}`.

### `GET /api/users/endpoints/` — Liste statique des endpoints
**Rôle** : public (`permission_classes = []`) · **Vue** : `ApiEndpointsListView` (views.py)

Effet : lecture seule ; liste codée en dur (partiellement obsolète : elle mentionne des routes `products/`, `sales/` qui n'existent plus dans cette application).

Réponse `200` :
```json
[
  {
    "path": "/api/users/login/",
    "method": "POST",
    "auth_required": false,
    "roles_allowed": ["Any"],
    "description": "Authentifie un utilisateur et retourne les tokens JWT (access & refresh)."
  },
  {
    "path": "/api/users/me/",
    "method": "GET",
    "auth_required": true,
    "roles_allowed": ["admin", "magasin", "employer"],
    "description": "Retourne le profil complet et les informations de l'utilisateur connecté."
  }
]
```

### `GET /api/users/backup/export/` — Exporter la base et les médias (zip)
**Rôle** : `admin` (`IsAdmin`) · **Vue** : `BackupExportView` (views.py)

Effet : lecture seule ; génère une archive `backup_YYYYMMDD_HHMMSS.zip` contenant `data.json` (`dumpdata` de toute la base, hors `contenttypes`, `auth.permission`, `admin.logentry`, `sessions.session`) et le dossier `media/`. Réponse binaire `Content-Type: application/zip`, en-tête `Content-Disposition: attachment; filename="backup_20260913_113000.zip"` (exposé en CORS). Aucun filtrage par société : l'archive contient toutes les données du serveur.

Erreurs :
- `403` — `{"detail": "You do not have permission to perform this action."}`.

### `POST /api/users/backup/import/` — Restaurer depuis une archive (multipart)
**Rôle** : `admin` (`IsAdmin`) · **Vue** : `BackupImportView` (views.py, `MultiPartParser`)

Effet : **destructif** — `flush` de toute la base, `loaddata` de `data.json`, suppression puis remplacement du dossier `media/`. Les comptes existants (y compris celui du demandeur) sont remplacés par ceux de l'archive ; aucune notification ni diffusion WebSocket.

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| file | corps (multipart) | fichier `.zip` | oui | Archive produite par `backup/export/`. |

Requête (champ de formulaire) :
```json
{ "file": "<backup_20260913_113000.zip>" }
```

Réponse `200` :
```json
{ "detail": "Backup restauré avec succès." }
```

Erreurs :
- `400` — `{"detail": "Aucun fichier fourni."}` ; `{"detail": "Le fichier doit être une archive .zip."}` ; `{"detail": "Fichier zip invalide."}` ; `{"detail": "Archive invalide : data.json introuvable."}` ; `{"detail": "data.json invalide ou corrompu."}`.
- `500` — `{"detail": "Erreur lors de la restauration : <message>"}` : échec de `flush`/`loaddata` (la base peut alors être partiellement vidée).
- `403` — `{"detail": "You do not have permission to perform this action."}`.

---

## Temps réel (WebSocket)

Routage ASGI (`Stock/asgi.py`) : `ws/chat/`, `ws/notifications/`, `ws/data/`, consumers dans `users/consumers.py`. Couche de canaux : Redis en production, `InMemoryChannelLayer` sinon. Toutes les trames sont du JSON texte.

**Authentification** : le jeton d'accès JWT est passé en query string `?token=<access>` (le client web construit `ws(s)://<hôte>/ws/…/?token=…`, cf. `frontend/lib/ws-utils.ts`). Sans jeton, jeton invalide/expiré ou utilisateur inconnu, la connexion est fermée sans être acceptée (pas de trame d'erreur). L'access n'expirant qu'au bout de 5 minutes, le client doit reconnecter avec un jeton frais après un `refresh/`.

### `/ws/notifications/?token=` — Flux de notifications
**Consumer** : `NotificationConsumer`

Groupes rejoints à la connexion :
- `admin` → `notifications_admin_<user_id>` ;
- `magasin` → `notifications_magasin_<magasin_id>` (son `MagasinProfile`) ; `employer` → `notifications_magasin_<magasin_id>` (magasin d'affectation, si présent) ;
- tous → `notifications_user_<user_id>` (notifications personnelles).

Émission (`users/signals.py::notification_created_broadcast`, `post_save` créé sur `Notification`) : la trame est envoyée à `notifications_admin_<admin>` (admin = `magasin.admin` de la notification, sinon l'admin résolu de `user` ; les co-admins ne sont donc pas ciblés), à `notifications_magasin_<magasin>` si `magasin` est renseigné, et à `notifications_user_<user>` si `user` est renseigné. Le client n'envoie rien ; il reçoit un objet notification brut (pas de champ `type`) :

```json
{
  "id": 130,
  "notif_type": "caisse",
  "message": "Caisse ouverte (Boutique Centre) par Rakoto Andry — fond: 50000.00",
  "magasin": 2,
  "magasin_name": "Boutique Centre",
  "is_read": false,
  "created_at": "2026-09-13T08:02:10.790000+03:00"
}
```

Sources de notifications dans cette application : inscription (`user`), ouverture/fermeture de caisse et mouvements (`caisse`), messages de chat (`chat`, message privé → `user = destinataire` ; salon général → `magasin` de l'expéditeur, `null` pour un admin), transferts de stock (`other`), création manuelle via `POST notifications/`. Les applications `orders`/`suppliers` en créent aussi (`order`, `supplier_order`).

### `/ws/data/?token=` — Synchronisation des données
**Consumer** : `DataSyncConsumer` · **Émetteur** : `users/broadcast.py::broadcast_data_event` (appelé par les signaux de `users`, `catalog`, `orders`, `suppliers`)

Groupes rejoints : `admin` → `data_admin_<user_id>` ; `magasin`/`employer` → `data_magasin_<magasin_id>` (si un magasin est résolu). L'événement est envoyé à `data_admin_<magasin.admin_id>` (admin propriétaire uniquement, pas les co-admins) et à `data_magasin_<magasin_id>` ; le magasin est déduit de l'instance (`magasin`, `order.magasin`, ou chaîne `product_variant → product_reference → type → category → magasin`). Le client n'envoie rien ; chaque trame invite à recharger la ressource concernée :

```json
{ "model": "caisse_session", "action": "created", "id": 7, "magasin_id": 2 }
```

| `model` | `action` | Source |
| --- | --- | --- |
| `caisse_session` | `created`, `updated` | `users/signals.py` (open/close) |
| `caisse_movement` | `created`, `deleted` | `users/signals.py` |
| `product_variant` | `created`, `updated` | `catalog/signals.py` (dont transferts de stock) |
| `stock_movement` | `created` | `catalog/signals.py` |
| `order` | `created`, `updated` | `orders/signals.py` |
| `order_status_history` | `created` | `orders/signals.py` |
| `supplier_order` | `created`, `updated` | `suppliers/signals.py` |

### `/ws/chat/?token=&recipient_id=` (ou `&room=`) — Messagerie
**Consumer** : `ChatConsumer`

Connexion :
- `recipient_id=<id>` → conversation privée ; room `dm_<idMin>_<idMax>`, groupe `chat_dm_<idMin>_<idMax>`. Fermée sans acceptation si le destinataire n'existe pas, n'appartient pas à la même société (aucun magasin commun) ou si les deux participants sont `LIVREUR`.
- sans `recipient_id` et `room` absent ou `general` → salon général `general_<company_id>` (`company_id` = `admin_id` du premier magasin de la société), groupe `chat_general_<company_id>`.
- `room=<autre valeur>` → utilisée telle quelle comme nom de room (aucune vérification).
- L'utilisateur doit appartenir à au moins un magasin, sinon fermeture.
À l'acceptation puis à chaque trame reçue, `CustomUser.last_seen_at` est mis à jour (présence « En ligne » dans `chat/users/`).

Trames envoyées par le client (`action` par défaut : `send`) :

```json
{ "content": "Bonjour, la commande CMD-2-20260912-0002 est prête." }
```
```json
{ "action": "edit", "message_id": 1, "content": "Bonjour, la commande CMD-2-20260912-0002 est prête (corrigé)." }
```
```json
{ "action": "delete", "message_id": 1 }
```
```json
{ "action": "read" }
```

Règles : `send` ignore un `content` vide (les images passent par `POST chat/upload/`) ; `edit`/`delete` ne s'appliquent qu'aux messages de la room dont l'utilisateur est l'expéditeur (un message supprimé n'est plus éditable) ; `read` n'a d'effet qu'en conversation privée et marque lus tous les messages non lus reçus dans la room. Une trame invalide (JSON illisible, champ manquant, message d'autrui) est ignorée silencieusement. Chaque `send` crée un `ChatMessage` et, par signal, une notification `chat`.

Trames reçues par tous les membres du groupe :

`type: "message"` (nouveau message texte, ou image envoyée via `chat/upload/` — alors `image` est une URL) :
```json
{
  "type": "message",
  "id": 3,
  "sender": 11,
  "sender_name": "Rakoto Andry",
  "sender_email": "admin@boutique-demo.mg",
  "sender_role": "admin",
  "recipient": 17,
  "recipient_name": "Onja Rasolo",
  "recipient_email": "onja.rasolo@boutique-demo.mg",
  "room_name": "dm_11_17",
  "content": "Bonjour, la commande CMD-2-20260912-0002 est prête.",
  "image": null,
  "is_edited": false,
  "is_deleted": false,
  "timestamp": "2026-09-13T11:40:12.512000+03:00",
  "read_at": null
}
```

`type: "message_edited"` :
```json
{
  "type": "message_edited",
  "id": 3,
  "room_name": "dm_11_17",
  "content": "Bonjour, la commande CMD-2-20260912-0002 est prête (corrigé).",
  "is_edited": true,
  "edited_at": "2026-09-13T11:41:03.004000+03:00"
}
```

`type: "message_deleted"` :
```json
{ "type": "message_deleted", "id": 3, "room_name": "dm_11_17" }
```

`type: "message_read"` (accusé de lecture, ids des messages marqués lus) :
```json
{ "type": "message_read", "ids": [3, 4], "read_at": "2026-09-13T11:42:30.120000+03:00", "room_name": "dm_11_17" }
```

---

## Catalog (catalogue produit et stock)

Préfixe d'URL : `/api/catalog/` (monté dans `Stock/urls.py`, routes générées par `DefaultRouter` dans `catalog/urls.py`). Authentification JWT (`Authorization: Bearer <access>`) sur toutes les routes. Aucune pagination n'est configurée : les listes renvoient un tableau JSON complet.

**Rôles** (`users/permissions.py`) :

- `IsGerantOrReadOnly` (toutes les ressources sauf `movements/`) : lecture (`GET`, `HEAD`, `OPTIONS`) pour tout utilisateur authentifié ; écriture (`POST`, `PUT`, `PATCH`, `DELETE`) réservée au **Gérant**, c'est-à-dire `user_commande_role(user) == "GERANT"` : `role == "admin"` (propriétaire ou co-admin de la société) ou `role == "magasin"`. Un `employer` (Préparateur / Livreur) ne peut que lire.
- `IsAuthenticated` (`movements/`) : lecture seule pour tout utilisateur authentifié.
- **Scoping magasin** : chaque `get_queryset` filtre sur `get_accessible_magasins(user)` — admin : tous les magasins de sa société ; magasin : le sien ; employer : le magasin de son affectation. Un objet d'un autre magasin renvoie `404`.
- **Magasin de création** (`resolve_magasin_for_request`) pour `categories/`, `brands/`, `colors/` et `import-excel/` : `magasin_id` (ou `magasin`) dans le corps si l'utilisateur accède à plusieurs magasins ; sinon l'unique magasin accessible est utilisé automatiquement.

**Erreurs communes à toutes les routes** :

- `401` — `{"detail": "Authentication credentials were not provided."}` : sans jeton ; `{"detail": "Given token not valid for any token type", "code": "token_not_valid", "messages": [{"token_class": "AccessToken", "token_type": "access", "message": "Token is invalid or expired"}]}` : jeton invalide/expiré.
- `403` — `{"detail": "You do not have permission to perform this action."}` : méthode d'écriture par un non-Gérant.
- `404` — `{"detail": "Not found."}` : identifiant inexistant ou objet d'un magasin non accessible.
- `405` — `{"detail": "Method \"PUT\" not allowed."}` : méthode non exposée (ex. `PUT`/`PATCH` sur `variants/`).

**Serializers** (`catalog/serializers.py`) : un seul serializer par ressource, identique quel que soit le rôle. `prix_achat` n'est **pas** masqué selon le rôle : un Préparateur ou un Livreur qui lit `references/` voit `prix_achat` (le masquage éventuel est à faire côté client). `ProductReferenceAutocompleteSerializer` (action `autocomplete/`) n'expose en revanche que `prix_vente`.

**Mouvements de stock** : le stock d'une variante (`stock_actuel`) n'est jamais écrit directement par l'API ; il ne change que via `catalog/services.py::apply_stock_movement`, qui verrouille la variante (`select_for_update`), applique `+quantite` (`ENTREE`) ou `-quantite` (`SORTIE`) et crée un `StockMovement`. Origines possibles (`StockMovement.ORIGINE_CHOICES`) :

| Origine | Créée par | Type |
| --- | --- | --- |
| `PREPARATION` | `orders/services.py` — passage d'une commande en préparation | `SORTIE` |
| `RETOUR` | `orders/services.py` — retour d'une commande livrée/en cours | `ENTREE` |
| `ANNULATION` | `orders/services.py` — annulation d'une commande déjà préparée | `ENTREE` |
| `FOURNISSEUR` | `suppliers/services.py` — réception d'une commande fournisseur (`reference` = numéro de la commande fournisseur) | `ENTREE` |
| `AJUSTEMENT` | `variants/{id}/adjust/`, stock initial à la création d'une variante, `import-excel/`, corrections d'état et modifications d'articles d'une commande (`orders/services.py`) | `ENTREE` ou `SORTIE` |

Le stock peut devenir négatif : `apply_stock_movement` ne vérifie pas la disponibilité (seule la logique commande le fait, hors de cette application).

**WebSocket** (`catalog/signals.py` → `users/broadcast.py`, consumer `ws/data/?token=<access>`) : chaque sauvegarde d'une `ProductVariant` (création, ou mise à jour du stock/seuil) et chaque création d'un `StockMovement` diffusent aux groupes `data_admin_{admin_id}` et `data_magasin_{magasin_id}` une trame :

```json
{"model": "product_variant", "action": "updated", "id": 727, "magasin_id": 2}
```

```json
{"model": "stock_movement", "action": "created", "id": 29, "magasin_id": 2}
```

Les autres modèles (catégories, sous-types, marques, couleurs, références, notes) n'émettent aucun événement WebSocket.

---

### Catégories — `categories/`

Modèle `ProductCategory` : `nom` unique par magasin, `ordre` (tri), `avec_couleurs` (`false` pour chargeur/écouteur… : la référence n'a qu'une variante « Standard » et le formulaire saisit directement une quantité). Tri : `ordre`, puis `nom`.

Serializer `ProductCategorySerializer` : `id`, `magasin` (lecture seule), `nom`, `ordre`, `avec_couleurs`.

### `GET /api/catalog/categories/` — Lister les catégories
**Rôle** : tout utilisateur authentifié · **Vue** : `ProductCategoryViewSet` (views.py)

Effet : aucun. Renvoie les catégories des magasins accessibles, triées par `ordre` puis `nom`.

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| `magasin_id` | query | entier | non | Restreint à un magasin (doit être accessible, sinon liste vide). |

Réponse `200` :
```json
[
  {"id": 4, "magasin": 2, "nom": "HOUSSE", "ordre": 0, "avec_couleurs": true},
  {"id": 5, "magasin": 2, "nom": "CACHE ÉCRAN", "ordre": 1, "avec_couleurs": true}
]
```

Erreurs : erreurs communes uniquement.

### `POST /api/catalog/categories/` — Créer une catégorie
**Rôle** : Gérant · **Vue** : `ProductCategoryViewSet` (views.py)

Effet : crée la catégorie dans le magasin résolu par `resolve_magasin_for_request`.

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| `nom` | corps | chaîne ≤ 100 | oui | Nom, unique par magasin. |
| `ordre` | corps | entier ≥ 0 | non (défaut `0`) | Position d'affichage. |
| `avec_couleurs` | corps | booléen | non (défaut `true`) | `false` = pas de déclinaison couleur. |
| `magasin_id` | corps | entier | si plusieurs magasins accessibles | Magasin cible (ignoré par le serializer, lu par `resolve_magasin_for_request`). |

Requête :
```json
{"nom": "CHARGEUR", "ordre": 2, "avec_couleurs": false, "magasin_id": 2}
```

Réponse `201` :
```json
{"id": 6, "magasin": 2, "nom": "CHARGEUR", "ordre": 2, "avec_couleurs": false}
```

Erreurs :
- `400` — `{"nom": ["This field is required."]}` : `nom` absent.
- `400` — `{"nom": ["This field may not be blank."]}` : `nom` vide.
- `400` — `{"nom": ["Ensure this field has no more than 100 characters."]}` : nom trop long.
- `400` — `{"ordre": ["Ensure this value is greater than or equal to 0."]}` : ordre négatif.
- `400` — `{"avec_couleurs": ["Must be a valid boolean."]}` : valeur non booléenne.
- `400` — `{"magasin_id": "Ce champ est requis (plusieurs magasins accessibles)."}` : admin multi-magasins sans `magasin_id`.
- `403` — `{"detail": "Magasin non autorisé."}` : `magasin_id` d'un magasin non accessible.
- `500` — nom déjà existant dans ce magasin (contrainte `unique_together(magasin, nom)` non validée par le serializer car `magasin` est en lecture seule : `IntegrityError` non interceptée).

### `GET /api/catalog/categories/{id}/` — Détail d'une catégorie
**Rôle** : tout utilisateur authentifié · **Vue** : `ProductCategoryViewSet` (views.py)

Effet : aucun.

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| `id` | chemin | entier | oui | Identifiant de la catégorie. |

Réponse `200` :
```json
{"id": 4, "magasin": 2, "nom": "HOUSSE", "ordre": 0, "avec_couleurs": true}
```

Erreurs :
- `404` — `{"detail": "Not found."}` : id inexistant ou magasin non accessible.

### `PUT /api/catalog/categories/{id}/` — Remplacer une catégorie
**Rôle** : Gérant · **Vue** : `ProductCategoryViewSet` (views.py)

Effet : met à jour `nom`, `ordre`, `avec_couleurs` (le magasin ne change jamais). Aucun événement WebSocket.

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| `id` | chemin | entier | oui | Identifiant. |
| `nom` | corps | chaîne ≤ 100 | oui | Nom. |
| `ordre` | corps | entier ≥ 0 | non | Position. |
| `avec_couleurs` | corps | booléen | non | Déclinaison couleur. |

Requête :
```json
{"nom": "HOUSSES", "ordre": 0, "avec_couleurs": true}
```

Réponse `200` :
```json
{"id": 4, "magasin": 2, "nom": "HOUSSES", "ordre": 0, "avec_couleurs": true}
```

Erreurs : identiques au `POST` (`400` de validation, `500` si doublon de nom), plus `404`.

### `PATCH /api/catalog/categories/{id}/` — Modifier partiellement une catégorie
**Rôle** : Gérant · **Vue** : `ProductCategoryViewSet` (views.py)

Effet : même chose que `PUT`, tous les champs facultatifs.

Requête :
```json
{"ordre": 3}
```

Réponse `200` :
```json
{"id": 4, "magasin": 2, "nom": "HOUSSE", "ordre": 3, "avec_couleurs": true}
```

Erreurs : identiques au `PUT`.

### `DELETE /api/catalog/categories/{id}/` — Supprimer une catégorie
**Rôle** : Gérant · **Vue** : `ProductCategoryViewSet` (views.py)

Effet : supprime la catégorie **uniquement si elle n'a aucun sous-type** ; sinon refus. (Les notes produit rattachées à la catégorie sont supprimées en cascade.)

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| `id` | chemin | entier | oui | Identifiant. |

Réponse `204` : corps vide.

Erreurs :
- `400` — `["Impossible de supprimer une catégorie qui a des sous-types — supprimez ou déplacez d'abord ses sous-types."]` : la catégorie a au moins un `ProductType`.
- `404` — `{"detail": "Not found."}`.

---

### Sous-types — `types/`

Modèle `ProductType` : `nom` unique par catégorie (FLIP COVER, Z-FOLD, PRIVACY…). Serializer `ProductTypeSerializer` : `id`, `category`, `nom`. Le magasin est hérité de la catégorie. Note : le champ `category` accepte tout id existant (`PrimaryKeyRelatedField` non restreint aux magasins accessibles) ; seule la lecture est scopée.

### `GET /api/catalog/types/` — Lister les sous-types
**Rôle** : tout utilisateur authentifié · **Vue** : `ProductTypeViewSet` (views.py)

Effet : aucun. Tri : catégorie, puis `nom`.

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| `category` | query | entier | non | Filtre sur l'id de catégorie. |

Réponse `200` :
```json
[
  {"id": 5, "category": 4, "nom": "FLIP COVER"},
  {"id": 7, "category": 4, "nom": "Z-FLIP"}
]
```

### `POST /api/catalog/types/` — Créer un sous-type
**Rôle** : Gérant · **Vue** : `ProductTypeViewSet` (views.py)

Effet : crée le sous-type dans la catégorie donnée.

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| `category` | corps | entier | oui | Id de la catégorie parente. |
| `nom` | corps | chaîne ≤ 100 | oui | Nom, unique dans la catégorie. |

Requête :
```json
{"category": 4, "nom": "Z-FOLD"}
```

Réponse `201` :
```json
{"id": 9, "category": 4, "nom": "Z-FOLD"}
```

Erreurs :
- `400` — `{"category": ["This field is required."], "nom": ["This field is required."]}` : champs absents.
- `400` — `{"category": ["Invalid pk \"99999\" - object does not exist."]}` : catégorie inexistante.
- `400` — `{"non_field_errors": ["The fields category, nom must make a unique set."]}` : doublon de nom dans la catégorie.
- `400` — `{"nom": ["Ensure this field has no more than 100 characters."]}`.

### `GET /api/catalog/types/{id}/` — Détail d'un sous-type
**Rôle** : tout utilisateur authentifié · **Vue** : `ProductTypeViewSet` (views.py)

Effet : aucun.

Réponse `200` :
```json
{"id": 5, "category": 4, "nom": "FLIP COVER"}
```

Erreurs : `404` — `{"detail": "Not found."}`.

### `PUT /api/catalog/types/{id}/` — Remplacer un sous-type
**Rôle** : Gérant · **Vue** : `ProductTypeViewSet` (views.py)

Effet : met à jour `category` et `nom` (permet de déplacer un sous-type vers une autre catégorie ; ses références suivent).

Requête :
```json
{"category": 4, "nom": "FLIP COVER PREMIUM"}
```

Réponse `200` :
```json
{"id": 5, "category": 4, "nom": "FLIP COVER PREMIUM"}
```

Erreurs : identiques au `POST`, plus `404`.

### `PATCH /api/catalog/types/{id}/` — Modifier partiellement un sous-type
**Rôle** : Gérant · **Vue** : `ProductTypeViewSet` (views.py)

Requête :
```json
{"nom": "FLIP COVER"}
```

Réponse `200` :
```json
{"id": 5, "category": 4, "nom": "FLIP COVER"}
```

Erreurs : identiques au `PUT`.

### `DELETE /api/catalog/types/{id}/` — Supprimer un sous-type
**Rôle** : Gérant · **Vue** : `ProductTypeViewSet` (views.py)

Effet : supprime le sous-type **uniquement s'il n'a aucune référence produit**. Les notes produit rattachées sont supprimées en cascade.

Réponse `204` : corps vide.

Erreurs :
- `400` — `["Impossible de supprimer un sous-type qui a des références produit — supprimez ou déplacez d'abord ses références."]` : au moins une `ProductReference` utilise ce sous-type.
- `404` — `{"detail": "Not found."}`.

---

### Marques — `brands/`

Modèle `Brand` : `nom` unique par magasin, tri par `nom`. Serializer `BrandSerializer` : `id`, `magasin` (lecture seule), `nom`.

### `GET /api/catalog/brands/` — Lister les marques
**Rôle** : tout utilisateur authentifié · **Vue** : `BrandViewSet` (views.py)

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| `magasin_id` | query | entier | non | Restreint à un magasin. |

Réponse `200` :
```json
[
  {"id": 18, "magasin": 2, "nom": "Google Pixel"},
  {"id": 17, "magasin": 2, "nom": "Huawei"}
]
```

### `POST /api/catalog/brands/` — Créer une marque
**Rôle** : Gérant · **Vue** : `BrandViewSet` (views.py)

Effet : crée la marque dans le magasin résolu par `resolve_magasin_for_request`.

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| `nom` | corps | chaîne ≤ 100 | oui | Nom, unique par magasin. |
| `magasin_id` | corps | entier | si plusieurs magasins accessibles | Magasin cible. |

Requête :
```json
{"nom": "Xiaomi", "magasin_id": 2}
```

Réponse `201` :
```json
{"id": 19, "magasin": 2, "nom": "Xiaomi"}
```

Erreurs :
- `400` — `{"nom": ["This field is required."]}` / `{"nom": ["This field may not be blank."]}` / `{"nom": ["Ensure this field has no more than 100 characters."]}`.
- `400` — `{"magasin_id": "Ce champ est requis (plusieurs magasins accessibles)."}`.
- `403` — `{"detail": "Magasin non autorisé."}`.
- `500` — nom déjà existant dans ce magasin (`IntegrityError` non interceptée).

### `GET /api/catalog/brands/{id}/` — Détail d'une marque
**Rôle** : tout utilisateur authentifié · **Vue** : `BrandViewSet` (views.py)

Réponse `200` :
```json
{"id": 18, "magasin": 2, "nom": "Google Pixel"}
```

Erreurs : `404` — `{"detail": "Not found."}`.

### `PUT /api/catalog/brands/{id}/` — Remplacer une marque
**Rôle** : Gérant · **Vue** : `BrandViewSet` (views.py)

Requête :
```json
{"nom": "Google"}
```

Réponse `200` :
```json
{"id": 18, "magasin": 2, "nom": "Google"}
```

Erreurs : identiques au `POST` (hors magasin), plus `404`.

### `PATCH /api/catalog/brands/{id}/` — Modifier partiellement une marque
**Rôle** : Gérant · **Vue** : `BrandViewSet` (views.py)

Requête :
```json
{"nom": "Google Pixel"}
```

Réponse `200` :
```json
{"id": 18, "magasin": 2, "nom": "Google Pixel"}
```

Erreurs : identiques au `PUT`.

### `DELETE /api/catalog/brands/{id}/` — Supprimer une marque
**Rôle** : Gérant · **Vue** : `BrandViewSet` (views.py)

Effet : supprime la marque **uniquement si aucune référence ne l'utilise**. Les notes produit qui la référencent passent à `brand = null` (`SET_NULL`).

Réponse `204` : corps vide.

Erreurs :
- `400` — `["Impossible de supprimer une marque qui a des références produit — supprimez ou déplacez d'abord ses références."]`.
- `404` — `{"detail": "Not found."}`.

---

### Couleurs — `colors/`

Modèle `Color` : liste de couleurs suggérées par magasin (menu Paramètres), `nom` unique par magasin. Elle alimente uniquement le sélecteur du frontend : `ProductVariant.couleur` reste un texte libre et n'est pas contraint par cette table. Serializer `ColorSerializer` : `id`, `magasin` (lecture seule), `nom`.

### `GET /api/catalog/colors/` — Lister les couleurs
**Rôle** : tout utilisateur authentifié · **Vue** : `ColorViewSet` (views.py)

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| `magasin_id` | query | entier | non | Restreint à un magasin. |

Réponse `200` :
```json
[
  {"id": 2, "magasin": 2, "nom": "Bleu"},
  {"id": 4, "magasin": 2, "nom": "Noir"}
]
```

### `POST /api/catalog/colors/` — Créer une couleur
**Rôle** : Gérant · **Vue** : `ColorViewSet` (views.py)

Effet : crée la couleur dans le magasin résolu.

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| `nom` | corps | chaîne ≤ 100 | oui | Nom, unique par magasin. |
| `magasin_id` | corps | entier | si plusieurs magasins accessibles | Magasin cible. |

Requête :
```json
{"nom": "Vert sauge"}
```

Réponse `201` :
```json
{"id": 18, "magasin": 2, "nom": "Vert sauge"}
```

Erreurs :
- `400` — `{"nom": ["This field is required."]}` / `{"nom": ["This field may not be blank."]}` / `{"nom": ["Ensure this field has no more than 100 characters."]}`.
- `400` — `{"magasin_id": "Ce champ est requis (plusieurs magasins accessibles)."}`.
- `403` — `{"detail": "Magasin non autorisé."}`.
- `500` — nom déjà existant dans ce magasin (`IntegrityError` non interceptée).

### `GET /api/catalog/colors/{id}/` — Détail d'une couleur
**Rôle** : tout utilisateur authentifié · **Vue** : `ColorViewSet` (views.py)

Réponse `200` :
```json
{"id": 2, "magasin": 2, "nom": "Bleu"}
```

Erreurs : `404` — `{"detail": "Not found."}`.

### `PUT /api/catalog/colors/{id}/` — Remplacer une couleur
**Rôle** : Gérant · **Vue** : `ColorViewSet` (views.py)

Effet : renomme la couleur suggérée (les variantes existantes conservent leur texte `couleur`).

Requête :
```json
{"nom": "Bleu nuit"}
```

Réponse `200` :
```json
{"id": 2, "magasin": 2, "nom": "Bleu nuit"}
```

Erreurs : identiques au `POST` (hors magasin), plus `404`.

### `PATCH /api/catalog/colors/{id}/` — Modifier partiellement une couleur
**Rôle** : Gérant · **Vue** : `ColorViewSet` (views.py)

Requête :
```json
{"nom": "Bleu"}
```

Réponse `200` :
```json
{"id": 2, "magasin": 2, "nom": "Bleu"}
```

### `DELETE /api/catalog/colors/{id}/` — Supprimer une couleur
**Rôle** : Gérant · **Vue** : `ColorViewSet` (views.py)

Effet : supprime la suggestion ; aucune règle de protection (les variantes ne pointent pas vers cette table).

Réponse `204` : corps vide.

Erreurs : `404` — `{"detail": "Not found."}`.

---

### Références produit — `references/`

Modèle `ProductReference` : une référence de téléphone pour un sous-type et une marque (`unique_together(type, brand, reference_name)`), avec `prix_achat` (coût unitaire saisi pour la marge, défaut `0`), `prix_vente` (obligatoire), `photo` (image facultative), `actif`. Tri : marque, puis `reference_name`.

Serializer `ProductReferenceSerializer` (lecture et écriture, identique pour tous les rôles) :

| Champ | Type | Écriture | Description |
| --- | --- | --- | --- |
| `id` | entier | lecture seule | |
| `type` | entier | oui, obligatoire | Id du sous-type. |
| `type_name`, `category_name` | chaîne | lecture seule | Dérivés de `type`. |
| `brand` | entier | oui, obligatoire | Id de la marque. |
| `brand_name` | chaîne | lecture seule | |
| `reference_name` | chaîne ≤ 150 | oui, obligatoire | Nom (ex. « Galaxy A15 »). |
| `prix_achat` | décimal (12 chiffres, 2 décimales), chaîne en JSON | non (défaut `"0.00"`) | Coût d'achat. |
| `prix_vente` | décimal | oui, obligatoire | Prix de vente. |
| `photo` | fichier image / `null` | non | **Envoi en `multipart/form-data`** (champ fichier `photo`) ; en lecture : URL absolue (`http://<hôte>/media/products/<fichier>`) ou `null`. Un `PATCH` JSON `"photo": null` efface la photo. |
| `actif` | booléen | non (défaut `true`) | Une référence inactive est exclue de `autocomplete/`. |
| `variants` | liste | lecture seule | Variantes (voir `ProductVariantSerializer`) — créées via `variants/`. |
| `magasin` | entier | lecture seule | `type.category.magasin_id`. |

Note : `type` et `brand` acceptent tout id existant (non restreints aux magasins accessibles à l'écriture) ; les références sont ensuite scopées en lecture par le magasin de la catégorie du sous-type.

### `GET /api/catalog/references/` — Lister les références
**Rôle** : tout utilisateur authentifié · **Vue** : `ProductReferenceViewSet` (views.py)

Effet : aucun. Chaque référence embarque ses variantes (`prefetch_related`).

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| `type` | query | entier | non | Filtre sur le sous-type. |
| `brand` | query | entier | non | Filtre sur la marque. |
| `category` | query | entier | non | Filtre sur la catégorie (`type__category`). |
| `magasin_id` | query | entier | non | Filtre sur le magasin. |

Réponse `200` :
```json
[
  {
    "id": 410,
    "type": 6,
    "type_name": "PRIVACY",
    "category_name": "CACHE ÉCRAN",
    "brand": 18,
    "brand_name": "Google Pixel",
    "reference_name": "Pixel 10 Pro XL",
    "prix_achat": "25000.00",
    "prix_vente": "30000.00",
    "photo": null,
    "actif": true,
    "variants": [
      {
        "id": 727,
        "product_reference": 410,
        "reference_name": "Pixel 10 Pro XL",
        "brand_name": "Google Pixel",
        "prix_vente": "30000.00",
        "couleur": "Standard",
        "sku_loyverse": "10359",
        "stock_actuel": 7,
        "seuil_alerte": 1,
        "is_rupture": false,
        "is_stock_bas": false
      }
    ],
    "magasin": 2
  },
  {
    "id": 323,
    "type": 5,
    "type_name": "FLIP COVER",
    "category_name": "HOUSSE",
    "brand": 15,
    "brand_name": "Infinix",
    "reference_name": "Hot 10 Play",
    "prix_achat": "30000.00",
    "prix_vente": "40000.00",
    "photo": "http://api.example.mg/media/products/hot10play.jpg",
    "actif": true,
    "variants": [
      {
        "id": 593,
        "product_reference": 323,
        "reference_name": "Hot 10 Play",
        "brand_name": "Infinix",
        "prix_vente": "40000.00",
        "couleur": "Noir",
        "sku_loyverse": null,
        "stock_actuel": 1,
        "seuil_alerte": 1,
        "is_rupture": false,
        "is_stock_bas": true
      }
    ],
    "magasin": 2
  }
]
```

### `POST /api/catalog/references/` — Créer une référence
**Rôle** : Gérant · **Vue** : `ProductReferenceViewSet` (views.py)

Effet : crée la référence **sans variante** (créer ensuite les couleurs via `POST /api/catalog/variants/`). Envoyer en JSON, ou en `multipart/form-data` pour joindre `photo`.

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| `type` | corps | entier | oui | Sous-type. |
| `brand` | corps | entier | oui | Marque. |
| `reference_name` | corps | chaîne ≤ 150 | oui | Unique pour (type, brand). |
| `prix_vente` | corps | décimal | oui | ≤ 12 chiffres au total. |
| `prix_achat` | corps | décimal | non | Défaut `0`. |
| `photo` | corps (multipart) | fichier image | non | |
| `actif` | corps | booléen | non | Défaut `true`. |

Requête (JSON) :
```json
{"type": 5, "brand": 18, "reference_name": "Pixel 9a", "prix_achat": "28000.00", "prix_vente": "45000.00", "actif": true}
```

Réponse `201` :
```json
{
  "id": 612,
  "type": 5,
  "type_name": "FLIP COVER",
  "category_name": "HOUSSE",
  "brand": 18,
  "brand_name": "Google Pixel",
  "reference_name": "Pixel 9a",
  "prix_achat": "28000.00",
  "prix_vente": "45000.00",
  "photo": null,
  "actif": true,
  "variants": [],
  "magasin": 2
}
```

Erreurs :
- `400` — `{"type": ["This field is required."], "brand": ["This field is required."], "reference_name": ["This field is required."], "prix_vente": ["This field is required."]}` : champs absents.
- `400` — `{"non_field_errors": ["The fields type, brand, reference_name must make a unique set."]}` : doublon exact (sensible à la casse).
- `400` — `{"type": ["Invalid pk \"999\" - object does not exist."]}` (idem `brand`).
- `400` — `{"prix_vente": ["A valid number is required."]}` ; `{"prix_achat": ["Ensure that there are no more than 12 digits in total."]}` ; `{"prix_vente": ["Ensure that there are no more than 2 decimal places."]}`.
- `400` — `{"photo": ["The submitted data was not a file. Check the encoding type on the form."]}` : `photo` envoyé en JSON au lieu de multipart ; `{"photo": ["Upload a valid image. The file you uploaded was either not an image or a corrupted image."]}` : fichier non image.
- `400` — `{"reference_name": ["Ensure this field has no more than 150 characters."]}`.

### `GET /api/catalog/references/{id}/` — Détail d'une référence
**Rôle** : tout utilisateur authentifié · **Vue** : `ProductReferenceViewSet` (views.py)

Réponse `200` : même objet que dans la liste (voir ci-dessus, élément `id: 410`).

Erreurs : `404` — `{"detail": "Not found."}`.

### `PUT /api/catalog/references/{id}/` — Remplacer une référence
**Rôle** : Gérant · **Vue** : `ProductReferenceViewSet` (views.py)

Effet : met à jour tous les champs modifiables (`type`, `brand`, `reference_name`, `prix_achat`, `prix_vente`, `photo`, `actif`). Ne touche ni au stock ni aux variantes ; aucun mouvement, aucun événement WebSocket.

Requête :
```json
{"type": 5, "brand": 18, "reference_name": "Pixel 9a", "prix_achat": "28000.00", "prix_vente": "48000.00", "actif": true}
```

Réponse `200` : objet complet mis à jour (même forme que `POST`).

Erreurs : identiques au `POST` (le contrôle d'unicité exclut l'instance elle-même), plus `404`.

### `PATCH /api/catalog/references/{id}/` — Modifier partiellement une référence
**Rôle** : Gérant · **Vue** : `ProductReferenceViewSet` (views.py)

Effet : idem `PUT`, champs facultatifs. Sert typiquement à désactiver (`actif: false`), changer un prix ou effacer la photo.

Requête :
```json
{"prix_vente": "35000.00", "actif": false}
```

Réponse `200` : objet complet mis à jour.

Erreurs : identiques au `PUT`.

### `DELETE /api/catalog/references/{id}/` — Supprimer une référence
**Rôle** : Gérant · **Vue** : `ProductReferenceViewSet` (views.py)

Effet : supprime la référence **et toutes ses variantes en cascade** (avec leur historique `StockMovement`). Aucune vérification préalable dans la vue : si l'une des variantes est utilisée par une ligne de commande client (`OrderItem`, `on_delete=PROTECT`) ou un approvisionnement fournisseur (`SupplierOrder.product_variant`, `PROTECT`), la base refuse la suppression. Préférer `PATCH {"actif": false}` pour retirer une référence encore liée à des commandes.

Réponse `204` : corps vide.

Erreurs :
- `404` — `{"detail": "Not found."}`.
- `500` — `django.db.models.ProtectedError` non interceptée (réponse HTML/`Server Error (500)`) : une variante est référencée par une commande client ou fournisseur.

### `GET /api/catalog/references/autocomplete/` — Recherche pour le formulaire Nouvelle commande
**Rôle** : tout utilisateur authentifié · **Vue** : `ProductReferenceViewSet.autocomplete` (views.py)

Effet : aucun. Renvoie au plus **20** références **actives** (`actif=true`) des magasins accessibles, avec leurs couleurs et stocks, via `ProductReferenceAutocompleteSerializer` (sans `prix_achat`).

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| `q` | query | chaîne | non | Recherche insensible à la casse contenue dans `reference_name`. |
| `type` | query | entier | non | Filtre sous-type (hérité de `get_queryset`). |
| `brand` | query | entier | non | Filtre marque. |
| `category` | query | entier | non | Filtre catégorie. |
| `magasin_id` | query | entier | non | Filtre magasin. |

Réponse `200` :
```json
[
  {
    "id": 323,
    "type": 5,
    "type_name": "FLIP COVER",
    "brand": 15,
    "brand_name": "Infinix",
    "reference_name": "Hot 10 Play",
    "prix_vente": "40000.00",
    "photo": null,
    "couleurs": [
      {"variant_id": 593, "couleur": "Noir", "stock_actuel": 1}
    ]
  },
  {
    "id": 376,
    "type": 6,
    "type_name": "PRIVACY",
    "brand": 15,
    "brand_name": "Infinix",
    "reference_name": "Infinix Smart 10",
    "prix_vente": "30000.00",
    "photo": null,
    "couleurs": [
      {"variant_id": 693, "couleur": "Standard", "stock_actuel": 5}
    ]
  }
]
```

Erreurs : erreurs communes uniquement (sans `q`, renvoie les 20 premières références actives).

### `POST /api/catalog/references/bulk-update-price/` — Modification groupée des prix d'un sous-type
**Rôle** : Gérant · **Vue** : `ProductReferenceViewSet.bulk_update_price` (views.py)

Effet : met à jour `prix_achat` et/ou `prix_vente` de **toutes** les références du sous-type `type_id` accessibles à l'utilisateur (`queryset.update()`, sans passer par `save()` — `updated_at` n'est pas modifié). Pas de mouvement de stock ni d'événement WebSocket.

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| `type_id` | corps | entier | oui | Sous-type ciblé. |
| `prix_achat` | corps | décimal ≥ 0 | au moins l'un des deux | Nouveau prix d'achat. |
| `prix_vente` | corps | décimal ≥ 0 | au moins l'un des deux | Nouveau prix de vente. |

Requête :
```json
{"type_id": 5, "prix_vente": "42000.00"}
```

Réponse `200` :
```json
{"updated": 87}
```

Erreurs :
- `400` — `{"type_id": ["This field is required."]}`.
- `400` — `{"non_field_errors": ["Indiquez au moins un prix à modifier."]}` : ni `prix_achat` ni `prix_vente`.
- `400` — `{"prix_vente": ["Ensure this value is greater than or equal to 0."]}` (idem `prix_achat`) ; `{"prix_vente": ["A valid number is required."]}`.
- `404` — `{"error": "Aucune référence pour ce sous-type."}` : aucune référence accessible pour `type_id` (sous-type inexistant, vide, ou d'un autre magasin).

### `GET /api/catalog/references/export-excel/` — Exporter le catalogue en Excel
**Rôle** : tout utilisateur authentifié · **Vue** : `ProductReferenceViewSet.export_excel` (views.py)

Effet : aucun en base. Génère un classeur `.xlsx` (feuille « Catalogue ») avec **une ligne par variante** (une référence sans variante donne une ligne avec `Couleur`, `Stock actuel`, `Seuil alerte` vides), triée par catégorie / sous-type / marque / référence. Les filtres de liste (`type`, `brand`, `category`, `magasin_id`) s'appliquent.

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| `type`, `brand`, `category`, `magasin_id` | query | entier | non | Mêmes filtres que la liste. |

Réponse `200` : corps binaire (pas de JSON).

- `Content-Type: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet`
- `Content-Disposition: attachment; filename="catalogue.xlsx"` (exposé via `CORS_EXPOSE_HEADERS`)

Colonnes, dans l'ordre (ligne 1 = en-têtes) : `Catégorie`, `Sous-type`, `Marque`, `Référence`, `Couleur`, `Prix achat` (nombre), `Prix vente` (nombre), `Stock actuel` (entier), `Seuil alerte` (entier), `Actif` (`Oui` / `Non`). Ce fichier est le format d'entrée de `import-excel/`.

Erreurs : erreurs communes uniquement.

### `POST /api/catalog/references/import-excel/` — Importer / actualiser le catalogue depuis Excel
**Rôle** : Gérant · **Vue** : `ProductReferenceViewSet.import_excel` (views.py) · parseur : `MultiPartParser` uniquement

Effet : pour chaque ligne du fichier (format `export-excel/`, feuille active, données à partir de la ligne 2), crée ou met à jour dans l'ordre **Catégorie → Sous-type → Marque → Référence → Couleur (variante)**, avec recherche **insensible à la casse** (`iexact`) après `strip()` pour ne pas créer de doublon. Chaque ligne est traitée dans sa propre transaction. Un `ImportBatch` est créé (magasin résolu par `resolve_magasin_for_request`, `created_by` = utilisateur) et mémorise chaque objet créé/modifié pour permettre l'annulation via `import-batches/{id}/cancel/`.

Règles par ligne :
- Ligne entièrement vide : ignorée (non comptée).
- Colonne 11 « Statut » déjà remplie (ligne traitée par un import précédent du même fichier) : ligne **sautée** (`X-Import-Skipped-Count`).
- `Catégorie`, `Sous-type`, `Marque`, `Référence` obligatoires ; sinon erreur `Catégorie/Sous-type/Marque/Référence manquant(e).`
- Catégorie / sous-type / marque absents du magasin : créés (une catégorie créée a `avec_couleurs = true`, `ordre = 0`).
- `Prix achat` / `Prix vente` : nombres, vides ⇒ `0` ; invalides ⇒ erreur `Prix achat/vente invalide (nombre attendu).` (rien n'est créé pour la ligne).
- `Actif` : `Non`, `false` ou `0` (insensible à la casse) ⇒ inactif ; toute autre valeur (y compris vide) ⇒ actif.
- Référence trouvée (type + marque + nom) : `prix_achat`, `prix_vente`, `actif` **écrasés** par le fichier ; sinon créée.
- `Couleur` vide : la ligne s'arrête après la référence (statut « Référence créée (sans couleur) » / « Référence mise à jour (sans couleur) »).
- `Stock actuel` / `Seuil alerte` : entiers, vides ⇒ `0` / `1` ; invalides ⇒ erreur `Stock/Seuil d'alerte invalide (nombre entier attendu).` (la référence reste créée/mise à jour).
- Variante nouvelle : créée à stock `0` puis, si `Stock actuel > 0`, mouvement `ENTREE` / origine `AJUSTEMENT` / note `Import Excel`.
- Variante existante : `seuil_alerte` mis à jour si différent ; l'écart entre `Stock actuel` du fichier et le stock en base génère un mouvement `ENTREE` (écart positif) ou `SORTIE` (écart négatif), origine `AJUSTEMENT`, note `Import Excel`. Écart nul : aucun mouvement.
- Toute exception inattendue sur une ligne annule ce que cette ligne a fait et inscrit `Erreur : <message>` dans « Statut ».

Chaque mouvement et chaque variante sauvegardée déclenchent les événements WebSocket `stock_movement`/`product_variant`.

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| `file` | corps (`multipart/form-data`) | fichier `.xlsx` | oui | Classeur au format `export-excel/`. |
| `magasin_id` | corps (multipart) | entier | si plusieurs magasins accessibles | Magasin cible. |

Requête : `multipart/form-data` avec le champ `file=@catalogue.xlsx` (et éventuellement `magasin_id=2`).

Réponse `200` : **le fichier Excel lui-même, annoté** (pas de JSON). Les colonnes 11 « Statut » et 12 « Date de traitement » (format `JJ/MM/AAAA HH:MM`, fuseau `Indian/Antananarivo`) sont ajoutées/remplies pour chaque ligne traitée ; le fichier renvoyé peut être réimporté tel quel pour poursuivre (les lignes déjà statuées sont sautées). Valeurs possibles de « Statut » : `Référence créée (sans couleur)`, `Référence mise à jour (sans couleur)`, `Référence créée ; couleur créée`, `Référence créée ; couleur mise à jour`, `Référence mise à jour ; couleur créée`, `Référence mise à jour ; couleur mise à jour`, `Erreur : <message>`.

En-têtes de réponse (tous exposés au navigateur via `CORS_EXPOSE_HEADERS`) :

| En-tête | Valeur | Description |
| --- | --- | --- |
| `Content-Type` | `application/vnd.openxmlformats-officedocument.spreadsheetml.sheet` | Fichier Excel. |
| `Content-Disposition` | `attachment; filename="catalogue_import_2026-09-13.xlsx"` | Nom = `catalogue_import_<date ISO du jour>.xlsx`. |
| `X-Import-Batch-Id` | entier, ex. `7` | Id de l'`ImportBatch` à passer à `import-batches/{id}/cancel/`. |
| `X-Import-Created-References` | entier | Nombre de références créées. |
| `X-Import-Updated-References` | entier | Nombre de références existantes mises à jour (prix/actif). |
| `X-Import-Created-Variants` | entier | Nombre de variantes (couleurs) créées. |
| `X-Import-Updated-Variants` | entier | Nombre de variantes existantes mises à jour (seuil et/ou stock). |
| `X-Import-Errors-Count` | entier | Nombre de lignes en erreur (chaque erreur est aussi inscrite dans la colonne « Statut » de la ligne). |
| `X-Import-Skipped-Count` | entier | Nombre de lignes sautées car déjà statuées. |
| `X-Import-New-Reference-Names` | JSON, ex. `["Google Pixel Pixel 9a", "Samsung Galaxy A16"]` | Libellés `"<Marque> <Référence>"` des références créées, **50 premiers maximum**. |
| `X-Import-Updated-Reference-Names` | JSON, ex. `["Infinix Hot 10 Play"]` | Libellés des références mises à jour, 50 premiers maximum. |

Erreurs :
- `400` — `{"error": "Fichier requis (champ 'file')."}` : pas de fichier `file` dans le multipart.
- `400` — `{"error": "Fichier Excel invalide."}` : `openpyxl` ne peut pas ouvrir le fichier (pas un `.xlsx`, corrompu).
- `400` — `{"magasin_id": "Ce champ est requis (plusieurs magasins accessibles)."}`.
- `403` — `{"detail": "Magasin non autorisé."}`.
- `415` — `{"detail": "Unsupported media type \"application/json\" in request."}` : corps envoyé en JSON au lieu de multipart.

Les erreurs par ligne ne produisent **pas** de code d'erreur HTTP : elles sont comptées dans `X-Import-Errors-Count` et détaillées dans le fichier (`Erreur : Catégorie/Sous-type/Marque/Référence manquant(e).`, `Erreur : Prix achat/vente invalide (nombre attendu).`, `Erreur : Stock/Seuil d'alerte invalide (nombre entier attendu).`).

---

### Lots d'import — `import-batches/`

`ImportBatchViewSet` est un `GenericViewSet` sans `list`/`retrieve` : seule l'action `cancel` est exposée. Le lot est scopé aux magasins accessibles.

### `POST /api/catalog/import-batches/{id}/cancel/` — Annuler un import Excel
**Rôle** : Gérant · **Vue** : `ImportBatchViewSet.cancel` (views.py) → `services.revert_import_batch`

Effet : défait l'import dans l'ordre inverse des lignes traitées, en une transaction : suppression des variantes créées (et de leur mouvement de stock initial), restauration de `seuil_alerte` / `stock_actuel` des variantes mises à jour **et suppression du mouvement `AJUSTEMENT` correspondant**, suppression des références créées, restauration de `prix_achat` / `prix_vente` / `actif` des références mises à jour, puis suppression des sous-types, catégories et marques créés **seulement s'ils n'ont plus aucun enfant** (best-effort, pour ne jamais entraîner des données saisies par ailleurs). `cancelled_at` est horodaté. Le stock est restauré par écriture directe (pas de mouvement inverse), les variantes sauvegardées émettent l'événement WebSocket `product_variant/updated`. Attention : si une variante créée par l'import a depuis été utilisée dans une commande (`PROTECT`), l'annulation échoue en `500`.

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| `id` | chemin | entier | oui | `X-Import-Batch-Id` renvoyé par `import-excel/`. |

Réponse `200` :
```json
{"status": "cancelled"}
```

Erreurs :
- `400` — `{"error": "Cet import a déjà été annulé."}` : `cancelled_at` déjà renseigné.
- `404` — `{"detail": "Not found."}` : lot inexistant ou d'un magasin non accessible.
- `500` — `ProtectedError` non interceptée si une variante à supprimer est liée à une commande.

---

### Variantes (couleurs) — `variants/`

Modèle `ProductVariant` : déclinaison couleur d'une référence (`unique_together(product_reference, couleur)`), niveau où le stock est suivi : `stock_actuel`, `seuil_alerte` (défaut `1`), `sku_loyverse` (référence Loyverse d'origine, ≤ 30 caractères). Méthodes exposées : **`GET`, `POST`, `DELETE` uniquement** (`PUT`/`PATCH` ⇒ `405` : le stock ne se modifie que via `adjust/`, et le seuil/couleur ne sont pas modifiables par l'API).

Serializer `ProductVariantSerializer` :

| Champ | Type | Écriture | Description |
| --- | --- | --- | --- |
| `id` | entier | lecture seule | |
| `product_reference` | entier | oui, obligatoire | Id de la référence. |
| `reference_name`, `brand_name`, `prix_vente` | chaîne | lecture seule | Dérivés de la référence. |
| `couleur` | chaîne ≤ 100 | non (défaut `"Standard"`) | Texte libre, unique par référence. |
| `sku_loyverse` | chaîne ≤ 30 / `null` | non | |
| `stock_actuel` | entier | **lecture seule** dans le serializer ; à la création, la vue lit `stock_actuel` dans le corps pour créer un mouvement d'entrée initial | Stock courant. |
| `seuil_alerte` | entier | non (défaut `1`) | Seuil de stock bas. |
| `is_rupture` | booléen | lecture seule | `stock_actuel <= 0`. |
| `is_stock_bas` | booléen | lecture seule | `0 < stock_actuel <= seuil_alerte`. |

### `GET /api/catalog/variants/` — Lister les variantes
**Rôle** : tout utilisateur authentifié · **Vue** : `ProductVariantViewSet` (views.py)

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| `reference` | query | entier | non | Filtre sur `product_reference`. |

Réponse `200` :
```json
[
  {
    "id": 727,
    "product_reference": 410,
    "reference_name": "Pixel 10 Pro XL",
    "brand_name": "Google Pixel",
    "prix_vente": "30000.00",
    "couleur": "Standard",
    "sku_loyverse": "10359",
    "stock_actuel": 7,
    "seuil_alerte": 1,
    "is_rupture": false,
    "is_stock_bas": false
  },
  {
    "id": 593,
    "product_reference": 323,
    "reference_name": "Hot 10 Play",
    "brand_name": "Infinix",
    "prix_vente": "40000.00",
    "couleur": "Noir",
    "sku_loyverse": null,
    "stock_actuel": 1,
    "seuil_alerte": 1,
    "is_rupture": false,
    "is_stock_bas": true
  }
]
```

### `POST /api/catalog/variants/` — Créer une variante (couleur)
**Rôle** : Gérant · **Vue** : `ProductVariantViewSet` (views.py)

Effet : crée la variante à stock `0`, puis, si `stock_actuel` > 0 est fourni dans le corps, applique un mouvement `ENTREE` d'origine `AJUSTEMENT` avec la note `Stock initial à la création de la couleur` (utilisateur = appelant). Une valeur `stock_actuel` non numérique ou négative est ignorée (stock `0`). Événements WebSocket : `product_variant/created`, puis `product_variant/updated` et `stock_movement/created` si stock initial.

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| `product_reference` | corps | entier | oui | Référence parente. |
| `couleur` | corps | chaîne ≤ 100 | non (défaut `Standard`) | Unique par référence (sensible à la casse). |
| `sku_loyverse` | corps | chaîne ≤ 30 | non | |
| `seuil_alerte` | corps | entier | non (défaut `1`) | |
| `stock_actuel` | corps | entier ≥ 0 | non | Stock initial (mouvement tracé). |

Requête :
```json
{"product_reference": 612, "couleur": "Noir", "seuil_alerte": 2, "stock_actuel": 10}
```

Réponse `201` :
```json
{
  "id": 901,
  "product_reference": 612,
  "reference_name": "Pixel 9a",
  "brand_name": "Google Pixel",
  "prix_vente": "45000.00",
  "couleur": "Noir",
  "sku_loyverse": null,
  "stock_actuel": 10,
  "seuil_alerte": 2,
  "is_rupture": false,
  "is_stock_bas": false
}
```

Erreurs :
- `400` — `{"product_reference": ["This field is required."]}`.
- `400` — `{"product_reference": ["Invalid pk \"999\" - object does not exist."]}`.
- `400` — `{"non_field_errors": ["The fields product_reference, couleur must make a unique set."]}` : couleur déjà existante pour cette référence.
- `400` — `{"seuil_alerte": ["A valid integer is required."]}` ; `{"sku_loyverse": ["Ensure this field has no more than 30 characters."]}` ; `{"couleur": ["Ensure this field has no more than 100 characters."]}`.

### `GET /api/catalog/variants/{id}/` — Détail d'une variante
**Rôle** : tout utilisateur authentifié · **Vue** : `ProductVariantViewSet` (views.py)

Réponse `200` :
```json
{
  "id": 727,
  "product_reference": 410,
  "reference_name": "Pixel 10 Pro XL",
  "brand_name": "Google Pixel",
  "prix_vente": "30000.00",
  "couleur": "Standard",
  "sku_loyverse": "10359",
  "stock_actuel": 7,
  "seuil_alerte": 1,
  "is_rupture": false,
  "is_stock_bas": false
}
```

Erreurs : `404` — `{"detail": "Not found."}`.

### `DELETE /api/catalog/variants/{id}/` — Supprimer une variante
**Rôle** : Gérant · **Vue** : `ProductVariantViewSet` (views.py)

Effet : supprime la variante et **tout son historique de mouvements** (cascade). Aucune vérification dans la vue : une variante utilisée par une ligne de commande client ou fournisseur (`on_delete=PROTECT`) ne peut pas être supprimée.

Réponse `204` : corps vide.

Erreurs :
- `404` — `{"detail": "Not found."}`.
- `500` — `ProtectedError` non interceptée : la variante figure dans au moins un `OrderItem` ou un `SupplierOrder`.

### `POST /api/catalog/variants/{id}/adjust/` — Ajustement manuel du stock
**Rôle** : Gérant · **Vue** : `ProductVariantViewSet.adjust` (views.py) → `services.apply_stock_movement`

Effet : applique `+quantite` (`ENTREE`) ou `-quantite` (`SORTIE`) sur `stock_actuel` sous verrou, et crée un `StockMovement` d'origine `AJUSTEMENT` (`user` = appelant, `reference` = `null`, `note` = note ou `null`). Aucun contrôle de stock négatif. Événements WebSocket : `product_variant/updated` et `stock_movement/created`.

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| `id` | chemin | entier | oui | Variante. |
| `type` | corps | `"ENTREE"` ou `"SORTIE"` | oui | Sens du mouvement. |
| `quantite` | corps | entier ≥ 1 | oui | Quantité. |
| `note` | corps | chaîne | non (défaut `""` ⇒ stocké `null`) | Motif. |

Requête :
```json
{"type": "ENTREE", "quantite": 5, "note": "Réassort hors commande fournisseur"}
```

Réponse `200` (variante mise à jour) :
```json
{
  "id": 727,
  "product_reference": 410,
  "reference_name": "Pixel 10 Pro XL",
  "brand_name": "Google Pixel",
  "prix_vente": "30000.00",
  "couleur": "Standard",
  "sku_loyverse": "10359",
  "stock_actuel": 12,
  "seuil_alerte": 1,
  "is_rupture": false,
  "is_stock_bas": false
}
```

Erreurs :
- `400` — `{"type": ["This field is required."], "quantite": ["This field is required."]}`.
- `400` — `{"type": ["\"AJOUT\" is not a valid choice."]}` : type hors `ENTREE`/`SORTIE`.
- `400` — `{"quantite": ["Ensure this value is greater than or equal to 1."]}` ; `{"quantite": ["A valid integer is required."]}`.
- `404` — `{"detail": "Not found."}`.

---

### Mouvements de stock — `movements/`

`StockMovementViewSet` est un `ReadOnlyModelViewSet` (`IsAuthenticated`) : lecture seule pour tout utilisateur authentifié, y compris Préparateur/Livreur ; toute écriture passe par `apply_stock_movement`. Tri : `timestamp` décroissant. Serializer `StockMovementSerializer` (tous champs en lecture seule) : `id`, `product_variant`, `reference_name`, `couleur`, `type` (`ENTREE`/`SORTIE`), `quantite`, `origine`, `reference` (numéro de commande client `CMD-…` ou fournisseur, ou `null`), `note`, `user` (id ou `null`), `user_name` (`full_name`), `timestamp` (ISO 8601, fuseau `Indian/Antananarivo`).

### `GET /api/catalog/movements/` — Historique des mouvements
**Rôle** : tout utilisateur authentifié · **Vue** : `StockMovementViewSet` (views.py)

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| `variant` | query | entier | non | Filtre sur `product_variant`. |

Réponse `200` :
```json
[
  {
    "id": 28,
    "product_variant": 658,
    "reference_name": "Pixel 8 Pro",
    "couleur": "Bleu",
    "type": "ENTREE",
    "quantite": 1,
    "origine": "RETOUR",
    "reference": "CMD-2-20260909-0005",
    "note": null,
    "user": 16,
    "user_name": "Rakoto Hery",
    "timestamp": "2026-09-12T10:33:45.500204+03:00"
  },
  {
    "id": 27,
    "product_variant": 659,
    "reference_name": "Pixel 8 Pro",
    "couleur": "Noir",
    "type": "SORTIE",
    "quantite": 1,
    "origine": "PREPARATION",
    "reference": "CMD-2-20260911-0002",
    "note": null,
    "user": 11,
    "user_name": "Gérant Démo",
    "timestamp": "2026-09-11T19:17:28.671748+03:00"
  }
]
```

Erreurs : erreurs communes uniquement.

### `GET /api/catalog/movements/{id}/` — Détail d'un mouvement
**Rôle** : tout utilisateur authentifié · **Vue** : `StockMovementViewSet` (views.py)

Réponse `200` :
```json
{
  "id": 29,
  "product_variant": 727,
  "reference_name": "Pixel 10 Pro XL",
  "couleur": "Standard",
  "type": "ENTREE",
  "quantite": 5,
  "origine": "AJUSTEMENT",
  "reference": null,
  "note": "Réassort hors commande fournisseur",
  "user": 11,
  "user_name": "Gérant Démo",
  "timestamp": "2026-09-13T09:05:12.118377+03:00"
}
```

Erreurs : `404` — `{"detail": "Not found."}`.

---

### Notes produit (produits à commander) — `notes/`

Modèle `ProductNote` : pense-bête pour un produit repéré mais pas encore au catalogue (pas de prix, pas de stock), avec la même hiérarchie (catégorie, sous-type, marque facultative, `couleurs` = liste de noms libres, vide = sans couleur). Tri : `created_at` décroissant. Lecture pour tout utilisateur du magasin, écriture Gérant.

Serializer `ProductNoteSerializer` : `id`, `magasin` (lecture seule), `nom` (≤ 255, obligatoire), `category` (obligatoire), `category_name`, `type` (obligatoire), `type_name`, `brand` (facultatif, `null`), `brand_name` (`""` si pas de marque), `couleurs` (liste de chaînes ≤ 100, non vides ; les espaces de bord sont retirés), `created_by_name` (`full_name` ou `username` du créateur, `""` si supprimé), `created_at`.

Validation (`validate`) : `type.category_id` doit être égal à `category.id` ; `brand.magasin_id` doit être égal à `category.magasin_id`. La vue vérifie en plus que la catégorie appartient à un magasin accessible ; le magasin de la note est celui de la catégorie.

### `GET /api/catalog/notes/` — Lister les notes produit
**Rôle** : tout utilisateur authentifié · **Vue** : `ProductNoteViewSet` (views.py)

Effet : aucun. Aucun filtre de requête.

Réponse `200` :
```json
[
  {
    "id": 3,
    "magasin": 2,
    "nom": "Coque MagSafe transparente iPhone 17",
    "category": 4,
    "category_name": "HOUSSE",
    "type": 5,
    "type_name": "FLIP COVER",
    "brand": 12,
    "brand_name": "Apple",
    "couleurs": ["Transparent", "Noir"],
    "created_by_name": "Gérant Démo",
    "created_at": "2026-09-12T15:40:02.301554+03:00"
  },
  {
    "id": 2,
    "magasin": 2,
    "nom": "Verre trempé Galaxy A56",
    "category": 5,
    "category_name": "CACHE ÉCRAN",
    "type": 6,
    "type_name": "PRIVACY",
    "brand": null,
    "brand_name": "",
    "couleurs": [],
    "created_by_name": "Gérant Démo",
    "created_at": "2026-09-10T08:12:45.000000+03:00"
  }
]
```

### `POST /api/catalog/notes/` — Créer une note produit
**Rôle** : Gérant · **Vue** : `ProductNoteViewSet` (views.py)

Effet : crée la note dans le magasin de la catégorie, `created_by` = appelant. Pas de stock, pas d'événement WebSocket.

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| `nom` | corps | chaîne ≤ 255 | oui | Libellé du produit. |
| `category` | corps | entier | oui | Catégorie (doit être d'un magasin accessible). |
| `type` | corps | entier | oui | Sous-type appartenant à `category`. |
| `brand` | corps | entier / `null` | non | Marque du même magasin que la catégorie. |
| `couleurs` | corps | liste de chaînes ≤ 100 | non (défaut `[]`) | Couleurs à commander. |

Requête :
```json
{"nom": "Coque MagSafe transparente iPhone 17", "category": 4, "type": 5, "brand": 12, "couleurs": ["Transparent", "Noir"]}
```

Réponse `201` :
```json
{
  "id": 3,
  "magasin": 2,
  "nom": "Coque MagSafe transparente iPhone 17",
  "category": 4,
  "category_name": "HOUSSE",
  "type": 5,
  "type_name": "FLIP COVER",
  "brand": 12,
  "brand_name": "Apple",
  "couleurs": ["Transparent", "Noir"],
  "created_by_name": "Gérant Démo",
  "created_at": "2026-09-12T15:40:02.301554+03:00"
}
```

Erreurs :
- `400` — `{"nom": ["This field is required."], "category": ["This field is required."], "type": ["This field is required."]}`.
- `400` — `{"type": "Ce sous-type n'appartient pas à la catégorie choisie."}` : `type.category != category`.
- `400` — `{"brand": "Cette marque n'appartient pas au même magasin."}`.
- `400` — `{"category": "Catégorie non autorisée."}` : catégorie d'un magasin non accessible à l'utilisateur.
- `400` — `{"couleurs": ["Expected a list of items but got type \"str\"."]}` : `couleurs` n'est pas une liste ; `{"couleurs": {"1": ["This field may not be blank."]}}` : élément vide (index en clé) ; `{"couleurs": {"1": ["Ensure this field has no more than 100 characters."]}}`.
- `400` — `{"category": ["Invalid pk \"999\" - object does not exist."]}` (idem `type`, `brand`).
- `400` — `{"nom": ["Ensure this field has no more than 255 characters."]}`.

### `GET /api/catalog/notes/{id}/` — Détail d'une note produit
**Rôle** : tout utilisateur authentifié · **Vue** : `ProductNoteViewSet` (views.py)

Réponse `200` : même objet que dans la liste.

Erreurs : `404` — `{"detail": "Not found."}`.

### `PUT /api/catalog/notes/{id}/` — Remplacer une note produit
**Rôle** : Gérant · **Vue** : `ProductNoteViewSet` (views.py)

Effet : met à jour `nom`, `category`, `type`, `brand`, `couleurs` ; le magasin est réaligné sur celui de la catégorie (`created_by` inchangé).

Requête :
```json
{"nom": "Coque MagSafe iPhone 17 Pro", "category": 4, "type": 5, "brand": 12, "couleurs": ["Noir"]}
```

Réponse `200` : objet complet mis à jour.

Erreurs : identiques au `POST`, plus `404`.

### `PATCH /api/catalog/notes/{id}/` — Modifier partiellement une note produit
**Rôle** : Gérant · **Vue** : `ProductNoteViewSet` (views.py)

Effet : idem `PUT`, champs facultatifs ; la cohérence `type`/`category`/`brand` est vérifiée avec les valeurs actuelles de l'instance pour les champs omis.

Requête :
```json
{"couleurs": ["Noir", "Bleu"]}
```

Réponse `200` : objet complet mis à jour.

Erreurs : identiques au `PUT`.

### `DELETE /api/catalog/notes/{id}/` — Supprimer une note produit
**Rôle** : Gérant · **Vue** : `ProductNoteViewSet` (views.py)

Effet : supprime la note (aucune dépendance, aucune règle de protection).

Réponse `204` : corps vide.

Erreurs : `404` — `{"detail": "Not found."}`.

---

## Commandes (application `orders`)

Préfixe de toutes les routes : **`/api/orders/`** (fichier `orders/urls.py`). Authentification JWT obligatoire sur chaque route (`IsAuthenticated`) ; sans jeton la réponse est `401 {"detail": "Authentication credentials were not provided."}`.

**Rôles du module Commande** (`users/permissions.py::user_commande_role`) :

| Rôle | Qui | Serializer de lecture des commandes |
| --- | --- | --- |
| `GERANT` | `CustomUser.role` = `admin` ou `magasin` | `OrderGerantSerializer` — vue complète : prix unitaires, `prix_catalogue`, `remise_unitaire`, `remise_total`, `status_history`, `campagnes` / `campagne_nom` (boosts couvrant la date, calculés — `campagne` = FK historique, toujours `null` pour les nouvelles commandes), `note_preparateur` **et** `note_livreur` |
| `PREPARATEUR` | `role = employer` avec `EmployerProfile.commande_role = PREPARATEUR` | `OrderPreparateurSerializer` — sans prix unitaires, sans historique, avec `note_preparateur` uniquement |
| `LIVREUR` | `role = employer` avec `commande_role = LIVREUR` | `OrderLivreurSerializer` — sans prix unitaires, avec `status_history` (photo de préparation) et `note_livreur` uniquement |
| aucun (`None`) | employer sans `commande_role` | traité comme un gérant pour la lecture, mais refusé sur toute action de workflow |

`IsGerant` (permission DRF) : lorsqu'elle échoue, la réponse est toujours `403 {"detail": "You do not have permission to perform this action."}`.

**Portée des données** : toutes les listes sont restreintes aux magasins accessibles (`get_accessible_magasins`) — admin : tous les magasins de sa société ; magasin : le sien ; employer : celui de son affectation. Les zones de livraison et les types de dépense sont partagés par toute la **société** (`AdminProfile`).

**Conventions de réponse** :
- Les montants issus d'un serializer (`prix`, `total_a_payer`, `montant`…) sont des **chaînes** décimales (`"3000.00"`). Les montants calculés par les vues Dashboard/Rapports sont des **nombres** (`3000.0`).
- Les dates/heures sont en ISO 8601 avec le fuseau `Indian/Antananarivo` (`+03:00`).
- Les erreurs levées par les vues avec un simple message (`DRFValidationError("…")`) sont renvoyées sous forme de **liste** : `400 ["…"]`. Les erreurs de serializer sont un objet `{"champ": ["…"]}`. Les refus (`PermissionDenied`) sont `403 {"detail": "…"}`.
- `PUT` n'est autorisé sur aucune ressource (`http_method_names` sans `put`) → `405 {"detail": "Method \"PUT\" not allowed."}`. Les mises à jour se font en `PATCH`.
- Objet inexistant ou hors portée : `404 {"detail": "No Order matches the given query."}` (le nom du modèle varie : `Delivery zone`, `Expense type`, `Livreur expense`, `Marketing campaign`).

**Statuts d'une commande** (`Order.STATUT_CHOICES`) : `NOUVELLE` (Nouvelle) → `EN_PREPARATION` (En préparation) → `PRETE` (Prête) → `EN_LIVRAISON` (En livraison) → `LIVRE` (Livré) ; états terminaux alternatifs : `RETOUR` (Retour), `ANNULEE` (Annulée). Modes de paiement : `AVANT` (Paiement avant la livraison), `LIVRAISON` (Paiement à la livraison).

**Impact stock** (`orders/services.py`) : le stock est déduit au passage `EN_PREPARATION` (mouvement `SORTIE`, origine `PREPARATION`), restitué au passage `RETOUR` (origine `RETOUR`), à l'annulation d'une commande déjà en préparation ou plus (origine `ANNULATION`), et corrigé en `AJUSTEMENT` lors d'une modification d'articles en préparation ou d'une correction de statut. `LIVRE` ne touche pas au stock.

---

### Commandes

### `GET /api/orders/` — Liste des commandes
**Rôle** : tout utilisateur authentifié (réponse et filtrage différents par rôle) · **Vue** : `OrderViewSet.list` (views.py)

Effet : lecture seule. Le gérant voit toutes les commandes de ses magasins ; le préparateur et le livreur ne voient que les commandes **déjà assignées à leur nom**. Sans `historique=1` : le préparateur voit ses commandes `NOUVELLE`/`EN_PREPARATION` plus ses retraits sur place (`PRETE` + `livraison_zone = RECUPERATION`) ; le livreur voit ses commandes `NOUVELLE`/`EN_PREPARATION`/`PRETE`/`EN_LIVRAISON` (son planning, hors retraits sur place). Tri : `-created_at` (gérant/file du jour) ou `-date_commande` (historique). Pas de pagination.

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| `statut` | query | string | non | Gérant : un seul code. Préparateur/livreur : un ou plusieurs codes séparés par des virgules (`LIVRE,RETOUR`), sans sortir des statuts autorisés au rôle |
| `date_debut` | query | date `YYYY-MM-DD` | non | `date_commande` ≥ ce jour (gérant et file préparateur/livreur) |
| `date_fin` | query | date `YYYY-MM-DD` | non | `date_commande` ≤ ce jour, journée entière incluse |
| `magasin_id` | query | int | non | Gérant uniquement : restreint à un magasin |
| `livraison_zone` | query | string | non | Code de zone (`ZONE1`…) ou `RECUPERATION` |
| `preparateur_id` | query | int | non | Gérant uniquement : commandes assignées à ce préparateur |
| `historique` | query | `1` | non | Préparateur/livreur uniquement : journal personnel, tous statuts confondus, filtrable par `date_from`/`date_to`/`statut` |
| `date_from` | query | datetime ISO | non | Avec `historique=1` : `date_commande` ≥ cet instant (date **et** heure) |
| `date_to` | query | datetime ISO | non | Avec `historique=1` : `date_commande` ≤ cet instant |

Réponse `200` — **gérant** (`OrderGerantSerializer`) :
```json
[
  {
    "id": 19,
    "magasin": 2,
    "numero": "CMD-2-20260912-0002",
    "date_commande": "2026-09-12T13:05:00+03:00",
    "client_nom": "Rasoa Hanta",
    "telephone": "+261340000001",
    "telephone_2": "",
    "livraison_zone": "ZONE1",
    "adresse_livraison": "Lot II B 12, Ankorondrano",
    "mode_paiement": "LIVRAISON",
    "frais_livraison": "3000.00",
    "total_a_payer": "33000.00",
    "remise_total": "0.00",
    "note_preparateur": "",
    "note_livreur": "",
    "statut_courant": "NOUVELLE",
    "preparateur": 13,
    "preparateur_name": "Faniry",
    "livreur": 17,
    "livreur_name": "Mamy",
    "campagne": null,
    "campagne_nom": "",
    "campagnes": [],
    "items": [
      {
        "id": 22,
        "product_variant": 727,
        "reference_name": "pixel 10 pro xl",
        "brand_name": "Google Pixel",
        "type_name": "PRIVACY",
        "category_name": "CACHE ÉCRAN",
        "couleur": "Standard",
        "prix_unitaire": "30000.00",
        "prix_catalogue": "30000.00",
        "remise_unitaire": "0.00",
        "quantite": 1,
        "retourne": false
      }
    ],
    "status_history": [
      {
        "id": 63,
        "ancien_statut": null,
        "nouveau_statut": "NOUVELLE",
        "changed_by": 11,
        "changed_by_name": "Rakoto Jean",
        "note": null,
        "photo": null,
        "timestamp": "2026-09-12T13:05:35.327794+03:00"
      }
    ],
    "created_at": "2026-09-12T13:05:35.316374+03:00",
    "updated_at": "2026-09-12T13:05:50.358101+03:00"
  }
]
```
Remarques : `prix_catalogue` vaut `null` sur les commandes antérieures à la fonctionnalité de remise (alors `remise_unitaire` = `"0.00"`). `photo` est une URL absolue (`http://<hôte>/media/order_status_photos/<uuid>.jpeg`) ou `null`.

Réponse `200` — **préparateur** (`OrderPreparateurSerializer`) :
```json
[
  {
    "id": 19,
    "numero": "CMD-2-20260912-0002",
    "date_commande": "2026-09-12T13:05:00+03:00",
    "client_nom": "Rasoa Hanta",
    "telephone": "+261340000001",
    "telephone_2": "",
    "livraison_zone": "ZONE1",
    "adresse_livraison": "Lot II B 12, Ankorondrano",
    "mode_paiement": "LIVRAISON",
    "frais_livraison": "3000.00",
    "total_a_payer": "33000.00",
    "remise_total": "0.00",
    "statut_courant": "NOUVELLE",
    "note_preparateur": "",
    "preparateur": 13,
    "preparateur_name": "Faniry",
    "livreur": 17,
    "livreur_name": "Mamy",
    "items": [
      {
        "id": 22,
        "reference_name": "pixel 10 pro xl",
        "brand_name": "Google Pixel",
        "type_name": "PRIVACY",
        "category_name": "CACHE ÉCRAN",
        "couleur": "Standard",
        "quantite": 1,
        "retourne": false
      }
    ],
    "created_at": "2026-09-12T13:05:35.316374+03:00"
  }
]
```

Réponse `200` — **livreur** (`OrderLivreurSerializer`, ici avec `historique=1` sur une livraison partielle) :
```json
[
  {
    "id": 16,
    "numero": "CMD-2-20260911-0001",
    "date_commande": "2026-09-11T16:01:00+03:00",
    "client_nom": "Randria Solo",
    "telephone": "+261330000002",
    "telephone_2": "",
    "livraison_zone": "ZONE1",
    "adresse_livraison": "Villa 5, Ivandry",
    "mode_paiement": "LIVRAISON",
    "frais_livraison": "3000.00",
    "total_a_payer": "33000.00",
    "remise_total": "0.00",
    "statut_courant": "LIVRE",
    "note_livreur": "",
    "livreur": 15,
    "livreur_name": "Rivo",
    "items": [
      {
        "id": 18,
        "reference_name": "pixel 10 pro xl",
        "brand_name": "Google Pixel",
        "type_name": "PRIVACY",
        "category_name": "CACHE ÉCRAN",
        "couleur": "Standard",
        "quantite": 1,
        "retourne": false
      },
      {
        "id": 19,
        "reference_name": "Pixel 9pro",
        "brand_name": "Google Pixel",
        "type_name": "FLIP COVER",
        "category_name": "HOUSSE",
        "couleur": "Noir",
        "quantite": 1,
        "retourne": true
      }
    ],
    "status_history": [
      {
        "id": 50,
        "ancien_statut": null,
        "nouveau_statut": "NOUVELLE",
        "changed_by": 11,
        "changed_by_name": "Rakoto Jean",
        "note": null,
        "photo": null,
        "timestamp": "2026-09-11T16:02:15.839816+03:00"
      },
      {
        "id": 54,
        "ancien_statut": "EN_LIVRAISON",
        "nouveau_statut": "LIVRE",
        "changed_by": 15,
        "changed_by_name": "Rivo",
        "note": "Articles rapportés : Pixel 9pro (Noir) x1",
        "photo": null,
        "timestamp": "2026-09-11T16:02:42.923005+03:00"
      }
    ],
    "created_at": "2026-09-11T16:02:15.826311+03:00"
  }
]
```

Erreurs :
- `401` — `{"detail": "Authentication credentials were not provided."}` : sans jeton.

---

### `POST /api/orders/` — Créer une commande
**Rôle** : `GERANT` ou `PREPARATEUR` (le préparateur uniquement pour un retrait sur place) · **Vue** : `OrderViewSet.create` (views.py) → `services.create_order`, serializer `OrderCreateSerializer`

Effet : crée la commande en statut `NOUVELLE` avec ses articles (prix figés au moment de la commande), calcule `frais_livraison` (prix de la zone, 0 pour `RECUPERATION`) et `total_a_payer`, écrit la première ligne d'historique (`null → NOUVELLE`), puis notifie tous les préparateurs du magasin (`Notification` type `order` : « Nouvelle commande CMD-… — Client (ZONE1) ») et diffuse en WebSocket sur `notifications_magasin_<id>`, `notifications_admin_<id>` et `notifications_user_<id>` de chaque préparateur. Aucun mouvement de stock à ce stade. Une commande créée par un préparateur lui est auto-assignée (`preparateur = créateur`).

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| `client_nom` | corps | string ≤ 255 | oui | Nom du client |
| `telephone` | corps | string | oui | Format strict `+261XXXXXXXXX` (9 chiffres après `+261`) |
| `telephone_2` | corps | string | non | Second numéro, même format, ou chaîne vide (défaut `""`) |
| `livraison_zone` | corps | string ≤ 20 | oui | `code` d'une `DeliveryZoneOption` **active** de la société (ex. `ZONE1`) ou le littéral `RECUPERATION` |
| `adresse_livraison` | corps | string ≤ 255 | non | Adresse libre (défaut `""`) |
| `mode_paiement` | corps | `AVANT` \| `LIVRAISON` | non | Défaut `LIVRAISON` |
| `date_commande` | corps | datetime ISO | non | Date **et heure** de livraison prévue ; défaut = maintenant |
| `note_preparateur` | corps | string | non | Note vue du préparateur uniquement |
| `note_livreur` | corps | string | non | Note vue du livreur uniquement |
| `campagne` | corps | — | non | **Ignoré** : l'affectation à un boost est automatique par période (voir *Campagnes marketing*) |
| `items` | corps | liste | oui | Au moins un article |
| `items[].product_variant` | corps | int | oui | Id d'un `ProductVariant` existant |
| `items[].quantite` | corps | int ≥ 1 | non | Défaut 1 |
| `items[].prix_unitaire` | corps | decimal ≥ 0 \| null | non | Prix **remisé** appliqué à cette commande, au plus égal au prix catalogue (`ProductReference.prix_vente`). Absent/`null` = prix catalogue |
| `magasin_id` (ou `magasin`) | corps | int | selon le cas | Magasin cible ; obligatoire seulement si l'utilisateur accède à plusieurs magasins (admin multi-boutiques) |

Requête :
```json
{
  "client_nom": "Rasoa Hanta",
  "telephone": "+261340000001",
  "telephone_2": "",
  "livraison_zone": "ZONE1",
  "adresse_livraison": "Lot II B 12, Ankorondrano",
  "mode_paiement": "LIVRAISON",
  "date_commande": "2026-09-14T10:00:00+03:00",
  "note_preparateur": "Emballage cadeau",
  "note_livreur": "Appeler avant d'arriver",
  "campagne": null,
  "items": [
    { "product_variant": 727, "quantite": 1 },
    { "product_variant": 661, "quantite": 2, "prix_unitaire": "35000.00" }
  ],
  "magasin_id": 2
}
```

Réponse `201` (gérant → `OrderGerantSerializer` ; préparateur → `OrderPreparateurSerializer`) :
```json
{
  "id": 21,
  "magasin": 2,
  "numero": "CMD-2-20260913-0001",
  "date_commande": "2026-09-14T10:00:00+03:00",
  "client_nom": "Rasoa Hanta",
  "telephone": "+261340000001",
  "telephone_2": "",
  "livraison_zone": "ZONE1",
  "adresse_livraison": "Lot II B 12, Ankorondrano",
  "mode_paiement": "LIVRAISON",
  "frais_livraison": "3000.00",
  "total_a_payer": "103000.00",
  "remise_total": "10000.00",
  "note_preparateur": "Emballage cadeau",
  "note_livreur": "Appeler avant d'arriver",
  "statut_courant": "NOUVELLE",
  "preparateur": null,
  "preparateur_name": null,
  "livreur": null,
  "livreur_name": null,
  "campagne": null,
  "campagne_nom": "",
  "campagnes": [],
  "items": [
    {
      "id": 30,
      "product_variant": 727,
      "reference_name": "pixel 10 pro xl",
      "brand_name": "Google Pixel",
      "type_name": "PRIVACY",
      "category_name": "CACHE ÉCRAN",
      "couleur": "Standard",
      "prix_unitaire": "30000.00",
      "prix_catalogue": "30000.00",
      "remise_unitaire": "0.00",
      "quantite": 1,
      "retourne": false
    },
    {
      "id": 31,
      "product_variant": 661,
      "reference_name": "Pixel 9pro",
      "brand_name": "Google Pixel",
      "type_name": "FLIP COVER",
      "category_name": "HOUSSE",
      "couleur": "Noir",
      "prix_unitaire": "35000.00",
      "prix_catalogue": "40000.00",
      "remise_unitaire": "5000.00",
      "quantite": 2,
      "retourne": false
    }
  ],
  "status_history": [
    {
      "id": 70,
      "ancien_statut": null,
      "nouveau_statut": "NOUVELLE",
      "changed_by": 11,
      "changed_by_name": "Rakoto Jean",
      "note": null,
      "photo": null,
      "timestamp": "2026-09-13T09:12:41.100000+03:00"
    }
  ],
  "created_at": "2026-09-13T09:12:41.090000+03:00",
  "updated_at": "2026-09-13T09:12:41.150000+03:00"
}
```

Erreurs :
- `403` — `{"detail": "Seuls le gérant et le préparateur peuvent créer une commande."}` : livreur ou employer sans rôle.
- `400` — `{"client_nom": ["This field is required."], "telephone": ["This field is required."], "livraison_zone": ["This field is required."], "items": ["This field is required."]}` : champs obligatoires absents.
- `400` — `{"telephone": ["Format attendu : +261XXXXXXXXX"]}` ou `{"telephone_2": ["Format attendu : +261XXXXXXXXX"]}` : numéro mal formé.
- `400` — `{"livraison_zone": ["Zone de livraison invalide."]}` : code inconnu, zone désactivée, ou zone d'une autre société.
- `400` — `{"mode_paiement": ["\"X\" is not a valid choice."]}`.
- `400` — `{"date_commande": ["Datetime has wrong format. Use one of these formats instead: YYYY-MM-DDThh:mm[:ss[.uuuuuu]][+HH:MM|-HH:MM|Z]."]}`.
- `400` — `{"items": ["Au moins un article est requis."]}` : liste vide.
- `400` — `{"items": [{}, {"quantite": ["Ensure this value is greater than or equal to 1."]}]}` : quantité nulle sur le 2e article (une entrée par article, `{}` pour ceux sans erreur).
- `400` — `{"items": [{"product_variant": ["Invalid pk \"999999\" - object does not exist."]}]}`.
- `400` — `{"items": [{"prix_unitaire": ["Le prix remisé ne peut pas dépasser le prix catalogue (30000 Ar)."]}]}` : remise négative.
- `400` — `["Le préparateur ne peut créer que des commandes 'Récupération sur place'."]` : préparateur avec `livraison_zone` ≠ `RECUPERATION`.
- `400` — `{"magasin_id": ["Ce champ est requis (plusieurs magasins accessibles)."]}` ; `403` — `{"detail": "Magasin non autorisé."}` : `magasin_id` hors portée.

---

### `GET /api/orders/{id}/` — Détail d'une commande
**Rôle** : tout utilisateur authentifié, dans les limites de visibilité de `GET /api/orders/` (un préparateur/livreur ne peut ouvrir qu'une commande qui apparaît dans sa liste du jour) · **Vue** : `OrderViewSet.retrieve` (views.py)

Effet : lecture seule ; même serializer par rôle que la liste.

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| `id` | chemin | int | oui | Id de la commande |

Réponse `200` (gérant) : même objet que dans la liste gérant ci-dessus, ici une commande livrée avec photo de préparation :
```json
{
  "id": 12,
  "magasin": 2,
  "numero": "CMD-2-20260910-0002",
  "date_commande": "2026-09-10T15:07:00+03:00",
  "client_nom": "Rabe Lanto",
  "telephone": "+261320000003",
  "telephone_2": "+261340000004",
  "livraison_zone": "ZONE1",
  "adresse_livraison": "Ampasanimalo, près de l'école",
  "mode_paiement": "LIVRAISON",
  "frais_livraison": "3000.00",
  "total_a_payer": "33000.00",
  "remise_total": "0.00",
  "note_preparateur": "",
  "note_livreur": "",
  "statut_courant": "LIVRE",
  "preparateur": 12,
  "preparateur_name": "Haja",
  "livreur": 16,
  "livreur_name": "Tahina",
  "campagne": null,
  "campagne_nom": "",
  "campagnes": [],
  "items": [
    {
      "id": 13,
      "product_variant": 729,
      "reference_name": "Pixel 7 Pro",
      "brand_name": "Google Pixel",
      "type_name": "PRIVACY",
      "category_name": "CACHE ÉCRAN",
      "couleur": "Standard",
      "prix_unitaire": "30000.00",
      "prix_catalogue": null,
      "remise_unitaire": "0.00",
      "quantite": 1,
      "retourne": false
    }
  ],
  "status_history": [
    {
      "id": 36,
      "ancien_statut": null,
      "nouveau_statut": "NOUVELLE",
      "changed_by": 11,
      "changed_by_name": "Rakoto Jean",
      "note": null,
      "photo": null,
      "timestamp": "2026-09-10T15:08:15.854046+03:00"
    },
    {
      "id": 37,
      "ancien_statut": "NOUVELLE",
      "nouveau_statut": "EN_PREPARATION",
      "changed_by": 12,
      "changed_by_name": "Haja",
      "note": "",
      "photo": null,
      "timestamp": "2026-09-10T15:08:00+03:00"
    },
    {
      "id": 39,
      "ancien_statut": "EN_PREPARATION",
      "nouveau_statut": "PRETE",
      "changed_by": 12,
      "changed_by_name": "Haja",
      "note": "",
      "photo": "http://localhost/media/order_status_photos/17d9bc22-0d36-4fdb-9a8a-8dd366a63e31.jpeg",
      "timestamp": "2026-09-10T23:06:44.001355+03:00"
    },
    {
      "id": 41,
      "ancien_statut": "PRETE",
      "nouveau_statut": "EN_LIVRAISON",
      "changed_by": 16,
      "changed_by_name": "Tahina",
      "note": "",
      "photo": null,
      "timestamp": "2026-09-11T08:07:00+03:00"
    },
    {
      "id": 45,
      "ancien_statut": "EN_LIVRAISON",
      "nouveau_statut": "LIVRE",
      "changed_by": 16,
      "changed_by_name": "Tahina",
      "note": "",
      "photo": null,
      "timestamp": "2026-09-11T15:05:07.672683+03:00"
    }
  ],
  "created_at": "2026-09-10T15:08:15.841950+03:00",
  "updated_at": "2026-09-11T15:05:07.669248+03:00"
}
```

Erreurs :
- `404` — `{"detail": "No Order matches the given query."}` : id inconnu, commande d'un autre magasin, ou commande hors de la liste visible du rôle.

---

### `PATCH /api/orders/{id}/` — Modifier une commande
**Rôle** : `GERANT` uniquement (`get_permissions` → `IsGerant`) · **Vue** : `OrderViewSet.partial_update` (views.py) → `services.update_order`, serializer `OrderUpdateSerializer` (tous les champs facultatifs)

Effet : deux régimes selon `statut_courant`.
- **Régime complet** (`NOUVELLE` ou `EN_PREPARATION`) : tous les champs sont modifiables, y compris `items`. Si `items` est fourni, les anciens articles sont supprimés et recréés ; si la commande est déjà `EN_PREPARATION` (stock déjà déduit), l'ancien stock est restitué (`ENTREE`, origine `AJUSTEMENT`, note « Modification de commande — article retiré ») puis le nouveau déduit (`SORTIE`, `AJUSTEMENT`, « Modification de commande — article ajouté »). `frais_livraison` et `total_a_payer` sont recalculés.
- **Régime restreint** (`PRETE` ou `EN_LIVRAISON`) : seuls `mode_paiement`, `livraison_zone`, `adresse_livraison`, `date_commande` et `note_livreur` sont acceptés ; changer la zone recalcule les frais et le total (donc le bilan du livreur).
- Commande terminée (`LIVRE`, `RETOUR`, `ANNULEE`) : aucune modification.
Le statut et les affectations ne se modifient **jamais** ici (voir `/status/`, `/assign-*`). Pas de notification.

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| `id` | chemin | int | oui | Commande à modifier |
| `client_nom` | corps | string ≤ 255 | non | Régime complet seulement |
| `telephone` | corps | `+261XXXXXXXXX` | non | Régime complet seulement |
| `telephone_2` | corps | `+261XXXXXXXXX` ou `""` | non | Régime complet seulement |
| `livraison_zone` | corps | code de zone active ou `RECUPERATION` | non | Les deux régimes |
| `adresse_livraison` | corps | string ≤ 255 | non | Les deux régimes |
| `mode_paiement` | corps | `AVANT` \| `LIVRAISON` | non | Les deux régimes |
| `date_commande` | corps | datetime ISO | non | Les deux régimes |
| `note_preparateur` | corps | string | non | Régime complet seulement |
| `note_livreur` | corps | string | non | Les deux régimes |
| `items` | corps | liste non vide de `{product_variant, quantite, prix_unitaire}` | non | Régime complet seulement ; remplace **tous** les articles |

Requête (régime complet) :
```json
{
  "adresse_livraison": "Lot II B 12 bis, Ankorondrano",
  "items": [
    { "product_variant": 727, "quantite": 2, "prix_unitaire": "28000.00" }
  ]
}
```

Requête (régime restreint, commande `EN_LIVRAISON`) :
```json
{
  "mode_paiement": "AVANT",
  "date_commande": "2026-09-12T16:30:00+03:00"
}
```

Réponse `200` : la commande complète au format `OrderGerantSerializer` (même structure que `GET /api/orders/{id}/`).

Erreurs :
- `403` — `{"detail": "You do not have permission to perform this action."}` : non-gérant.
- `400` — `["Cette commande est 'Livré' — elle ne peut plus être modifiée."]` : statut terminal (le libellé varie : `'Retour'`, `'Annulée'`).
- `400` — `["Cette commande est 'Prête' — seuls le paiement, la zone, l'adresse, la date de livraison et la note du livreur peuvent encore être modifiés."]` : champ interdit en régime restreint (libellé `'En livraison'` selon le cas).
- `400` — `["Aucune modification demandée."]` : régime restreint sans aucun champ autorisé.
- `400` — `{"items": ["Au moins un article est requis."]}` : `items` fourni mais vide.
- `400` — `{"telephone": ["Format attendu : +261XXXXXXXXX"]}`, `{"livraison_zone": ["Zone de livraison invalide."]}`, `{"items": [{"prix_unitaire": ["Le prix remisé ne peut pas dépasser le prix catalogue (30000 Ar)."]}]}` : mêmes validations qu'à la création.
- `404` — `{"detail": "No Order matches the given query."}`.

---

### `DELETE /api/orders/{id}/` — Supprimer une commande
**Rôle** : `GERANT` uniquement · **Vue** : `OrderViewSet.destroy` (views.py)

Effet : suppression physique de la commande, de ses articles et de son historique — uniquement tant qu'elle est `NOUVELLE` (aucun stock engagé). Pas de mouvement de stock, pas de notification.

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| `id` | chemin | int | oui | Commande à supprimer |

Réponse `204` : corps vide.

Erreurs :
- `403` — `{"detail": "You do not have permission to perform this action."}` : non-gérant.
- `400` — `["Seule une commande 'Nouvelle' peut être supprimée — le stock ou une affectation est déjà engagé sur celle-ci."]` : statut ≠ `NOUVELLE` (utiliser `/cancel/`).
- `404` — `{"detail": "No Order matches the given query."}`.

---

### `POST /api/orders/{id}/status/` — Changer le statut (workflow)
**Rôle** : dépend de la transition (voir tableau) ; le gérant peut forcer toute transition valide · **Vue** : `OrderViewSet.change_status` (views.py) → `services.change_order_status`, serializer `OrderStatusChangeSerializer`

Effet : fait avancer la commande d'une étape, enregistre une ligne d'historique (avec `note`, `photo`, et `timestamp = assigned_at` si fourni), applique le stock et les notifications :
- `EN_PREPARATION` : assigne le préparateur, **déduit le stock** de chaque article (`SORTIE`, origine `PREPARATION`).
- `PRETE` : notifie tous les **livreurs** du magasin (« Commande CMD-… prête — Client (ZONE1) ») + WebSocket ; pour un retrait sur place, une seule notification magasin (« Commande CMD-… prête à récupérer sur place — Client »).
- `EN_LIVRAISON` : assigne le livreur (ou réutilise le livreur pré-assigné).
- `LIVRE` : clôture ; avec `items_livres`, les articles non listés sont marqués `retourne = true`, **remis en stock** (`ENTREE`, origine `RETOUR`, note « Article rapporté — livraison partielle »), retirés du total et listés dans la note d'historique (« Articles rapportés : Pixel 9pro (Noir) x1 »). Une liste `items_livres` **vide** transforme la demande en `RETOUR`.
- `RETOUR` : **remet en stock** tous les articles (`ENTREE`, origine `RETOUR`).
- Cas spécial retrait sur place : `PRETE → LIVRE` directement, par le gérant seulement, sans livreur ni mouvement de stock.

Transitions (`services.TRANSITIONS`) :

| Statut cible | Statut de départ requis | Rôle responsable (le gérant peut toujours) |
| --- | --- | --- |
| `EN_PREPARATION` | `NOUVELLE` | `PREPARATEUR` |
| `PRETE` | `EN_PREPARATION` | `PREPARATEUR` |
| `EN_LIVRAISON` | `PRETE` | `LIVREUR` |
| `LIVRE` | `EN_LIVRAISON` (ou `PRETE` si `RECUPERATION`, gérant) | `LIVREUR` (gérant pour le retrait) |
| `RETOUR` | `EN_LIVRAISON` | `LIVREUR` |

Règle du **jour J** (`services.ouverture_actions`, fuseau Indian/Antananarivo) : un préparateur ne peut agir qu'à partir de **19h00 la veille** du jour de `date_commande` (`AVANCE_PREPARATEUR = 5 h` avant minuit), un livreur qu'à partir de **minuit le jour même**. Le gérant n'est pas soumis à cette règle. Une fois la commande assignée, seul le préparateur/livreur désigné (ou le gérant) peut la faire progresser.

Affectation (`_resolve_assignee`) : le gérant doit fournir `preparateur_id` (pour `EN_PREPARATION`) ou `livreur_id` (pour `EN_LIVRAISON`), sauf si la personne a déjà été pré-assignée via `/assign-preparateur/` ou `/assign-livreur/`. Un préparateur/livreur s'auto-assigne (id facultatif, mais s'il est fourni il doit être le sien).

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| `id` | chemin | int | oui | Commande |
| `statut` | corps | `EN_PREPARATION` \| `PRETE` \| `EN_LIVRAISON` \| `LIVRE` \| `RETOUR` | oui | Statut cible (`NOUVELLE` et `ANNULEE` sont refusés ici) |
| `note` | corps | string | non | Note d'historique (défaut `""`) |
| `photo` | corps (multipart) | image | non | Photo justificative (ex. preuve de préparation au passage `PRETE`), stockée dans `order_status_photos/` |
| `preparateur_id` | corps | int \| null | selon le cas | Pour `EN_PREPARATION` par le gérant |
| `livreur_id` | corps | int \| null | selon le cas | Pour `EN_LIVRAISON` par le gérant |
| `assigned_at` | corps | datetime ISO \| null | non | Heure manuelle consignée dans l'historique (`timestamp`) à la place de maintenant |
| `items_livres` | corps | liste d'int (ids d'`OrderItem`) | non | Pour `LIVRE` : articles réellement remis. Absent = tout est remis ; `[]` = rien remis → `RETOUR` |

Requête JSON (gérant lance la préparation) :
```json
{
  "statut": "EN_PREPARATION",
  "preparateur_id": 13,
  "assigned_at": "2026-09-12T08:15:00+03:00",
  "note": "Prise en charge du matin"
}
```

Requête JSON (livreur, livraison partielle) :
```json
{
  "statut": "LIVRE",
  "note": "Client n'a pas voulu la housse",
  "items_livres": [18]
}
```

Requête multipart (préparateur passe en `PRETE` avec photo) — champs de formulaire : `statut=PRETE`, `note=Colis emballé`, `photo=<fichier image>`.

Réponse `200` : la commande au serializer du rôle appelant (gérant → `OrderGerantSerializer`, préparateur → `OrderPreparateurSerializer`, livreur → `OrderLivreurSerializer`), par exemple pour le livreur après la livraison partielle ci-dessus : voir l'exemple `historique=1` de `GET /api/orders/` (`total_a_payer` recalculé à `"33000.00"`, article 19 `retourne: true`, note « Client n'a pas voulu la housse — Articles rapportés : Pixel 9pro (Noir) x1 »).

Erreurs :
- `400` — `{"statut": ["This field is required."]}` ; `{"statut": ["\"FOO\" is not a valid choice."]}` ; `{"items_livres": {"0": ["A valid integer is required."]}}` ; `{"assigned_at": ["Datetime has wrong format. Use one of these formats instead: YYYY-MM-DDThh:mm[:ss[.uuuuuu]][+HH:MM|-HH:MM|Z]."]}` ; `{"photo": ["Upload a valid image. The file you uploaded was either not an image or a corrupted image."]}`.
- `400` — `["Statut cible invalide : ANNULEE"]` : `statut` = `NOUVELLE` ou `ANNULEE` (passer par `/cancel/`).
- `400` — `["Transition impossible : la commande est 'NOUVELLE', 'PRETE' nécessite 'EN_PREPARATION'."]` : étape sautée ou commande terminée.
- `403` — `{"detail": "Seul le rôle PREPARATEUR (ou le gérant) peut passer une commande à 'EN_PREPARATION'."}` (ou `LIVREUR` / `'EN_LIVRAISON'`, `'LIVRE'`, `'RETOUR'`) : mauvais rôle (y compris employer sans rôle).
- `403` — `{"detail": "Seul le gérant peut valider une récupération sur place."}` : `PRETE → LIVRE` sur une `RECUPERATION` par un non-gérant.
- `403` — `{"detail": "Cette commande est planifiée pour le 12/09/2026 — l'action sera possible à partir du 11/09/2026 à 19h00."}` : règle du jour J (préparateur) ; pour un livreur l'heure d'ouverture est `12/09/2026 à 00h00`.
- `403` — `{"detail": "Cette commande est assignée à un autre préparateur."}` / `{"detail": "Cette commande est assignée à un autre livreur."}`.
- `400` — `["Choisissez un preparateur pour cette commande."]` / `["Choisissez un livreur pour cette commande."]` : gérant sans id ni pré-assignation.
- `400` — `["Utilisateur introuvable pour ce rôle."]` : id qui n'est pas un employer avec le `commande_role` attendu.
- `400` — `["Cette personne n'appartient pas à ce magasin."]`.
- `403` — `{"detail": "Vous ne pouvez vous assigner que vous-même cette commande."}` : préparateur/livreur fournissant l'id de quelqu'un d'autre.
- `404` — `{"detail": "No Order matches the given query."}` : commande invisible pour ce rôle (non assignée à lui).

---

### `POST /api/orders/{id}/cancel/` — Annuler une commande
**Rôle** : `GERANT` (contrôlé dans `services.cancel_order`) · **Vue** : `OrderViewSet.cancel` (views.py)

Effet : passe la commande en `ANNULEE` depuis n'importe quel statut non terminal, écrit l'historique et **restitue intégralement le stock** si celui-ci avait été déduit (statut `EN_PREPARATION`, `PRETE` ou `EN_LIVRAISON` ; mouvement `ENTREE`, origine `ANNULATION`). Pas de notification.

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| `id` | chemin | int | oui | Commande |
| `note` | corps | string | non | Motif consigné dans l'historique (défaut `""`) |

Requête :
```json
{ "note": "Client injoignable" }
```

Réponse `200` : la commande (`OrderGerantSerializer`) avec `"statut_courant": "ANNULEE"` et une ligne d'historique supplémentaire `{"ancien_statut": "PRETE", "nouveau_statut": "ANNULEE", "note": "Client injoignable"}`.

Erreurs :
- `403` — `{"detail": "Seul le gérant peut annuler une commande."}`.
- `400` — `["Cette commande est déjà 'Livré' — impossible de l'annuler."]` : statut `LIVRE`, `RETOUR` ou `ANNULEE` (libellé selon le statut).
- `404` — `{"detail": "No Order matches the given query."}`.

---

### `POST /api/orders/{id}/assign-preparateur/` — Pré-assigner un préparateur
**Rôle** : `GERANT` (contrôlé dans `services.assign_preparateur_early`) · **Vue** : `OrderViewSet.assign_preparateur` (views.py)

Effet : renseigne `order.preparateur` **sans changer le statut** (la commande reste `NOUVELLE` jusqu'à ce que ce préparateur lance lui-même la préparation) ; elle devient visible dans la liste de ce préparateur. Autorisé en `NOUVELLE` et `EN_PREPARATION` (réaffectation). Pas de stock, pas de notification.

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| `id` | chemin | int | oui | Commande |
| `preparateur_id` | corps | int | oui | Id d'un utilisateur `commande_role = PREPARATEUR` du même magasin |

Requête :
```json
{ "preparateur_id": 13 }
```

Réponse `200` : la commande (`OrderGerantSerializer`) avec `"preparateur": 13, "preparateur_name": "Faniry"`.

Erreurs :
- `400` — `["preparateur_id requis."]`.
- `403` — `{"detail": "Seul le gérant peut assigner un préparateur à l'avance."}`.
- `400` — `["Préparateur introuvable."]`.
- `400` — `["Cette personne n'appartient pas à ce magasin."]`.
- `400` — `["Cette commande a déjà dépassé l'étape de préparation."]` : statut ∉ {`NOUVELLE`, `EN_PREPARATION`}.

---

### `POST /api/orders/{id}/assign-livreur/` — Pré-assigner un livreur
**Rôle** : `GERANT` (contrôlé dans `services.assign_livreur_early`) · **Vue** : `OrderViewSet.assign_livreur` (views.py)

Effet : renseigne `order.livreur` sans changer le statut, à n'importe quelle étape non close (`NOUVELLE` … `EN_LIVRAISON`, et même `RETOUR`) ; la commande apparaît dans le planning du livreur. Au passage `EN_LIVRAISON`, `_resolve_assignee` réutilise ce livreur sans le redemander. Pas de stock, pas de notification.

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| `id` | chemin | int | oui | Commande |
| `livreur_id` | corps | int | oui | Id d'un utilisateur `commande_role = LIVREUR` du même magasin |

Requête :
```json
{ "livreur_id": 17 }
```

Réponse `200` : la commande (`OrderGerantSerializer`) avec `"livreur": 17, "livreur_name": "Mamy"`.

Erreurs :
- `400` — `["livreur_id requis."]`.
- `403` — `{"detail": "Seul le gérant peut assigner un livreur à l'avance."}`.
- `400` — `["Livreur introuvable."]`.
- `400` — `["Cette personne n'appartient pas à ce magasin."]`.
- `400` — `["Cette commande est déjà terminée."]` : statut `LIVRE` ou `ANNULEE`.

---

### `POST /api/orders/{id}/corriger-statut/` — Corriger un statut final (LIVRE ↔ RETOUR)
**Rôle** : `GERANT` uniquement (`get_permissions` → `IsGerant`, puis re-vérifié dans `services.corriger_statut`) · **Vue** : `OrderViewSet.corriger_statut` (views.py)

Effet : répare une erreur de saisie sur une commande close : `LIVRE → RETOUR` (le colis est bien revenu : `ENTREE` en stock) ou `RETOUR → LIVRE` (le colis n'est jamais revenu : `SORTIE` du stock). Mouvements à l'origine `AJUSTEMENT`, note « Correction d'état : LIVRE -> RETOUR ». Une ligne d'historique est créée avec la note fournie ou, à défaut, « Correction d'état par le gérant ». Pas de notification.

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| `id` | chemin | int | oui | Commande `LIVRE` ou `RETOUR` |
| `statut` | corps | `LIVRE` \| `RETOUR` | oui | Nouveau statut (l'inverse du statut actuel) |
| `note` | corps | string | non | Justification |

Requête :
```json
{ "statut": "LIVRE", "note": "Retour touché par erreur, livraison bien effectuée" }
```

Réponse `200` : la commande (`OrderGerantSerializer`) avec le statut corrigé et la ligne d'historique `{"ancien_statut": "RETOUR", "nouveau_statut": "LIVRE", "note": "Retour touché par erreur, livraison bien effectuée"}`.

Erreurs :
- `403` — `{"detail": "You do not have permission to perform this action."}` : non-gérant.
- `400` — `["Le nouveau statut est requis."]`.
- `400` — `["Correction impossible : 'Nouvelle' ne peut pas devenir 'Livré'."]` : commande non close, ou cible identique/inconnue (libellés français des statuts ; un code inconnu est affiché tel quel).

---

### `POST /api/orders/{id}/share-chat/` — Partager la commande dans la messagerie
**Rôle** : `GERANT` ou `PREPARATEUR` · **Vue** : `OrderViewSet.share_chat` (views.py)

Effet : crée un `ChatMessage` côté serveur contenant le résumé de la commande (numéro, client, téléphone(s), adresse, articles, « À encaisser : 33000 Ar » ou « À encaisser : déjà payé » si `mode_paiement = AVANT` — jamais de coût/marge), y joint une **copie** de la photo de préparation la plus récente de l'historique si elle existe, et le diffuse en WebSocket sur le groupe `chat_<room_name>` (best-effort). Cible `livreur` : message privé au livreur assigné (`room_name = dm_<idMin>_<idMax>`) ; cible `general` : salon de la société (`room_name = general_<company_id>`).

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| `id` | chemin | int | oui | Commande |
| `cible` | corps | `livreur` \| `general` | non | Défaut `livreur` (insensible à la casse) |

Requête :
```json
{ "cible": "livreur" }
```

Réponse `201` (`ChatMessageSerializer`) :
```json
{
  "id": 412,
  "sender": 11,
  "sender_name": "Rakoto Jean",
  "sender_email": "gerant@exemple.mg",
  "sender_role": "admin",
  "recipient": 17,
  "recipient_name": "Mamy",
  "recipient_email": "mamy@exemple.mg",
  "room_name": "dm_11_17",
  "content": "📦 Commande CMD-2-20260912-0002\nClient : Rasoa Hanta\nTéléphone : +261340000001\nAdresse : Lot II B 12, Ankorondrano\nArticles : pixel 10 pro xl (Standard) x1\nÀ encaisser : 33000 Ar",
  "image": "http://localhost/media/chat/17d9bc22-0d36-4fdb-9a8a-8dd366a63e31.jpeg",
  "is_edited": false,
  "edited_at": null,
  "is_deleted": false,
  "timestamp": "2026-09-13T09:30:12.400000+03:00",
  "read_at": null
}
```
(`recipient`, `recipient_name`, `recipient_email` valent `null` pour la cible `general` ; `image` vaut `null` sans photo de préparation.)

Erreurs :
- `403` — `{"detail": "Seuls le gérant et le préparateur peuvent partager une commande."}`.
- `400` — `["Aucun livreur n'est assigné à cette commande."]` : cible `livreur` sans livreur.
- `403` — `{"detail": "Vous ne pouvez pas écrire à ce livreur."}` : messagerie bloquée entre l'appelant et le livreur (`chat_blocked_between` : deux livreurs).
- `400` — `["Société introuvable."]` : cible `general` sans société résolue.
- `400` — `["Cible inconnue : attendu 'livreur' ou 'general'."]`.

---

### `POST /api/orders/{id}/campagne/` — (obsolète) Rattacher une campagne marketing
**Rôle** : `GERANT` · **Vue** : `OrderViewSet.set_campagne` (views.py)

**Obsolète** : l'affectation commande ↔ campagne est désormais **automatique par période** (voir *Campagnes marketing*). L'action ne modifie plus rien ; elle renvoie simplement la commande (`200`, `OrderGerantSerializer`) avec ses campagnes calculées (`campagnes`, `campagne_nom`). Conservée pour les anciens clients.

---

### `GET /api/orders/available-staff/` — Disponibilité des préparateurs / livreurs
**Rôle** : `GERANT` (`get_permissions` → `IsGerant`) · **Vue** : `OrderViewSet.available_staff` (views.py)

Effet : lecture seule. Liste les employers du rôle demandé dans les magasins accessibles, avec un indicateur `available` purement indicatif : `false` si la personne a déjà une commande `EN_PREPARATION` (préparateur) / `EN_LIVRAISON` (livreur), ou, pour un livreur avec `date_commande`, si une autre commande non close lui est déjà (pré-)assignée le même jour à la même heure.

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| `role` | query | `PREPARATEUR` \| `LIVREUR` | oui | Rôle recherché |
| `magasin_id` | query | int | non | Restreint à un magasin accessible |
| `date_commande` | query | datetime ISO | non | `LIVREUR` seulement : détection de conflit d'horaire |

Réponse `200` :
```json
[
  { "id": 15, "full_name": "Rivo", "magasin_id": 2, "available": true },
  { "id": 16, "full_name": "Tahina", "magasin_id": 2, "available": false }
]
```

Erreurs :
- `403` — `{"detail": "You do not have permission to perform this action."}` : non-gérant.
- `400` — `["Paramètre 'role' requis : PREPARATEUR ou LIVREUR."]`.

---

### Zones de livraison (`delivery-zones/`)

Ressource partagée par toute la société (`AdminProfile.delivery_zones`). `code` est généré une seule fois à la création à partir du nom (`slugify(nom).upper()` sans tirets, 16 caractères max, suffixe numérique en cas de doublon) et **ne change plus** : c'est lui qui est stocké dans `Order.livraison_zone`. Le retrait sur place n'est pas une zone : c'est le littéral `RECUPERATION`. Si la société n'a encore aucune zone, la première lecture crée automatiquement 4 zones par défaut (« Zone gratuite » 0, « Zone 1 » 3000, « Zone 2 » 4000, « Zone 3 » 5000). Tri : `prix`, `nom`.

Objet `DeliveryZoneOptionSerializer` :
```json
{
  "id": 1,
  "code": "ZONE1",
  "nom": "Zone 1",
  "prix": "3000.00",
  "actif": true,
  "created_at": "2026-09-09T20:03:04.736454+03:00"
}
```

### `GET /api/orders/delivery-zones/` — Liste des zones
**Rôle** : tout utilisateur authentifié · **Vue** : `DeliveryZoneOptionViewSet.list` (views.py)

Effet : lecture (toutes les zones, actives ou non — le client filtre `actif` pour un select). Crée les zones par défaut si la société n'en a aucune.

Réponse `200` :
```json
[
  { "id": 1, "code": "ZONE1", "nom": "Zone 1", "prix": "3000.00", "actif": true, "created_at": "2026-09-09T20:03:04.736454+03:00" },
  { "id": 2, "code": "ZONE2", "nom": "Zone 2", "prix": "4000.00", "actif": true, "created_at": "2026-09-09T20:03:04.740283+03:00" }
]
```
Un utilisateur sans société résolue reçoit `[]`.

### `POST /api/orders/delivery-zones/` — Créer une zone
**Rôle** : `GERANT` · **Vue** : `DeliveryZoneOptionViewSet.create` (views.py)

Effet : crée la zone pour la société de l'appelant, avec un `code` généré.

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| `nom` | corps | string ≤ 100 | oui | Libellé |
| `prix` | corps | decimal ≥ 0 (10 chiffres, 2 décimales) | non | Frais de livraison, défaut `0` |
| `actif` | corps | bool | non | Défaut `true` |

Requête :
```json
{ "nom": "Zone périphérie", "prix": "7000.00" }
```

Réponse `201` :
```json
{ "id": 5, "code": "ZONEPERIPHERIE", "nom": "Zone périphérie", "prix": "7000.00", "actif": true, "created_at": "2026-09-13T09:40:00.120000+03:00" }
```

Erreurs :
- `403` — `{"detail": "You do not have permission to perform this action."}`.
- `400` — `{"nom": ["This field is required."]}` ; `{"prix": ["A valid number is required."]}`.
- `400` — `["Société introuvable."]` : aucun `AdminProfile` résolu.

### `GET /api/orders/delivery-zones/{id}/` — Détail d'une zone
**Rôle** : tout utilisateur authentifié · **Vue** : `DeliveryZoneOptionViewSet.retrieve`

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| `id` | chemin | int | oui | Zone |

Réponse `200` : l'objet zone. Erreur `404` — `{"detail": "No Delivery zone matches the given query."}` (hors société).

### `PATCH /api/orders/delivery-zones/{id}/` — Modifier une zone
**Rôle** : `GERANT` · **Vue** : `DeliveryZoneOptionViewSet.partial_update`

Effet : modifie `nom`, `prix`, `actif` ; `code` reste inchangé. Les commandes existantes gardent leurs frais (snapshot) — seules les nouvelles commandes utilisent le nouveau prix.

Requête :
```json
{ "prix": "3500.00", "actif": false }
```

Réponse `200` : l'objet zone mis à jour. Erreurs : `403` (non-gérant), `400` (validation), `404`.

### `DELETE /api/orders/delivery-zones/{id}/` — Supprimer (ou désactiver) une zone
**Rôle** : `GERANT` · **Vue** : `DeliveryZoneOptionViewSet.destroy`

Effet : si aucune commande de la société n'utilise ce `code`, suppression physique ; sinon **suppression douce** : `actif = false` et la zone reste résolue pour les commandes existantes.

Réponse `204` (corps vide) si supprimée ; réponse `200` avec la zone désactivée si elle est utilisée :
```json
{ "id": 1, "code": "ZONE1", "nom": "Zone 1", "prix": "3000.00", "actif": false, "created_at": "2026-09-09T20:03:04.736454+03:00" }
```

Erreurs : `403` (non-gérant), `404`.

---

### Types de dépense (`expense-types/`)

Catalogue de la société (`AdminProfile.expense_types`) proposé au livreur pour déclarer ses frais (repas, carburant, enveloppes…). `prix_unitaire` n'est qu'une valeur par défaut : le montant est figé sur chaque dépense. `nom` est unique par société (contrainte base). Tri : `nom`.

Objet `ExpenseTypeSerializer` :
```json
{
  "id": 4,
  "nom": "ENVELOPPE",
  "prix_unitaire": "500.00",
  "par_unite": true,
  "frais_livraison": false,
  "actif": true,
  "created_at": "2026-09-11T19:00:21.032017+03:00"
}
```

### `GET /api/orders/expense-types/` — Liste des types
**Rôle** : tout utilisateur authentifié · **Vue** : `ExpenseTypeViewSet.list` (views.py)

Réponse `200` :
```json
[
  { "id": 4, "nom": "ENVELOPPE", "prix_unitaire": "500.00", "par_unite": true, "frais_livraison": false, "actif": true, "created_at": "2026-09-11T19:00:21.032017+03:00" },
  { "id": 2, "nom": "REPAS", "prix_unitaire": "5000.00", "par_unite": false, "frais_livraison": false, "actif": true, "created_at": "2026-09-11T18:59:49.697558+03:00" }
]
```

### `POST /api/orders/expense-types/` — Créer un type
**Rôle** : `GERANT` · **Vue** : `ExpenseTypeViewSet.create`

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| `nom` | corps | string ≤ 100 | oui | Libellé, unique dans la société |
| `prix_unitaire` | corps | decimal | non | Tarif proposé par défaut (défaut `0`) |
| `par_unite` | corps | bool | non | `true` si la dépense se compte (quantité × prix), défaut `false` |
| `frais_livraison` | corps | bool | non | `true` pour un type « frais de livraison » (LIVRAISON 3K / 4K / 5K…) : seules les dépenses acceptées de ces types entrent dans le coût réel et la **marge livraison** des rapports Dépenses et Livraisons (repas, enveloppes, NAP exclus). Défaut `false` ; la migration `orders 0019` a coché les types dont le nom contient « livraison » |
| `actif` | corps | bool | non | Défaut `true` |

Requête :
```json
{ "nom": "CARBURANT", "prix_unitaire": "10000.00", "par_unite": false }
```

Réponse `201` :
```json
{ "id": 7, "nom": "CARBURANT", "prix_unitaire": "10000.00", "par_unite": false, "frais_livraison": false, "actif": true, "created_at": "2026-09-13T09:45:00.000000+03:00" }
```

Erreurs :
- `403` — `{"detail": "You do not have permission to perform this action."}`.
- `400` — `{"nom": ["This field is required."]}`.
- `400` — `["Aucune société associée à ce compte."]`.

### `GET /api/orders/expense-types/{id}/` — Détail d'un type
**Rôle** : tout utilisateur authentifié · **Vue** : `ExpenseTypeViewSet.retrieve`

Réponse `200` : l'objet type. Erreur `404` — `{"detail": "No Expense type matches the given query."}`.

### `PATCH /api/orders/expense-types/{id}/` — Modifier un type
**Rôle** : `GERANT` · **Vue** : `ExpenseTypeViewSet.partial_update`

Requête :
```json
{ "prix_unitaire": "600.00" }
```

Réponse `200` : l'objet mis à jour. Les dépenses déjà déclarées conservent leur ancien prix. Erreurs : `403`, `400`, `404`.

### `DELETE /api/orders/expense-types/{id}/` — Supprimer (ou désactiver) un type
**Rôle** : `GERANT` · **Vue** : `ExpenseTypeViewSet.destroy`

Effet : suppression physique si aucune dépense n'y fait référence ; sinon suppression douce (`actif = false`) pour ne pas perdre le lien des dépenses passées.

Réponse `204` (supprimé) ou `200` avec l'objet désactivé :
```json
{ "id": 4, "nom": "ENVELOPPE", "prix_unitaire": "500.00", "par_unite": true, "frais_livraison": false, "actif": false, "created_at": "2026-09-11T19:00:21.032017+03:00" }
```

Erreurs : `403`, `404`.

---

### Dépenses des livreurs (`expenses/`)

Une dépense (`LivreurExpense`) est déclarée par un livreur, puis tranchée par le gérant. Statuts : `EN_ATTENTE` (En attente), `ACCEPTE` (Acceptée), `REJETE` (Rejetée). Seules les dépenses `ACCEPTE` entrent dans les bilans (rapports, `depenses_livreur`), rattachées au jour `date` et au livreur. `montant = prix_unitaire × quantite` est calculé par le serveur. Tri : `-created_at`.

Objet `LivreurExpenseSerializer` :
```json
{
  "id": 2,
  "livreur": 15,
  "livreur_name": "Rivo",
  "type_depense": 4,
  "type_nom": "ENVELOPPE",
  "libelle": "ENVELOPPE",
  "prix_unitaire": "500.00",
  "quantite": 10,
  "montant": "5000.00",
  "motif": "",
  "date": "2026-09-11",
  "statut": "ACCEPTE",
  "motif_rejet": "",
  "resolved_by": 11,
  "resolved_by_name": "Rakoto Jean",
  "resolved_at": "2026-09-12T19:02:32.609022+03:00",
  "created_at": "2026-09-11T19:01:13.946852+03:00"
}
```
Champs en lecture seule : `id`, `livreur`, `livreur_name`, `type_nom`, `montant`, `statut`, `motif_rejet`, `resolved_by`, `resolved_by_name`, `resolved_at`, `created_at`.

### `GET /api/orders/expenses/` — Liste des dépenses
**Rôle** : tout utilisateur authentifié ; un **livreur ne voit que les siennes**, le gérant celles de tous ses magasins · **Vue** : `LivreurExpenseViewSet.list` (views.py)

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| `statut` | query | string | non | Un ou plusieurs codes séparés par des virgules (`EN_ATTENTE,ACCEPTE`) |
| `date_debut` | query | date `YYYY-MM-DD` | non | `date` ≥ |
| `date_fin` | query | date `YYYY-MM-DD` | non | `date` ≤ |
| `livreur_id` | query | int | non | Filtre par livreur (utile au gérant) |

Réponse `200` :
```json
[
  {
    "id": 2,
    "livreur": 15,
    "livreur_name": "Rivo",
    "type_depense": 4,
    "type_nom": "ENVELOPPE",
    "libelle": "ENVELOPPE",
    "prix_unitaire": "500.00",
    "quantite": 10,
    "montant": "5000.00",
    "motif": "",
    "date": "2026-09-11",
    "statut": "ACCEPTE",
    "motif_rejet": "",
    "resolved_by": 11,
    "resolved_by_name": "Rakoto Jean",
    "resolved_at": "2026-09-12T19:02:32.609022+03:00",
    "created_at": "2026-09-11T19:01:13.946852+03:00"
  }
]
```

### `POST /api/orders/expenses/` — Déclarer une dépense
**Rôle** : `LIVREUR` uniquement · **Vue** : `LivreurExpenseViewSet.create` → `perform_create` (views.py)

Effet : crée la dépense en `EN_ATTENTE` pour le livreur appelant et son magasin, calcule `montant`, puis crée une `Notification` magasin (type `order`) : « Dépense à valider : ENVELOPPE — 5000 Ar, déclarée par Rivo » (diffusée en WebSocket par le signal `post_save` des notifications).

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| `libelle` | corps | string ≤ 100 | oui | Libellé (recopié du type ou libre) |
| `type_depense` | corps | int \| null | non | Id d'un `ExpenseType` ; `null` pour une dépense libre |
| `prix_unitaire` | corps | decimal > 0 | oui (validation) | Le défaut modèle est 0, refusé par la validation |
| `quantite` | corps | int ≥ 1 | non | Défaut 1 |
| `motif` | corps | string | non | Justification libre |
| `date` | corps | date `YYYY-MM-DD` | non | Jour de rattachement, défaut aujourd'hui |
| `magasin_id` | corps | int | non | Résolu automatiquement (unique magasin du livreur) |

Requête :
```json
{
  "type_depense": 4,
  "libelle": "ENVELOPPE",
  "prix_unitaire": "500.00",
  "quantite": 10,
  "motif": "Enveloppes pour les reçus",
  "date": "2026-09-13"
}
```

Réponse `201` :
```json
{
  "id": 3,
  "livreur": 15,
  "livreur_name": "Rivo",
  "type_depense": 4,
  "type_nom": "ENVELOPPE",
  "libelle": "ENVELOPPE",
  "prix_unitaire": "500.00",
  "quantite": 10,
  "montant": "5000.00",
  "motif": "Enveloppes pour les reçus",
  "date": "2026-09-13",
  "statut": "EN_ATTENTE",
  "motif_rejet": "",
  "resolved_by": null,
  "resolved_by_name": null,
  "resolved_at": null,
  "created_at": "2026-09-13T10:02:00.000000+03:00"
}
```

Erreurs :
- `403` — `{"detail": "Seul un livreur peut déclarer une dépense."}` : gérant ou préparateur.
- `400` — `{"libelle": ["This field is required."]}`.
- `400` — `{"prix_unitaire": ["Le montant doit être supérieur à 0."]}` : prix absent, nul ou négatif.
- `400` — `{"quantite": ["Quantité minimale : 1."]}` (ou `{"quantite": ["Ensure this value is greater than or equal to 0."]}` pour une valeur négative).
- `400` — `{"type_depense": ["Invalid pk \"99\" - object does not exist."]}`.

### `GET /api/orders/expenses/{id}/` — Détail d'une dépense
**Rôle** : tout utilisateur authentifié (livreur : les siennes seulement) · **Vue** : `LivreurExpenseViewSet.retrieve`

Réponse `200` : l'objet dépense. Erreur `404` — `{"detail": "No Livreur expense matches the given query."}`.

### `PATCH /api/orders/expenses/{id}/` — Modifier une dépense en attente
**Rôle** : l'**auteur** (livreur) uniquement, tant que `statut = EN_ATTENTE` · **Vue** : `LivreurExpenseViewSet.partial_update`

Effet : met à jour `libelle`, `type_depense`, `prix_unitaire`, `quantite`, `motif`, `date` ; `montant` est recalculé.

Requête :
```json
{ "quantite": 12, "motif": "Deux enveloppes de plus" }
```

Réponse `200` : l'objet mis à jour (`"montant": "6000.00"`).

Erreurs :
- `400` — `["Cette dépense a déjà été traitée."]` : statut ≠ `EN_ATTENTE`.
- `403` — `{"detail": "Vous ne pouvez modifier que vos propres dépenses."}` : appelant ≠ auteur (y compris le gérant).
- `400` — `{"prix_unitaire": ["Le montant doit être supérieur à 0."]}`, `{"quantite": ["Quantité minimale : 1."]}`.
- `404`.

### `DELETE /api/orders/expenses/{id}/` — Supprimer une dépense en attente
**Rôle** : l'auteur (livreur) ou le `GERANT`, tant que `statut = EN_ATTENTE` · **Vue** : `LivreurExpenseViewSet.destroy`

Réponse `204` : corps vide.

Erreurs :
- `400` — `["Cette dépense a déjà été traitée."]`.
- `403` — `{"detail": "Vous ne pouvez supprimer que vos propres dépenses."}` : autre livreur/préparateur.
- `404`.

### `POST /api/orders/expenses/{id}/resoudre/` — Accepter ou rejeter une dépense
**Rôle** : `GERANT` (`permission_classes=[IsGerant]`) · **Vue** : `LivreurExpenseViewSet.resoudre` (views.py)

Effet : passe la dépense en `ACCEPTE` ou `REJETE`, renseigne `resolved_by`/`resolved_at`/`motif_rejet`, puis crée une `Notification` personnelle pour le livreur (type `order`) : « Dépense acceptée : ENVELOPPE — 5000 Ar » ou « Dépense rejetée : … ». Une dépense acceptée est déduite du bilan du jour de ce livreur.

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| `id` | chemin | int | oui | Dépense `EN_ATTENTE` |
| `statut` | corps | `ACCEPTE` \| `REJETE` | oui | Décision |
| `motif_rejet` | corps | string | non | Motif (espaces retirés), utile pour un rejet |

Requête :
```json
{ "statut": "REJETE", "motif_rejet": "Ticket manquant" }
```

Réponse `200` :
```json
{
  "id": 3,
  "livreur": 15,
  "livreur_name": "Rivo",
  "type_depense": 4,
  "type_nom": "ENVELOPPE",
  "libelle": "ENVELOPPE",
  "prix_unitaire": "500.00",
  "quantite": 10,
  "montant": "5000.00",
  "motif": "Enveloppes pour les reçus",
  "date": "2026-09-13",
  "statut": "REJETE",
  "motif_rejet": "Ticket manquant",
  "resolved_by": 11,
  "resolved_by_name": "Rakoto Jean",
  "resolved_at": "2026-09-13T10:10:00.000000+03:00",
  "created_at": "2026-09-13T10:02:00.000000+03:00"
}
```

Erreurs :
- `403` — `{"detail": "You do not have permission to perform this action."}` : non-gérant.
- `400` — `["Cette dépense a déjà été traitée."]`.
- `400` — `["Statut attendu : 'ACCEPTE' ou 'REJETE'."]`.
- `404`.

---

### Campagnes marketing (`campaigns/`)

`MarketingCampaign` : coût d'une campagne publicitaire (boost) par magasin. Plateformes : `FACEBOOK` (Facebook), `INSTAGRAM` (Instagram), `TIKTOK` (TikTok), `GOOGLE` (Google), `AUTRE` (Autre). Tri : `-date_debut`, `-created_at`.

**Affectation automatique par période** (`finance/services.py::commandes_du_boost`, source unique pour le rapport Marketing, la caisse et les commandes) :
- une commande est *concernée* par un boost si sa date de livraison prévue (`date_commande`, jour local Antananarivo) vérifie `date_debut ≤ jour ≤ date_fin`, **bornes comprises** ; `date_fin` vide = boost **en cours** → jusqu'à aujourd'hui (jamais l'avenir) ;
- les commandes annulées ne sont pas concernées ; un boost `actif = false` ne concerne plus rien ;
- aucune sélection manuelle : `Order.campagne` (FK historique) n'est plus renseigné ni utilisé ;
- **chevauchement** : deux boosts peuvent couvrir le même jour ; chacun est réparti sur *sa* période et une commande de la zone commune est concernée par les deux (une part de coût de chacun dans le gain réel ; les totaux du rapport la comptent une seule fois) ;
- **recalcul automatique** : toute création / modification (montant, dates, `actif`) / suppression recalcule le gain réel des ventes de l'union ancienne + nouvelle période (`finance/services.py::recalculer_apres_boost`).

Objet `MarketingCampaignSerializer` (les champs calculés le sont à la lecture, jamais stockés) :
```json
{
  "id": 3,
  "magasin": 2,
  "nom": "Boost Facebook rentrée",
  "plateforme": "FACEBOOK",
  "plateforme_label": "Facebook",
  "montant": "150000.00",
  "type_periode": "PERSONNALISE",
  "date_debut": "2026-09-01",
  "date_fin": "2026-09-30",
  "note": "Ciblage Antananarivo",
  "actif": true,
  "created_at": "2026-09-01T08:00:00.000000+03:00",
  "articles_vendus": 20,
  "cout_par_article": "7500.00",
  "en_caisse": false,
  "nb_commandes": 24,
  "nb_livrees": 18,
  "ca": "612000.00",
  "cout_par_commande": "6250.00",
  "periode_effective": { "from": "2026-09-01", "to": "2026-09-30", "en_cours": false }
}
```
- `nb_commandes` / `nb_livrees` : commandes concernées (non annulées) / livrées ; `ca` : total à payer des livrées ; `cout_par_commande = montant / nb_commandes` (`null` sans commande) — indicateur d'affichage ;
- `articles_vendus` / `cout_par_article` : répartition **financière** retenue dans le gain réel (caisse) : `montant / articles livrés sur la période` ;
- `periode_effective.to` : dernier jour couvert (aujourd'hui si `en_cours`).

### `GET /api/orders/campaigns/` — Liste des campagnes
**Rôle** : tout utilisateur authentifié (magasins accessibles) · **Vue** : `MarketingCampaignViewSet.list` (views.py)

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| `magasin_id` | query | int | non | Restreint à un magasin |
| `actif` | query | `1` | non | Uniquement les campagnes actives |

Réponse `200` :
```json
[
  {
    "id": 3,
    "magasin": 2,
    "nom": "Boost Facebook rentrée",
    "plateforme": "FACEBOOK",
    "plateforme_label": "Facebook",
    "montant": "150000.00",
    "date_debut": "2026-09-01",
    "date_fin": "2026-09-30",
    "note": "Ciblage Antananarivo",
    "actif": true,
    "created_at": "2026-09-01T08:00:00.000000+03:00"
  }
]
```

### `POST /api/orders/campaigns/` — Créer une campagne
**Rôle** : `GERANT` · **Vue** : `MarketingCampaignViewSet.create` → `perform_create` (magasin résolu par `resolve_magasin_for_request`, `created_by` = appelant)

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| `nom` | corps | string ≤ 150 | oui | Nom |
| `plateforme` | corps | `FACEBOOK` \| `INSTAGRAM` \| `TIKTOK` \| `GOOGLE` \| `AUTRE` | non | Défaut `FACEBOOK` |
| `montant` | corps | decimal | non | Coût de la campagne (défaut `0`) |
| `date_debut` | corps | date | non | Défaut aujourd'hui |
| `date_fin` | corps | date \| null | non | Doit être ≥ `date_debut` |
| `note` | corps | string | non | |
| `actif` | corps | bool | non | Défaut `true` |
| `magasin_id` | corps | int | selon le cas | Obligatoire si plusieurs magasins accessibles |

Requête :
```json
{
  "nom": "Boost Facebook rentrée",
  "plateforme": "FACEBOOK",
  "montant": "150000.00",
  "date_debut": "2026-09-01",
  "date_fin": "2026-09-30",
  "note": "Ciblage Antananarivo",
  "magasin_id": 2
}
```

Réponse `201` : l'objet campagne (voir ci-dessus).

Erreurs :
- `403` — `{"detail": "You do not have permission to perform this action."}`.
- `400` — `{"nom": ["This field is required."]}` ; `{"plateforme": ["\"FB\" is not a valid choice."]}`.
- `400` — `{"date_fin": ["La date de fin précède la date de début."]}`.
- `400` — `{"magasin_id": ["Ce champ est requis (plusieurs magasins accessibles)."]}` ; `403` — `{"detail": "Magasin non autorisé."}`.

### `GET /api/orders/campaigns/{id}/` — Détail d'une campagne
**Rôle** : tout utilisateur authentifié · **Vue** : `MarketingCampaignViewSet.retrieve`

Réponse `200` : l'objet campagne. Erreur `404` — `{"detail": "No Marketing campaign matches the given query."}`.

### `PATCH /api/orders/campaigns/{id}/` — Modifier une campagne
**Rôle** : `GERANT` · **Vue** : `MarketingCampaignViewSet.partial_update`

Requête :
```json
{ "montant": "180000.00", "actif": false }
```

Réponse `200` : l'objet mis à jour. Erreurs : `403`, `400` — `{"date_fin": ["La date de fin précède la date de début."]}`, `404`.

### `DELETE /api/orders/campaigns/{id}/` — Supprimer une campagne
**Rôle** : `GERANT` · **Vue** : `MarketingCampaignViewSet.destroy`

Effet : suppression physique ; la part de boost des ventes de la période est recalculée automatiquement (aucune commande supprimée).

Réponse `204` : corps vide. Erreurs : `403`, `404`.

---

### Tableau de bord

### `GET /api/orders/dashboard/` — Dashboard du gérant
**Rôle** : tout utilisateur authentifié (portée = magasins accessibles ; la vue est pensée pour le gérant) · **Vue** : `DashboardView` (dashboard.py)

Effet : lecture seule. KPIs de la période (défaut : du 1er du mois en cours à aujourd'hui, en `date_commande`), suivi des statuts, analyse financière (CA produits, frais encaissés, commandes fournisseur de la période, bénéfice estimé = CA + frais − fournisseurs), top produits sur les commandes `LIVRE`, résumé stock. Le bloc `resume` est un instantané indépendant de la période (valeur du stock au prix de vente, bénéfice potentiel du stock, `ca` = valeur de stock + total des entrées de caisse).

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| `date_from` | query | date `YYYY-MM-DD` | non | Début de période (format invalide = ignoré) |
| `date_to` | query | date `YYYY-MM-DD` | non | Fin de période |
| `magasin_id` | query | int | non | Restreint à un magasin accessible |

Réponse `200` :
```json
{
  "resume": {
    "ca": 43315000.0,
    "total_benefices_produits_vendus": 20000.0,
    "valeur_stock": 43315000.0,
    "benefice_estime_stock": 7035000.0
  },
  "periode": { "date_debut": "2026-09-01", "date_fin": "2026-09-13" },
  "kpis": {
    "nb_ventes": 8,
    "ca_periode": 339000.0,
    "ca_mois_en_cours": 339000.0,
    "taux_livraison_reussie_pct": 66.7,
    "nb_retours": 2
  },
  "suivi_commandes_temps_reel": {
    "NOUVELLE": 2,
    "EN_PREPARATION": 0,
    "PRETE": 0,
    "EN_LIVRAISON": 0,
    "LIVRE": 8,
    "RETOUR": 2,
    "ANNULEE": 0
  },
  "analyse_financiere": {
    "ca_produits_vendus": 315000.0,
    "frais_livraison_encaisses": 24000.0,
    "total_investi_fournisseurs": 0,
    "benefice_estime": 339000.0
  },
  "top_produits": {
    "par_sous_type": [
      { "label": "PRIVACY", "quantite_vendue": 6 },
      { "label": "FLIP COVER", "quantite_vendue": 4 }
    ],
    "marques": [
      { "label": "Google Pixel", "quantite_vendue": 5 },
      { "label": "iPhone", "quantite_vendue": 4 }
    ],
    "references": [
      { "label": "iphone 11", "quantite_vendue": 2 },
      { "label": "Pixel 7 Pro", "quantite_vendue": 1 }
    ],
    "couleurs": [
      { "label": "Standard", "quantite_vendue": 6 },
      { "label": "Noir", "quantite_vendue": 2 }
    ]
  },
  "stock_rapide": {
    "total_en_stock": 1321,
    "ruptures": 82,
    "stock_bas": 222
  }
}
```
(`top_produits.*` : 20 entrées max par liste ; `periode.date_debut`/`date_fin` valent `null` si un seul des deux paramètres est fourni.)

---

### Rapports du gérant (agrégé)

### `GET /api/orders/reports/` — Bilan complet de la période
**Rôle** : `GERANT` uniquement (`IsGerant` — la réponse contient les coûts d'achat) · **Vue** : `ReportsView` (reports.py)

Effet : lecture seule. Période par défaut : les 30 derniers jours (bornes comprises), en `date_commande`. Ventes = commandes `LIVRE`, articles non rapportés ; coût = `prix_achat` catalogue actuel ; dépenses = sorties de caisse hors achats de stock + dépenses livreur `ACCEPTE`. Contient une ligne par jour (jours vides inclus), les classements produits (10 max), la performance par livreur et par préparateur, et les mouvements de stock par jour.

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| `date_from` | query | date `YYYY-MM-DD` | non | Défaut `date_to − 29 jours` |
| `date_to` | query | date `YYYY-MM-DD` | non | Défaut aujourd'hui |
| `magasin_id` | query | int | non | Restreint à un magasin |

Réponse `200` :
```json
{
  "periode": { "from": "2026-09-08", "to": "2026-09-13" },
  "totaux": {
    "chiffre_affaires": 299000.0,
    "ca_produits": 275000.0,
    "cout_produits": 255000.0,
    "marge_produits": 20000.0,
    "frais_livraison": 24000.0,
    "depenses_caisse": 0.0,
    "depenses_livreur": 5000.0,
    "depenses_totales": 5000.0,
    "resultat": 39000.0,
    "nb_commandes": 12,
    "nb_livrees": 8,
    "nb_retours": 2,
    "montant_retours": 76000.0,
    "taux_livraison": 66.7
  },
  "par_jour": [
    {
      "date": "2026-09-08",
      "commandes": 0,
      "livrees": 0,
      "retours": 0,
      "ca": 0,
      "frais_livraison": 0,
      "depenses": 0,
      "difference": 0,
      "mouvements": 3,
      "part_mouvements": 13.0
    },
    {
      "date": "2026-09-09",
      "commandes": 4,
      "livrees": 3,
      "retours": 1,
      "ca": 114000.0,
      "frais_livraison": 9000.0,
      "depenses": 0,
      "difference": 114000.0,
      "mouvements": 9,
      "part_mouvements": 39.1
    }
  ],
  "top_produits": [
    { "label": "iphone 11", "marque": "iPhone", "quantite": 2, "ca": 50000.0 },
    { "label": "Pixel 8pro", "marque": "Google Pixel", "quantite": 1, "ca": 40000.0 }
  ],
  "produits_moins_vendus": [
    { "label": "Samsung A05", "marque": "Samsung", "quantite": 1, "ca": 30000.0 },
    { "label": "Pixel 6pro", "marque": "Google Pixel", "quantite": 1, "ca": 25000.0 }
  ],
  "livreurs": [
    {
      "id": 15,
      "nom": "Rivo",
      "livrees": 4,
      "retours": 0,
      "assignees": 4,
      "ca": 177000.0,
      "frais_livraison": 12000.0,
      "depenses": 5000.0,
      "taux_reussite": 100.0
    },
    {
      "id": 16,
      "nom": "Tahina",
      "livrees": 3,
      "retours": 2,
      "assignees": 5,
      "ca": 109000.0,
      "frais_livraison": 9000.0,
      "depenses": 0,
      "taux_reussite": 60.0
    }
  ],
  "preparateurs": [
    {
      "id": 13,
      "nom": "Faniry",
      "total": 5,
      "par_jour": [
        { "date": "2026-09-09", "nb": 1 },
        { "date": "2026-09-10", "nb": 2 }
      ]
    }
  ],
  "mouvements_par_jour": [
    { "date": "2026-09-08", "entrees": 3, "sorties": 0 },
    { "date": "2026-09-09", "entrees": 2, "sorties": 7 }
  ]
}
```

Erreurs :
- `403` — `{"detail": "You do not have permission to perform this action."}` : préparateur, livreur ou employer sans rôle.

---

### Centre de rapports (`reports/<section>/`)

Huit vues (`orders/reporting.py`), toutes réservées au **`GERANT`** (`IsGerant` → sinon `403 {"detail": "You do not have permission to perform this action."}`), toutes en lecture seule, toutes construites par `_Contexte` avec les mêmes paramètres :

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| `date_from` | query | date `YYYY-MM-DD` | non | Défaut `date_to − 29 jours` ; si `date_from > date_to` les bornes sont inversées |
| `date_to` | query | date `YYYY-MM-DD` | non | Défaut aujourd'hui ; période en date de livraison prévue (`date_commande`), bornes comprises |
| `prev_from` | query | date `YYYY-MM-DD` | non | Début de la période de comparaison ; défaut : fenêtre de même longueur juste avant |
| `prev_to` | query | date `YYYY-MM-DD` | non | Fin de la période de comparaison ; défaut `date_from − 1 jour` |
| `granularity` | query | `day` \| `week` \| `month` \| `year` | non | Pas des séries temporelles (défaut `day` ; valeur inconnue = `day`) |
| `magasin_id` | query | int | non | Restreint à un magasin accessible |
| `dormant_days` | query | int ≥ 1 | non | **Stock** uniquement : seuil du stock dormant (défaut 30) |
| `platform` | query | code plateforme | non | **Marketing** uniquement : filtre `plateforme` |
| `campaign` | query | int | non | **Marketing** uniquement : une seule campagne |

Structures communes :
- `periode` (dans chaque réponse) : `{"from", "to", "prev_from", "prev_to", "granularity"}`.
- **Variation** : `{"actuel": 299000.0, "precedent": 250000.0, "variation": 49000.0, "variation_pct": 19.6}` — `variation_pct` vaut `null` quand `precedent` est 0.
- **Série** : une ligne par bucket de la période (zéro-remplie), `{"periode": "2026-09-09", "label": "09/09", …}` ; libellés : `09/09` (day), `S37 08/09` (week), `09/2026` (month), `2026` (year).
- **Ligne de ventes groupées** (`_grouper_ventes`) : `{"label", "quantite", "nb_commandes", "ca", "cout", "marge", "marge_pct"}`.

Définitions : vente = commande `LIVRE`, articles `retourne = false` ; `ca_total = ca_produits + frais_livraison` ; `cout_achat = Σ quantité × prix_achat` (catalogue actuel) ; `marge_brute = ca_produits − cout_achat` ; `depenses = depenses_caisse (hors catégories « Commande stock » / « Achat(s) (de) stock ») + depenses_livreur (ACCEPTE)` ; `benefice_net = ca_total − cout_achat − depenses` ; `panier_moyen = ca_total / nb_livrees`.

### `GET /api/orders/reports/overview/` — Vue générale
**Rôle** : `GERANT` · **Vue** : `OverviewReportView` (reporting.py)

Effet : KPIs comparés (Variation) pour `ca_total`, `benefice_net`, `nb_commandes`, `panier_moyen`, `nb_livrees`, `depenses`, `marge_brute` ; `benefices.obtenu` = marge brute (Variation) et `benefices.estime` = potentiel du stock actuel (références actives, stock > 0) ; séries financières ; répartition des statuts.

Réponse `200` :
```json
{
  "kpis": {
    "ca_total": { "actuel": 299000.0, "precedent": 250000.0, "variation": 49000.0, "variation_pct": 19.6 },
    "benefice_net": { "actuel": 39000.0, "precedent": 31000.0, "variation": 8000.0, "variation_pct": 25.8 },
    "nb_commandes": { "actuel": 12, "precedent": 10, "variation": 2, "variation_pct": 20.0 },
    "panier_moyen": { "actuel": 37375.0, "precedent": 35714.29, "variation": 1660.71, "variation_pct": 4.7 },
    "nb_livrees": { "actuel": 8, "precedent": 7, "variation": 1, "variation_pct": 14.3 },
    "depenses": { "actuel": 5000.0, "precedent": 0.0, "variation": 5000.0, "variation_pct": null },
    "marge_brute": { "actuel": 20000.0, "precedent": 18000.0, "variation": 2000.0, "variation_pct": 11.1 }
  },
  "benefices": {
    "obtenu": { "actuel": 20000.0, "precedent": 18000.0, "variation": 2000.0, "variation_pct": 11.1 },
    "estime": {
      "benefice": 7035000.0,
      "valeur_vente": 43315000.0,
      "valeur_achat": 36280000.0,
      "quantite": 1321
    }
  },
  "series": [
    { "periode": "2026-09-08", "label": "08/09", "ventes": 0, "cout_achat": 0, "depenses": 0, "caisse": 0, "livreur": 0, "benefices": 0 },
    { "periode": "2026-09-09", "label": "09/09", "ventes": 114000.0, "cout_achat": 100000.0, "depenses": 0, "caisse": 0, "livreur": 0, "benefices": 14000.0 }
  ],
  "repartition_statuts": [
    { "statut": "NOUVELLE", "label": "Nouvelle", "nb": 2 },
    { "statut": "EN_PREPARATION", "label": "En préparation", "nb": 0 },
    { "statut": "PRETE", "label": "Prête", "nb": 0 },
    { "statut": "EN_LIVRAISON", "label": "En livraison", "nb": 0 },
    { "statut": "LIVRE", "label": "Livré", "nb": 8 },
    { "statut": "RETOUR", "label": "Retour", "nb": 2 },
    { "statut": "ANNULEE", "label": "Annulée", "nb": 0 }
  ],
  "periode": { "from": "2026-09-08", "to": "2026-09-13", "prev_from": "2026-09-02", "prev_to": "2026-09-07", "granularity": "day" }
}
```
(`series[].ventes` inclut les frais de livraison ; `caisse` et `livreur` détaillent `depenses`.)

### `GET /api/orders/reports/sales/` — Ventes
**Rôle** : `GERANT` · **Vue** : `SalesReportView` (reporting.py)

Effet : KPIs comparés (`ca_total`, `ca_produits`, `nb_livrees`, `quantite_vendue`, `panier_moyen`), ventes groupées par dimension (`par.<cle>`, 50 lignes max chacune, triées par quantité décroissante), top/flop 10 produits, performance par livreur, série (`ca` produits hors frais, `quantite`, `ventes` = nb de commandes livrées).

Réponse `200` :
```json
{
  "kpis": {
    "ca_total": { "actuel": 299000.0, "precedent": 250000.0, "variation": 49000.0, "variation_pct": 19.6 },
    "ca_produits": { "actuel": 275000.0, "precedent": 229000.0, "variation": 46000.0, "variation_pct": 20.1 },
    "nb_livrees": { "actuel": 8, "precedent": 7, "variation": 1, "variation_pct": 14.3 },
    "quantite_vendue": { "actuel": 9, "precedent": 8, "variation": 1, "variation_pct": 12.5 },
    "panier_moyen": { "actuel": 37375.0, "precedent": 35714.29, "variation": 1660.71, "variation_pct": 4.7 }
  },
  "dimensions": [
    { "cle": "produit", "label": "Produit" },
    { "cle": "modele", "label": "Modèle" },
    { "cle": "sous_type", "label": "Sous-type" },
    { "cle": "categorie", "label": "Catégorie" },
    { "cle": "marque", "label": "Marque" },
    { "cle": "couleur", "label": "Couleur" }
  ],
  "par": {
    "produit": [
      { "label": "iphone 11 iPhone", "quantite": 2, "nb_commandes": 1, "ca": 50000.0, "cout": 50000.0, "marge": 0.0, "marge_pct": 0.0 }
    ],
    "modele": [
      { "label": "iphone 11", "quantite": 2, "nb_commandes": 1, "ca": 50000.0, "cout": 50000.0, "marge": 0.0, "marge_pct": 0.0 }
    ],
    "sous_type": [
      { "label": "PRIVACY", "quantite": 6, "nb_commandes": 5, "ca": 170000.0, "cout": 150000.0, "marge": 20000.0, "marge_pct": 11.8 }
    ],
    "categorie": [
      { "label": "CACHE ÉCRAN", "quantite": 6, "nb_commandes": 5, "ca": 170000.0, "cout": 150000.0, "marge": 20000.0, "marge_pct": 11.8 }
    ],
    "marque": [
      { "label": "Google Pixel", "quantite": 4, "nb_commandes": 4, "ca": 125000.0, "cout": 115000.0, "marge": 10000.0, "marge_pct": 8.0 }
    ],
    "couleur": [
      { "label": "Standard", "quantite": 6, "nb_commandes": 5, "ca": 170000.0, "cout": 150000.0, "marge": 20000.0, "marge_pct": 11.8 }
    ]
  },
  "top_produits": [
    { "label": "iphone 11 iPhone", "quantite": 2, "nb_commandes": 1, "ca": 50000.0, "cout": 50000.0, "marge": 0.0, "marge_pct": 0.0 }
  ],
  "moins_vendus": [
    { "label": "Pixel 6pro Google Pixel", "quantite": 1, "nb_commandes": 1, "ca": 25000.0, "cout": 20000.0, "marge": 5000.0, "marge_pct": 20.0 }
  ],
  "par_livreur": [
    { "id": 15, "nom": "Rivo", "commandes": 4, "livrees": 4, "retours": 0, "en_cours": 0, "ca": 177000.0, "taux_reussite": 100.0 },
    { "id": 16, "nom": "Tahina", "commandes": 5, "livrees": 3, "retours": 2, "en_cours": 0, "ca": 109000.0, "taux_reussite": 60.0 }
  ],
  "serie": [
    { "periode": "2026-09-08", "label": "08/09", "ca": 0, "quantite": 0, "ventes": 0 },
    { "periode": "2026-09-09", "label": "09/09", "ca": 105000.0, "quantite": 4, "ventes": 3 }
  ],
  "periode": { "from": "2026-09-08", "to": "2026-09-13", "prev_from": "2026-09-02", "prev_to": "2026-09-07", "granularity": "day" }
}
```

### `GET /api/orders/reports/financial/` — Financier
**Rôle** : `GERANT` · **Vue** : `FinancialReportView` (reporting.py)

Effet : totaux de la période (+ `achats_stock`, `taux_marge_brute` = marge/CA produits, `taux_benefice` = bénéfice net/CA total), comparaison (Variation) sur les mêmes clés, ventes groupées par produit (200 max), catégorie (100) et sous-type (100), séries financières.

Réponse `200` :
```json
{
  "totaux": {
    "ca_total": 299000.0,
    "ca_produits": 275000.0,
    "frais_livraison": 24000.0,
    "cout_achat": 255000.0,
    "marge_brute": 20000.0,
    "depenses_caisse": 0.0,
    "depenses_livreur": 5000.0,
    "depenses": 5000.0,
    "benefice_net": 39000.0,
    "achats_stock": 0.0,
    "taux_marge_brute": 7.3,
    "taux_benefice": 13.0
  },
  "comparaison": {
    "ca_total": { "actuel": 299000.0, "precedent": 250000.0, "variation": 49000.0, "variation_pct": 19.6 },
    "ca_produits": { "actuel": 275000.0, "precedent": 229000.0, "variation": 46000.0, "variation_pct": 20.1 },
    "frais_livraison": { "actuel": 24000.0, "precedent": 21000.0, "variation": 3000.0, "variation_pct": 14.3 },
    "cout_achat": { "actuel": 255000.0, "precedent": 211000.0, "variation": 44000.0, "variation_pct": 20.9 },
    "marge_brute": { "actuel": 20000.0, "precedent": 18000.0, "variation": 2000.0, "variation_pct": 11.1 },
    "depenses_caisse": { "actuel": 0.0, "precedent": 0.0, "variation": 0.0, "variation_pct": null },
    "depenses_livreur": { "actuel": 5000.0, "precedent": 0.0, "variation": 5000.0, "variation_pct": null },
    "depenses": { "actuel": 5000.0, "precedent": 0.0, "variation": 5000.0, "variation_pct": null },
    "benefice_net": { "actuel": 39000.0, "precedent": 39000.0, "variation": 0.0, "variation_pct": 0.0 }
  },
  "par_produit": [
    { "label": "iphone 11 iPhone", "quantite": 2, "nb_commandes": 1, "ca": 50000.0, "cout": 50000.0, "marge": 0.0, "marge_pct": 0.0 }
  ],
  "par_categorie": [
    { "label": "CACHE ÉCRAN", "quantite": 6, "nb_commandes": 5, "ca": 170000.0, "cout": 150000.0, "marge": 20000.0, "marge_pct": 11.8 }
  ],
  "par_sous_type": [
    { "label": "PRIVACY", "quantite": 6, "nb_commandes": 5, "ca": 170000.0, "cout": 150000.0, "marge": 20000.0, "marge_pct": 11.8 }
  ],
  "series": [
    { "periode": "2026-09-08", "label": "08/09", "ventes": 0, "cout_achat": 0, "depenses": 0, "caisse": 0, "livreur": 0, "benefices": 0 },
    { "periode": "2026-09-09", "label": "09/09", "ventes": 114000.0, "cout_achat": 100000.0, "depenses": 0, "caisse": 0, "livreur": 0, "benefices": 14000.0 }
  ],
  "periode": { "from": "2026-09-08", "to": "2026-09-13", "prev_from": "2026-09-02", "prev_to": "2026-09-07", "granularity": "day" }
}
```

### `GET /api/orders/reports/expenses/` — Dépenses
**Rôle** : `GERANT` · **Vue** : `ExpensesReportView` (reporting.py)

Effet : totaux comparés (Variation) — `total` (caisse + livreur, achats de stock **inclus**), `caisse`, `livreur`, `achats_stock`, `charges` (= total − achats de stock) — et `nb_mouvements` ; répartition par catégorie (source `caisse` ou `livreur`, `hors_resultat = true` pour les achats de marchandise) ; série `caisse`/`livreur`/`total` ; bloc `livraison` (frais facturés au client vs coût réel = dépenses acceptées des seuls types `frais_livraison = true`, ex. LIVRAISON 3K / 4K / 5K — repas, enveloppes, NAP exclus ; `marge_livraison = frais_factures_client − cout_reel_livreurs`) ; liste des mouvements (200 par source, 300 max au total, triés par date décroissante).

Réponse `200` :
```json
{
  "totaux": {
    "total": { "actuel": 65000.0, "precedent": 40000.0, "variation": 25000.0, "variation_pct": 62.5 },
    "caisse": { "actuel": 60000.0, "precedent": 40000.0, "variation": 20000.0, "variation_pct": 50.0 },
    "livreur": { "actuel": 5000.0, "precedent": 0.0, "variation": 5000.0, "variation_pct": null },
    "achats_stock": { "actuel": 45000.0, "precedent": 40000.0, "variation": 5000.0, "variation_pct": 12.5 },
    "charges": { "actuel": 20000.0, "precedent": 0.0, "variation": 20000.0, "variation_pct": null },
    "nb_mouvements": 3
  },
  "par_categorie": [
    { "label": "Commande stock", "source": "caisse", "total": 45000.0, "nb": 1, "hors_resultat": true },
    { "label": "Carburant", "source": "caisse", "total": 15000.0, "nb": 1, "hors_resultat": false },
    { "label": "Tournée livreur : ENVELOPPE", "source": "livreur", "total": 5000.0, "nb": 1, "hors_resultat": false }
  ],
  "serie": [
    { "periode": "2026-09-08", "label": "08/09", "caisse": 0, "livreur": 0, "total": 0 },
    { "periode": "2026-09-11", "label": "11/09", "caisse": 60000.0, "livreur": 5000.0, "total": 65000.0 }
  ],
  "livraison": {
    "frais_factures_client": 24000.0,
    "cout_reel_livreurs": 5000.0,
    "marge_livraison": 19000.0,
    "nb_livrees": 8,
    "frais_moyen_client": 3000.0,
    "cout_moyen_livraison": 625.0
  },
  "mouvements": [
    { "date": "2026-09-11T14:20:05.000000+03:00", "source": "caisse", "categorie": "Carburant", "libelle": "Plein moto", "montant": 15000.0, "auteur": "Rakoto Jean" },
    { "date": "2026-09-11", "source": "livreur", "categorie": "ENVELOPPE", "libelle": "ENVELOPPE × 10", "montant": 5000.0, "auteur": "Rivo" }
  ],
  "periode": { "from": "2026-09-08", "to": "2026-09-13", "prev_from": "2026-09-02", "prev_to": "2026-09-07", "granularity": "day" }
}
```
(`mouvements[].date` est un datetime ISO pour la caisse et une date `YYYY-MM-DD` pour une dépense livreur ; `categorie` vaut « Sans catégorie » / « Tournée » à défaut.)

### `GET /api/orders/reports/stock/` — Stock
**Rôle** : `GERANT` · **Vue** : `StockReportView` (reporting.py)

Effet : état instantané du stock des références actives (`etat`), listes de ruptures (`stock ≤ 0`) et de réapprovisionnement (`stock ≤ seuil_alerte`, 300 lignes max), valeur par catégorie, mouvements de stock de la période (résumé par origine, 300 derniers mouvements, série entrées/sorties en quantités) et stock dormant (variantes en stock sans sortie `PREPARATION` depuis `dormant_days` jours, triées par valeur immobilisée décroissante).

Réponse `200` :
```json
{
  "etat": {
    "quantite_totale": 1321,
    "valeur_achat": 36280000.0,
    "valeur_vente": 43315000.0,
    "nb_variantes": 527,
    "nb_references": 298,
    "nb_ruptures": 82,
    "nb_reappro": 304,
    "nb_stock_bas": 222
  },
  "ruptures": [
    { "variant_id": 1026, "produit": "FLIP COVER Samsung Z-Fold 3", "variante": "Noir", "stock": 0, "seuil": 1, "prix_achat": 30000.0, "prix_vente": 45000.0 }
  ],
  "reappro": [
    { "variant_id": 1026, "produit": "FLIP COVER Samsung Z-Fold 3", "variante": "Noir", "stock": 0, "seuil": 1, "prix_achat": 30000.0, "prix_vente": 45000.0 },
    { "variant_id": 658, "produit": "FLIP COVER Google Pixel Pixel 8pro", "variante": "Bleu", "stock": 1, "seuil": 2, "prix_achat": 30000.0, "prix_vente": 40000.0 }
  ],
  "par_categorie": [
    { "label": "CACHE ÉCRAN", "quantite": 975, "valeur_achat": 24375000.0, "nb_variantes": 164 },
    { "label": "HOUSSE", "quantite": 346, "valeur_achat": 11905000.0, "nb_variantes": 210 }
  ],
  "mouvements_resume": [
    { "origine": "PREPARATION", "label": "Préparation de commande", "nb": 11, "entrees": 0, "sorties": 12 },
    { "origine": "RETOUR", "label": "Retour de commande", "nb": 3, "entrees": 3, "sorties": 0 },
    { "origine": "ANNULATION", "label": "Annulation de commande", "nb": 0, "entrees": 0, "sorties": 0 },
    { "origine": "FOURNISSEUR", "label": "Réception fournisseur", "nb": 0, "entrees": 0, "sorties": 0 },
    { "origine": "AJUSTEMENT", "label": "Ajustement manuel", "nb": 9, "entrees": 16, "sorties": 3 }
  ],
  "mouvements": [
    {
      "id": 28,
      "date": "2026-09-12T07:33:45.500204+00:00",
      "variant_id": 658,
      "produit": "FLIP COVER Google Pixel Pixel 8pro",
      "variante": "Bleu",
      "quantite": 1,
      "type": "ENTREE",
      "origine": "RETOUR",
      "origine_label": "Retour de commande",
      "reference": "CMD-2-20260909-0005",
      "note": "",
      "utilisateur": "Tahina"
    }
  ],
  "nb_mouvements": 23,
  "serie": [
    { "periode": "2026-09-08", "label": "08/09", "entrees": 13, "sorties": 0 },
    { "periode": "2026-09-09", "label": "09/09", "entrees": 2, "sorties": 7 }
  ],
  "dormant": {
    "jours": 30,
    "nb": 1,
    "valeur_immobilisee": 90000.0,
    "lignes": [
      { "variant_id": 812, "produit": "PRIVACY Samsung A05", "variante": "", "stock": 3, "derniere_vente": null, "jours_sans_vente": 41, "valeur_immobilisee": 90000.0 }
    ]
  },
  "periode": { "from": "2026-09-08", "to": "2026-09-13", "prev_from": "2026-09-02", "prev_to": "2026-09-07", "granularity": "day" }
}
```
(`variante` est vide pour la couleur « Standard » ; `mouvements[].date` est en UTC (`+00:00`) car le `timestamp` du mouvement est sérialisé tel quel ; `derniere_vente` vaut `null` si la variante n'a jamais été sortie pour une commande — l'ancienneté est alors comptée depuis la création de la référence.)

### `GET /api/orders/reports/orders/` — Commandes
**Rôle** : `GERANT` · **Vue** : `OrdersReportView` (reporting.py)

Effet : compteurs par statut de la période (`kpis`), comparaison (Variation) sur `total`, `livrees`, `annulees`, `retournees`, `taux_annulation`, répartition avec part en %, ventilation par zone et par mode de paiement (CA et frais sur les livrées), série `total`/`livrees`/`annulees`/`retours`, montants annulés et retournés.

Réponse `200` :
```json
{
  "kpis": {
    "total": 12,
    "nouvelles": 2,
    "en_preparation": 0,
    "pretes": 0,
    "en_cours": 0,
    "en_livraison": 0,
    "livrees": 8,
    "annulees": 0,
    "retournees": 2,
    "taux_annulation": 0.0,
    "taux_livraison": 66.7,
    "taux_retour": 20.0
  },
  "comparaison": {
    "total": { "actuel": 12, "precedent": 10, "variation": 2, "variation_pct": 20.0 },
    "livrees": { "actuel": 8, "precedent": 7, "variation": 1, "variation_pct": 14.3 },
    "annulees": { "actuel": 0, "precedent": 1, "variation": -1, "variation_pct": -100.0 },
    "retournees": { "actuel": 2, "precedent": 2, "variation": 0, "variation_pct": 0.0 },
    "taux_annulation": { "actuel": 0.0, "precedent": 10.0, "variation": -10.0, "variation_pct": -100.0 }
  },
  "repartition": [
    { "statut": "NOUVELLE", "label": "Nouvelle", "nb": 2, "part": 16.7 },
    { "statut": "EN_PREPARATION", "label": "En préparation", "nb": 0, "part": 0.0 },
    { "statut": "PRETE", "label": "Prête", "nb": 0, "part": 0.0 },
    { "statut": "EN_LIVRAISON", "label": "En livraison", "nb": 0, "part": 0.0 },
    { "statut": "LIVRE", "label": "Livré", "nb": 8, "part": 66.7 },
    { "statut": "RETOUR", "label": "Retour", "nb": 2, "part": 16.7 },
    { "statut": "ANNULEE", "label": "Annulée", "nb": 0, "part": 0.0 }
  ],
  "par_zone": [
    { "zone": "ZONE1", "nb": 10, "livrees": 7, "ca": 296000.0, "frais": 21000.0 },
    { "zone": "RECUPERATION", "nb": 2, "livrees": 1, "ca": 43000.0, "frais": 0.0 }
  ],
  "par_paiement": [
    { "mode": "LIVRAISON", "label": "Paiement à la livraison", "nb": 9, "ca": 263000.0 },
    { "mode": "AVANT", "label": "Paiement avant la livraison", "nb": 3, "ca": 76000.0 }
  ],
  "serie": [
    { "periode": "2026-09-08", "label": "08/09", "total": 0, "livrees": 0, "annulees": 0, "retours": 0 },
    { "periode": "2026-09-09", "label": "09/09", "total": 4, "livrees": 3, "annulees": 0, "retours": 1 }
  ],
  "montant_annule": 0.0,
  "montant_retourne": 76000.0,
  "periode": { "from": "2026-09-08", "to": "2026-09-13", "prev_from": "2026-09-02", "prev_to": "2026-09-07", "granularity": "day" }
}
```
(`taux_retour` = retours / (livrées + retours) ; `en_cours` = en préparation + prêtes.)

### `GET /api/orders/reports/deliveries/` — Livraisons
**Rôle** : `GERANT` · **Vue** : `DeliveriesReportView` (reporting.py)

Effet : commandes de la période **hors** `RECUPERATION`. `totaux` sur les livraisons terminées (`LIVRE` + `RETOUR`), coût = dépenses acceptées des seuls types `frais_livraison = true` (LIVRAISON 3K / 4K / 5K…), délai moyen `EN_LIVRAISON → LIVRE` en minutes d'après l'historique ; performance par livreur (triée par réussites), par zone, série réussies/échouées.

Réponse `200` :
```json
{
  "totaux": {
    "livraisons": 10,
    "reussies": 8,
    "echouees": 2,
    "en_cours": 0,
    "taux_reussite": 80.0,
    "taux_echec": 20.0,
    "cout_total": 5000.0,
    "cout_moyen": 500.0,
    "frais_factures": 24000.0,
    "marge_livraison": 19000.0,
    "delai_moyen_minutes": 277,
    "nb_delais_mesures": 8
  },
  "par_livreur": [
    {
      "id": 15,
      "nom": "Rivo",
      "assignees": 4,
      "livraisons": 4,
      "reussies": 4,
      "echouees": 0,
      "en_cours": 0,
      "cout_total": 5000.0,
      "cout_moyen": 1250.0,
      "frais_factures": 12000.0,
      "marge_livraison": 7000.0,
      "ca": 177000.0,
      "taux_reussite": 100.0,
      "taux_echec": 0.0,
      "delai_moyen_minutes": 42
    },
    {
      "id": 16,
      "nom": "Tahina",
      "assignees": 5,
      "livraisons": 5,
      "reussies": 3,
      "echouees": 2,
      "en_cours": 0,
      "cout_total": 0.0,
      "cout_moyen": 0.0,
      "frais_factures": 9000.0,
      "marge_livraison": 9000.0,
      "ca": 109000.0,
      "taux_reussite": 60.0,
      "taux_echec": 40.0,
      "delai_moyen_minutes": 735
    }
  ],
  "par_zone": [
    { "zone": "ZONE1", "livraisons": 10, "reussies": 8, "echouees": 2, "frais": 24000.0, "taux_reussite": 80.0 }
  ],
  "serie": [
    { "periode": "2026-09-08", "label": "08/09", "reussies": 0, "echouees": 0 },
    { "periode": "2026-09-09", "label": "09/09", "reussies": 3, "echouees": 1 }
  ],
  "periode": { "from": "2026-09-08", "to": "2026-09-13", "prev_from": "2026-09-02", "prev_to": "2026-09-07", "granularity": "day" }
}
```
(`delai_moyen_minutes` vaut `null` sans délai mesurable.)

### `GET /api/orders/reports/marketing/` — Marketing
**Rôle** : `GERANT` · **Vue** : `MarketingReportView` (reporting.py)

Effet : campagnes actives sur la période (`date_debut ≤ date_to` et `date_fin` nulle ou ≥ `date_from`), filtrables par `platform` et `campaign` ; pour chacune : commandes **concernées par sa période** (affectation automatique, restreinte à la fenêtre du rapport — voir *Campagnes marketing*), livrées, CA (total à payer des livrées), marge produits, bénéfice = marge − coût, `roi_pct = (ca − coût) / coût × 100` (`null` si coût nul), coût par commande, `periode_effective`. Totaux sur les commandes **distinctes** (chevauchement dé-doublonné). Agrégats par plateforme, top 3 / flop 3 des campagnes avec ROI, dépenses « Pub » enregistrées en caisse, `commandes_sans_campagne` = commandes de la période (non annulées) qu'aucune campagne ne couvre.

Réponse `200` :
```json
{
  "totaux": {
    "depenses_campagnes": 150000.0,
    "depenses_pub_caisse": 150000.0,
    "commandes": 5,
    "commandes_livrees": 4,
    "ca": 172000.0,
    "marge_produits": 28000.0,
    "roi_pct": 14.7,
    "nb_campagnes": 1,
    "commandes_sans_campagne": 7
  },
  "campagnes": [
    {
      "id": 3,
      "nom": "Boost Facebook rentrée",
      "plateforme": "FACEBOOK",
      "plateforme_label": "Facebook",
      "date_debut": "2026-09-01",
      "date_fin": "2026-09-30",
      "actif": true,
      "depenses": 150000.0,
      "commandes": 5,
      "commandes_livrees": 4,
      "ca": 172000.0,
      "marge_produits": 28000.0,
      "benefice": -122000.0,
      "roi_pct": 14.7,
      "cout_par_commande": 30000.0
    }
  ],
  "par_plateforme": [
    { "plateforme": "FACEBOOK", "label": "Facebook", "depenses": 150000.0, "commandes": 5, "commandes_livrees": 4, "ca": 172000.0, "nb_campagnes": 1, "roi_pct": 14.7 }
  ],
  "plus_rentables": [
    {
      "id": 3,
      "nom": "Boost Facebook rentrée",
      "plateforme": "FACEBOOK",
      "plateforme_label": "Facebook",
      "date_debut": "2026-09-01",
      "date_fin": "2026-09-30",
      "actif": true,
      "depenses": 150000.0,
      "commandes": 5,
      "commandes_livrees": 4,
      "ca": 172000.0,
      "marge_produits": 28000.0,
      "benefice": -122000.0,
      "roi_pct": 14.7,
      "cout_par_commande": 30000.0
    }
  ],
  "moins_rentables": [],
  "plateformes": [
    { "code": "FACEBOOK", "label": "Facebook" },
    { "code": "INSTAGRAM", "label": "Instagram" },
    { "code": "TIKTOK", "label": "TikTok" },
    { "code": "GOOGLE", "label": "Google" },
    { "code": "AUTRE", "label": "Autre" }
  ],
  "periode": { "from": "2026-09-08", "to": "2026-09-13", "prev_from": "2026-09-02", "prev_to": "2026-09-07", "granularity": "day" }
}
```
(Sans campagne sur la période : `campagnes`, `par_plateforme`, `plus_rentables`, `moins_rentables` sont `[]` et `totaux.roi_pct` vaut `null`. `moins_rentables` n'est rempli que s'il y a au moins deux campagnes avec ROI ; `cout_par_commande` vaut `null` sans commande.)

Erreurs communes aux huit sections :
- `403` — `{"detail": "You do not have permission to perform this action."}` : préparateur, livreur ou employer sans rôle.
- Un paramètre de date mal formé est ignoré (valeur par défaut), jamais rejeté.

---

## Suppliers (approvisionnements fournisseur)

**Base** : `/api/suppliers/` · **Rôle** : `GERANT` (`IsGerant`) sur toutes les routes.

**Règle métier** : un approvisionnement = **1 fournisseur + 1 sous-type de produit + 1 quantité** + N paiements (chacun avec son taux du jour, montant MGA figé) + 1 expédition + **1 seul montant Frais + Douane** + 1 coût total rendu Madagascar + 1 coût de revient par pièce. LE produit est un **sous-type** du catalogue (`ProductType` : FLIP COVER, Z-FOLD… — la même liste que le filtre « sous-type » de la page Produits), **sans couleur ni variante** : le module est indépendant du stock (aucun mouvement de stock, aucun changement de prix d'achat). Pour un autre sous-type, on crée un autre approvisionnement ; le même sous-type acheté plusieurs fois = plusieurs approvisionnements, chacun avec son coût historique. Le champ `product_variant` n'existe plus que pour les anciens approvisionnements convertis (legacy, `null` sinon).

Formules (toutes en MGA, calculées par le serveur — `suppliers/services.py`) :
```text
total fournisseur MGA       = Σ (montant paiement × taux du jour du paiement)
coût total rendu Madagascar = total fournisseur MGA + Frais + Douane
coût de revient par pièce   = coût total rendu Madagascar / quantité
marge / pièce               = prix de vente − coût de revient par pièce
```

Statuts (`statut`) dans l'ordre du cycle : `BROUILLON` → `COMMANDE` → `ACOMPTE_PAYE` → `PREPARATION` → `PAYE` (entièrement payé) → `EXPEDIE` → `EN_TRANSIT` → `ARRIVE` → `COUT_FINALISE`. `ACOMPTE_PAYE` / `PAYE` sont dérivés des paiements (par rapport à `montant_prevu`) tant que la marchandise n'est pas expédiée ; `PREPARATION` est posé à la main. Un approvisionnement `COUT_FINALISE` ne change plus (400 sur toute modification).

Objet `SupplierOrderSerializer` :
```json
{
  "id": 12,
  "numero": "SUP-2-20260917-0001",
  "date": "2026-09-01",
  "description": "Envoi #001",
  "statut": "COUT_FINALISE",
  "statut_label": "Coût finalisé",
  "magasin": 2,
  "magasin_name": "Smartphone.Mg",
  "supplier": 3,
  "supplier_nom": "Fournisseur Chine A",
  "supplier_pays": "Chine",
  "product_type": 14,
  "sous_type": { "id": 14, "libelle": "Coques / FLIP COVER", "nom": "FLIP COVER", "category": 5, "category_name": "Coques" },
  "produit_libelle": "Coques / FLIP COVER",
  "product_variant": null,
  "produit": null,
  "quantite": 100,
  "quantite_recue": 100,
  "devise": "USD",
  "montant_prevu": "2000.00",
  "total_paye_devise": "2000.00",
  "reste_a_payer_devise": "0.00",
  "pourcentage_paye": "100.0",
  "date_expedition": "2026-09-10",
  "transporteur": "DHL",
  "mode_transport": "AERIEN",
  "mode_transport_label": "Aérien",
  "tracking": "TRK123",
  "numero_colis": "COLIS-1",
  "lieu_depart": "Chine",
  "destination": "Madagascar",
  "date_arrivee": "2026-09-20",
  "commentaire_transport": "",
  "frais_douane_mga": "5000000.00",
  "total_paiements_mga": "9100000.00",
  "cout_total_mga": "14100000.00",
  "cout_unitaire_mga": "141000.00",
  "prix_vente_unitaire": "200000.00",
  "marge_unitaire": "59000.00",
  "payments": [
    { "id": 1, "date": "2026-09-01", "type_paiement": "ACOMPTE", "type_label": "Acompte", "methode": "VIREMENT", "methode_label": "Virement bancaire", "montant": "1000.00", "devise": "USD", "taux_change": "4500.0000", "montant_mga": "4500000.00", "reference": "", "commentaire": "", "justificatif": null, "created_by_name": "Gérant", "created_at": "2026-09-01T09:00:00+03:00" },
    { "id": 2, "date": "2026-09-08", "type_paiement": "SOLDE", "type_label": "Solde", "methode": "VIREMENT", "methode_label": "Virement bancaire", "montant": "1000.00", "devise": "USD", "taux_change": "4600.0000", "montant_mga": "4600000.00", "reference": "", "commentaire": "", "justificatif": null, "created_by_name": "Gérant", "created_at": "2026-09-08T09:00:00+03:00" }
  ],
  "caisse": { "paiements": [1], "frais_douane": true },
  "received_at": "2026-09-21T10:00:00+03:00",
  "finalise_at": "2026-09-21T10:00:00+03:00",
  "created_by_name": "Gérant",
  "created_at": "2026-09-01T08:00:00+03:00"
}
```
`sous_type` / `produit_libelle` : le sous-type (« Catégorie / Sous-type »). `prix_vente_unitaire` = prix de vente moyen des références actives du sous-type (base de `marge_unitaire`) ; `produit` (legacy) n'est renseigné que pour un ancien appro converti qui connaissait sa variante. `caisse` : sorties de caisse déjà enregistrées pour cet appro (paiements `APPRO:<n°>:P<id>`, frais `APPRO:<n°>:FRAIS`, origine `ACHAT_STOCK` — marchandise, exclue des charges des rapports).

Temps réel : chaque enregistrement diffuse `supplier_order` (`created` / `updated`) sur `/ws/data/`.

### Fournisseurs

### `GET /api/suppliers/suppliers/` — Liste des fournisseurs
Paramètres : `search` (nom, pays, contact, e-mail), `actif=1`. Chaque fiche porte son résumé financier : `nb_approvisionnements`, `nb_en_cours`, `nb_finalises`, `total_paye_mga`, `total_frais_douane_mga`, `cout_total_mga`, `reste_a_payer_devise`, `quantite_totale`, `dernier_approvisionnement {id, numero, statut, statut_label, date}`.
```json
[{ "id": 3, "nom": "Fournisseur Chine A", "pays": "Chine", "contact": "M. Li", "telephone": "+86…", "email": "li@example.cn", "adresse": "Shenzhen", "notes": "", "devise": "USD", "actif": true, "nb_approvisionnements": 2, "nb_en_cours": 1, "nb_finalises": 1, "total_paye_mga": "9100000.00", "total_frais_douane_mga": "5000000.00", "cout_total_mga": "14100000.00", "reste_a_payer_devise": "1000.00", "quantite_totale": 300, "dernier_approvisionnement": { "id": 13, "numero": "SUP-2-20260917-0002", "statut": "ACOMPTE_PAYE", "statut_label": "Acompte payé", "date": "2026-09-17" }, "created_at": "2026-09-01T08:00:00+03:00" }]
```

### `POST /api/suppliers/suppliers/` — Créer un fournisseur
Corps : `nom` (obligatoire), `pays`, `contact`, `telephone`, `email`, `adresse`, `notes`, `devise` (défaut `USD`), `actif`. Réponse `201` : la fiche.

### `GET /api/suppliers/suppliers/{id}/` — Fiche fournisseur
La fiche + `approvisionnements` : liste complète de ses approvisionnements (objets `SupplierOrderSerializer`).

### `PATCH /api/suppliers/suppliers/{id}/` — Modifier · `DELETE /api/suppliers/suppliers/{id}/` — Supprimer / désactiver
`DELETE` : supprimé s'il n'a aucun approvisionnement, sinon **désactivé** (`actif = false`, historique conservé) — `200` avec la fiche.

### Approvisionnements

### `GET /api/suppliers/orders/kpis/` — Indicateurs de la page
```json
{ "nb_approvisionnements": 5, "nb_en_cours": 3, "nb_finalises": 2, "total_paye_mga": "23000000.00", "total_frais_douane_mga": "9000000.00", "cout_total_mga": "32000000.00", "reste_a_payer_devise": "1500.00", "quantite_totale": 600, "nb_fournisseurs": 2, "nb_fournisseurs_actifs": 2, "en_transit": { "nb": 1, "valeur_mga": "4600000.00" }, "a_finaliser": 1, "cout_moyen_par_piece_mga": "148000.00", "par_statut": [{ "statut": "BROUILLON", "label": "Brouillon", "nb": 0 }] }
```

### `GET /api/suppliers/orders/` — Liste · `GET /api/suppliers/orders/{id}/` — Détail
Paramètres de liste : `magasin_id`, `supplier`, `product_type` (sous-type), `statut` (plusieurs séparés par `,`), `search` (n°, description, fournisseur, tracking, n° colis, sous-type, catégorie). Tri : le plus récent en premier.

### `POST /api/suppliers/orders/` — Créer un approvisionnement
| Paramètre | Type | Obligatoire | Description |
| --- | --- | --- | --- |
| `product_type` | int | oui | LE produit de l'envoi = un sous-type du catalogue (`GET /api/catalog/types/`) — pas de couleur |
| `quantite` | int ≥ 1 | oui | Nombre de pièces |
| `supplier` | int \| null | non | Fiche fournisseur de la société |
| `devise` | `USD` \| `EUR` \| `CNY` \| `MGA` | non | Devise du fournisseur (défaut : celle du fournisseur, sinon `USD`) |
| `montant_prevu` | decimal | non | Total convenu, dans `devise` — sert au « reste à payer » |
| `description`, `date` | | non | |
| `statut` | `BROUILLON` \| `COMMANDE` | non | Défaut `BROUILLON` |
| `magasin_id` | int | admin multi-magasins | Magasin destinataire |
```json
{ "supplier": 3, "product_type": 14, "quantite": 100, "devise": "USD", "montant_prevu": "2000", "description": "Envoi #001", "statut": "COMMANDE" }
```
Réponse `201` : l'objet. Erreurs `400` : `{"quantite": ["La quantité doit être supérieure à zéro."]}`, `{"product_type": ["Ce sous-type n'appartient pas à ce magasin."]}`, `{"supplier": ["Ce fournisseur n'appartient pas à votre société."]}`. Les champs `product_variant` / `lines` des anciens modules sont ignorés : `product_type` est requis (`400 {"product_type": ["Ce champ est obligatoire."]}`).

### `PATCH /api/suppliers/orders/{id}/` — Modifier · `DELETE` — Supprimer un brouillon
`PATCH` (tant que non finalisé) : `supplier`, `product_type`, `quantite` (≥ quantité déjà reçue), `devise`, `montant_prevu`, `description`, `date`, transport (`date_expedition`, `transporteur`, `mode_transport`, `tracking`, `numero_colis`, `lieu_depart`, `destination`, `date_arrivee`, `commentaire_transport`), `frais_douane_mga`. Les coûts sont recalculés.
`DELETE` : `204` uniquement pour un brouillon sans paiement, sinon `405 {"detail": "Seul un brouillon sans paiement peut être supprimé (historique comptable)."}`.

### `POST …/commander/` · `…/preparer/` · `…/expedier/` · `…/transit/` · `…/arriver/` — Avancer le cycle
| Action | Depuis | Corps |
| --- | --- | --- |
| `commander/` | `BROUILLON` | — |
| `preparer/` | `COMMANDE`, `ACOMPTE_PAYE`, `PAYE` | — |
| `expedier/` (départ Chine) | `COMMANDE`, `ACOMPTE_PAYE`, `PREPARATION`, `PAYE` | `date_expedition` (défaut aujourd'hui), `transporteur`, `mode_transport` (`AERIEN` \| `MARITIME` \| `ROUTIER` \| `EXPRESS` \| `AUTRE`), `tracking`, `numero_colis`, `lieu_depart`, `destination`, `commentaire_transport` |
| `transit/` | `EXPEDIE` | `transporteur`, `mode_transport`, `tracking`, `numero_colis`, `commentaire_transport` |
| `arriver/` (Madagascar) | `EXPEDIE`, `EN_TRANSIT` | `date_arrivee` (défaut aujourd'hui), `frais_douane_mga` (facultatif) |
Réponse `200` : l'objet. Transition impossible → `400 ["Passage « … » → « … » impossible."]`.

### `POST /api/suppliers/orders/{id}/frais-douane/` — Frais + Douane
Corps : `frais_douane_mga` (decimal ≥ 0, **un seul montant**), `en_caisse` (bool : enregistre aussi la sortie de caisse `APPRO:<n°>:FRAIS`, une seule fois, session ouverte requise sinon `400 {"en_caisse": [...]}`). Coût total et coût unitaire recalculés.
```json
{ "frais_douane_mga": "5000000", "en_caisse": true }
```

### `POST /api/suppliers/orders/{id}/finaliser/` — Finaliser le coût
Depuis `ARRIVE` uniquement. Corps : `quantite_recue` (défaut : la quantité commandée ; 0 ≤ … ≤ quantité), `mettre_a_jour_prix_achat` (défaut `true`, **sans effet** sur un appro sous-type). Effet : statut `COUT_FINALISE`, coût figé (historique), `received_at` / `finalise_at` posés. **Aucun mouvement de stock** : le module fournisseur est indépendant du stock. Seul un ancien appro converti qui porte encore un `product_variant` (legacy) crée une entrée de stock (`StockMovement` origine `FOURNISSEUR`) et, si `mettre_a_jour_prix_achat`, met à jour le prix d'achat de référence (moyenne pondérée).

### `GET|POST /api/suppliers/orders/{id}/payments/` · `DELETE …/payments/{pid}/` — Paiements fournisseur
`POST` (tant que non finalisé) : `montant` (> 0), `devise`, `taux_change` (Ar pour 1 unité — **obligatoire hors MGA**, figé : `montant_mga = montant × taux`), `date`, `type_paiement` (`ACOMPTE` \| `SOLDE` \| `PARTIEL` \| `AUTRE`), `methode` (`VIREMENT` \| `MOBILE_MONEY` \| `ESPECES` \| `CARTE` \| `AUTRE`), `reference`, `commentaire`, `justificatif` (fichier, multipart), `en_caisse` (sortie `APPRO:<n°>:P<id>`). Un premier paiement sur un brouillon le passe en `COMMANDE` puis `ACOMPTE_PAYE`. Réponse `201` : l'approvisionnement complet.
```json
{ "montant": "1000", "devise": "USD", "taux_change": "4500", "date": "2026-09-01", "type_paiement": "ACOMPTE", "methode": "VIREMENT" }
```
`DELETE …/payments/{pid}/` : `200` avec l'appro recalculé (une sortie de caisse déjà enregistrée n'est pas annulée).

### `GET /api/suppliers/cost-history/` — Historique des envois d'un sous-type
`?type=<id>` (sous-type) : `libelle`, `cout_actuel_mga` (dernier envoi finalisé), `cout_moyen_pondere_mga` (Σ coûts totaux / Σ quantités des envois finalisés), `historique[]` (envois finalisés : `id, numero, supplier_nom, produit_libelle, date, finalise_at, quantite, total_paiements_mga, frais_douane_mga, cout_total_mga, cout_unitaire_mga`). Sous-type inconnu ou d'un autre magasin → `404 {"detail": "Sous-type introuvable."}`. Sans `type` : les 200 derniers envois finalisés de la société (liste d'`historique[]`).
```json
{ "type": 14, "libelle": "Coques / FLIP COVER", "cout_actuel_mga": "155000.00", "cout_moyen_pondere_mga": "150333.33", "historique": [{ "id": 13, "numero": "SUP-2-20260917-0002", "supplier_nom": "Fournisseur Chine A", "produit_libelle": "Coques / FLIP COVER", "date": "2026-09-17", "finalise_at": "2026-09-30T10:00:00+03:00", "quantite": 200, "total_paiements_mga": "23000000.00", "frais_douane_mga": "8000000.00", "cout_total_mga": "31000000.00", "cout_unitaire_mga": "155000.00" }] }
```

---

## Espace client (nouveau — app `clients`)

Couche API ajoutée à côté de l'application de gestion, pour le futur espace client en ligne (web/mobile). Elle réutilise le catalogue et le modèle `Order` existants — aucun catalogue ni système de commande parallèle — et n'expose jamais les données internes (prix d'achat, marges, stock chiffré, personnel, caisse, rapports).

- **Catalogue public** (`/api/produit/`, `/api/categories/`, `/api/type/`, `/api/sous-type/`, `/api/marque/`, `/api/couleurs/`, `/api/boutiques/`) : sans authentification, lecture seule.
- **Compte client** (`/api/client/…`) : authentification JWT **distincte** — les jetons portent `client_id` (pas `user_id`) ; un jeton client est refusé par toute route interne (`401`), un jeton interne est refusé par toute route client (`401`). En-tête : `Authorization: Bearer <access>` (access 5 min, refresh 24 h).
- **Commandes client** : créées en statut **`EN_ATTENTE_APPROBATION`** (nouveau statut, sans effet sur le stock) ; le gérant les **approuve** (`→ NOUVELLE`, puis workflow habituel : préparation, livraison…) ou les **refuse** (`→ ANNULEE`). Le client peut modifier/annuler tant que la préparation n'a pas commencé.
- **Limitation de débit** (`429 {"detail": "Request was throttled. Expected available in N seconds."}`) : `client_auth` 20/min (inscription, connexion, refresh), `client_public` 300/min (catalogue), `client_orders` 60/min.
- **Erreurs métier** : `400` avec `{"champ": ["message"]}` ou `{"items": ["message par article", …]}` ; `404` si la ressource n'appartient pas au client.

### Catalogue public

### `GET /api/boutiques/` — Boutiques
**Rôle** : public · **Vue** : `PublicBoutiqueListView` (clients/views.py)

Réponse `200` :
```json
[
  { "id": 2, "nom": "Boutique Centre", "description": "Accessoires téléphone", "logo": "http://185.215.167.79:8010/media/shop_logo/centre.png" }
]
```

### `GET /api/boutiques/{id}/zones/` — Zones de livraison d'une boutique
**Rôle** : public · **Vue** : `PublicBoutiqueZonesView`

Effet : zones actives de la société de la boutique (le `code` est à renvoyer dans `livraison_zone`) + le retrait sur place.

Réponse `200` :
```json
{
  "boutique": 2,
  "recuperation": { "code": "RECUPERATION", "nom": "Retrait sur place", "prix": 0 },
  "zones": [
    { "code": "CENTREVILLE", "nom": "Centre-ville", "prix": 3000.0 },
    { "code": "PERIPHERIE", "nom": "Périphérie", "prix": 5000.0 }
  ]
}
```

Erreurs : `404` — `{"detail": "No MagasinProfile matches the given query."}`.

### `GET /api/categories/` — Catégories (alias : `GET /api/type/`)
**Rôle** : public · **Vue** : `PublicCategorieListView`

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| boutique | query | int | non | Ne garder que les catégories de cette boutique. |

Réponse `200` :
```json
[
  { "id": 1, "nom": "Coques", "avec_couleurs": true, "boutique": 2 },
  { "id": 2, "nom": "Chargeurs", "avec_couleurs": false, "boutique": 2 }
]
```

### `GET /api/sous-type/` — Sous-types
**Rôle** : public · **Vue** : `PublicSousTypeListView`

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| category (ou categorie) | query | int | non | Sous-types d'une catégorie. |
| boutique | query | int | non | Boutique. |

Réponse `200` :
```json
[ { "id": 4, "nom": "iPhone", "categorie": 1, "categorie_nom": "Coques" } ]
```

### `GET /api/marque/` — Marques
**Rôle** : public · **Vue** : `PublicMarqueListView` · `?boutique=`

Réponse `200` :
```json
[ { "id": 3, "nom": "Apple", "boutique": 2 } ]
```

### `GET /api/couleurs/` — Couleurs
**Rôle** : public · **Vue** : `PublicCouleurListView` · `?boutique=`

Réponse `200` :
```json
[ { "id": 7, "nom": "Noir", "boutique": 2 }, { "id": 8, "nom": "Rouge", "boutique": 2 } ]
```

### `GET /api/produit/` — Produits (liste paginée)
**Rôle** : public · **Vue** : `PublicProduitViewSet` (références actives uniquement)

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| search | query | string | non | Recherche dans le nom, la marque, le sous-type et la catégorie (insensible à la casse). |
| category (ou categorie, ou type) | query | int | non | Catégorie. |
| sous_type | query | int | non | Sous-type. |
| brand (ou marque) | query | int | non | Marque. |
| couleur | query | string | non | Nom de couleur exact (insensible à la casse). |
| available | query | `true`/`1` | non | Seulement les produits ayant au moins une couleur en stock. |
| min_price / max_price | query | nombre | non | Fourchette de prix de vente (Ar). |
| boutique | query | int | non | Boutique. |
| page / page_size | query | int | non | Pagination (24 par page, 100 max). |

Réponse `200` :
```json
{
  "count": 278,
  "next": "http://185.215.167.79:8010/api/produit/?page=2",
  "previous": null,
  "results": [
    {
      "id": 12,
      "nom": "Coque iPhone 15",
      "nom_complet": "Apple Coque iPhone 15",
      "prix_vente": 25000.0,
      "photo": "http://185.215.167.79:8010/media/products/coque-15.jpg",
      "categorie": { "id": 1, "nom": "Coques" },
      "sous_type": { "id": 4, "nom": "iPhone" },
      "marque": { "id": 3, "nom": "Apple" },
      "boutique": { "id": 2, "nom": "Boutique Centre" },
      "disponible": true,
      "variantes": [
        { "id": 40, "couleur": "Noir", "disponible": true },
        { "id": 41, "couleur": "Rouge", "disponible": false }
      ]
    }
  ]
}
```

Erreurs : `400` — `{"detail": "min_price / max_price doivent être des nombres."}`.

### `GET /api/produit/{id}/` — Détail d'un produit
**Rôle** : public · **Vue** : `PublicProduitViewSet`

Réponse `200` : même objet qu'un élément de `results` ci-dessus. Erreurs : `404` (produit inexistant ou inactif).

### Compte client

### `POST /api/client/register/` — Inscription
**Rôle** : public (20/min) · **Vue** : `ClientRegisterView`

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| email | corps | string | oui | Unique (insensible à la casse). |
| password | corps | string | oui | 8 caractères minimum. |
| nom | corps | string | oui | Nom complet. |
| telephone | corps | string | oui | `+261XXXXXXXXX`. |
| adresse | corps | string | non | Adresse par défaut des livraisons. |

Requête :
```json
{ "email": "alice@example.mg", "password": "MotDePasse123", "nom": "Alice Rakoto", "telephone": "+261340000001", "adresse": "Lot II A Antananarivo" }
```

Réponse `201` :
```json
{
  "client": { "id": 1, "email": "alice@example.mg", "nom": "Alice Rakoto", "telephone": "+261340000001", "adresse": "Lot II A Antananarivo", "created_at": "2026-09-13T14:02:11.120000+03:00", "last_login": "2026-09-13T14:02:11.130000+03:00" },
  "refresh": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "access": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

Erreurs : `400` — `{"email": ["Un compte existe déjà avec cet e-mail."]}`, `{"password": ["Ensure this field has at least 8 characters."]}`, `{"telephone": ["Format attendu : +261XXXXXXXXX"]}` ; `429` limitation de débit.

### `POST /api/client/login/` — Connexion
**Rôle** : public (20/min) · **Vue** : `ClientLoginView`

Requête :
```json
{ "email": "alice@example.mg", "password": "MotDePasse123" }
```

Réponse `200` : `{ "client": {…}, "refresh": "…", "access": "…" }` (même forme que l'inscription).

Erreurs : `401` — `{"detail": "E-mail ou mot de passe incorrect."}` (message identique que l'e-mail existe ou non) ; `403` — `{"detail": "Compte désactivé."}`.

### `POST /api/client/refresh/` — Renouveler l'access
**Rôle** : public (20/min) · **Vue** : `ClientRefreshView`

Requête :
```json
{ "refresh": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..." }
```

Réponse `200` :
```json
{ "access": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..." }
```

Erreurs : `401` — `{"detail": "Jeton invalide ou expiré : …"}` (y compris un refresh interne présenté ici).

### `GET /api/client/me/` — Profil
**Rôle** : client · **Vue** : `ClientMeView`

Réponse `200` :
```json
{ "id": 1, "email": "alice@example.mg", "nom": "Alice Rakoto", "telephone": "+261340000001", "adresse": "Lot II A Antananarivo", "created_at": "2026-09-13T14:02:11.120000+03:00", "last_login": "2026-09-13T15:10:00.000000+03:00" }
```

Erreurs : `401` — `{"detail": "Authentication credentials were not provided."}` / `{"detail": "Ce jeton n'est pas un jeton client."}`.

### `PATCH /api/client/me/` — Modifier le profil
**Rôle** : client · **Vue** : `ClientMeView` · champs modifiables : `nom`, `telephone`, `adresse` (l'e-mail est en lecture seule).

Requête :
```json
{ "adresse": "Ivandry, Antananarivo", "telephone": "+261330000002" }
```

Réponse `200` : profil mis à jour (même forme que `GET`). Erreurs : `400` — `{"telephone": ["Format attendu : +261XXXXXXXXX"]}`.

### `POST /api/client/change-password/` — Changer de mot de passe
**Rôle** : client · **Vue** : `ClientChangePasswordView`

Requête :
```json
{ "ancien_mot_de_passe": "MotDePasse123", "nouveau_mot_de_passe": "NouveauPass456" }
```

Réponse `200` : `{ "detail": "Mot de passe modifié." }`. Erreurs : `400` — `{"ancien_mot_de_passe": ["Mot de passe actuel incorrect."]}`, `{"nouveau_mot_de_passe": ["Ensure this field has at least 8 characters."]}`.

### Commandes du client

Forme d'une commande côté client (aucune donnée interne : ni préparateur, ni livreur, ni notes du gérant, ni photos) :
```json
{
  "id": 981,
  "numero": "CMD-2-20260913-0007",
  "statut": "EN_ATTENTE_APPROBATION",
  "statut_label": "En attente d'approbation",
  "date_commande": "2026-09-13T14:20:05.410000+03:00",
  "boutique": { "id": 2, "nom": "Boutique Centre" },
  "livraison_zone": "CENTREVILLE",
  "adresse_livraison": "Lot II A Antananarivo",
  "telephone": "+261340000001",
  "telephone_2": "",
  "mode_paiement": "LIVRAISON",
  "note": "Appeler avant de passer",
  "frais_livraison": 3000.0,
  "total_a_payer": 53000.0,
  "items": [
    { "id": 1501, "produit": { "id": 12, "nom": "Coque iPhone 15", "nom_complet": "Apple Coque iPhone 15" }, "variante": { "id": 40, "couleur": "Noir" }, "quantite": 2, "prix_unitaire": 25000.0, "total": 50000.0, "retourne": false }
  ],
  "peut_modifier": true,
  "peut_annuler": true,
  "created_at": "2026-09-13T14:20:05.412000+03:00",
  "updated_at": "2026-09-13T14:20:05.412000+03:00"
}
```

Statuts vus par le client : `EN_ATTENTE_APPROBATION` → (approbation du gérant) `NOUVELLE` → `EN_PREPARATION` → `PRETE` → `EN_LIVRAISON` → `LIVRE` | `RETOUR` ; `ANNULEE` (refus du gérant, annulation par le client ou par la boutique). `peut_modifier` = en attente d'approbation ; `peut_annuler` = en attente ou nouvelle.

### `GET /api/client/orders/` — Mes commandes
**Rôle** : client · **Vue** : `ClientOrderViewSet.list` · `?statut=NOUVELLE,EN_LIVRAISON` (facultatif, valeurs séparées par des virgules)

Réponse `200` : tableau de commandes (forme ci-dessus), les plus récentes en premier.

### `POST /api/client/orders/` — Passer une commande
**Rôle** : client (60/min) · **Vue** : `ClientOrderViewSet.create` → `clients/services.py::create_client_order`

Effet : vérifie sous verrou que chaque variante est active, appartient à la boutique, a un stock suffisant et (si `prix_attendu` est fourni) que son prix n'a pas changé ; crée la commande en `EN_ATTENTE_APPROBATION` aux prix catalogue du moment, calcule frais et total, notifie le gérant. **Le stock n'est pas touché** : il sort, comme pour toute commande, au passage « En préparation ».

| Paramètre | Où | Type | Obligatoire | Description |
| --- | --- | --- | --- | --- |
| boutique | corps | int | oui | Boutique (tous les articles doivent en faire partie). |
| items | corps | liste | oui | `[{ "variante": id, "quantite": n, "prix_attendu": "25000.00" }]` — `prix_attendu` facultatif. |
| livraison_zone | corps | string | oui | `code` d'une zone de la boutique ou `RECUPERATION`. |
| adresse_livraison | corps | string | non | Requise pour une livraison si le profil n'a pas d'adresse. |
| telephone / telephone_2 | corps | string | non | `+261XXXXXXXXX` (défaut : téléphone du profil). |
| mode_paiement | corps | `AVANT` \| `LIVRAISON` | non | Défaut `LIVRAISON`. |
| note | corps | string | non | Consigne pour la livraison. |

Requête :
```json
{
  "boutique": 2,
  "livraison_zone": "CENTREVILLE",
  "adresse_livraison": "Lot II A Antananarivo",
  "mode_paiement": "LIVRAISON",
  "note": "Appeler avant de passer",
  "items": [
    { "variante": 40, "quantite": 2, "prix_attendu": "25000.00" }
  ]
}
```

Réponse `201` : la commande créée (forme ci-dessus).

Erreurs `400` :
- `{"items": ["Stock insuffisant pour « Coque iPhone 15 (Noir) » : 1 disponible(s), 2 demandé(s)."]}`
- `{"items": ["Le prix de « Coque iPhone 15 » a changé : 25000 Ar (vous aviez 20000 Ar)."]}`
- `{"items": ["Article 999 indisponible."]}` (variante inconnue ou référence inactive)
- `{"items": ["L'article « Chargeur 25W » n'appartient pas à cette boutique."]}`
- `{"livraison_zone": ["Zone de livraison invalide pour cette boutique."]}`
- `{"adresse_livraison": ["Adresse de livraison requise pour une livraison."]}`
- `{"boutique": ["Boutique introuvable."]}`, `{"items": ["Ajoutez au moins un article."]}`

### `GET /api/client/orders/{id}/` — Suivi d'une commande
**Rôle** : client · **Vue** : `ClientOrderViewSet.retrieve`

Réponse `200` : la commande. Erreurs : `404` — `{"detail": "No Order matches the given query."}` (commande d'un autre client ou inexistante).

### `PATCH /api/client/orders/{id}/` — Modifier une commande en attente
**Rôle** : client · **Vue** : `ClientOrderViewSet.partial_update` → `update_client_order`

Effet : uniquement tant que la commande est `EN_ATTENTE_APPROBATION`. Champs : `adresse_livraison`, `telephone`, `telephone_2`, `livraison_zone`, `mode_paiement`, `note` (les articles ne se modifient pas : annuler puis recommander). Changer la zone recalcule frais et total.

Requête :
```json
{ "livraison_zone": "RECUPERATION", "note": "Je passe samedi matin" }
```

Réponse `200` : la commande mise à jour (`frais_livraison` 0, `adresse_livraison` vidée pour un retrait).

Erreurs : `400` — `{"detail": ["Cette commande est 'Nouvelle' — elle ne peut plus être modifiée depuis l'espace client."]}`, `{"livraison_zone": ["Zone de livraison invalide pour cette boutique."]}`, `{"detail": ["Aucune modification demandée."]}` ; `404`.

### `POST /api/client/orders/{id}/cancel/` — Annuler une commande
**Rôle** : client · **Vue** : `ClientOrderViewSet.cancel` → `orders/services.py::annuler_commande_par_client`

Effet : possible tant que la commande est `EN_ATTENTE_APPROBATION` ou `NOUVELLE` (stock intact) ; passe en `ANNULEE`, trace « Annulée par le client — motif » dans l'historique, notifie la boutique.

Requête :
```json
{ "note": "Changement d'avis" }
```

Réponse `200` : la commande (`statut` = `ANNULEE`, `peut_annuler` = `false`).

Erreurs : `400` — `{"detail": ["Cette commande est 'En préparation' — elle ne peut plus être annulée depuis l'espace client, contactez la boutique."]}` ; `404`.

### Côté gérant (API interne, ajouts)

Les commandes client apparaissent dans `GET /api/orders/` (gérant) avec le statut `EN_ATTENTE_APPROBATION` et trois champs additionnels dans `OrderGerantSerializer` : `client` (id du compte client, `null` en interne), `client_email`, `est_commande_client` (`true`/`false`). Les préparateurs et livreurs ne les voient qu'une fois approuvées et assignées, comme toute commande. Le gérant peut aussi les corriger (`PATCH /api/orders/{id}/`, régime complet) avant approbation.

### `POST /api/orders/{id}/approuver/` — Approuver une commande client
**Rôle** : gérant (`IsGerant`) · **Vue** : `OrderViewSet.approuver` → `orders/services.py::approuver_commande_client`

Effet : `EN_ATTENTE_APPROBATION` → `NOUVELLE`, entrée d'historique, notification des préparateurs (comme une commande interne) et notification « commande approuvée ».

Requête (facultative) :
```json
{ "note": "Validée par téléphone" }
```

Réponse `200` : la commande (vue gérant complète, `statut_courant` = `NOUVELLE`).

Erreurs : `400` — `["Cette commande est 'Nouvelle' — seule une commande en attente d'approbation peut être approuvée."]` ; `403` pour un préparateur / livreur.

### `POST /api/orders/{id}/refuser/` — Refuser une commande client
**Rôle** : gérant · **Vue** : `OrderViewSet.refuser` → `refuser_commande_client`

Effet : `EN_ATTENTE_APPROBATION` → `ANNULEE` (aucun stock n'avait été touché), motif dans l'historique.

Requête :
```json
{ "note": "Rupture fournisseur" }
```

Réponse `200` : la commande (`statut_courant` = `ANNULEE`). Erreurs : `400` si la commande n'est pas en attente ; `403` hors gérant.
