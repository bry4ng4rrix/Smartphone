# API Smartphone.Mg — endpoints

Base : `http://127.0.0.1:8010/api/` (dev). Auth JWT (`Authorization: Bearer <access>`) sauf `/users/login/`.

## Users (`/api/users/`)

| Méthode | URL | Rôle | Description |
|---|---|---|---|
| POST | `login/` | public | `{email, password}` → `access`, `refresh`, `role`, `full_name` |
| POST | `refresh/` | public | `{refresh}` → nouveau `access` |
| GET | `me/` | tous | Profil de l'utilisateur connecté |
| GET/POST | `accounts/` | GERANT | Liste / création de comptes préparateur/livreur |
| GET/PUT/PATCH/DELETE | `accounts/<id>/` | GERANT | Gestion d'un compte |

## Catalog (`/api/catalog/`)

| Méthode | URL | Rôle | Description |
|---|---|---|---|
| GET/POST | `categories/`, `types/`, `brands/`, `references/` | lecture: tous / écriture: GERANT | CRUD catalogue |
| GET | `types/?category=<id>` | | Filtre par catégorie |
| GET | `references/?type=<id>&brand=<id>` | | Filtre par sous-type/marque |
| GET | `references/autocomplete/?q=...` | tous | Recherche pour le formulaire Nouvelle commande (§6) |
| GET/POST/DELETE | `variants/` | lecture: tous / écriture: GERANT | Variantes (couleur/stock) — stock modifiable uniquement via `/api/stock/` |

## Orders (`/api/orders/`)

| Méthode | URL | Rôle | Description |
|---|---|---|---|
| GET | `` | tous (vue filtrée par rôle) | Préparateur : NOUVELLE/EN_PREPARATION. Livreur : PRETE/EN_LIVRAISON. Gérant : tout (+ filtres `?statut=&date_debut=&date_fin=`) |
| POST | `` | GERANT | Formulaire Nouvelle commande (§6) : `{client_nom, telephone (+261XXXXXXXXX), livraison_zone, note, items: [{product_variant, quantite}]}` — prix/frais/total calculés serveur |
| GET | `<id>/` | tous | Détail (champs financiers masqués pour préparateur/livreur) |
| POST | `<id>/status/` | selon transition (§5) | `{statut, note}` — transitions strictes, stock impacté uniquement à `LIVRE` |
| GET | `dashboard/` | GERANT | KPIs (§7.7) : `?date_debut=&date_fin=` (défaut : mois en cours) |

### Règles de transition (`<id>/status/`)

| Statut cible | Depuis | Rôle requis (ou gérant) | Effet stock |
|---|---|---|---|
| EN_PREPARATION | NOUVELLE | PREPARATEUR | aucun |
| PRETE | EN_PREPARATION | PREPARATEUR | aucun (→ notif LIVREUR) |
| EN_LIVRAISON | PRETE | LIVREUR | aucun |
| LIVRE | EN_LIVRAISON | LIVREUR | déduction stock |
| RETOUR | EN_LIVRAISON | LIVREUR | aucun (livraison échouée, jamais livré) |

## Stock (`/api/stock/`)

| Méthode | URL | Rôle | Description |
|---|---|---|---|
| GET | `movements/?variant=<id>` | GERANT | Historique des mouvements |
| POST | `adjustments/` | GERANT | `{product_variant, type: ENTREE\|SORTIE, quantite, note}` — correction manuelle |
| GET | `ruptures/` | GERANT | Produits en rupture (stock=0) ou stock bas (stock≤seuil) |
| GET | `ruptures/export-pdf/` | GERANT | Export PDF de la liste de réapprovisionnement |

## Suppliers (`/api/suppliers/`)

| Méthode | URL | Rôle | Description |
|---|---|---|---|
| GET/POST | `orders/` | GERANT | Commande fournisseur : `{description, prix_fournisseur, fret_import, douane, meta_ads, lines: [{product_variant, quantite}]}` — coût total/unitaire/marge calculés serveur |
| GET | `orders/<id>/` | GERANT | Détail |
| POST | `orders/<id>/receive/` | GERANT | Réception → entrée stock automatique par ligne |

## Notifications (`/api/notifications/`)

| Méthode | URL | Rôle | Description |
|---|---|---|---|
| GET | `` | tous | Notifications de l'utilisateur (par rôle ciblé) |
| POST | `<id>/mark_read/` | tous | Marquer comme lue |

### WebSocket temps réel

`ws://<host>/ws/notifications/?token=<jwt access token>` — pousse un événement JSON dès qu'une notification est créée (nouvelle commande → groupe PREPARATEUR, commande prête → groupe LIVREUR).

---

## Comptes de test (`python manage.py seed_catalog`)

| Email | Mot de passe | Rôle |
|---|---|---|
| gerant@smartphone.mg | test1234 | GERANT |
| preparateur@smartphone.mg | test1234 | PREPARATEUR |
| livreur@smartphone.mg | test1234 | LIVREUR |
