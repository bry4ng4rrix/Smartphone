# API Espace client — Smartphone.Mg

Référence des endpoints ajoutés pour le futur espace client en ligne (web / mobile).
Extension du backend Django existant (app `clients`) : le catalogue et les commandes sont ceux de
l'application de gestion, sans duplication ; les données internes (prix d'achat, marges, stock chiffré,
personnel, caisse, rapports) ne sont jamais exposées.

- **Base URL** : production `http://185.215.167.79:8010/api` · local `http://127.0.0.1:8010/api`
- **Authentification client** : `POST /api/client/login/` → `{ access, refresh }`, puis `Authorization: Bearer <access>`
  (access 5 min, refresh 24 h, `POST /api/client/refresh/`). Les jetons clients portent `client_id` : ils sont refusés
  par l'API interne, et les jetons internes sont refusés ici.
- **Dates** ISO 8601 en heure d'Antananarivo (`+03:00`) · **montants** en Ar (nombres) · **erreurs** `{"champ": ["message"]}` ou `{"detail": "…"}`.
- Référence complète de toute l'API (routes internes comprises) : `endpoint.md`.

## Sommaire

- **Catalogue public**
  - [GET /api/boutiques/ — Boutiques](#get-apiboutiques-boutiques)
  - [GET /api/boutiques/{id}/zones/ — Zones de livraison d'une boutique](#get-apiboutiquesidzones-zones-de-livraison-dune-boutique)
  - [GET /api/categories/ — Catégories (alias : GET /api/type/)](#get-apicategories-catégories-alias-get-apitype)
  - [GET /api/sous-type/ — Sous-types](#get-apisous-type-sous-types)
  - [GET /api/marque/ — Marques](#get-apimarque-marques)
  - [GET /api/couleurs/ — Couleurs](#get-apicouleurs-couleurs)
  - [GET /api/produit/ — Produits (liste paginée)](#get-apiproduit-produits-liste-paginée)
  - [GET /api/produit/{id}/ — Détail d'un produit](#get-apiproduitid-détail-dun-produit)
- **Compte client**
  - [POST /api/client/register/ — Inscription](#post-apiclientregister-inscription)
  - [POST /api/client/login/ — Connexion](#post-apiclientlogin-connexion)
  - [POST /api/client/refresh/ — Renouveler l'access](#post-apiclientrefresh-renouveler-laccess)
  - [GET /api/client/me/ — Profil](#get-apiclientme-profil)
  - [PATCH /api/client/me/ — Modifier le profil](#patch-apiclientme-modifier-le-profil)
  - [POST /api/client/change-password/ — Changer de mot de passe](#post-apiclientchange-password-changer-de-mot-de-passe)
- **Commandes du client**
  - [GET /api/client/orders/ — Mes commandes](#get-apiclientorders-mes-commandes)
  - [POST /api/client/orders/ — Passer une commande](#post-apiclientorders-passer-une-commande)
  - [GET /api/client/orders/{id}/ — Suivi d'une commande](#get-apiclientordersid-suivi-dune-commande)
  - [PATCH /api/client/orders/{id}/ — Modifier une commande en attente](#patch-apiclientordersid-modifier-une-commande-en-attente)
  - [POST /api/client/orders/{id}/cancel/ — Annuler une commande](#post-apiclientordersidcancel-annuler-une-commande)
- **Côté gérant (API interne, ajouts)**
  - [POST /api/orders/{id}/approuver/ — Approuver une commande client](#post-apiordersidapprouver-approuver-une-commande-client)
  - [POST /api/orders/{id}/refuser/ — Refuser une commande client](#post-apiordersidrefuser-refuser-une-commande-client)

---

## Espace client (app `clients`)

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
