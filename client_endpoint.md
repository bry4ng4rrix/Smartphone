# API de la boutique en ligne — Smartphone.Mg

Référence des routes destinées à **la boutique en ligne** : catalogue public et
prise de commande. C'est l'unique document nécessaire pour la développer ; les
routes de l'application de gestion interne (`/api/users/`, `/api/catalog/`,
`/api/orders/`, `/api/suppliers/`, `/api/finance/`) ne la concernent pas.

**Tout est public.** La boutique ne demande ni compte ni connexion : on
parcourt le catalogue et on commande directement, et c'est le gérant qui
rappelle au téléphone pour confirmer. Voir la section 2 pour ce que cela
implique — notamment l'absence de suivi en ligne.

Les exemples sont conformes aux tests de `python manage.py test clients`.

---

## Sommaire

- [1. Conventions](#1-conventions)
- [2. Pas d'authentification](#2-pas-dauthentification)
- [3. Catalogue public](#3-catalogue-public)
  - [GET /api/boutiques/](#get-apiboutiques--liste-des-boutiques)
  - [GET /api/boutiques/{id}/zones/](#get-apiboutiquesidzones--modes-de-remise)
  - [GET /api/categories/](#get-apicategories--catégories-alias-apitype)
  - [GET /api/sous-type/](#get-apisous-type--sous-types)
  - [GET /api/marque/](#get-apimarque--marques)
  - [GET /api/couleurs/](#get-apicouleurs--couleurs)
  - [GET /api/produit/](#get-apiproduit--catalogue-paginé)
  - [GET /api/produit/{id}/](#get-apiproduitid--fiche-produit)
- [4. Passer commande](#4-passer-commande)
  - [POST /api/commandes/](#post-apicommandes--passer-commande-sans-compte)
- [5. Cycle de vie d'une commande](#5-cycle-de-vie-dune-commande)
- [6. Erreurs et limitation de débit](#6-erreurs-et-limitation-de-débit)
- [7. Ce que l'API n'expose jamais](#7-ce-que-lapi-nexpose-jamais)
- [8. Fonctionnalités frontend supplémentaires](#8-fonctionnalités-frontend-supplémentaires)
- [9. Propositions d'évolution API](#9-propositions-dévolution-api)
- [10. Architecture du front client](#10-architecture-du-front-client)
- [11. Commande spéciale Housse / Cache-écran](#11-commande-spéciale-housse--cache-écran)

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

Aucune route de cette API ne lit ni ne modifie de données personnelles existantes : il n'y a pas de compte. Les coordonnées (nom, téléphone, adresse) sont fournies à chaque commande et ne servent qu'à celle-ci.

---

## 2. Pas d'authentification

La boutique en ligne ne demande **ni compte, ni connexion, ni jeton**. Toutes
les routes de ce document sont publiques : on parcourt le catalogue et on
commande sans rien créer.

Il n'y a donc **rien à envoyer** : pas d'en-tête `Authorization`, pas de
refresh, pas d'écran de connexion à prévoir.

> **Ce qui a été retiré.** Les routes `/api/client/register/`, `/login/`,
> `/refresh/`, `/me/`, `/change-password/` et tout `/api/client/orders/`
> n'existent plus (elles répondent `404`), et le modèle `clients.Client` a été
> supprimé côté serveur. Une commande passée en ligne n'est plus rattachée à
> un compte : elle porte `Order.origine_en_ligne = True` et ses coordonnées en
> propre (`client_nom`, `telephone`, `telephone_2`, `adresse_livraison`).

**Conséquence à assumer côté produit** : le client ne peut pas revenir
consulter sa commande. Il n'existe aucun endpoint de relecture, parce que sans
compte rien ne permettrait d'authentifier celui qui la demanderait. C'est
l'appel téléphonique du gérant qui tient ce rôle.

Les **routes internes** (application de gestion, `/api/users/`, `/api/orders/`,
`/api/catalog/`…) restent protégées exactement comme avant : rien n'a changé
de ce côté.

---

## 3. Catalogue public

> **Vitrine filtrée par la boutique.** Depuis l'ajout de `visible_client` sur
> la catégorie et le sous-type (front de gestion → Produits → Paramètres),
> l'API publique ne sert QUE ce que le gérant a marqué « Affiché ». Une
> catégorie masquée (ex. `SANTE`, usage interne) disparaît de
> `/api/categories/`, de `/api/sous-type/`, du catalogue paginé et de la fiche
> produit — qui renvoie alors `404`. Le drapeau vaut `true` par défaut :
> l'existant reste affiché tant que personne ne le change. Ce champ n'est pas
> exposé côté client, il n'y a rien à filtrer dans le front.

Toutes ces routes acceptent `?boutique=<id>` pour ne garder que le catalogue d'une boutique. Aucune authentification, aucune donnée interne.

### `GET /api/boutiques/` — liste des boutiques

```json
[
  { "id": 1, "nom": "Boutique Centre", "description": null, "logo": null },
  { "id": 2, "nom": "Boutique Nord", "description": null, "logo": null }
]
```

`logo` est une URL absolue quand la boutique en a une (`http://185.215.167.79:8010/media/shop_logo/...`).

### `GET /api/boutiques/{id}/zones/` — modes de remise

Les deux seuls choix proposés en ligne. Le prix vient du serveur ; le
navigateur ne l'envoie jamais.

```json
{
  "boutique": 1,
  "recuperation": { "code": "RECUPERATION", "nom": "Retrait sur place", "prix": 0.0 },
  "zones": [{ "code": "EN_LIGNE", "nom": "Livraison", "prix": 3000.0 }]
}
```

Le code à renvoyer dans `livraison_zone` est `EN_LIGNE` ou `RECUPERATION` —
aucun autre n'est accepté.

**Tarif de livraison : 3000 Ar.** Il est porté par une `DeliveryZoneOption` de
code `EN_LIGNE`, créée à la demande la première fois que cette route est
appelée. Le gérant peut en changer le prix depuis ses paramètres de zones : le
site suivra, puisqu'il lit le montant ici. Le découpage par quartier
(ZONE1/ZONE2/ZONE3) reste utilisé par les commandes saisies en interne, mais
n'est plus exposé en ligne.

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

## 4. Passer commande

### `POST /api/commandes/` — passer commande sans compte

| | |
| --- | --- |
| **Authentification** | aucune |
| **Débit** | 10 requêtes/minute (`429` au-delà) |
| **Corps** | JSON |

| Champ | Type | Obligatoire | Notes |
| --- | --- | --- | --- |
| `boutique` | int | oui | id de la boutique — tous les articles doivent lui appartenir |
| `items` | liste | oui | `{variante, quantite, prix_attendu?}` — au moins un |
| `livraison_zone` | string | oui | `EN_LIGNE` ou `RECUPERATION` |
| `client_nom` | string | oui | nom de la personne à rappeler |
| `telephone` | string | oui | `+261XXXXXXXXX` |
| `telephone_2` | string | non | second numéro, même format |
| `adresse_livraison` | string | si `EN_LIGNE` | refusée vide pour une livraison |
| `note` | string | non | précision pour la boutique |

**Le corps ne porte aucun montant.** Ni frais de livraison, ni total : le
serveur les calcule depuis le catalogue et la zone. `prix_attendu` est la
seule donnée chiffrée acceptée, et elle ne sert **qu'à détecter un changement
de tarif** — jamais à fixer le prix. Un `frais_livraison` ou un
`total_a_payer` envoyé par le client est ignoré.

```http
POST /api/commandes/
Content-Type: application/json

{
  "boutique": 1,
  "items": [{ "variante": 12, "quantite": 2, "prix_attendu": 30000 }],
  "livraison_zone": "EN_LIGNE",
  "client_nom": "Rakoto Jean",
  "telephone": "+261340000000",
  "telephone_2": "+261320000000",
  "adresse_livraison": "Lot II A 15 Ambohipo",
  "note": "Appeler après 17h"
}
```

**Réponse `201`** — accusé de commande, affiché une seule fois :

```json
{
  "id": 42,
  "numero": "CMD-1-20260928-0003",
  "statut": "EN_ATTENTE_APPROBATION",
  "statut_label": "En attente d'approbation",
  "date_commande": "2026-09-28T10:12:00+03:00",
  "boutique": { "id": 1, "nom": "Smartphone.Mg" },
  "livraison_zone": "EN_LIGNE",
  "adresse_livraison": "Lot II A 15 Ambohipo",
  "client_nom": "Rakoto Jean",
  "telephone": "+261340000000",
  "telephone_2": "+261320000000",
  "note": "Appeler après 17h",
  "frais_livraison": 3000.0,
  "total_a_payer": 63000.0,
  "items": [
    {
      "id": 88,
      "produit": { "id": 7, "nom": "Galaxy A15", "nom_complet": "Samsung Galaxy A15" },
      "couleur": "Noir",
      "quantite": 2,
      "prix_unitaire": 30000.0,
      "total": 60000.0
    }
  ],
  "created_at": "2026-09-28T10:12:00+03:00"
}
```

> **Écriture seule.** Il n'existe ni `GET /api/commandes/{id}/`, ni liste, ni
> `PATCH`, ni annulation. Cet accusé est la seule occasion d'afficher ces
> informations : le front doit les présenter en entier et permettre de les
> imprimer. Toute correction passe par l'appel du gérant.

**Erreurs**

| Statut | Cas |
| --- | --- |
| `400` | champ manquant, téléphone mal formé, adresse absente pour une livraison, zone inconnue |
| `400` | `{"items": ["Stock insuffisant pour « … » : 1 disponible(s), 3 demandé(s)."]}` |
| `400` | `{"items": ["Le prix de « … » a changé : 32000 Ar (vous aviez 30000 Ar)."]}` |
| `400` | `{"boutique": ["Boutique introuvable."]}` |
| `429` | plus de 10 commandes par minute |

Aucun stock n'est réservé à ce stade : la réservation a lieu quand le gérant
approuve.

---

## 5. Cycle de vie d'une commande

Le client ne voit ce cycle **qu'une fois**, sur l'accusé de commande : ensuite
c'est la boutique qui l'informe par téléphone. Le tableau ci-dessous décrit ce
qui se passe côté gestion.

| `statut` | `statut_label` | Ce qui se passe |
| --- | --- | --- |
| `EN_ATTENTE_APPROBATION` | En attente d'approbation | Commande reçue. **Le gérant appelle le client pour confirmer.** Aucun stock réservé |
| `NOUVELLE` | Nouvelle | Le gérant a approuvé : les articles sont réservés |
| `EN_PREPARATION` | En préparation | En cours d'emballage |
| `PRETE` | Prête | Prête à partir (ou à retirer si `RECUPERATION`) |
| `EN_LIVRAISON` | En livraison | Le livreur est en route |
| `LIVRE` | Livré | Terminée, réglée à la remise |
| `RETOUR` | Retour | Livraison non aboutie, colis revenu en boutique |
| `ANNULEE` | Annulée | Refusée par la boutique, ou annulée par elle |

```
   boutique en ligne                  gestion (gérant)
   POST /api/commandes/
           │
  EN_ATTENTE_APPROBATION ──┬─appel puis approuve──> NOUVELLE ──> EN_PREPARATION ──> PRETE ──> EN_LIVRAISON ──> LIVRE
                           │                                                                          └──> RETOUR
                           └─refuse──> ANNULEE
```

**L'appel téléphonique fait partie du circuit**, il n'est pas optionnel : la
commande reste en attente tant que le gérant n'a pas joint le client. C'est là
que se corrige une adresse mal saisie ou une quantité, puisque le site ne le
permet plus.

Le client **n'a aucun moyen d'annuler en ligne** : il le demande pendant
l'appel, ou rappelle la boutique. Le gérant refuse alors la commande, ce qui
la passe en `ANNULEE` sans avoir touché au stock.

Un article marqué `retourne: true` a été rapporté par le livreur : son `total`
passe à `0` et il sort du `total_a_payer`. Cette information n'est visible que
côté gestion.

---

## 6. Erreurs et limitation de débit

| Code | Signification | Réaction conseillée dans l'app |
| --- | --- | --- |
| `400` | Données invalides — corps `{champ: [messages]}` ou `{"detail": [messages]}` | Afficher les messages métier tels quels (français) ; traduire les messages de format du framework (anglais) |
| `404` | Ressource inexistante | « Produit introuvable » |
| `429` | Trop de requêtes | Attendre et réessayer (voir ci-dessous) |

Il n'y a plus de `401` ni de `403` : aucune route ne demande de jeton.

**Limitation de débit**, par adresse IP :

| Portée | Routes | Limite |
| --- | --- | --- |
| `client_public` | Catalogue (section 3) | 300 requêtes / minute |
| `commande_en_ligne` | `POST /api/commandes/` | **10 requêtes / minute** |

L'écriture est nettement plus stricte que la lecture : l'endpoint de commande
est ouvert à tous et crée des enregistrements. Le front doit présenter le
`429` comme une attente, pas comme un échec de la commande.

Réponse `429` : `{"detail": "Request was throttled. Expected available in 42 seconds."}` — l'en-tête `Retry-After` donne le délai en secondes.

---

## 7. Ce que l'API n'expose jamais

Volontairement absent de toutes les réponses ci-dessus :

- prix d'achat, marges, coûts de revient, chiffre d'affaires ;
- quantités en stock (seulement `disponible: true/false`) et seuils d'alerte ;
- personnel de la boutique : préparateur, livreur, gérant, leurs notes internes et leurs photos de préparation ;
- caisse, dépenses, campagnes publicitaires, rapports, approvisionnements fournisseur ;
- **toute commande déjà passée**, la sienne comprise — il n'existe aucune route de lecture (voir section 2).

Le front n'a donc aucun filtrage de sécurité à faire : tout ce qu'il reçoit
est public par construction.

---

## 8. Fonctionnalités frontend supplémentaires

> Cette section décrit des comportements de **l'application cliente uniquement**
> (`clients_frontend/`). Ce ne sont **pas** des endpoints : le backend les
> ignore totalement, et rien ici n'ajoute, ne modifie ni ne contourne une règle
> de l'API décrite plus haut.

### 9.1 Panier local

**Type** : frontend uniquement.

**Description** : l'API ne connaît pas de panier — une commande est créée d'un
bloc par `POST /api/commandes/`. Le panier est donc construit côté client.

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

**Endpoints utilisés** : aucun pour le panier lui-même ; `POST /api/commandes/`
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

### 9.8 Livraison à tarif unique

Le site ne propose plus de choisir un quartier : **livraison à 3000 Ar**, ou
retrait sur place gratuit. Le montant n'est pas écrit dans le front — il est
lu sur `GET /api/boutiques/{id}/zones/` à l'entrée du tunnel, et c'est le
serveur qui l'applique à la commande (`Order.save()` le recalcule depuis la
zone `EN_LIGNE`). Changer le prix dans les paramètres de la boutique suffit
donc à le changer partout, sans redéploiement.

Si l'appel échoue, l'étape affiche « — » plutôt qu'un chiffre inventé : la
commande reste possible, le serveur facturera le bon montant.

### 9.9 Quatre confirmations avant l'envoi

Sans compte, une erreur de saisie ne se rattrape plus en ligne. Le tunnel
demande donc quatre validations successives :

1. **Coordonnées** — nom, téléphone, second numéro facultatif ;
2. **Livraison** — mode, adresse si livraison, précision facultative ;
3. **Vérification** — tout est réaffiché et **tout reste modifiable** :
   quantités et suppression d'articles sur place, retour à l'étape 1 ou 2 pour
   le reste, total détaillé ;
4. **Confirmation** — attestation à cocher, puis fenêtre de confirmation.

Le numéro saisi est normalisé dès l'étape 1 (`034…`, `261…` et `+261…`
donnent la même valeur canonique) : ce que le client relit à l'étape 3 est
exactement ce qui partira au serveur.

### 9.10 Montant confirmé par la boutique

Les montants affichés pendant le tunnel sont **indicatifs**. Le corps envoyé
n'en contient aucun : le serveur recalcule les frais depuis la zone et le
total depuis le catalogue. L'accusé de commande (`201`) porte les valeurs qui
font foi, et le gérant les reconfirme au téléphone.

`prix_attendu` sert uniquement à détecter un changement de tarif entre l'ajout
au panier et la commande : dans ce cas la commande est refusée avec le
nouveau prix, plutôt que facturée en silence.

### 9.11 Aucun suivi en ligne

Il n'existe pas de page « mes commandes » : sans compte, rien n'authentifierait
le demandeur. L'accusé affiché après l'envoi est la seule trace — d'où le
numéro mis en avant et le bouton d'impression. La suite se règle par
téléphone.

### 9.12 Proxy d'API same-origin

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

## 9. Propositions d'évolution API

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

### 10.4 Modèles de téléphone d'une marque

**Fonctionnalité** : alimenter la liste « Modèle / Référence » du parcours
Housse / Cache-écran (section 12) sans télécharger tout le catalogue.

**Endpoint proposé** :

```
GET /api/modeles/?category=<id>&brand=<id>&boutique=<id>
```

```json
[
  { "nom": "Galaxy A15", "disponible": true, "nb_produits": 3 },
  { "nom": "Galaxy S25 Ultra", "disponible": false, "nb_produits": 1 }
]
```

**Pourquoi** : le modèle du téléphone est déjà porté par
`ProductReference.reference_name`, mais aucun endpoint ne renvoie la liste
*distincte* de ces valeurs. Le front la dérive donc aujourd'hui de
`GET /api/produit/?category=&brand=&page_size=100`, en suivant la pagination
(voir `hooks/use-modeles-telephone.ts`) : correct, mais il transfère toutes
les références d'une marque pour n'en afficher que les noms.

**Statut** : optimisation. Le parcours fonctionne sans, rien n'est bloqué.

### 10.5 Réinitialisation du mot de passe

**Fonctionnalité** : « mot de passe oublié » pour un client.

**Endpoints proposés** : `POST /api/client/password-reset/` et
`POST /api/client/password-reset/confirm/`.

**Pourquoi** : `POST /api/client/change-password/` exige le mot de passe
actuel ; un client qui l'a perdu n'a aujourd'hui aucun recours en ligne.

**Statut** : à implémenter côté backend ultérieurement.

---

## 10. Architecture du front client

L'application cliente vit dans `clients_frontend/` (Next.js 16, App Router,
React 19, Tailwind CSS v4, TypeScript). Elle écoute le port **3000**, distinct
du front de gestion (3010) et de l'API (8010).

| Dossier | Rôle |
| --- | --- |
| `app/` | Routes : accueil, `catalogue`, `compatibilite/[slug]` (parcours Housse / Cache-écran, §11), `produit/[id]`, `panier`, `checkout`, `favoris` |
| `components/` | UI (`ui/`), enveloppe du site (`layout/`), catalogue, `compatibilite/` (sélecteur de téléphone, résultats, commande spéciale), fiche produit, panier, `checkout/` (les quatre étapes + accusé) |
| `hooks/` | `use-modeles-telephone.ts` — modèles couverts par une catégorie pour une marque |
| `lib/` | `api.ts` (fetch, sans jeton), `endpoints.ts` (une fonction par route), `types.ts`, `commande.ts` (étapes et validation du tunnel), `store.ts`, `compatibilite.ts`, utilitaires |
| `providers/` | Panier, favoris, thème, notifications |

**Rendu** : le catalogue et les fiches produit sont rendus côté serveur (appel
direct à Django, bon pour le référencement) ; le panier et le tunnel de
commande sont rendus côté client.

**Aucun jeton, aucune session.** Seuls le panier, les favoris et le thème
persistent, en `localStorage`, sur l'appareil du visiteur. Rien n'identifie
celui-ci d'une visite à l'autre.


---

## 11. Commande spéciale Housse / Cache-écran

### 12.1 Le parcours

Housse et Cache-écran ne mènent plus à un listing général : on demande
d'abord le téléphone, parce que ces deux catégories n'ont de sens que
rapportées à un modèle précis.

```
Catégorie (Housse / Cache-écran)
  └─ Marque du téléphone          GET /api/marque/
      └─ Modèle / référence        dérivé de GET /api/produit/
          └─ Rechercher
              ├─ produits compatibles disponibles → panier et commande habituels (§5)
              └─ aucun disponible → commande spéciale
                      └─ formulaire (prérempli depuis le compte)
                          └─ acompte de 50 %
                              └─ validation par la boutique
```

**La compatibilité n'est pas une recherche textuelle.** Le catalogue est déjà
structuré par téléphone : une référence porte une marque (`marque.nom` =
Samsung) et un nom qui est le modèle (`nom` = « Galaxy A15 »). Chercher les
housses d'un Galaxy A15 revient donc à filtrer sur ces relations, pas à faire
un `search=` approximatif.

Routes front : `/compatibilite/housse` et `/compatibilite/cache-ecran`.
`/catalogue?category=<id>` reste accessible et inchangé.

### 12.2 Endpoints utilisés (existants)

| Appel | Rôle dans le parcours |
| --- | --- |
| `GET /api/categories/` | Retrouver la catégorie Housse / Cache-écran de la boutique |
| `GET /api/marque/` | Remplir « Marque du téléphone » |
| `GET /api/produit/?category=&brand=&page_size=100` | Modèles de la marque, puis produits compatibles et leur `disponible` |
| `POST /api/commandes/` | Achat normal quand un produit compatible est en stock |

Aucun endpoint n'a été inventé pour faire tourner cette partie : elle
fonctionne telle quelle.

### 12.3 Ce qui manque au backend

> **Rien de cette sous-section n'existe aujourd'hui.** Vérifié sur `orders/`,
> `clients/`, `finance/` et `users/` : il n'y a **ni modèle de commande
> spéciale, ni notion d'acompte, ni système de paiement** — le site
> n'encaisse rien, tout se règle à la remise.
>
> Le front va donc jusqu'au récapitulatif de la demande et **ne simule ni
> enregistrement ni paiement**. Le code d'appel est écrit
> (`lib/endpoints.ts::commandesSpeciales`) et reste inactif tant que
> `NEXT_PUBLIC_COMMANDE_SPECIALE=1` n'est pas positionné.

#### `POST /api/commandes-speciales/` — déposer une demande

| | |
| --- | --- |
| **Authentification** | aucune (comme le reste de la boutique) |
| **Corps** | JSON |

| Champ | Type | Obligatoire | Notes |
| --- | --- | --- | --- |
| `boutique` | int | oui | id de la boutique |
| `categorie` | int | oui | id de la catégorie (Housse / Cache-écran) |
| `telephone_marque` | string | oui | « Samsung » |
| `telephone_modele` | string | oui | « Galaxy A15 » — texte libre : le modèle peut ne pas être au catalogue |
| `produit_souhaite` | string | oui | « Housse silicone noire » |
| `quantite` | int | oui | ≥ 1 |
| `contact_nom` | string | oui | saisi par le client |
| `contact_telephone` | string | oui | format `+261XXXXXXXXX` |
| `precision` | string | non | couleur, matière, motif… |

**Le corps ne porte aucun montant, volontairement.** Le prix, l'acompte et le
solde sont fixés par la boutique : un montant envoyé par le client ne doit
jamais être accepté.

```http
POST /api/commandes-speciales/
Content-Type: application/json

{
  "boutique": 1,
  "categorie": 3,
  "telephone_marque": "Samsung",
  "telephone_modele": "Galaxy A15",
  "produit_souhaite": "Housse silicone noire",
  "quantite": 1,
  "contact_nom": "Rakoto Jean",
  "contact_telephone": "+261340000000",
  "precision": "Plutôt mat si possible"
}
```

**Réponse `201`**

```json
{
  "id": 12,
  "numero": "CS-000012",
  "statut": "EN_ATTENTE_ACOMPTE",
  "statut_label": "En attente d'acompte",
  "boutique": { "id": 1, "nom": "Smartphone.Mg" },
  "categorie": { "id": 3, "nom": "HOUSSE" },
  "telephone_marque": "Samsung",
  "telephone_modele": "Galaxy A15",
  "produit_souhaite": "Housse silicone noire",
  "quantite": 1,
  "contact_nom": "Rakoto Jean",
  "contact_telephone": "+261340000000",
  "precision": "Plutôt mat si possible",
  "prix_unitaire": null,
  "total": null,
  "acompte_du": null,
  "acompte_paye": 0,
  "reste_a_payer": null,
  "date_disponibilite_estimee": null,
  "created_at": "2026-09-23T10:12:00+03:00",
  "updated_at": "2026-09-23T10:12:00+03:00"
}
```

Les montants sont `null` tant que la boutique n'a pas chiffré : le client voit
« chiffré par la boutique », pas un faux total.

**Erreurs** : `400` (champ manquant ou `quantite < 1`), `404` (boutique ou catégorie inconnue), `429` (limitation de débit,
§7).

#### Relecture d'une commande spéciale

Non retenus : sans compte, rien n'authentifierait le demandeur. Le suivi
d'une commande spéciale se fait par téléphone, comme pour une commande
ordinaire.

#### Acompte

Deux options selon ce que la boutique veut vraiment :

1. **Sans paiement en ligne** (le plus proche de l'existant) : la boutique
   chiffre, encaisse l'acompte sur place ou par mobile money, puis marque
   `POST /api/commandes-speciales/{id}/acompte/` côté gestion. Aucune
   intégration de paiement à construire.
2. **Avec paiement en ligne** : il faut alors un vrai prestataire et une
   confirmation côté serveur. **Ne pas** faire confiance à un appel du
   navigateur qui déclarerait l'acompte payé.

Dans les deux cas, `acompte_du` est calculé **par le serveur**
(`total × 0,5`). Le front affiche 50 % et un ordre de grandeur, jamais un
montant qui ferait foi.

### 12.4 Statuts proposés

Le projet nomme déjà ses statuts en français et en majuscules
(`EN_ATTENTE_APPROBATION`, `EN_PREPARATION`, `LIVRE`…). La commande spéciale
suit la même convention plutôt que d'introduire de l'anglais :

| Statut | Sens |
| --- | --- |
| `EN_ATTENTE_ACOMPTE` | Demande déposée, acompte pas encore réglé |
| `ACOMPTE_PAYE` | Acompte encaissé |
| `EN_ATTENTE_VALIDATION` | Soumise à la boutique |
| `APPROUVEE` | Validée, commande lancée chez le fournisseur |
| `REFUSEE` | Refusée (motif attendu dans la réponse) |
| `EN_COURS` | En cours d'approvisionnement |
| `PRETE` | Disponible en boutique |
| `LIVREE` | Remise au client |
| `ANNULEE` | Annulée |

### 12.5 Délai de 15 jours

Le délai annoncé est de **15 jours**. La date affichée est calculée, jamais
écrite en dur. Aujourd'hui le front la calcule depuis le jour courant, faute
de mieux ; dès que l'endpoint existe, `date_disponibilite_estimee` fait foi et
doit être comptée **à partir de la validation**, pas du dépôt de la demande.

### 12.6 Côté gestion

Pour traiter ces demandes, le gérant doit voir : client et contact, téléphone
demandé (marque + modèle), catégorie, produit souhaité, quantité, prix,
acompte dû, acompte payé, reste à payer, date de demande, date estimée et
statut. Tous ces champs sont dans la structure ci-dessus.
