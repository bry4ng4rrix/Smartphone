# syntax=docker/dockerfile:1.7
# Espace client Smartphone.Mg — Next.js 16 (App Router) servi sur le port 3000.
# Image en trois étapes : dépendances, build, exécution (sortie « standalone »).
#
# L'image se construit avec **npm** (comme le reste du déploiement VPS) à
# partir de package-lock.json. Le développement local, lui, reste sous pnpm :
# les deux fichiers de verrouillage décrivent les mêmes dépendances.

# ----------------------------------------------------------------- deps ----
FROM node:22-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
# `npm ci` installe exactement le contenu du lockfile. Le délai est allongé :
# un registre lent ne doit pas faire échouer toute la construction.
RUN npm ci --no-audit --no-fund --fetch-timeout=600000

# ---------------------------------------------------------------- build ----
FROM node:22-alpine AS builder
WORKDIR /app
ENV NEXT_TELEMETRY_DISABLED=1
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN npm run build

# --------------------------------------------------------------- runner ----
FROM node:22-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production \
    NEXT_TELEMETRY_DISABLED=1 \
    PORT=3000 \
    HOSTNAME=0.0.0.0

# Exécution sans privilèges.
RUN addgroup -g 1001 -S nodejs && adduser -u 1001 -S nextjs -G nodejs

COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static
COPY --from=builder --chown=nextjs:nodejs /app/public ./public

USER nextjs
EXPOSE 3000

# `DJANGO_ORIGIN` est lu au démarrage du serveur (rewrites de next.config.ts) :
# il se règle à l'exécution, sans reconstruire l'image.
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:3000/').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "server.js"]
