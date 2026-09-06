# Roadmap de déploiement — Smartphone.Mg

Ce document explique comment faire tourner ce projet (backend Django +
frontend Next.js) en local avec Docker, puis comment le déployer sur le VPS
avec Postgres — y compris l'import du catalogue réel. Les fichiers de
référence utilisés pendant le développement (`Smartphone_Mg_Cahier_des_charges.pdf`,
`Smartreadme.md`, `schema.sql`, `seed catalogue.sql` à la racine) ont été
retirés du dépôt : le catalogue lui-même vit maintenant dans
`catalog/management/commands/data/seed_catalogue.sql`, livré avec le code
et lu par la commande `seed_smartphone` (§6.3).

L'app mobile Flutter (`smartcross/`) n'a pas besoin de ce workflow : elle
appelle la même API que le frontend web, il suffit de changer l'URL du
serveur dans l'écran "Configuration serveur" de l'app (ou `kDefaultServerUrl`
dans `smartcross/lib/core/api_client.dart` pour changer la valeur par défaut).

## 1. Vue d'ensemble

| Dossier | Rôle | Techno |
|---|---|---|
| racine (`Stock/`, `catalog/`, `orders/`, `suppliers/`, `users/`) | API backend | Django 6 + DRF + Channels (WebSocket) |
| `frontend/` | Application web | Next.js 16 |
| `smartcross/` | Application mobile | Flutter |
| `old/` | Ancienne implémentation de référence mono-tenant (si encore présente) | — |

Le backend est **multi-base** : SQLite en local (par défaut, zéro config),
Postgres en production (via `DB_ENGINE`, voir §3). Aucune donnée métier
n'est codée en dur : tout passe par des migrations Django + la commande de
seed ci-dessous.

## 2. Prérequis sur le VPS

- Docker Engine + Docker Compose plugin (`docker compose version` doit
  répondre).
- Un nom de domaine (ou l'IP du VPS) pointant vers le serveur, avec les
  ports 80/443 (ou au minimum 3010/8010 si pas de reverse proxy) ouverts —
  volontairement non-standards pour cohabiter avec d'autres projets sur le
  même Docker (§6, `BACKEND_PORT`/`FRONTEND_PORT`).
- Accès SSH avec droits pour lancer Docker.
- (Recommandé) un reverse proxy TLS devant les conteneurs (Caddy, Nginx +
  certbot, ou Traefik) — non fourni ici, ce roadmap documente les conteneurs
  applicatifs eux-mêmes.

## 3. Variables d'environnement

Copier le gabarit et le remplir :

```bash
cp .env.example .env
```

| Variable | Rôle | Exemple prod |
|---|---|---|
| `DJANGO_SECRET_KEY` | Clé Django — **jamais** la valeur par défaut en prod | générée (voir commentaire dans `.env.example`) |
| `DEBUG` | Doit être `False` en production | `False` |
| `ALLOWED_HOSTS` | Domaines/IP autorisés à servir l'API (séparés par des espaces) | `smartphone.mg 157.173.103.147` |
| `CORS_ALLOWED_ORIGINS` | Origines autorisées à appeler l'API depuis un navigateur | `https://smartphone.mg` |
| `CSRF_TRUSTED_ORIGINS` | Idem pour les requêtes avec cookies/CSRF | `https://smartphone.mg` |
| `DB_ENGINE` | `django.db.backends.postgresql` en prod, `sqlite3` en local | `django.db.backends.postgresql` |
| `DB_NAME` / `DB_USER` / `DB_PASSWORD` / `DB_HOST` / `DB_PORT` | Connexion Postgres (le service `db` du compose prod) | voir `.env.example` |
| `NEXT_PUBLIC_DJANGO_API_URL` | URL publique de l'API, **inlinée dans le build** du frontend (pas modifiable après coup sans rebuild) | `https://smartphone.mg/api` |

`.env` est ignoré par git (`.gitignore`) — ne jamais le committer.

## 4. Développement local (sans Docker)

Inchangé, c'est ce qui a servi pendant tout le développement :

```bash
python -m venv .venv && .venv/bin/pip install -r requirements.txt
.venv/bin/python manage.py migrate
.venv/bin/python manage.py seed_smartphone   # catalogue réel + comptes de démo
.venv/bin/python manage.py runserver 8010
```

```bash
cd frontend && npm install && npm run dev
```

`npm run dev`/`npm run start` sont déjà fixés sur le port 3010 (voir
`frontend/package.json`) — `manage.py runserver` doit par contre toujours
préciser `8010` explicitement (Django n'a pas d'équivalent du `PORT` env var
de Next.js), sinon il retombe sur son port par défaut 8000 et le frontend
(configuré pour appeler `:8010` via `NEXT_PUBLIC_API_URL`) échoue avec
"Failed to fetch".

## 5. Test local avec Docker (SQLite) — `docker-compose.yml`

Sert à vérifier que les images Docker fonctionnent avant de toucher au VPS,
sans dépendance Postgres :

```bash
docker compose up --build
```

Le conteneur `backend` migre automatiquement au démarrage
(`docker-entrypoint.sh`). Pour charger le catalogue dans ce conteneur :

```bash
docker compose exec backend python manage.py seed_smartphone
```

## 6. Déploiement production sur le VPS — `docker-compose.prod.yml`

### 6.1 Première installation

```bash
git clone <url-du-repo> smartphone && cd smartphone
cp .env.example .env && nano .env       # remplir toutes les valeurs, § 3
docker compose -f docker-compose.prod.yml up -d --build
```

Ce compose lance 3 services : `db` (Postgres 15), `backend` (Daphne/ASGI,
migre automatiquement au démarrage via `docker-entrypoint.sh`), `frontend`
(Next.js, build de production). Les fichiers statiques/médias Django sont
persistés dans les volumes nommés `static_volume`/`media_volume`.

### 6.2 Vérifier les migrations

Elles tournent automatiquement à chaque démarrage du conteneur `backend`
(`python manage.py migrate --noinput` dans `docker-entrypoint.sh`). Pour
vérifier ou relancer manuellement :

```bash
docker compose -f docker-compose.prod.yml exec backend python manage.py migrate
docker compose -f docker-compose.prod.yml exec backend python manage.py showmigrations
```

### 6.3 Importer le catalogue réel dans Postgres

C'est l'étape qui remplace l'ancien `seed catalogue.sql`/`schema.sql` à la
racine : les données (298 références, ~530 variantes couleur, catégories,
marques) sont maintenant embarquées dans le code sous
`catalog/management/commands/data/seed_catalogue.sql`, lues par la commande
`seed_smartphone` — **idempotente**, donc sans risque de la relancer :

```bash
docker compose -f docker-compose.prod.yml exec backend python manage.py seed_smartphone
```

Cette commande crée aussi le tenant (magasin "Smartphone.Mg") et 3 comptes
de démo (Gérant/Préparateur/Livreur) avec un mot de passe **connu et
documenté dans le code** — voir §7, à traiter avant d'exposer le VPS
publiquement.

### 6.4 Vérifier que ça tourne

```bash
docker compose -f docker-compose.prod.yml ps
docker compose -f docker-compose.prod.yml logs -f backend
curl -I http://localhost:8010/api/users/login/    # doit répondre (405 sur GET est normal)
```

## 7. Sécurité — à faire avant d'ouvrir l'accès au public

`seed_smartphone` crée/réinitialise systématiquement 3 comptes avec le mot
de passe par défaut `smartphone2026` (`gerant@smartphone.mg`,
`preparateur@smartphone.mg`, `livreur@smartphone.mg` — la commande affiche
d'ailleurs un avertissement à chaque exécution). **Ne pas laisser ces
identifiants actifs sur une instance publique.** Deux options :

- Se connecter avec le compte gérant puis changer le mot de passe depuis
  Paramètres → Sécurité (web ou mobile), pour les 3 comptes ; ou
- Changer directement en base :

  ```bash
  docker compose -f docker-compose.prod.yml exec backend python manage.py shell -c "
  from django.contrib.auth import get_user_model
  U = get_user_model()
  for email in ['gerant@smartphone.mg','preparateur@smartphone.mg','livreur@smartphone.mg']:
      u = U.objects.get(email=email)
      u.set_password('UN_MOT_DE_PASSE_FORT_DIFFERENT')
      u.save()
  "
  ```

Autres points de sécurité déjà couverts par le compose/`.env.example` mais à
ne pas oublier : `DJANGO_SECRET_KEY` unique et aléatoire, `DEBUG=False`,
`ALLOWED_HOSTS`/`CORS_ALLOWED_ORIGINS`/`CSRF_TRUSTED_ORIGINS` limités au(x)
vrai(s) domaine(s), TLS via un reverse proxy devant les ports 3010/8010.

## 8. Mises à jour (déploiement continu)

Depuis la machine de dev : commit + push habituels (`git add`, `git commit`,
`git push`) sur la branche `main`.

Sur le VPS, après un `git pull`, reconstruire et relancer :

```bash
git pull origin main
docker compose -f docker-compose.prod.yml up -d --build
```

Les migrations tournent automatiquement au redémarrage du conteneur
`backend` ; `seed_smartphone` n'a besoin d'être relancée que si le fichier
`data/seed_catalogue.sql` a changé (elle est idempotente, donc sans danger
de la rejouer par précaution).

## 9. Sauvegarde Postgres

```bash
docker compose -f docker-compose.prod.yml exec db pg_dump -U stock stock_db > backup_$(date +%Y%m%d).sql
```

Restauration :

```bash
cat backup_20260101.sql | docker compose -f docker-compose.prod.yml exec -T db psql -U stock stock_db
```

Le backend expose aussi un export/import complet (DB + médias) via
`/api/users/backup/export/` et `/api/users/backup/import/` (réservé admin,
utilisé par le bouton correspondant du frontend web).

## 10. Analyse IA (Ollama local)

Le bouton "Générer l'analyse" de la page Rapports (`frontend/components/ai-analysis.tsx`)
appelle `frontend/app/api/ai/analyze/route.ts`, qui interroge un modèle
**Ollama local** — pas d'API cloud, pas de clé à gérer/exposer.

**Installation sur le VPS** (une fois, en dehors de ce docker-compose — Ollama
tourne directement sur l'hôte) :

```bash
curl -fsSL https://ollama.com/install.sh | sh
ollama pull qwen3:4b
ollama serve   # ou : systemctl enable --now ollama (si installé comme service)
```

Vérifier qu'il répond sur l'hôte :

```bash
curl http://localhost:11434/api/generate -d '{"model":"qwen3:4b","prompt":"Bonjour","stream":false}'
```

**Depuis le conteneur frontend**, Ollama est joignable via
`http://host.docker.internal:11434` (voir `extra_hosts` dans
`docker-compose.prod.yml`, et `OLLAMA_BASE_URL`/`OLLAMA_MODEL` dans `.env`).
Si `host.docker.internal` ne résout pas sur votre configuration Docker,
remplacer `OLLAMA_BASE_URL` par l'IP du VPS elle-même (`http://<ip-vps>:11434`)
dans `.env`, puis `docker compose -f docker-compose.prod.yml up -d frontend`.

**Modifier le prompt d'analyse** : tout est dans la constante `buildPrompt()`
en haut de `frontend/app/api/ai/analyze/route.ts`, avec un commentaire dédié.
Le plus simple, directement sur le VPS avec Claude Code :

```
claude "dans frontend/app/api/ai/analyze/route.ts, modifie buildPrompt() pour ..."
```

Puis reconstruire le conteneur pour que le changement soit pris en compte :

```bash
docker compose -f docker-compose.prod.yml up -d --build frontend
```

## 11. Dépannage courant

| Symptôme | Piste |
|---|---|
| `psycopg2.OperationalError: could not connect to server` | Le service `db` n'a pas fini de démarrer — `backend` réessaiera au prochain restart ; vérifier `DB_HOST=db` (nom du service, pas `localhost`) |
| Frontend appelle `127.0.0.1:8010` en prod | `NEXT_PUBLIC_DJANGO_API_URL` doit être fourni **avant** le build (c'est un `build.args`, pas juste une variable runtime — voir `frontend/Dockerfile`) ; rebuild avec `--build` après correction du `.env` |
| Frontend inaccessible (rien ne répond sur `FRONTEND_PORT`) | Le conteneur `next start` doit recevoir `PORT=3010` (déjà réglé dans les deux compose) — sans ça il écoute sur 3000 alors que le mapping hôte cible 3010 |
| 401 CORS/CSRF en prod | Vérifier que le domaine exact (avec `https://`) est bien dans `CORS_ALLOWED_ORIGINS`/`CSRF_TRUSTED_ORIGINS` |
| "Impossible de contacter Ollama" sur la page Rapports | Ollama n'est pas lancé sur le VPS (`systemctl status ollama` / `ollama serve`), ou `host.docker.internal` ne résout pas depuis le conteneur — voir §10, remplacer `OLLAMA_BASE_URL` par l'IP du VPS |
| `Limite d'appareils atteinte` en boucle pendant les tests | Purger les `Device` de test : `manage.py shell -c "from users.models import Device; Device.objects.filter(user__email='...').delete()"` |
| Catalogue vide après un déploiement propre | `seed_smartphone` n'a pas été lancée (§6.3) — les migrations seules ne créent pas de données |
