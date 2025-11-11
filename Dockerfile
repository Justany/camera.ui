# ===================================
# Stage 1: Builder - Build UI
# ===================================
FROM node:18-alpine AS builder

# Définir le répertoire de travail
WORKDIR /app

# Copier les fichiers de dépendances
COPY package*.json ./
COPY ui/package*.json ./ui/

# Installer les dépendances avec cache optimisé
RUN npm ci --only=production && \
  npm ci --prefix ui --only=production

# Copier le code source
COPY . .

# Build de l'interface utilisateur
RUN npm run build

# ===================================
# Stage 2: Production - Application
# ===================================
FROM node:18-alpine

# Métadonnées
LABEL maintainer="Mvutu Security Team"
LABEL description="camera.ui - NVR like PWA for RTSP cameras"
LABEL version="1.1.17"

# Installer FFmpeg et les dépendances système
RUN apk add --no-cache \
  ffmpeg \
  python3 \
  make \
  g++ \
  curl \
  tzdata \
  && rm -rf /var/cache/apk/*

# Créer un utilisateur non-root pour la sécurité
RUN addgroup -g 1000 cameraui && \
  adduser -D -u 1000 -G cameraui cameraui

# Définir le répertoire de travail
WORKDIR /app

# Copier les dépendances depuis le builder
COPY --from=builder --chown=cameraui:cameraui /app/node_modules ./node_modules
COPY --from=builder --chown=cameraui:cameraui /app/interface ./interface

# Copier le code source de l'application
COPY --chown=cameraui:cameraui package*.json ./
COPY --chown=cameraui:cameraui bin ./bin
COPY --chown=cameraui:cameraui src ./src

# Créer les répertoires nécessaires avec les bonnes permissions
RUN mkdir -p /app/data && \
  chown -R cameraui:cameraui /app/data

# Variables d'environnement par défaut
ENV NODE_ENV=production \
  CUI_SERVICE_MODE=1 \
  CUI_STORAGE_PATH=/app/data \
  DISABLE_OPENCOLLECTIVE=true \
  PORT=8081

# Exposer le port de l'application
EXPOSE 8081

# Volume pour la persistance des données
VOLUME ["/app/data"]

# Changer vers l'utilisateur non-root
USER cameraui

# Healthcheck pour vérifier l'état de l'application
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD curl -f http://localhost:8081/version || exit 1

# Commande de démarrage
CMD ["node", "bin/camera.ui.js", "-D", "-C", "-T", "-S", "/app/data"]

