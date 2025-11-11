FROM node:16-alpine AS build-stage

WORKDIR /app

# Configuration npm pour plus de stabilité
RUN npm config set fetch-retry-mintimeout 20000 && \
  npm config set fetch-retry-maxtimeout 120000 && \
  npm config set fetch-retries 5

# Copier les fichiers de dépendances
COPY package*.json ./
COPY ui/package*.json ./ui/

# Installer les dépendances avec npm install (plus tolérant que ci)
RUN npm install --omit=dev --legacy-peer-deps
RUN cd ui && npm install --legacy-peer-deps

# Copier le code source
COPY . .

# Build du frontend Vue.js (avec openssl-legacy-provider directement)
RUN cd ui && node --openssl-legacy-provider node_modules/.bin/vue-cli-service build

# Stage de production
FROM node:16-alpine AS production-stage

# Installer FFmpeg (requis pour le streaming vidéo)
RUN apk add --no-cache ffmpeg

WORKDIR /app

# Configuration npm
RUN npm config set fetch-retry-mintimeout 20000 && \
  npm config set fetch-retry-maxtimeout 120000

# Copier les dépendances de production
COPY package*.json ./
RUN npm install --omit=dev --production --legacy-peer-deps

# Copier le code source backend
COPY src ./src
COPY bin ./bin

# Copier le build frontend depuis le stage précédent
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

