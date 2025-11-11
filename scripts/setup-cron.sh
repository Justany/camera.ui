#!/bin/bash

# ===================================
# Configuration des tâches cron pour camera.ui
# ===================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}                            📅 Configuration des tâches automatiques                              ${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Créer les scripts dans /opt pour faciliter l'accès
echo -e "${GREEN}1. Création des scripts dans /opt...${NC}"
sudo mkdir -p /opt/camera-ui-scripts

# Script de sauvegarde
cat > /tmp/backup-camera-ui.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/backup/camera-ui"
PROJECT_DIR="/opt/camera.ui"  # Ajuster selon votre installation

mkdir -p $BACKUP_DIR
cd $PROJECT_DIR
docker exec mvutu-camera-ui node bin/camera.ui.js --backup 2>&1 | logger -t camera-ui-backup
docker cp mvutu-camera-ui:/app/data/backup/. $BACKUP_DIR/ 2>&1 | logger -t camera-ui-backup

# Garder seulement les 7 derniers jours
find $BACKUP_DIR -name "backup-*.tar.gz" -mtime +7 -delete 2>&1 | logger -t camera-ui-backup

# Notification en cas d'erreur
if [ $? -ne 0 ]; then
    echo "Erreur lors de la sauvegarde camera.ui" | logger -t camera-ui-backup -p user.err
fi
EOF

sudo mv /tmp/backup-camera-ui.sh /opt/camera-ui-scripts/backup.sh
sudo chmod +x /opt/camera-ui-scripts/backup.sh

# Script de monitoring
cat > /tmp/monitor-camera-ui.sh << EOF
#!/bin/bash
${SCRIPT_DIR}/monitor.sh >> /var/log/camera-ui-monitor.log 2>&1
EOF

sudo mv /tmp/monitor-camera-ui.sh /opt/camera-ui-scripts/monitor.sh
sudo chmod +x /opt/camera-ui-scripts/monitor.sh

# Script de nettoyage des enregistrements anciens
cat > /tmp/cleanup-recordings.sh << 'EOF'
#!/bin/bash
RECORDINGS_DIR="/opt/camera.ui/recordings"  # Ajuster selon votre installation
RETENTION_DAYS=30  # Nombre de jours à conserver

find $RECORDINGS_DIR -type f -mtime +$RETENTION_DAYS -delete 2>&1 | logger -t camera-ui-cleanup
echo "Nettoyage des enregistrements > $RETENTION_DAYS jours effectué" | logger -t camera-ui-cleanup
EOF

sudo mv /tmp/cleanup-recordings.sh /opt/camera-ui-scripts/cleanup-recordings.sh
sudo chmod +x /opt/camera-ui-scripts/cleanup-recordings.sh

# Script de mise à jour des certificats Let's Encrypt
cat > /tmp/renew-ssl.sh << 'EOF'
#!/bin/bash
PROJECT_DIR="/opt/camera.ui"  # Ajuster selon votre installation

# Renouveler les certificats
certbot renew --quiet 2>&1 | logger -t camera-ui-ssl

# Copier les nouveaux certificats si le renouvellement a réussi
if [ $? -eq 0 ]; then
    DOMAIN=$(cat ${PROJECT_DIR}/.env | grep DOMAIN_NAME | cut -d'=' -f2)
    if [ ! -z "$DOMAIN" ]; then
        cp /etc/letsencrypt/live/${DOMAIN}/fullchain.pem ${PROJECT_DIR}/nginx/ssl/cert.pem
        cp /etc/letsencrypt/live/${DOMAIN}/privkey.pem ${PROJECT_DIR}/nginx/ssl/key.pem
        
        # Recharger nginx
        cd $PROJECT_DIR
        docker-compose exec nginx-proxy nginx -s reload 2>&1 | logger -t camera-ui-ssl
    fi
fi
EOF

sudo mv /tmp/renew-ssl.sh /opt/camera-ui-scripts/renew-ssl.sh
sudo chmod +x /opt/camera-ui-scripts/renew-ssl.sh

echo -e "${GREEN}✓ Scripts créés dans /opt/camera-ui-scripts/${NC}"
echo ""

# Proposer les tâches cron
echo -e "${BLUE}2. Tâches cron recommandées:${NC}"
echo ""
echo -e "${YELLOW}a) Sauvegarde quotidienne (3h du matin)${NC}"
echo "   0 3 * * * /opt/camera-ui-scripts/backup.sh"
echo ""
echo -e "${YELLOW}b) Monitoring toutes les 5 minutes${NC}"
echo "   */5 * * * * /opt/camera-ui-scripts/monitor.sh"
echo ""
echo -e "${YELLOW}c) Nettoyage des enregistrements (tous les dimanches à 4h)${NC}"
echo "   0 4 * * 0 /opt/camera-ui-scripts/cleanup-recordings.sh"
echo ""
echo -e "${YELLOW}d) Renouvellement SSL Let's Encrypt (tous les mois)${NC}"
echo "   0 2 1 * * /opt/camera-ui-scripts/renew-ssl.sh"
echo ""
echo -e "${YELLOW}e) Redémarrage hebdomadaire (tous les lundis à 5h)${NC}"
echo "   0 5 * * 1 cd /opt/camera.ui && docker-compose restart"
echo ""

# Demander confirmation
echo -e "${GREEN}Voulez-vous installer ces tâches cron automatiquement? (y/n)${NC}"
read -r response

if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    # Créer un fichier crontab temporaire
    crontab -l > /tmp/current-crontab 2>/dev/null || touch /tmp/current-crontab
    
    # Ajouter les tâches si elles n'existent pas déjà
    grep -q "camera-ui-scripts/backup.sh" /tmp/current-crontab || \
        echo "0 3 * * * /opt/camera-ui-scripts/backup.sh" >> /tmp/current-crontab
    
    grep -q "camera-ui-scripts/monitor.sh" /tmp/current-crontab || \
        echo "*/5 * * * * /opt/camera-ui-scripts/monitor.sh" >> /tmp/current-crontab
    
    grep -q "camera-ui-scripts/cleanup-recordings.sh" /tmp/current-crontab || \
        echo "0 4 * * 0 /opt/camera-ui-scripts/cleanup-recordings.sh" >> /tmp/current-crontab
    
    grep -q "camera-ui-scripts/renew-ssl.sh" /tmp/current-crontab || \
        echo "0 2 1 * * /opt/camera-ui-scripts/renew-ssl.sh" >> /tmp/current-crontab
    
    grep -q "docker-compose restart" /tmp/current-crontab || \
        echo "0 5 * * 1 cd ${PROJECT_DIR} && docker-compose restart" >> /tmp/current-crontab
    
    # Installer le nouveau crontab
    crontab /tmp/current-crontab
    rm /tmp/current-crontab
    
    echo ""
    echo -e "${GREEN}✓ Tâches cron installées avec succès!${NC}"
    echo ""
    echo -e "${BLUE}Pour voir les tâches installées:${NC}"
    echo "  crontab -l"
    echo ""
    echo -e "${BLUE}Pour éditer les tâches:${NC}"
    echo "  crontab -e"
    echo ""
else
    echo ""
    echo -e "${YELLOW}Installation des tâches cron annulée.${NC}"
    echo -e "${BLUE}Vous pouvez les installer manuellement avec:${NC}"
    echo "  crontab -e"
    echo ""
fi

# Créer les répertoires de logs
echo -e "${GREEN}3. Création des répertoires de logs...${NC}"
sudo mkdir -p /var/log/camera-ui
sudo touch /var/log/camera-ui-monitor.log
sudo chmod 664 /var/log/camera-ui-monitor.log

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}                            ✅ Configuration terminée                                              ${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${BLUE}📝 Scripts disponibles:${NC}"
echo "  - /opt/camera-ui-scripts/backup.sh"
echo "  - /opt/camera-ui-scripts/monitor.sh"
echo "  - /opt/camera-ui-scripts/cleanup-recordings.sh"
echo "  - /opt/camera-ui-scripts/renew-ssl.sh"
echo ""
echo -e "${BLUE}📊 Logs:${NC}"
echo "  - /var/log/camera-ui-monitor.log"
echo "  - journalctl -t camera-ui-backup"
echo "  - journalctl -t camera-ui-cleanup"
echo "  - journalctl -t camera-ui-ssl"
echo ""

