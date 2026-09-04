FROM node:20-alpine AS builder

WORKDIR /app

ARG NEXT_PUBLIC_DJANGO_API_URL
ENV NEXT_PUBLIC_DJANGO_API_URL=$NEXT_PUBLIC_DJANGO_API_URL

RUN apk add --no-cache python3 make g++

COPY frontend/package*.json ./
COPY frontend/tsconfig.json ./
COPY frontend/next.config.mjs ./
COPY frontend/postcss.config.mjs ./
COPY frontend/components.json ./
COPY frontend/public ./public
COPY frontend/styles ./styles
COPY frontend/app ./app
COPY frontend/components ./components
COPY frontend/lib ./lib
COPY frontend/hooks ./hooks

RUN npm install
RUN npm run build

FROM node:20-alpine
WORKDIR /app
COPY --from=builder /app .

EXPOSE 3010
CMD ["npm", "run", "start"]
