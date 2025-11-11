#!/bin/bash

# ===================================
# Script de monitoring pour camera.ui
# Vérifie l'état des services et envoie des alertes
# ===================================

set -e

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="/var/log/camera-ui-monitor.log"
ALERT_FILE="/tmp/camera-ui-alerts.txt"

# Seuils d'alerte
CPU_THRESHOLD=80
MEMORY_THRESHOLD=80
DISK_THRESHOLD=90
RESTART_THRESHOLD=3

# Fonctions
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

alert() {
    echo -e "${RED}[ALERTE]${NC} $1" | tee -a "$LOG_FILE" "$ALERT_FILE"
}

success() {
    echo -e "${GREEN}[OK]${NC} $1" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}[ATTENTION]${NC} $1" | tee -a "$LOG_FILE"
}

# Vérifier si un conteneur est en cours d'exécution
check_container_running() {
    local container_name=$1
    
    if docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
        return 0
    else
        return 1
    fi
}

# Vérifier la santé d'un conteneur
check_container_health() {
    local container_name=$1
    
    health_status=$(docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "none")
    
    case $health_status in
        "healthy")
            success "Conteneur $container_name: HEALTHY"
            return 0
            ;;
        "unhealthy")
            alert "Conteneur $container_name: UNHEALTHY"
            return 1
            ;;
        "starting")
            warning "Conteneur $container_name: STARTING..."
            return 2
            ;;
        "none")
            warning "Conteneur $container_name: Pas de healthcheck configuré"
            return 2
            ;;
    esac
}

# Vérifier l'utilisation CPU d'un conteneur
check_container_cpu() {
    local container_name=$1
    
    cpu_usage=$(docker stats --no-stream --format "{{.CPUPerc}}" "$container_name" | sed 's/%//' || echo "0")
    cpu_usage_int=${cpu_usage%.*}
    
    if [ "$cpu_usage_int" -gt "$CPU_THRESHOLD" ]; then
        alert "Conteneur $container_name: CPU élevé (${cpu_usage}%)"
        return 1
    else
        success "Conteneur $container_name: CPU OK (${cpu_usage}%)"
        return 0
    fi
}

# Vérifier l'utilisation mémoire d'un conteneur
check_container_memory() {
    local container_name=$1
    
    mem_usage=$(docker stats --no-stream --format "{{.MemPerc}}" "$container_name" | sed 's/%//' || echo "0")
    mem_usage_int=${mem_usage%.*}
    
    if [ "$mem_usage_int" -gt "$MEMORY_THRESHOLD" ]; then
        alert "Conteneur $container_name: Mémoire élevée (${mem_usage}%)"
        return 1
    else
        success "Conteneur $container_name: Mémoire OK (${mem_usage}%)"
        return 0
    fi
}

# Vérifier le nombre de redémarrages
check_container_restarts() {
    local container_name=$1
    
    restart_count=$(docker inspect --format='{{.RestartCount}}' "$container_name" 2>/dev/null || echo "0")
    
    if [ "$restart_count" -gt "$RESTART_THRESHOLD" ]; then
        alert "Conteneur $container_name: Redémarrages excessifs ($restart_count)"
        return 1
    else
        success "Conteneur $container_name: Redémarrages OK ($restart_count)"
        return 0
    fi
}

# Vérifier l'espace disque
check_disk_space() {
    local path=$1
    
    disk_usage=$(df -h "$path" | tail -1 | awk '{print $5}' | sed 's/%//')
    
    if [ "$disk_usage" -gt "$DISK_THRESHOLD" ]; then
        alert "Espace disque critique: ${disk_usage}% utilisé sur $path"
        return 1
    else
        success "Espace disque OK: ${disk_usage}% utilisé sur $path"
        return 0
    fi
}

# Vérifier l'accessibilité HTTP
check_http_endpoint() {
    local url=$1
    local timeout=${2:-10}
    
    if curl -k -f -s -o /dev/null -w "%{http_code}" --max-time "$timeout" "$url" | grep -q "200"; then
        success "Endpoint accessible: $url"
        return 0
    else
        alert "Endpoint inaccessible: $url"
        return 1
    fi
}

# Vérifier les logs pour les erreurs récentes
check_recent_errors() {
    local container_name=$1
    local minutes=${2:-5}
    
    error_count=$(docker logs --since "${minutes}m" "$container_name" 2>&1 | grep -i "error" | wc -l)
    
    if [ "$error_count" -gt 10 ]; then
        alert "Conteneur $container_name: $error_count erreurs dans les dernières ${minutes} minutes"
        return 1
    elif [ "$error_count" -gt 0 ]; then
        warning "Conteneur $container_name: $error_count erreurs dans les dernières ${minutes} minutes"
        return 0
    else
        success "Conteneur $container_name: Aucune erreur récente"
        return 0
    fi
}

# Redémarrer un conteneur si nécessaire
restart_container_if_unhealthy() {
    local container_name=$1
    
    if ! check_container_health "$container_name"; then
        log "Tentative de redémarrage de $container_name..."
        docker restart "$container_name" &>> "$LOG_FILE"
        sleep 10
        
        if check_container_health "$container_name"; then
            success "Conteneur $container_name redémarré avec succès"
            return 0
        else
            alert "Échec du redémarrage de $container_name"
            return 1
        fi
    fi
}

# Envoyer une notification (à personnaliser)
send_notification() {
    local message=$1
    
    # Option 1: Email (nécessite mailutils)
    # echo "$message" | mail -s "[camera.ui] Alerte" admin@example.com
    
    # Option 2: Webhook
    # curl -X POST -H 'Content-Type: application/json' \
    #     -d "{\"text\":\"$message\"}" \
    #     https://hooks.slack.com/services/YOUR/WEBHOOK/URL
    
    # Option 3: Telegram
    # TELEGRAM_BOT_TOKEN="your_bot_token"
    # TELEGRAM_CHAT_ID="your_chat_id"
    # curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    #     -d chat_id="${TELEGRAM_CHAT_ID}" \
    #     -d text="$message"
    
    log "Notification: $message"
}

# Rapport de monitoring
generate_report() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "                            📊 Rapport de Monitoring camera.ui"
    echo "                                $(date +'%Y-%m-%d %H:%M:%S')"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# Fonction principale de monitoring
main() {
    cd "$PROJECT_DIR" || exit 1
    
    # Supprimer l'ancien fichier d'alertes
    rm -f "$ALERT_FILE"
    
    generate_report
    
    # Vérifier camera.ui
    log "=== Vérification de camera.ui ==="
    if check_container_running "mvutu-camera-ui"; then
        check_container_health "mvutu-camera-ui"
        check_container_cpu "mvutu-camera-ui"
        check_container_memory "mvutu-camera-ui"
        check_container_restarts "mvutu-camera-ui"
        check_recent_errors "mvutu-camera-ui" 5
        check_http_endpoint "https://localhost/version" 10
    else
        alert "Conteneur mvutu-camera-ui n'est pas en cours d'exécution!"
    fi
    
    echo ""
    
    # Vérifier nginx
    log "=== Vérification de nginx ==="
    if check_container_running "mvutu-nginx-proxy"; then
        check_container_health "mvutu-nginx-proxy"
        check_container_cpu "mvutu-nginx-proxy"
        check_container_memory "mvutu-nginx-proxy"
        check_container_restarts "mvutu-nginx-proxy"
    else
        warning "Conteneur mvutu-nginx-proxy n'est pas en cours d'exécution"
    fi
    
    echo ""
    
    # Vérifier MQTT
    log "=== Vérification de MQTT ==="
    if check_container_running "mvutu-mqtt"; then
        check_container_cpu "mvutu-mqtt"
        check_container_memory "mvutu-mqtt"
        check_container_restarts "mvutu-mqtt"
    else
        warning "Conteneur mvutu-mqtt n'est pas en cours d'exécution"
    fi
    
    echo ""
    
    # Vérifier l'espace disque
    log "=== Vérification de l'espace disque ==="
    check_disk_space "$PROJECT_DIR/recordings"
    check_disk_space "/"
    
    echo ""
    
    # Si des alertes existent, envoyer une notification
    if [ -f "$ALERT_FILE" ]; then
        alert_content=$(cat "$ALERT_FILE")
        send_notification "⚠️ Alertes camera.ui détectées:\n\n$alert_content"
    fi
    
    echo ""
    log "Monitoring terminé. Log complet: $LOG_FILE"
}

# Exécution
main "$@"

