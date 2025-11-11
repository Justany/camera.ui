# 🚀 Démarrage Rapide - camera.ui Docker

Guide rapide pour déployer camera.ui avec Docker en moins de 5 minutes.

## ⚡ Installation Express

### 1. Prérequis

- Docker et Docker Compose installés
- Minimum 2 Go RAM, 20 Go d'espace disque

### 2. Déploiement Automatique

```bash
# Cloner ou accéder au projet
cd /path/to/camera.ui

# Exécuter le script de déploiement automatique
chmod +x scripts/deploy.sh
sudo ./scripts/deploy.sh
```

Le script va automatiquement:
- ✅ Vérifier les prérequis
- ✅ Créer les répertoires nécessaires
- ✅ Générer les certificats SSL
- ✅ Configurer l'environnement
- ✅ Configurer le firewall
- ✅ Build et démarrer les services

### 3. Déploiement Manuel (Alternatif)

Si vous préférez contrôler chaque étape:

```bash
# 1. Copier l'exemple de configuration
cp .env.example .env

# 2. Générer les certificats SSL
make ssl

# 3. Build et démarrer
make build
make up
```

## 🎯 Accès à l'Interface

- **Interface Web**: https://votre-ip
- **API Documentation**: https://votre-ip/swagger

**Identifiants par défaut:**
- Username: `master`
- Password: `master`

⚠️ **Changez ces identifiants immédiatement!**

## 📋 Commandes Essentielles

```bash
# Via Makefile (recommandé)
make help          # Afficher toutes les commandes
make status        # État des services
make logs          # Voir les logs en temps réel
make restart       # Redémarrer les services
make backup        # Créer une sauvegarde
make update        # Mettre à jour camera.ui

# Via Docker Compose (alternatif)
docker-compose ps           # État des conteneurs
docker-compose logs -f      # Logs en temps réel
docker-compose restart      # Redémarrer
docker-compose down         # Arrêter
docker-compose up -d        # Démarrer
```

## 🎥 Configuration des Caméras

1. Connectez-vous à l'interface web
2. Allez dans **Settings** → **Cameras**
3. Cliquez sur **Add Camera**
4. Entrez les informations de votre caméra RTSP:

```json
{
  "name": "Camera Entrée",
  "source": "rtsp://admin:password@192.168.1.100:554/stream1",
  "videoanalysis": {
    "active": true
  },
  "prebuffering": true,
  "recorder": {
    "active": true
  }
}
```

5. Sauvegardez et testez le stream

## 🔒 Sécurité Recommandée

### 1. Changer les identifiants par défaut
Lors de la première connexion, changez immédiatement le username et password.

### 2. Configurer HTTPS avec Let's Encrypt (Production)

```bash
# Installer certbot
sudo apt-get install certbot

# Obtenir un certificat (remplacer votre-domaine.com)
sudo certbot certonly --standalone -d votre-domaine.com

# Copier les certificats
sudo cp /etc/letsencrypt/live/votre-domaine.com/fullchain.pem nginx/ssl/cert.pem
sudo cp /etc/letsencrypt/live/votre-domaine.com/privkey.pem nginx/ssl/key.pem

# Redémarrer nginx
make restart-nginx
```

### 3. Activer Fail2ban

Fail2ban est déjà configuré dans le docker-compose.yml. Il bannira automatiquement les IPs malveillantes.

### 4. Configurer le firewall

```bash
# UFW (Ubuntu/Debian)
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 80/tcp    # HTTP
sudo ufw allow 443/tcp   # HTTPS
sudo ufw enable
```

## 📊 Monitoring

### Vérifier l'état de santé

```bash
# Vérification manuelle
make health

# Script de monitoring automatique
chmod +x scripts/monitor.sh
./scripts/monitor.sh

# Monitoring automatique (cron - toutes les 5 minutes)
echo "*/5 * * * * /path/to/camera.ui/scripts/monitor.sh >> /var/log/camera-ui-monitor.log 2>&1" | crontab -
```

## 💾 Sauvegardes

### Sauvegarde manuelle

```bash
make backup
```

Les sauvegardes sont stockées dans `./backups/`

### Sauvegarde automatique (cron)

```bash
# Tous les jours à 3h du matin
echo "0 3 * * * cd /path/to/camera.ui && make backup" | crontab -
```

### Restauration

```bash
make restore FILE=backup-20231115.tar.gz
```

## 🔧 Troubleshooting

### Problème: Conteneur ne démarre pas

```bash
# Voir les logs détaillés
make logs-app

# Vérifier les permissions
sudo chown -R 1000:1000 recordings/
```

### Problème: Erreur SSL/Certificat

```bash
# Régénérer les certificats
rm -rf nginx/ssl/*
make ssl
make restart-nginx
```

### Problème: Caméra ne se connecte pas

```bash
# Tester la connexion RTSP depuis le conteneur
docker exec -it mvutu-camera-ui sh
apk add ffmpeg
ffmpeg -i rtsp://admin:password@192.168.1.100:554/stream1 -frames:v 1 -f null -
```

### Problème: Haute utilisation CPU/RAM

```bash
# Vérifier l'utilisation
make stats

# Ajuster les limites dans docker-compose.yml:
# deploy.resources.limits.cpus: '1'
# deploy.resources.limits.memory: 1G

# Redémarrer
make restart
```

## 📡 Configuration MQTT (Optionnel)

Si vous utilisez la détection de mouvement via MQTT:

1. MQTT est déjà déployé sur le port 1883
2. Configurez vos caméras/capteurs pour publier sur:
   - Broker: `votre-ip:1883`
   - Topic: `camera-ui/motion/[nom_camera]`
   - Message: `ON` ou JSON

## 🌐 Intégration avec d'autres services

### HomeKit via Homebridge

Installez le plugin `homebridge-camera-ui` depuis Homebridge Config UI X.

### Notifications Telegram

1. Créez un bot via @BotFather
2. Obtenez votre Chat ID via @userinfobot
3. Éditez `.env`:

```bash
TELEGRAM_BOT_TOKEN=123456789:ABCdefGHIjklMNOpqrsTUVwxyz
TELEGRAM_CHAT_ID=123456789
```

4. Redémarrez: `make restart`

## 📚 Documentation Complète

Pour plus de détails, consultez:
- [DOCKER_DEPLOYMENT.md](DOCKER_DEPLOYMENT.md) - Guide complet de déploiement
- [README.md](README.md) - Documentation officielle camera.ui

## 🆘 Support

- **GitHub Issues**: https://github.com/SeydX/camera.ui/issues
- **Wiki**: https://github.com/seydx/homebridge-camera-ui/wiki
- **Discord**: [Rejoindre la communauté](https://discord.gg/camera-ui)

---

**Durée d'installation**: ~5 minutes  
**Dernière mise à jour**: Novembre 2025  
**Auteur**: Mvutu Security Team

