#!/bin/bash

# ===================================
# Script de déploiement automatique
# camera.ui sur infrastructure TPS/Cloud
# ===================================

set -e

# Couleurs pour les messages
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="/tmp/camera-ui-deploy-$(date +%Y%m%d-%H%M%S).log"

# Fonctions utilitaires
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERREUR]${NC} $1" | tee -a "$LOG_FILE"
    exit 1
}

warning() {
    echo -e "${YELLOW}[ATTENTION]${NC} $1" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

# Vérifier que le script est exécuté en tant que root ou avec sudo
check_root() {
    if [ "$EUID" -eq 0 ]; then
        warning "Script exécuté en tant que root. Utilisez sudo si possible."
    fi
}

# Vérifier les prérequis
check_requirements() {
    log "Vérification des prérequis..."
    
    # Vérifier Docker
    if ! command -v docker &> /dev/null; then
        error "Docker n'est pas installé. Veuillez l'installer d'abord."
    fi
    info "✓ Docker installé: $(docker --version)"
    
    # Vérifier Docker Compose
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        error "Docker Compose n'est pas installé. Veuillez l'installer d'abord."
    fi
    info "✓ Docker Compose installé"
    
    # Vérifier l'espace disque (minimum 20 Go)
    available_space=$(df -BG "$PROJECT_DIR" | tail -1 | awk '{print $4}' | sed 's/G//')
    if [ "$available_space" -lt 20 ]; then
        warning "Espace disque insuffisant: ${available_space}G disponibles (minimum 20G recommandé)"
    else
        info "✓ Espace disque suffisant: ${available_space}G disponibles"
    fi
    
    # Vérifier la RAM (minimum 2 Go)
    total_ram=$(free -g | awk '/^Mem:/{print $2}')
    if [ "$total_ram" -lt 2 ]; then
        warning "RAM insuffisante: ${total_ram}G disponible (minimum 2G recommandé)"
    else
        info "✓ RAM suffisante: ${total_ram}G disponible"
    fi
}

# Créer les répertoires nécessaires
create_directories() {
    log "Création des répertoires nécessaires..."
    
    cd "$PROJECT_DIR" || error "Impossible d'accéder au répertoire du projet"
    
    mkdir -p recordings
    mkdir -p backups
    mkdir -p nginx/ssl
    mkdir -p nginx/conf.d
    mkdir -p mqtt
    mkdir -p fail2ban/jail.d
    mkdir -p fail2ban/filter.d
    mkdir -p logs
    
    info "✓ Répertoires créés"
}

# Générer les certificats SSL
generate_ssl_certificates() {
    log "Génération des certificats SSL..."
    
    if [ -f "nginx/ssl/cert.pem" ] && [ -f "nginx/ssl/key.pem" ]; then
        warning "Certificats SSL déjà existants. Ignorer la génération."
        return
    fi
    
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout nginx/ssl/key.pem \
        -out nginx/ssl/cert.pem \
        -subj "/C=CD/ST=Kinshasa/L=Kinshasa/O=Mvutu Security/CN=camera.mvutu.local" \
        &>> "$LOG_FILE"
    
    chmod 600 nginx/ssl/key.pem
    
    info "✓ Certificats SSL générés"
}

# Créer le fichier .env si nécessaire
setup_environment() {
    log "Configuration de l'environnement..."
    
    if [ ! -f ".env" ]; then
        if [ -f ".env.example" ]; then
            cp .env.example .env
            info "✓ Fichier .env créé depuis .env.example"
            warning "Veuillez éditer le fichier .env avant de continuer"
            read -p "Appuyez sur Entrée pour éditer le fichier .env maintenant..." -r
            ${EDITOR:-nano} .env
        else
            warning "Fichier .env.example non trouvé. Création d'un .env par défaut..."
            cat > .env << 'EOF'
TZ=Africa/Kinshasa
HTTP_PORT=80
HTTPS_PORT=443
MQTT_PORT=1883
MQTT_WS_PORT=9001
CPU_LIMIT=2
MEMORY_LIMIT=2G
DEBUG_MODE=false
LOG_LEVEL=info
EOF
            info "✓ Fichier .env par défaut créé"
        fi
    else
        info "✓ Fichier .env existant"
    fi
}

# Configurer le firewall
setup_firewall() {
    log "Configuration du firewall..."
    
    if command -v ufw &> /dev/null; then
        info "Configuration d'UFW..."
        
        # Vérifier si UFW est installé et actif
        if sudo ufw status | grep -q "Status: active"; then
            warning "UFW est déjà actif"
        else
            # Autoriser SSH avant d'activer
            sudo ufw allow 22/tcp comment 'SSH' &>> "$LOG_FILE"
        fi
        
        # Autoriser les ports nécessaires
        sudo ufw allow 80/tcp comment 'HTTP camera.ui' &>> "$LOG_FILE"
        sudo ufw allow 443/tcp comment 'HTTPS camera.ui' &>> "$LOG_FILE"
        sudo ufw allow 1883/tcp comment 'MQTT' &>> "$LOG_FILE"
        
        info "✓ Règles firewall configurées"
    else
        warning "UFW n'est pas installé. Configuration du firewall ignorée."
    fi
}

# Build des images Docker
build_images() {
    log "Build des images Docker..."
    
    cd "$PROJECT_DIR" || error "Impossible d'accéder au répertoire du projet"
    
    docker-compose build --no-cache &>> "$LOG_FILE" || error "Échec du build Docker"
    
    info "✓ Images Docker construites"
}

# Démarrer les services
start_services() {
    log "Démarrage des services..."
    
    cd "$PROJECT_DIR" || error "Impossible d'accéder au répertoire du projet"
    
    docker-compose up -d &>> "$LOG_FILE" || error "Échec du démarrage des services"
    
    info "✓ Services démarrés"
}

# Vérifier l'état des services
check_services() {
    log "Vérification de l'état des services..."
    
    sleep 5
    
    # Vérifier que les conteneurs sont en cours d'exécution
    if docker-compose ps | grep -q "Up"; then
        info "✓ Les conteneurs sont en cours d'exécution"
    else
        error "Les conteneurs ne sont pas en cours d'exécution"
    fi
    
    # Attendre que camera.ui soit prêt
    log "Attente du démarrage de camera.ui..."
    for i in {1..30}; do
        if curl -k -f https://localhost/version &> /dev/null; then
            info "✓ camera.ui est opérationnel"
            break
        fi
        
        if [ $i -eq 30 ]; then
            error "Timeout: camera.ui ne répond pas après 30 secondes"
        fi
        
        sleep 1
    done
}

# Afficher les informations de déploiement
show_deployment_info() {
    log "Déploiement terminé avec succès!"
    
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}                            📹 camera.ui - Déploiement terminé                                    ${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${BLUE}📍 Accès à l'interface:${NC}"
    echo -e "   • HTTP:  http://$(hostname -I | awk '{print $1}')"
    echo -e "   • HTTPS: https://$(hostname -I | awk '{print $1}')"
    echo ""
    echo -e "${BLUE}📍 API Documentation:${NC}"
    echo -e "   • Swagger: https://$(hostname -I | awk '{print $1}')/swagger"
    echo ""
    echo -e "${BLUE}🔐 Identifiants par défaut:${NC}"
    echo -e "   • Username: ${YELLOW}master${NC}"
    echo -e "   • Password: ${YELLOW}master${NC}"
    echo -e "   ${RED}⚠️  Changez ces identifiants lors de la première connexion!${NC}"
    echo ""
    echo -e "${BLUE}📊 Commandes utiles:${NC}"
    echo -e "   • Voir les logs:        ${YELLOW}docker-compose logs -f${NC}"
    echo -e "   • Arrêter:              ${YELLOW}docker-compose down${NC}"
    echo -e "   • Redémarrer:           ${YELLOW}docker-compose restart${NC}"
    echo -e "   • État des services:    ${YELLOW}docker-compose ps${NC}"
    echo -e "   • Utiliser le Makefile: ${YELLOW}make help${NC}"
    echo ""
    echo -e "${BLUE}📝 Log de déploiement:${NC} $LOG_FILE"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Fonction principale
main() {
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}                            📹 Déploiement de camera.ui                                          ${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    check_root
    check_requirements
    create_directories
    generate_ssl_certificates
    setup_environment
    setup_firewall
    build_images
    start_services
    check_services
    show_deployment_info
}

# Gestion des erreurs
trap 'error "Une erreur est survenue. Consultez le log: $LOG_FILE"' ERR

# Exécution
main "$@"

