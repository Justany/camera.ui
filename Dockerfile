# Stage 1: Build du frontend Vue.js
# Node 17+ requis pour --openssl-legacy-provider
FROM node:17-alpine AS build-stage

WORKDIR /app

# Configuration npm pour plus de stabilité
RUN npm config set fetch-retry-mintimeout 20000 && \
  npm config set fetch-retry-maxtimeout 120000 && \
  npm config set fetch-retries 5

# Copier uniquement les fichiers de dépendances UI
COPY ui/package*.json ./ui/

# Installer les dépendances UI (avec devDependencies pour le build)
WORKDIR /app/ui
RUN npm install --legacy-peer-deps

# Copier le code source UI
COPY ui/ ./

# Build du frontend Vue.js avec openssl-legacy-provider
RUN NODE_OPTIONS=--openssl-legacy-provider npm run build

# Stage 2: Production
# Node 16 ou 17+ pour la production (16 est suffisant pour le runtime)
FROM node:16-alpine AS production-stage

# Installer FFmpeg (requis pour le streaming vidéo)
RUN apk add --no-cache ffmpeg

WORKDIR /app

# Configuration npm
RUN npm config set fetch-retry-mintimeout 20000 && \
  npm config set fetch-retry-maxtimeout 120000

# Copier les fichiers de dépendances backend
COPY package*.json ./

# Installer uniquement les dépendances de production backend
RUN npm install --omit=dev --production --legacy-peer-deps && \
  npm cache clean --force

# Copier le code source backend
COPY src ./src
COPY bin ./bin

# Copier le build frontend depuis le stage de build
COPY --from=build-stage /app/interface ./interface

# Créer les répertoires nécessaires
RUN mkdir -p /app/data

# Variables d'environnement par défaut
ENV CUI_STORAGE_PATH=/app/data
ENV CUI_LOG_MODE=1
ENV CUI_SERVICE_MODE=1
ENV NODE_ENV=production

# Exposer le port
EXPOSE 8081

# Commande de démarrage
CMD ["node", "bin/camera.ui.js", "-S", "/app/data"]
