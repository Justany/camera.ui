# 🐳 Guide de Déploiement Docker - camera.ui

Guide complet pour déployer camera.ui avec Docker Compose sur votre infrastructure (TPS, cloud, etc.).

## 📋 Table des matières

- [Prérequis](#prérequis)
- [Architecture](#architecture)
- [Installation](#installation)
- [Configuration](#configuration)
- [Sécurité](#sécurité)
- [Déploiement](#déploiement)
- [Maintenance](#maintenance)
- [Troubleshooting](#troubleshooting)

---

## 🔧 Prérequis

### Logiciels requis

- **Docker** >= 20.10
- **Docker Compose** >= 2.0
- **Git** (pour cloner le projet)
- Minimum **2 Go RAM** disponible
- Minimum **20 Go** d'espace disque

### Installation de Docker

#### Ubuntu/Debian

```bash
# Installer Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Installer Docker Compose
sudo apt-get install docker-compose-plugin

# Ajouter votre utilisateur au groupe docker
sudo usermod -aG docker $USER

# Redémarrer la session ou exécuter
newgrp docker
```

#### CentOS/RHEL

```bash
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo yum install docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo systemctl start docker
sudo systemctl enable docker
```

---

## 🏗️ Architecture

### Structure des conteneurs

```
┌─────────────────────────────────────────────┐
│             Internet / Client               │
└─────────────────┬───────────────────────────┘
                  │
      ┌───────────▼───────────┐
      │  nginx-proxy (80/443) │  ← Reverse Proxy + Firewall
      │  - SSL/TLS            │
      │  - Rate Limiting      │
      │  - Security Headers   │
      └───────────┬───────────┘
                  │
      ┌───────────▼───────────┐
      │   camera-ui (8081)    │  ← Application principale
      │   - Node.js/Express   │
      │   - WebSocket         │
      │   - FFmpeg            │
      └───────┬───────┬───────┘
              │       │
   ┌──────────▼───┐   │
   │ mqtt-broker  │   │
   │   (1883)     │   │
   └──────────────┘   │
                      │
              ┌───────▼───────┐
              │  fail2ban     │  ← Protection intrusion
              │  (monitoring) │
              └───────────────┘
```

### Réseaux Docker

- **frontend**: Communication entre nginx et camera-ui
- **camera-network**: Communication interne (MQTT, caméras)

### Volumes persistants

- `camera-ui-data`: Configuration et base de données
- `./recordings`: Enregistrements vidéo (monté directement)
- `nginx-logs`: Logs Nginx pour fail2ban
- `mqtt-data`: Données MQTT

---

## 🚀 Installation

### 1. Cloner le projet

```bash
cd /opt
git clone https://github.com/votre-org/camera.ui.git
cd camera.ui
```

### 2. Créer les certificats SSL

Pour HTTPS, vous avez deux options:

#### Option A: Certificats auto-signés (développement)

```bash
mkdir -p nginx/ssl
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout nginx/ssl/key.pem \
  -out nginx/ssl/cert.pem \
  -subj "/C=CD/ST=Kinshasa/L=Kinshasa/O=Mvutu Security/CN=camera.local"
```

#### Option B: Let's Encrypt (production)

```bash
# Installer certbot
sudo apt-get install certbot

# Obtenir un certificat (remplacer votre-domaine.com)
sudo certbot certonly --standalone -d votre-domaine.com

# Copier les certificats
mkdir -p nginx/ssl
sudo cp /etc/letsencrypt/live/votre-domaine.com/fullchain.pem nginx/ssl/cert.pem
sudo cp /etc/letsencrypt/live/votre-domaine.com/privkey.pem nginx/ssl/key.pem
sudo chown -R $USER:$USER nginx/ssl
```

### 3. Créer les dossiers nécessaires

```bash
mkdir -p recordings
mkdir -p nginx/conf.d
mkdir -p mqtt
mkdir -p fail2ban/jail.d
mkdir -p fail2ban/filter.d
```

---

## ⚙️ Configuration

### 1. Variables d'environnement

Créer un fichier `.env`:

```bash
cat > .env << 'EOF'
# ===================================
# Configuration camera.ui
# ===================================

# Timezone
TZ=Africa/Kinshasa

# Port de l'application (interne)
CAMERA_UI_PORT=8081

# Port HTTP externe
HTTP_PORT=80

# Port HTTPS externe
HTTPS_PORT=443

# Port MQTT
MQTT_PORT=1883
MQTT_WS_PORT=9001

# ===================================
# Notifications (Optionnel)
# ===================================

# Telegram
TELEGRAM_BOT_TOKEN=
TELEGRAM_CHAT_ID=

# AWS Rekognition
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
AWS_REGION=us-east-1

# ===================================
# Limites de ressources
# ===================================
CPU_LIMIT=2
MEMORY_LIMIT=2G
EOF
```

### 2. Configuration initiale camera.ui

Au premier démarrage, camera.ui créera automatiquement:
- Base de données dans `/app/data/database/`
- Configuration dans `/app/data/config.json`
- Logs dans `/app/data/logs/`

**Identifiants par défaut:**
- Username: `master`
- Password: `master`

⚠️ **IMPORTANT**: Changez ces identifiants lors de la première connexion!

### 3. Personnaliser le docker-compose (optionnel)

Éditer `docker-compose.yml` selon vos besoins:

```yaml
# Exemple: Désactiver MQTT si non utilisé
services:
  mqtt-broker:
    # Commenter ou supprimer ce service
    # ...

  # Exemple: Exposer un port différent
  nginx-proxy:
    ports:
      - "8080:80"  # Au lieu de 80
      - "8443:443" # Au lieu de 443
```

---

## 🔒 Sécurité

### 1. Firewall système (ufw)

```bash
# Installer ufw
sudo apt-get install ufw

# Règles de base
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Autoriser SSH (important!)
sudo ufw allow 22/tcp

# Autoriser HTTP/HTTPS
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Autoriser MQTT (si utilisé depuis l'extérieur)
sudo ufw allow 1883/tcp

# Activer le firewall
sudo ufw enable
```

### 2. Sécurisation MQTT

Créer un fichier de mot de passe pour MQTT:

```bash
# Dans le conteneur mosquitto
docker exec -it mvutu-mqtt sh
mosquitto_passwd -c /mosquitto/config/passwd admin
exit

# Puis décommenter dans mqtt/mosquitto.conf:
# password_file /mosquitto/config/passwd
```

### 3. Fail2ban Configuration

Les règles sont déjà configurées dans `fail2ban/`. Pour personnaliser:

```bash
# Éditer les paramètres
nano fail2ban/jail.d/nginx.local

# Modifier:
bantime = 7200    # Durée de bannissement (2h)
maxretry = 3      # Nombre de tentatives avant ban
findtime = 600    # Fenêtre de recherche (10min)
```

### 4. Mise à jour des secrets

```bash
# Générer des clés JWT fortes
docker exec -it mvutu-camera-ui sh -c "node -e \"console.log(require('crypto').randomBytes(32).toString('hex'))\""

# Ajouter dans config.json
{
  "jwt": {
    "secret": "votre-clé-générée-ici"
  }
}
```

---

## 🚢 Déploiement

### 1. Build et lancement

```bash
# Build des images
docker-compose build

# Lancer en arrière-plan
docker-compose up -d

# Voir les logs
docker-compose logs -f camera-ui
```

### 2. Vérifier l'état des services

```bash
# État des conteneurs
docker-compose ps

# Santé des services
docker-compose ps | grep healthy
```

### 3. Accès à l'interface

- **HTTP**: http://votre-ip
- **HTTPS**: https://votre-ip
- **API Docs**: https://votre-ip/swagger

### 4. Configuration des caméras

1. Connectez-vous à l'interface web
2. Allez dans **Settings > Cameras**
3. Ajoutez vos caméras RTSP:

```json
{
  "name": "Camera 1",
  "source": "rtsp://admin:password@192.168.1.100:554/stream1",
  "videoanalysis": {
    "active": true
  },
  "prebuffering": true
}
```

---

## 🔧 Maintenance

### Sauvegardes

#### Sauvegarde manuelle

```bash
# Créer un backup complet
docker exec mvutu-camera-ui node bin/camera.ui.js --backup

# Télécharger le backup
docker cp mvutu-camera-ui:/app/data/backup/backup-YYYYMMDD.tar.gz ./
```

#### Sauvegarde automatique (cron)

```bash
# Créer un script de sauvegarde
cat > /opt/backup-camera-ui.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/backup/camera-ui"
mkdir -p $BACKUP_DIR
docker exec mvutu-camera-ui node bin/camera.ui.js --backup
docker cp mvutu-camera-ui:/app/data/backup/. $BACKUP_DIR/
# Garder seulement les 7 derniers jours
find $BACKUP_DIR -name "backup-*.tar.gz" -mtime +7 -delete
EOF

chmod +x /opt/backup-camera-ui.sh

# Ajouter au cron (tous les jours à 3h)
echo "0 3 * * * /opt/backup-camera-ui.sh" | crontab -
```

### Restauration

```bash
# Copier le backup dans le conteneur
docker cp backup-20231115.tar.gz mvutu-camera-ui:/app/data/

# Restaurer
docker exec mvutu-camera-ui node bin/camera.ui.js --restore /app/data/backup-20231115.tar.gz

# Redémarrer
docker-compose restart camera-ui
```

### Mise à jour

```bash
# Sauvegarder avant la mise à jour
docker exec mvutu-camera-ui node bin/camera.ui.js --backup

# Arrêter les services
docker-compose down

# Mettre à jour le code
git pull

# Rebuild et redémarrer
docker-compose build --no-cache
docker-compose up -d
```

### Logs

```bash
# Logs en temps réel
docker-compose logs -f

# Logs d'un service spécifique
docker-compose logs -f camera-ui

# Logs Nginx (pour fail2ban)
docker-compose exec nginx-proxy tail -f /var/log/nginx/access.log

# Logs MQTT
docker-compose logs -f mqtt-broker
```

### Monitoring

```bash
# Utilisation des ressources
docker stats

# Espace disque
df -h
du -sh recordings/

# État des services
docker-compose ps
```

---

## 🐛 Troubleshooting

### Problème: Conteneur ne démarre pas

```bash
# Voir les logs détaillés
docker-compose logs camera-ui

# Vérifier les permissions
ls -la recordings/
sudo chown -R 1000:1000 recordings/
```

### Problème: Erreur de certificat SSL

```bash
# Régénérer les certificats
rm -rf nginx/ssl/*
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout nginx/ssl/key.pem \
  -out nginx/ssl/cert.pem

# Redémarrer nginx
docker-compose restart nginx-proxy
```

### Problème: Caméra ne se connecte pas

```bash
# Tester la connexion RTSP
docker run --rm -it --network=host linuxserver/ffmpeg \
  -i rtsp://admin:password@192.168.1.100:554/stream1 \
  -frames:v 1 -f null -

# Vérifier les logs
docker-compose logs -f camera-ui | grep -i error
```

### Problème: Haute utilisation CPU/RAM

```bash
# Limiter les ressources
docker-compose down
# Éditer docker-compose.yml et ajuster:
# deploy.resources.limits.cpus: '1'
# deploy.resources.limits.memory: 1G
docker-compose up -d
```

### Problème: Échec de détection de mouvement

```bash
# Vérifier la configuration videoanalysis
docker exec -it mvutu-camera-ui cat /app/data/config.json | grep -A 10 videoanalysis

# Vérifier MQTT (si utilisé)
docker exec -it mvutu-mqtt mosquitto_sub -t "#" -v
```

### Problème: Ports déjà utilisés

```bash
# Trouver le processus
sudo netstat -tlnp | grep :80
sudo netstat -tlnp | grep :443

# Arrêter le processus ou changer le port dans docker-compose.yml
```

---

## 📊 Performance

### Optimisations recommandées

#### 1. Utiliser un SSD pour les enregistrements

```bash
# Monter un SSD dédié
sudo mkfs.ext4 /dev/sdb1
sudo mount /dev/sdb1 /mnt/recordings
sudo chown -R 1000:1000 /mnt/recordings

# Modifier docker-compose.yml
volumes:
  - /mnt/recordings:/app/data/recordings
```

#### 2. Ajuster les paramètres de streaming

Dans l'interface camera.ui:

- **Résolution**: 1920x1080 max (pour HSV)
- **FPS**: 25-30
- **Bitrate**: 2-6 Mbit/s
- **Keyframe interval**: FPS × 4

#### 3. Activer le caching Nginx

```bash
# Déjà configuré dans nginx.conf pour les chunks vidéo
# Cache-Control: public, max-age=3600
```

---

## 🔍 Commandes utiles

```bash
# Redémarrer tous les services
docker-compose restart

# Redémarrer un service spécifique
docker-compose restart camera-ui

# Voir les ressources utilisées
docker stats mvutu-camera-ui

# Accéder au shell du conteneur
docker exec -it mvutu-camera-ui sh

# Nettoyer les images inutilisées
docker system prune -a

# Exporter les logs
docker-compose logs > logs-$(date +%Y%m%d).txt

# Vérifier la config Nginx
docker-compose exec nginx-proxy nginx -t

# Recharger Nginx sans downtime
docker-compose exec nginx-proxy nginx -s reload
```

---

## 📞 Support

Pour toute question ou problème:

1. Consultez la [documentation officielle](https://github.com/SeydX/camera.ui/wiki)
2. Vérifiez les [issues GitHub](https://github.com/SeydX/camera.ui/issues)
3. Contactez l'équipe Mvutu Security

---

## 📝 License

MIT License - voir [LICENSE](LICENSE)

---

**Dernière mise à jour**: Novembre 2025  
**Auteur**: Mvutu Security Team

