FROM node:18-alpine AS build-stage

WORKDIR /app

# Copier les fichiers de dépendances
COPY package*.json ./
COPY ui/package*.json ./ui/

# Installer les dépendances
RUN npm ci --omit=dev
RUN cd ui && npm ci

# Copier le code source
COPY . .

# Build du frontend Vue.js
RUN npm run build

# Stage de production
FROM node:18-alpine AS production-stage

# Installer FFmpeg (requis pour le streaming vidéo)
RUN apk add --no-cache ffmpeg

WORKDIR /app

# Copier les dépendances de production
COPY package*.json ./
RUN npm ci --omit=dev

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

