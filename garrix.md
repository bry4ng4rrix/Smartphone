
# ---------- Django ----------
DJANGO_SECRET_KEY=RCmSDLH3huNPxr6uSgiVOX5nuy4jRDxBTz3T_cWK2klbAVU2qXKeyTPTGQDCpPVxAVU
DEBUG=False
ALLOWED_HOSTS=157.173.103.147 localhost 127.0.0.1
CORS_ALLOWED_ORIGINS=http://157.173.103.147:3010
CSRF_TRUSTED_ORIGINS=http://157.173.103.147:3010 http://157.173.103.147:8010

# ---------- Base de données (Postgres, service `db`) ----------
DB_ENGINE=django.db.backends.postgresql
DB_NAME=smartphonemg_db
DB_USER=smartphonemg
DB_PASSWORD=NUu5O25Cpyqc8pA6AVYwrBEi
DB_HOST=db
DB_PORT=5432

# ---------- Ports hôte (§ port du VPS partagé — évite les collisions avec
# d'autres projets déjà sur ce Docker : ports volontairement non-standards,
# Postgres/Redis eux ne sont jamais exposés à l'hôte, voir
# docker-compose.prod.yml) ----------
BACKEND_PORT=8010
FRONTEND_PORT=3010

# ---------- Frontend (Next.js) — inlinée au build, voir roadmap.md § dépannage ----------
NEXT_PUBLIC_DJANGO_API_URL=http://157.173.103.147:8010/api
