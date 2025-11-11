# ===================================
# Stage 1: Builder - Build UI
# ===================================
FROM node:18-alpine AS builder

# Définir le répertoire de travail
WORKDIR /app

# Copier les fichiers de dépendances
COPY package*.json ./
COPY ui/package*.json ./ui/

# Installer TOUTES les dépendances (y compris dev) pour le build
RUN npm install && \
    npm install --prefix ui

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

# Définir le répertoire de travail
WORKDIR /app

# Copier les node_modules depuis le builder (déjà installés)
COPY --from=builder /app/node_modules ./node_modules

# Copier l'interface buildée
COPY --from=builder /app/interface ./interface

# Copier le code source de l'application
COPY package*.json ./
COPY bin ./bin
COPY src ./src

# Créer les répertoires nécessaires
RUN mkdir -p /app/data

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

# Healthcheck pour vérifier l'état de l'application
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD curl -f http://localhost:8081/version || exit 1

# Commande de démarrage
CMD ["node", "bin/camera.ui.js", "-D", "-C", "-T", "-S", "/app/data"]

