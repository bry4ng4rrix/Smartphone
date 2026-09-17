# Smartphone.Mg — gestion de boutique d'accessoires téléphone

Application de gestion pour une boutique d'accessoires (Madagascar) :
catalogue et stock, commandes clients avec préparation et livraison, caisse,
fournisseurs, messagerie interne, notifications et centre de rapports.
Elle existe en **web** (Next.js) et en **application mobile** (Flutter), toutes
deux branchées sur la **même API Django**.

## 1. Les trois parties du projet

| Dossier | Rôle | Technologie |
| --- | --- | --- |
| racine — `Stock/`, `users/`, `catalog/`, `orders/`, `suppliers/`, `clients/` | API backend + WebSocket temps réel (`clients/` = espace client en ligne, ajouté à côté de l'existant) | Django 6, Django REST Framework, Channels (Daphne), JWT |
| `frontend/` | Application web (gérant, préparateur, livreur) | Next.js 16, shadcn/ui, recharts |
| `smartcross/` | Application mobile (mêmes fonctionnalités que le web) | Flutter, Riverpod, go_router |

Base de données : SQLite en local par défaut (zéro configuration), **PostgreSQL en
production** (`DB_ENGINE` dans l'environnement). L'assistant et les rapports IA
utilisent **Ollama** (modèle local sur le serveur), appelé par le frontend
Next.js — l'application mobile passe par cette même route.

## 2. Rôles et fonctionnalités

| Rôle | Ce qu'il fait |
| --- | --- |
| **Gérant** (administrateur / gérant de magasin) | Tableau de bord (rapports), commandes (création avec remise par article, modification, assignation, correction d'état), catalogue et stock, caisse, fournisseurs, transferts, bilan des livreurs et validation de leurs dépenses, comptes de l'équipe, paramètres (zones de livraison, types de dépense) |
| **Préparateur** | Dépôt : commandes à préparer (photo de préparation), retraits sur place |
| **Livreur** | Tournée du jour, confirmation de livraison (articles remis / rapportés), bilan du jour, déclaration de dépenses |
| Tous | Messagerie interne, notifications (temps réel + notifications système sur mobile) |

Cycle d'une commande : `Nouvelle → En préparation → Prête → En livraison → Livrée / Retour`
(+ `Annulée`). Le stock sort à la préparation et revient au retour ou à
l'annulation. Les dates métier sont en heure d'**Antananarivo** (règle du
« jour J » : le préparateur agit dès 19 h la veille, le livreur à partir de minuit).

## 3. Lancer le projet en local

### Backend (API sur http://127.0.0.1:8010)

```bash
python -m venv .venv && .venv/bin/pip install -r requirements.txt
.venv/bin/python manage.py migrate
.venv/bin/python manage.py seed_smartphone      # catalogue réel + comptes de démo
.venv/bin/python manage.py runserver 8010       # toujours préciser 8010
```

Pour travailler contre PostgreSQL en local, renseigner `.env.local` (mêmes
variables que `.env.example`) puis utiliser `./run_local.sh` (ou
`./run_local.sh migrate`, `./run_local.sh shell` …) : le script charge
`.env.local` avant `manage.py`.

### Web (http://localhost:3010)

```bash
cd frontend && npm install && npm run dev
```

`frontend/.env` doit contenir `NEXT_PUBLIC_DJANGO_API_URL=http://localhost:8010/api`
(et `OLLAMA_BASE_URL` / `OLLAMA_MODEL_*` pour l'assistant, voir `.env.example`).

### Mobile (Flutter)

```bash
cd smartcross && flutter pub get && flutter run
```

L'app pointe par défaut sur le serveur de production
(`kDefaultServerUrl` dans `smartcross/lib/core/api_client.dart`). Pour un
serveur local, utiliser l'écran **« Configuration du serveur »** depuis la
connexion (ex. `http://10.0.2.2:8010` sur l'émulateur Android) ; le bouton
« Serveur par défaut » ramène à la production.

APK : `cd smartcross && flutter build apk --release`.

## 4. Déploiement (VPS, Docker)

Tout est décrit pas à pas dans **`roadmap.md`** (prérequis, variables,
première installation, import du catalogue, mises à jour, sauvegardes,
Ollama, dépannage). En résumé :

```bash
cp .env.example .env          # puis remplir les valeurs (secret, base, domaine…)
docker compose -f docker-compose.prod.yml up -d --build
```

Services : PostgreSQL et Redis (internes), backend Django sur le port `8010`,
frontend Next.js sur le port `3010`. Ollama tourne directement sur le serveur.

## 5. Points d'entrée de l'API

Toutes les routes sont sous `/api/` (authentification JWT) :

| Préfixe | Contenu |
| --- | --- |
| `/api/users/` | comptes, connexion, magasins, caisse, notifications, messagerie |
| `/api/catalog/` | catégories, sous-types, marques, couleurs, références, variantes, mouvements de stock, import/export Excel, notes produit |
| `/api/orders/` | commandes, zones de livraison, dépenses des livreurs, campagnes marketing, rapports (`reports/{overview,sales,financial,expenses,stock,orders,deliveries,marketing}/`) |
| `/api/suppliers/` | approvisionnements fournisseur (1 produit par envoi, paiements au taux du jour, Frais + Douane, coût de revient par pièce, réception en stock) |
| `/api/produit/`, `/api/categories/`, `/api/type/`, `/api/sous-type/`, `/api/marque/`, `/api/couleurs/`, `/api/boutiques/` | **catalogue public** (sans authentification, sans prix d'achat ni stock chiffré) — app `clients` |
| `/api/client/` | **espace client** : inscription, connexion (JWT distinct), profil, commandes client (créées « en attente d'approbation », validées par le gérant via `POST /api/orders/{id}/approuver/`) |

Temps réel (WebSocket, jeton en paramètre `token`) : `/ws/notifications/`
(notifications), `/ws/data/` (changements de données), `/ws/chat/` (messagerie).

## 6. Documents utiles

| Fichier | Contenu |
| --- | --- |
| `roadmap.md` | Déploiement, environnement, sauvegardes, Ollama, centre de rapports |
| `FLUTTER_FEATURE_PARITY.md` | Checklist de parité web → mobile, route par route, avec les écarts documentés |
| `FLUTTER_MIGRATION.md`, `PARITY_CHECKLIST.md` | Inventaire initial du frontend et checklist de la première migration (historique) |
| `endpoint.md` | Référence complète de l'API (toutes les routes, exemples JSON, dont l'espace client) |
| `.env.example` | Toutes les variables d'environnement commentées |

## 7. Conventions

- Le frontend Next.js est la référence fonctionnelle ; l'app Flutter le reproduit sur la même API.
- Ne jamais coder de données métier en dur : migrations Django + `seed_smartphone`.
- En local, `manage.py` sans `.env.local` utilise SQLite — pour agir sur PostgreSQL, toujours passer par `./run_local.sh`.
- Les prix d'une commande sont figés à la commande (`prix_unitaire`, `prix_catalogue`) : une remise n'affecte jamais le catalogue ni le stock.
