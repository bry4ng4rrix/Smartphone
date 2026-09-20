# API de l'espace client — Smartphone.Mg

Référence des routes destinées à **l'application client** (boutique en ligne web/mobile) : catalogue public, compte client, panier et commandes. C'est l'unique document nécessaire pour développer l'app client : les routes de l'application de gestion interne (`/api/users/`, `/api/catalog/`, `/api/orders/`, `/api/suppliers/`, `/api/finance/`) ne le concernent pas et **ne sont jamais accessibles** avec un jeton client.

Tous les exemples de ce document sont des **réponses réelles** capturées sur la base de test (`python manage.py test clients`), avec le jeu de données suivant : boutique 1 « Boutique Centre », catégorie « Coques » → sous-type « iPhone » → marque « Apple » → produit « Coque iPhone 15 » à 25 000 Ar (couleur Noir en stock, Rouge épuisée), zone `CENTREVILLE` à 3 000 Ar, cliente `alice@test.com`.

---

## Sommaire

- [1. Conventions](#1-conventions)
- [2. Authentification](#2-authentification)
- [3. Catalogue public](#3-catalogue-public)
  - [GET /api/boutiques/](#get-apiboutiques--liste-des-boutiques)
  - [GET /api/boutiques/{id}/zones/](#get-apiboutiquesidzones--zones-de-livraison-dune-boutique)
  - [GET /api/categories/](#get-apicategories--catégories-alias-apitype)
  - [GET /api/sous-type/](#get-apisous-type--sous-types)
  - [GET /api/marque/](#get-apimarque--marques)
  - [GET /api/couleurs/](#get-apicouleurs--couleurs)
  - [GET /api/produit/](#get-apiproduit--catalogue-paginé)
  - [GET /api/produit/{id}/](#get-apiproduitid--fiche-produit)
- [4. Compte client](#4-compte-client)
  - [POST /api/client/register/](#post-apiclientregister--créer-un-compte)
  - [POST /api/client/login/](#post-apiclientlogin--se-connecter)
  - [POST /api/client/refresh/](#post-apiclientrefresh--renouveler-laccess)
  - [GET/PATCH /api/client/me/](#getpatch-apiclientme--profil)
  - [POST /api/client/change-password/](#post-apiclientchange-password--changer-de-mot-de-passe)
- [5. Commandes du client](#5-commandes-du-client)
  - [POST /api/client/orders/](#post-apiclientorders--passer-commande)
  - [GET /api/client/orders/](#get-apiclientorders--mes-commandes)
  - [GET /api/client/orders/{id}/](#get-apiclientordersid--détail-dune-commande)
  - [PATCH /api/client/orders/{id}/](#patch-apiclientordersid--modifier-avant-approbation)
  - [POST /api/client/orders/{id}/cancel/](#post-apiclientordersidcancel--annuler)
- [6. Cycle de vie d'une commande](#6-cycle-de-vie-dune-commande)
- [7. Erreurs et limitation de débit](#7-erreurs-et-limitation-de-débit)
- [8. Ce que l'API client n'expose jamais](#8-ce-que-lapi-client-nexpose-jamais)
- [9. Fonctionnalités frontend supplémentaires](#9-fonctionnalités-frontend-supplémentaires)
- [10. Propositions d'évolution API](#10-propositions-dévolution-api)
- [11. Architecture du front client](#11-architecture-du-front-client)

---

## 1. Conventions

| | |
| --- | --- |
| **Base d'URL** | `http://185.215.167.79:8010/api/` (production) · `http://localhost:8010/api/` (développement) |
| **Format** | JSON (`Content-Type: application/json`) en entrée et en sortie |
| **Fuseau horaire** | `Indian/Antananarivo` (UTC+3). Toutes les dates sont ISO 8601 avec décalage : `2026-09-20T10:00:41.993449+03:00` |
| **Montants** | Ariary (MGA), **nombres JSON** et non chaînes : `25000.0`, `53000.0` |
| **Téléphone** | Format strict `+261XXXXXXXXX` (13 caractères). Sinon : `{"telephone": ["Format attendu : +261XXXXXXXXX"]}` |
| **Langue** | Les messages **métier** (stock, prix, zone, statut) sont en français et affichables tels quels. Les messages de **validation de format** viennent du framework et sont en anglais (`"This field is required."`, `"Enter a valid email address."`, `"Ensure this field has at least 8 characters."`) : les traduire dans l'app |

Un client ne voit et ne modifie **que ses propres données**. Toute commande demandée par id qui ne lui appartient pas répond `404` (et non `403`) : l'API ne révèle pas l'existence des commandes des autres.

---

## 2. Authentification

Deux mondes étanches partagent le même serveur :

| | Application de gestion | **Application client** |
| --- | --- | --- |
| Compte | `users.CustomUser` (admin / gérant / employé) | `clients.Client` |
| Connexion | `/api/users/login/` | `/api/client/login/` |
| Revendication JWT | `user_id` | **`client_id`** |
| Accès aux routes de l'autre monde | refusé | refusé |

Un jeton client présenté à une route interne est rejeté, et inversement — il n'y a donc rien à filtrer côté application.

**En-tête à envoyer** sur toutes les routes authentifiées :

```http
Authorization: Bearer <access>
```

Durées : l'`access` est court (≈ 5 min), le `refresh` long (≈ 1 jour). Quand une requête renvoie `401`, appeler `/api/client/refresh/` puis rejouer la requête ; si le refresh échoue lui aussi, renvoyer l'utilisateur vers l'écran de connexion.

Sans en-tête, sur une route protégée :

```json
{ "detail": "Authentication credentials were not provided." }
```

Les routes du **catalogue public** (section 3) ne demandent aucune authentification : on peut afficher toute la boutique avant même d'avoir un compte, et ne demander la connexion qu'au moment de valider le panier.

---

## 3. Catalogue public

Toutes ces routes acceptent `?boutique=<id>` pour ne garder que le catalogue d'une boutique. Aucune authentification, aucune donnée interne.

### `GET /api/boutiques/` — liste des boutiques

```json
[
  { "id": 1, "nom": "Boutique Centre", "description": null, "logo": null },
  { "id": 2, "nom": "Boutique Nord", "description": null, "logo": null }
]
```

`logo` est une URL absolue quand la boutique en a une (`http://185.215.167.79:8010/media/shop_logo/...`).

### `GET /api/boutiques/{id}/zones/` — zones de livraison d'une boutique

Le `code` renvoyé ici est **exactement** ce qu'il faut remettre dans `livraison_zone` à la commande.

```json
{
  "boutique": 1,
  "recuperation": { "code": "RECUPERATION", "nom": "Retrait sur place", "prix": 0 },
  "zones": [
    { "code": "CENTREVILLE", "nom": "Centre-ville", "prix": 3000.0 }
  ]
}
```

`RECUPERATION` (retrait en boutique) est toujours proposé, sans frais et sans adresse.

### `GET /api/categories/` — catégories (alias : `/api/type/`)

`?boutique=1`

```json
[ { "id": 1, "nom": "Coques", "avec_couleurs": true, "boutique": 1 } ]
```

`avec_couleurs: false` signifie que les produits de cette catégorie n'ont qu'une variante technique : inutile d'afficher un sélecteur de couleur.

### `GET /api/sous-type/` — sous-types

`?boutique=1` · `?category=1` (alias `?categorie=`)

```json
[ { "id": 1, "nom": "iPhone", "categorie": 1, "categorie_nom": "Coques" } ]
```

### `GET /api/marque/` — marques

`?boutique=1`

```json
[ { "id": 1, "nom": "Apple", "boutique": 1 } ]
```

### `GET /api/couleurs/` — couleurs

`?boutique=1`

```json
[ { "id": 1, "nom": "Noir", "boutique": 1 } ]
```

Référentiel des couleurs de la boutique (pour construire un filtre). Les couleurs réellement disponibles d'un produit sont dans `variantes`.

### `GET /api/produit/` — catalogue paginé

**Filtres** (tous cumulables) :

| Paramètre | Effet |
| --- | --- |
| `search` | Cherche dans le nom du produit, la marque, le sous-type et la catégorie |
| `boutique` | Une seule boutique |
| `category` (alias `categorie`, `type`) | Une catégorie |
| `sous_type` | Un sous-type |
| `brand` (alias `marque`) | Une marque |
| `couleur` | Nom de couleur exact, insensible à la casse (`?couleur=Noir`) |
| `available=1` | Seulement les produits avec au moins une couleur en stock |
| `min_price`, `max_price` | Bornes de prix en Ariary |
| `page`, `page_size` | Pagination — 24 par page par défaut, 100 maximum |

`GET /api/produit/?boutique=1&available=1`

```json
{
  "count": 1,
  "next": null,
  "previous": null,
  "results": [
    {
      "id": 1,
      "nom": "Coque iPhone 15",
      "nom_complet": "Apple Coque iPhone 15",
      "prix_vente": 25000.0,
      "photo": null,
      "categorie": { "id": 1, "nom": "Coques" },
      "sous_type": { "id": 1, "nom": "iPhone" },
      "marque": { "id": 1, "nom": "Apple" },
      "boutique": { "id": 1, "nom": "Boutique Centre" },
      "disponible": true,
      "variantes": [
        { "id": 1, "couleur": "Noir", "disponible": true },
        { "id": 2, "couleur": "Rouge", "disponible": false }
      ]
    }
  ]
}
```

Points importants pour l'app :

- **`variantes[].id` est ce qu'il faut envoyer comme `variante`** dans le panier — jamais l'`id` du produit.
- `disponible` est un simple booléen : la quantité exacte en stock n'est jamais exposée. Afficher « Disponible » / « Épuisé », pas un nombre.
- `prix_vente` est le prix du produit (toutes couleurs confondues).
- `min_price`/`max_price` non numériques → `400 {"detail": "min_price / max_price doivent être des nombres."}`.

### `GET /api/produit/{id}/` — fiche produit

Même objet que dans `results`, non paginé :

```json
{
  "id": 1,
  "nom": "Coque iPhone 15",
  "nom_complet": "Apple Coque iPhone 15",
  "prix_vente": 25000.0,
  "photo": null,
  "categorie": { "id": 1, "nom": "Coques" },
  "sous_type": { "id": 1, "nom": "iPhone" },
  "marque": { "id": 1, "nom": "Apple" },
  "boutique": { "id": 1, "nom": "Boutique Centre" },
  "disponible": true,
  "variantes": [
    { "id": 1, "couleur": "Noir", "disponible": true },
    { "id": 2, "couleur": "Rouge", "disponible": false }
  ]
}
```

Seuls les produits **actifs** apparaissent ; un produit retiré du catalogue renvoie `404`.

---

## 4. Compte client

### `POST /api/client/register/` — créer un compte

| Champ | Obligatoire | Règle |
| --- | --- | --- |
| `email` | oui | Unique, normalisé en minuscules |
| `password` | oui | 8 caractères minimum |
| `nom` | oui | Non vide |
| `telephone` | oui | `+261XXXXXXXXX` |
| `adresse` | non | Adresse par défaut, réutilisée à la commande |

Requête :

```json
{
  "email": "carla@test.com",
  "password": "MotDePasse123",
  "nom": "Carla Rakoto",
  "telephone": "+261341112233",
  "adresse": "Lot II B Ankorondrano"
}
```

Réponse `201` — le compte est créé **et** connecté, il n'y a pas besoin d'enchaîner sur `/login/` :

```json
{
  "client": {
    "id": 3,
    "email": "carla@test.com",
    "nom": "Carla Rakoto",
    "telephone": "+261341112233",
    "adresse": "Lot II B Ankorondrano",
    "created_at": "2026-09-20T10:00:39.269749+03:00",
    "last_login": "2026-09-20T10:00:39.270034+03:00"
  },
  "refresh": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ0b2tlbl90eXBlIjoicmVmcmVzaCIsImV4cCI6MTc4OTk3NDAzOSwiY2xpZW50X2lkIjozfQ...",
  "access": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ0b2tlbl90eXBlIjoiYWNjZXNzIiwiZXhwIjoxNzg5ODg3OTM5LCJjbGllbnRfaWQiOjN9..."
}
```

E-mail déjà pris → `400` :

```json
{ "email": ["Un compte existe déjà avec cet e-mail."] }
```

Champs manquants ou mal formés → `400`, un tableau de messages par champ :

```json
{
  "email": ["Enter a valid email address."],
  "password": ["Ensure this field has at least 8 characters."],
  "nom": ["This field may not be blank."],
  "telephone": ["Format attendu : +261XXXXXXXXX"]
}
```

### `POST /api/client/login/` — se connecter

```json
{ "email": "alice@test.com", "password": "MotDePasse123" }
```

Réponse `200` : même forme que `register` (`client` + `refresh` + `access`).

```json
{
  "client": {
    "id": 1,
    "email": "alice@test.com",
    "nom": "Alice",
    "telephone": "+261340000001",
    "adresse": "Lot II A Antananarivo",
    "created_at": "2026-09-20T10:00:37.862409+03:00",
    "last_login": "2026-09-20T10:00:40.041063+03:00"
  },
  "refresh": "eyJ...",
  "access": "eyJ..."
}
```

Identifiants faux → `401` (même message que l'e-mail existe ou non, pour ne pas révéler les comptes) :

```json
{ "detail": "E-mail ou mot de passe incorrect." }
```

Compte désactivé par la boutique → `403 {"detail": "Compte désactivé."}`.

### `POST /api/client/refresh/` — renouveler l'access

```json
{ "refresh": "eyJhbGciOiJIUzI1NiIs..." }
```

```json
{ "access": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ0b2tlbl90eXBlIjoiYWNjZXNzIiwiY2xpZW50X2lkIjoxfQ..." }
```

Refresh expiré, invalide ou jeton interne → `401 {"detail": "Jeton invalide ou expiré : …"}`.

### `GET`/`PATCH` `/api/client/me/` — profil

`GET` :

```json
{
  "id": 1,
  "email": "alice@test.com",
  "nom": "Alice",
  "telephone": "+261340000001",
  "adresse": "Lot II A Antananarivo",
  "created_at": "2026-09-20T10:00:37.862409+03:00",
  "last_login": "2026-09-20T10:00:40.041063+03:00"
}
```

`PATCH` — modifiables : `nom`, `telephone`, `adresse`. L'`email` est en lecture seule.

```json
{ "nom": "Alice R.", "telephone": "+261340000009", "adresse": "Lot II A Antananarivo" }
```

```json
{
  "id": 1,
  "email": "alice@test.com",
  "nom": "Alice R.",
  "telephone": "+261340000009",
  "adresse": "Lot II A Antananarivo",
  "created_at": "2026-09-20T10:00:37.862409+03:00",
  "last_login": "2026-09-20T10:00:40.041063+03:00"
}
```

### `POST /api/client/change-password/` — changer de mot de passe

```json
{ "ancien_mot_de_passe": "MotDePasse123", "nouveau_mot_de_passe": "NouveauPass123" }
```

```json
{ "detail": "Mot de passe modifié." }
```

Ancien mot de passe faux → `400 {"ancien_mot_de_passe": ["Mot de passe actuel incorrect."]}`. Nouveau trop court → `400 {"nouveau_mot_de_passe": ["Ensure this field has at least 8 characters."]}`. Les jetons déjà émis restent valides jusqu'à leur expiration.

---

## 5. Commandes du client

Toutes ces routes exigent `Authorization: Bearer <access>`.

### `POST /api/client/orders/` — passer commande

| Champ | Obligatoire | Description |
| --- | --- | --- |
| `boutique` | oui | Id de la boutique. **Tous les articles doivent lui appartenir** |
| `items` | oui | Liste de `{variante, quantite, prix_attendu?}`, au moins un élément |
| `items[].variante` | oui | Id d'une **variante** (`variantes[].id` du catalogue), pas du produit |
| `items[].quantite` | oui | ≥ 1. Les doublons de variante sont additionnés |
| `items[].prix_attendu` | non | Prix affiché dans l'app. S'il ne correspond plus au catalogue, la commande est refusée avec le nouveau prix |
| `livraison_zone` | oui | `code` d'une zone de la boutique, ou `RECUPERATION` |
| `adresse_livraison` | si livraison | Requise hors retrait sur place, sauf si le profil a déjà une adresse (elle est alors reprise) |
| `telephone` | non | Par défaut celui du profil |
| `telephone_2` | non | Second numéro, `+261XXXXXXXXX` ou chaîne vide |
| `mode_paiement` | non | `LIVRAISON` (défaut) ou `AVANT` |
| `note` | non | Message pour le livreur (« Appeler avant de venir ») |

Requête :

```json
{
  "boutique": 1,
  "items": [
    { "variante": 1, "quantite": 2, "prix_attendu": "25000" }
  ],
  "livraison_zone": "CENTREVILLE",
  "adresse_livraison": "Lot II A Antananarivo",
  "telephone": "+261340000001",
  "mode_paiement": "LIVRAISON",
  "note": "Appeler avant de venir"
}
```

Réponse `201` :

```json
{
  "id": 1,
  "numero": "CMD-1-20260920-0001",
  "statut": "EN_ATTENTE_APPROBATION",
  "statut_label": "En attente d'approbation",
  "date_commande": "2026-09-20T10:00:41.993449+03:00",
  "boutique": { "id": 1, "nom": "Boutique Centre" },
  "livraison_zone": "CENTREVILLE",
  "adresse_livraison": "Lot II A Antananarivo",
  "telephone": "+261340000001",
  "telephone_2": "",
  "mode_paiement": "LIVRAISON",
  "note": "Appeler avant de venir",
  "frais_livraison": 3000.0,
  "total_a_payer": 53000.0,
  "items": [
    {
      "id": 1,
      "produit": { "id": 1, "nom": "Coque iPhone 15", "nom_complet": "Apple Coque iPhone 15" },
      "variante": { "id": 1, "couleur": "Noir" },
      "quantite": 2,
      "prix_unitaire": 25000.0,
      "total": 50000.0,
      "retourne": false
    }
  ],
  "peut_modifier": true,
  "peut_annuler": true,
  "created_at": "2026-09-20T10:00:41.996740+03:00",
  "updated_at": "2026-09-20T10:00:41.996761+03:00"
}
```

- Le **prix et les frais sont calculés par le serveur** : ne jamais envoyer de total, ne jamais recalculer côté app. `total_a_payer = Σ items[].total + frais_livraison` (ici 2 × 25 000 + 3 000 = 53 000).
- La commande naît en `EN_ATTENTE_APPROBATION` : la boutique doit l'approuver. **Aucun stock n'est réservé** à ce stade, la disponibilité est seulement vérifiée.
- `peut_modifier` / `peut_annuler` disent directement s'il faut afficher les boutons correspondants — ne pas déduire ces droits du statut dans l'app.

**Erreurs `400` — articles** (tous les problèmes sont renvoyés d'un coup, chaque message est affichable tel quel) :

```json
{
  "items": [
    "Stock insuffisant pour « Coque iPhone 15 (Rouge) » : 0 disponible(s), 1 demandé(s).",
    "L'article « Chargeur 25W » n'appartient pas à cette boutique."
  ]
}
```

**Prix changé entre l'ajout au panier et la validation** (grâce à `prix_attendu`) :

```json
{ "items": ["Le prix de « Coque iPhone 15 » a changé : 25000 Ar (vous aviez 20000 Ar)."] }
```

→ rafraîchir le panier depuis `/api/produit/` et faire reconfirmer le client.

**Zone inconnue** :

```json
{ "livraison_zone": ["Zone de livraison invalide pour cette boutique."] }
```

**Autres `400` courants** : `{"items": ["Ajoutez au moins un article."]}`, `{"adresse_livraison": ["Adresse de livraison requise pour une livraison."]}`, `{"boutique": ["Boutique introuvable."]}`.

### `GET /api/client/orders/` — mes commandes

Filtre facultatif : `?statut=EN_ATTENTE_APPROBATION,NOUVELLE` (plusieurs valeurs séparées par des virgules). Tri : la plus récente en premier. Réponse non paginée.

```json
[
  {
    "id": 1,
    "numero": "CMD-1-20260920-0001",
    "statut": "EN_ATTENTE_APPROBATION",
    "statut_label": "En attente d'approbation",
    "date_commande": "2026-09-20T10:01:05.490855+03:00",
    "boutique": { "id": 1, "nom": "Boutique Centre" },
    "livraison_zone": "CENTREVILLE",
    "adresse_livraison": "Lot II A Antananarivo",
    "telephone": "+261340000001",
    "telephone_2": "",
    "mode_paiement": "LIVRAISON",
    "note": "Appeler avant de venir",
    "frais_livraison": 3000.0,
    "total_a_payer": 53000.0,
    "items": [
      {
        "id": 1,
        "produit": { "id": 1, "nom": "Coque iPhone 15", "nom_complet": "Apple Coque iPhone 15" },
        "variante": { "id": 1, "couleur": "Noir" },
        "quantite": 2,
        "prix_unitaire": 25000.0,
        "total": 50000.0,
        "retourne": false
      }
    ],
    "peut_modifier": true,
    "peut_annuler": true,
    "created_at": "2026-09-20T10:01:05.496294+03:00",
    "updated_at": "2026-09-20T10:01:05.496322+03:00"
  }
]
```

### `GET /api/client/orders/{id}/` — détail d'une commande

Même objet, seul. Une commande qui n'appartient pas au client connecté :

```json
{ "detail": "No Order matches the given query." }
```

(statut `404`)

### `PATCH /api/client/orders/{id}/` — modifier avant approbation

Possible **uniquement** tant que `peut_modifier` vaut `true` (statut `EN_ATTENTE_APPROBATION`). Champs acceptés : `adresse_livraison`, `telephone`, `telephone_2`, `livraison_zone`, `mode_paiement`, `note`.

**Les articles ne se modifient pas** : pour changer le panier, annuler et repasser commande.

```json
{ "adresse_livraison": "Lot III C Ivandry", "telephone_2": "+261331112244", "note": "Livrer le matin" }
```

Réponse `200` : la commande complète, frais et total recalculés si la zone a changé.

```json
{
  "id": 1,
  "numero": "CMD-1-20260920-0001",
  "statut": "EN_ATTENTE_APPROBATION",
  "statut_label": "En attente d'approbation",
  "livraison_zone": "CENTREVILLE",
  "adresse_livraison": "Lot III C Ivandry",
  "telephone": "+261340000001",
  "telephone_2": "+261331112244",
  "note": "Livrer le matin",
  "frais_livraison": 3000.0,
  "total_a_payer": 53000.0,
  "peut_modifier": true,
  "peut_annuler": true,
  "updated_at": "2026-09-20T10:01:05.565905+03:00"
}
```

Trop tard :

```json
{ "detail": ["Cette commande est 'En préparation' — elle ne peut plus être modifiée depuis l'espace client."] }
```

Aucun champ modifiable envoyé → `400 {"detail": ["Aucune modification demandée."]}`. Passer `livraison_zone: "RECUPERATION"` vide automatiquement l'adresse.

### `POST /api/client/orders/{id}/cancel/` — annuler

Possible tant que `peut_annuler` vaut `true` (statuts `EN_ATTENTE_APPROBATION` et `NOUVELLE`, c'est-à-dire avant le début de la préparation). Corps facultatif :

```json
{ "note": "Erreur de couleur" }
```

Réponse `200` — la commande passe en `ANNULEE`, la boutique est notifiée, le stock éventuellement réservé revient en rayon :

```json
{
  "id": 1,
  "numero": "CMD-1-20260920-0001",
  "statut": "ANNULEE",
  "statut_label": "Annulée",
  "total_a_payer": 53000.0,
  "peut_modifier": false,
  "peut_annuler": false,
  "updated_at": "2026-09-20T10:01:05.594864+03:00"
}
```

Trop tard :

```json
{ "detail": ["Cette commande est 'En préparation' — elle ne peut plus être annulée depuis l'espace client, contactez la boutique."] }
```

---

## 6. Cycle de vie d'une commande

| `statut` | `statut_label` | Ce que voit le client | `peut_modifier` | `peut_annuler` |
| --- | --- | --- | --- | --- |
| `EN_ATTENTE_APPROBATION` | En attente d'approbation | Commande envoyée, la boutique doit la valider | ✅ | ✅ |
| `NOUVELLE` | Nouvelle | Validée par la boutique, articles réservés | ❌ | ✅ |
| `EN_PREPARATION` | En préparation | En cours d'emballage | ❌ | ❌ |
| `PRETE` | Prête | Prête à partir (ou à retirer si `RECUPERATION`) | ❌ | ❌ |
| `EN_LIVRAISON` | En livraison | Le livreur est en route | ❌ | ❌ |
| `LIVRE` | Livré | Terminée | ❌ | ❌ |
| `RETOUR` | Retour | Livraison non aboutie, colis revenu en boutique | ❌ | ❌ |
| `ANNULEE` | Annulée | Annulée par le client ou refusée par la boutique | ❌ | ❌ |

```
      app client                    boutique (gestion)
   POST /client/orders/
           │
  EN_ATTENTE_APPROBATION ──approuve──> NOUVELLE ──> EN_PREPARATION ──> PRETE ──> EN_LIVRAISON ──> LIVRE
           │        │                     │                                            └──> RETOUR
           │        └──refuse──> ANNULEE  │
           └──cancel──> ANNULEE ──────────┘
```

Côté boutique, le gérant **approuve** (la commande passe en `NOUVELLE` et le stock est réservé) ou **refuse** (elle passe directement en `ANNULEE`, aucun stock touché) ; dans les deux cas le client le voit au prochain chargement de ses commandes.

Il n'y a **pas de WebSocket côté client** : pour suivre l'avancement, recharger `GET /api/client/orders/` (par exemple à l'ouverture de l'écran et par un « tirer pour rafraîchir »).

Un article marqué `retourne: true` dans `items` a été rapporté par le livreur (le client n'en a pas voulu) : son `total` passe à `0` et il sort du `total_a_payer`.

---

## 7. Erreurs et limitation de débit

| Code | Signification | Réaction conseillée dans l'app |
| --- | --- | --- |
| `400` | Données invalides — corps `{champ: [messages]}` ou `{"detail": [messages]}` | Afficher les messages métier tels quels (français) ; traduire les messages de format du framework (anglais) |
| `401` | Jeton absent, invalide ou expiré | Tenter `/api/client/refresh/`, sinon déconnecter |
| `403` | Compte désactivé, ou jeton interne sur une route client | Message « Compte désactivé, contactez la boutique » |
| `404` | Ressource inexistante **ou appartenant à un autre client** | « Commande introuvable » |
| `429` | Trop de requêtes | Attendre et réessayer (voir ci-dessous) |

**Limitation de débit**, par adresse IP :

| Portée | Routes | Limite |
| --- | --- | --- |
| `client_public` | Catalogue (section 3) | 300 requêtes / minute |
| `client_auth` | `register`, `login`, `refresh` | 20 requêtes / minute |
| `client_orders` | `/api/client/orders/…` | 60 requêtes / minute |

Réponse `429` : `{"detail": "Request was throttled. Expected available in 42 seconds."}` — l'en-tête `Retry-After` donne le délai en secondes.

---

## 8. Ce que l'API client n'expose jamais

Volontairement absent de toutes les réponses ci-dessus, et inaccessible avec un jeton client :

- prix d'achat, marges, coûts de revient, chiffre d'affaires ;
- quantités en stock (seulement `disponible: true/false`) et seuils d'alerte ;
- personnel de la boutique : préparateur, livreur, gérant, leurs notes internes et leurs photos de préparation ;
- caisse, dépenses, campagnes publicitaires, rapports, approvisionnements fournisseur ;
- commandes des autres clients, y compris par id.

L'application cliente n'a donc besoin d'aucun filtrage de sécurité de son côté : tout ce qu'elle reçoit est destiné au client connecté.

---

## 9. Fonctionnalités frontend supplémentaires

> Cette section décrit des comportements de **l'application cliente uniquement**
> (`clients_frontend/`). Ce ne sont **pas** des endpoints : le backend les
> ignore totalement, et rien ici n'ajoute, ne modifie ni ne contourne une règle
> de l'API décrite plus haut.

### 9.1 Panier local

**Type** : frontend uniquement.

**Description** : l'API ne connaît pas de panier — une commande est créée d'un
bloc par `POST /api/client/orders/`. Le panier est donc construit côté client.

**Stockage** : `localStorage`, clé `smg_client_panier`. Une ligne contient
l'identifiant de variante, la quantité, et une copie d'affichage du produit
(nom, couleur, prix, photo, boutique).

**Comportement** :
- une commande ne pouvant concerner qu'une seule boutique, l'ajout d'un article
  d'une autre boutique demande confirmation et remplace le panier ;
- le prix mémorisé est envoyé comme `prix_attendu` à la création de la commande :
  si la boutique a changé son prix, l'API refuse et le client voit le nouveau prix ;
- le total affiché est explicitement présenté comme **estimatif** ; le montant
  qui fait foi reste `total_a_payer` renvoyé par l'API ;
- le panier est partagé entre les onglets ouverts (événement `storage`).

**Endpoints utilisés** : aucun pour le panier lui-même ; `POST /api/client/orders/`
à la validation.

### 9.2 Favoris

**Type** : frontend uniquement.

**Description** : liste de produits mis de côté, accessible sans compte.

**Stockage** : `localStorage`, clé `smg_client_favoris` — uniquement des
identifiants produit.

**Comportement** : la page `/favoris` recharge chaque fiche via
`GET /api/produit/{id}/`, donc prix et disponibilité sont toujours à jour ; un
produit devenu introuvable (404) est retiré silencieusement de la liste locale.

**Endpoints utilisés** : `GET /api/produit/{id}/`.

### 9.3 Préférence de thème (clair / sombre)

**Type** : frontend uniquement.

**Stockage** : `localStorage`, clé `smg_client_theme`. Sans valeur enregistrée,
la préférence système (`prefers-color-scheme`) s'applique.

### 9.4 Tri des produits affichés

**Type** : frontend uniquement.

**Description** : `GET /api/produit/` n'expose aucun paramètre d'ordre. Le
catalogue propose donc un tri (prix croissant/décroissant, nom) appliqué aux
produits **déjà chargés**, et le libellé du contrôle le dit explicitement
(« Trier les produits affichés »). Les filtres, eux, sont bien envoyés à l'API.

Voir la proposition d'évolution 10.1 pour un tri complet côté serveur.

### 9.5 Chargement progressif du catalogue

**Type** : frontend uniquement.

**Description** : la première page du catalogue est rendue côté serveur (SEO) ;
le bouton « Charger plus de produits » appelle la page suivante avec le
paramètre `page` déjà documenté, et concatène les résultats sans recharger la
page.

**Endpoints utilisés** : `GET /api/produit/?page=N`.

### 9.6 Pastilles de couleur

**Type** : frontend uniquement.

**Description** : l'API renvoie la couleur d'une variante sous forme de texte
(`"Bleu ciel"`). L'interface affiche une pastille colorée à côté du nom, par
correspondance de mots-clés ; un nom inconnu reçoit une teinte stable dérivée
de ses lettres. Aucune donnée n'est inventée : le texte de l'API reste affiché
tel quel à côté de la pastille.

### 9.7 Visuel de remplacement

**Type** : frontend uniquement.

**Description** : quand `photo` vaut `null`, la carte produit affiche une
composition sobre construite à partir des vraies données du produit (marque,
sous-type, couleurs des variantes). Aucune image factice n'est utilisée.

### 9.8 Zone de livraison décidée par la boutique

**Type** : frontend uniquement (le contrat de l'API ne change pas).

**Description** : à la commande, le client choisit seulement **livraison** ou
**retrait sur place**. Il ne choisit plus de zone : c'est la boutique qui la
fixe — et avec elle les frais — au moment de valider la commande, d'après
l'adresse saisie.

**Comportement** :
- `livraison_zone` restant obligatoire côté API, le front envoie
  `RECUPERATION` pour un retrait, et sinon la **première zone** renvoyée par
  `GET /api/boutiques/{id}/zones/` (la moins chère, l'API les ordonne par
  prix) à titre provisoire ;
- le gérant ajuste ensuite la zone depuis l'application de gestion, ce qui
  recalcule `frais_livraison` et `total_a_payer` ;
- aucun montant de livraison n'est donc affiché au client avant validation :
  le récapitulatif indique « Total articles » et « Livraison : fixée par la
  boutique » ;
- l'adresse n'est demandée (et envoyée) que pour une livraison ;
- si la boutique n'a aucune zone active, seul le retrait est proposé ;
- le client ne peut pas non plus changer la zone en modifiant sa commande :
  `PATCH /api/client/orders/{id}/` n'envoie plus `livraison_zone`, pour ne pas
  écraser ce que la boutique a fixé.

**Endpoints utilisés** : `GET /api/boutiques/{id}/zones/`,
`POST /api/client/orders/`, `PATCH /api/client/orders/{id}/`.

### 9.9 Compteur « commandes en attente »

**Type** : frontend uniquement.

**Description** : la barre de navigation mène aux commandes que la boutique
n'a pas encore validées, avec une pastille indiquant leur nombre (elle
remplace l'ancien raccourci « Favoris », toujours accessible depuis le pied
de page).

**Comportement** : lorsque le client est connecté, le compteur est relu à
chaque changement de page — donc juste après une commande ou une annulation.
Hors session, le lien renvoie vers la connexion.

**Endpoint utilisé** : `GET /api/client/orders/?statut=EN_ATTENTE_APPROBATION`.

### 9.10 Montant confirmé par la boutique

**Type** : frontend uniquement.

**Description** : tant que la commande est `EN_ATTENTE_APPROBATION`, aucun
total n'est affiché au client — ni au moment de commander, ni sur la fiche de
suivi. À la place : « En attente de confirmation du gérant ». Le détail des
articles, lui, reste affiché (ce sont les prix catalogue réels).

**Pourquoi** : les frais de livraison dépendent de la zone que la boutique
fixe à la validation (voir 9.8) ; afficher un total avant cela reviendrait à
annoncer un montant qui va changer.

**Comportement** : dès que la commande passe à `NOUVELLE` ou au-delà, la
fiche affiche `total_a_payer` et `frais_livraison` tels que renvoyés par
l'API.

### 9.11 Proxy d'API same-origin

**Type** : frontend uniquement (aucune modification du backend).

**Description** : le backend n'autorise pas l'origine du front client dans
`CORS_ALLOWED_ORIGINS`. Le navigateur n'appelle donc jamais Django
directement : Next réécrit `/backend/<chemin>` vers `<DJANGO_ORIGIN>/api/<chemin>/`
et `/media/<fichier>` vers `<DJANGO_ORIGIN>/media/<fichier>` côté serveur.
Les chemins, corps et en-têtes (dont `Authorization`) sont inchangés — le
contrat d'API décrit dans ce document reste valable tel quel.

> **Note d'exploitation** : la limitation de débit (section 7) est comptée par
> adresse IP. Derrière ce proxy, toutes les requêtes navigateur arrivent avec
> l'IP du serveur Next. Pour retrouver un comptage par visiteur, il suffit
> d'ajouter l'origine publique du front client à la variable d'environnement
> `CORS_ALLOWED_ORIGINS` du backend (aucune modification de code) et de faire
> pointer le front directement sur l'API.

---

## 10. Propositions d'évolution API

> Fonctionnalités utiles qui **nécessiteraient une évolution du backend**.
> Rien de tout cela n'est implémenté ni appelé aujourd'hui : le front
> fonctionne uniquement avec les endpoints des sections 3 à 5.

### 10.1 Tri côté serveur du catalogue

**Fonctionnalité** : trier l'ensemble du catalogue, pas seulement la page chargée.

**Endpoint proposé** : `GET /api/produit/?ordering=prix_vente|-prix_vente|reference_name`.

**Pourquoi** : le tri actuel ne porte que sur les produits déjà reçus ; avec 298
références, « le moins cher d'abord » ne donne pas le vrai premier prix.

**Statut** : à implémenter côté backend ultérieurement.

### 10.2 Nouveautés

**Fonctionnalité** : une section « Nouveautés » en page d'accueil.

**Endpoint proposé** : exposer `created_at` sur `PublicProduitSerializer`, ou
`GET /api/produit/?ordering=-created_at`.

**Pourquoi** : aujourd'hui aucune donnée ne permet de savoir ce qui est récent.
La page d'accueil se limite donc à « Disponibles maintenant »
(`?available=1`), qui est vérifiable.

**Statut** : à implémenter côté backend ultérieurement.

### 10.3 Galerie produit

**Fonctionnalité** : plusieurs visuels par produit, et un visuel par couleur.

**Endpoint proposé** : `photos: [...]` sur le produit, et/ou `photo` sur la variante.

**Pourquoi** : `PublicProduitSerializer` ne renvoie qu'une seule `photo` pour
toute la référence ; la fiche produit ne peut donc pas proposer de galerie.

**Statut** : à implémenter côté backend ultérieurement.

### 10.4 Réinitialisation du mot de passe

**Fonctionnalité** : « mot de passe oublié » pour un client.

**Endpoints proposés** : `POST /api/client/password-reset/` et
`POST /api/client/password-reset/confirm/`.

**Pourquoi** : `POST /api/client/change-password/` exige le mot de passe
actuel ; un client qui l'a perdu n'a aujourd'hui aucun recours en ligne.

**Statut** : à implémenter côté backend ultérieurement.

---

## 11. Architecture du front client

L'application cliente vit dans `clients_frontend/` (Next.js 16, App Router,
React 19, Tailwind CSS v4, TypeScript). Elle écoute le port **3000**, distinct
du front de gestion (3010) et de l'API (8010).

| Dossier | Rôle |
| --- | --- |
| `app/` | Routes : accueil, `catalogue`, `produit/[id]`, `panier`, `checkout`, `connexion`, `inscription`, `favoris`, `compte` (profil, commandes, suivi) |
| `components/` | UI (`ui/`), enveloppe du site (`layout/`), catalogue, fiche produit, panier, checkout, commandes, compte |
| `lib/` | `api.ts` (fetch + JWT + refresh), `endpoints.ts` (une fonction par route), `types.ts`, `statuts.ts`, `store.ts`, utilitaires |
| `providers/` | Session client, panier, favoris, thème, notifications |

**Rendu** : le catalogue et les fiches produit sont rendus côté serveur (appel
direct à Django, bon pour le référencement) ; tout ce qui dépend du compte
(panier, commandes, profil) est rendu côté client avec le jeton du visiteur.

**Jetons** : `access` et `refresh` en `localStorage`. Sur `401`, un seul refresh
est lancé pour toutes les requêtes en attente, puis la requête est rejouée ; si
le refresh échoue, les jetons sont effacés et le visiteur est redirigé vers la
connexion.

