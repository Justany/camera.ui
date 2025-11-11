# ===================================
# Makefile pour camera.ui
# Simplifie les commandes Docker
# ===================================

.PHONY: help build up down restart logs status clean backup restore update ssl

# Variables
COMPOSE := docker-compose
SERVICE := camera-ui
NGINX := nginx-proxy
MQTT := mqtt-broker

# Couleurs pour les messages
GREEN := \033[0;32m
YELLOW := \033[0;33m
RED := \033[0;31m
NC := \033[0m # No Color

##@ Aide

help: ## Afficher l'aide
	@echo "$(GREEN)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(GREEN)                            📹 camera.ui - Commandes Docker                                      $(NC)"
	@echo "$(GREEN)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@awk 'BEGIN {FS = ":.*##"; printf "\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  $(YELLOW)%-15s$(NC) %s\n", $$1, $$2 } /^##@/ { printf "\n$(GREEN)%s$(NC)\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
	@echo ""

##@ Installation

install: ## Installation complète (première fois)
	@echo "$(GREEN)🚀 Installation de camera.ui...$(NC)"
	@cp .env.example .env || true
	@echo "$(YELLOW)⚠️  Veuillez éditer le fichier .env avant de continuer$(NC)"
	@echo "$(YELLOW)⚠️  Exécutez 'make ssl' pour générer les certificats SSL$(NC)"
	@echo "$(GREEN)✅ Installation terminée. Exécutez 'make up' pour démarrer.$(NC)"

ssl: ## Générer les certificats SSL auto-signés
	@echo "$(GREEN)🔐 Génération des certificats SSL...$(NC)"
	@mkdir -p nginx/ssl
	@openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
		-keyout nginx/ssl/key.pem \
		-out nginx/ssl/cert.pem \
		-subj "/C=CD/ST=Kinshasa/L=Kinshasa/O=Mvutu Security/CN=camera.local"
	@chmod 600 nginx/ssl/key.pem
	@echo "$(GREEN)✅ Certificats SSL générés.$(NC)"

##@ Déploiement

build: ## Build les images Docker
	@echo "$(GREEN)🔨 Build des images Docker...$(NC)"
	@$(COMPOSE) build --no-cache
	@echo "$(GREEN)✅ Build terminé.$(NC)"

up: ## Démarrer tous les services
	@echo "$(GREEN)🚀 Démarrage des services...$(NC)"
	@$(COMPOSE) up -d
	@echo "$(GREEN)✅ Services démarrés.$(NC)"
	@echo "$(YELLOW)📍 Interface web: https://localhost$(NC)"
	@echo "$(YELLOW)📍 API Docs: https://localhost/swagger$(NC)"

down: ## Arrêter tous les services
	@echo "$(YELLOW)🛑 Arrêt des services...$(NC)"
	@$(COMPOSE) down
	@echo "$(GREEN)✅ Services arrêtés.$(NC)"

restart: ## Redémarrer tous les services
	@echo "$(YELLOW)🔄 Redémarrage des services...$(NC)"
	@$(COMPOSE) restart
	@echo "$(GREEN)✅ Services redémarrés.$(NC)"

restart-app: ## Redémarrer uniquement camera.ui
	@echo "$(YELLOW)🔄 Redémarrage de camera.ui...$(NC)"
	@$(COMPOSE) restart $(SERVICE)
	@echo "$(GREEN)✅ camera.ui redémarré.$(NC)"

restart-nginx: ## Redémarrer uniquement nginx
	@echo "$(YELLOW)🔄 Redémarrage de nginx...$(NC)"
	@$(COMPOSE) restart $(NGINX)
	@echo "$(GREEN)✅ nginx redémarré.$(NC)"

reload-nginx: ## Recharger la config nginx sans downtime
	@echo "$(YELLOW)🔄 Rechargement de nginx...$(NC)"
	@$(COMPOSE) exec $(NGINX) nginx -t && $(COMPOSE) exec $(NGINX) nginx -s reload
	@echo "$(GREEN)✅ nginx rechargé.$(NC)"

##@ Monitoring

status: ## Afficher l'état des services
	@echo "$(GREEN)📊 État des services:$(NC)"
	@$(COMPOSE) ps

logs: ## Afficher les logs en temps réel
	@$(COMPOSE) logs -f

logs-app: ## Logs de camera.ui uniquement
	@$(COMPOSE) logs -f $(SERVICE)

logs-nginx: ## Logs de nginx uniquement
	@$(COMPOSE) logs -f $(NGINX)

logs-mqtt: ## Logs de MQTT uniquement
	@$(COMPOSE) logs -f $(MQTT)

stats: ## Afficher les statistiques de ressources
	@echo "$(GREEN)📊 Utilisation des ressources:$(NC)"
	@docker stats --no-stream

health: ## Vérifier la santé des services
	@echo "$(GREEN)🏥 Vérification de la santé des services:$(NC)"
	@$(COMPOSE) ps | grep -E "healthy|unhealthy" || echo "$(YELLOW)Aucun healthcheck configuré$(NC)"

##@ Maintenance

backup: ## Créer une sauvegarde complète
	@echo "$(GREEN)💾 Création d'une sauvegarde...$(NC)"
	@mkdir -p backups
	@docker exec mvutu-camera-ui node bin/camera.ui.js --backup
	@docker cp mvutu-camera-ui:/app/data/backup/. ./backups/
	@echo "$(GREEN)✅ Sauvegarde créée dans ./backups/$(NC)"

restore: ## Restaurer depuis une sauvegarde (make restore FILE=backup.tar.gz)
	@if [ -z "$(FILE)" ]; then \
		echo "$(RED)❌ Erreur: Spécifiez un fichier avec FILE=backup.tar.gz$(NC)"; \
		exit 1; \
	fi
	@echo "$(YELLOW)📦 Restauration de la sauvegarde $(FILE)...$(NC)"
	@docker cp ./backups/$(FILE) mvutu-camera-ui:/app/data/
	@docker exec mvutu-camera-ui node bin/camera.ui.js --restore /app/data/$(FILE)
	@$(COMPOSE) restart $(SERVICE)
	@echo "$(GREEN)✅ Restauration terminée.$(NC)"

update: ## Mettre à jour camera.ui
	@echo "$(YELLOW)📦 Mise à jour de camera.ui...$(NC)"
	@make backup
	@git pull
	@make build
	@make up
	@echo "$(GREEN)✅ Mise à jour terminée.$(NC)"

clean: ## Nettoyer les conteneurs et volumes inutilisés
	@echo "$(YELLOW)🧹 Nettoyage...$(NC)"
	@docker system prune -f
	@echo "$(GREEN)✅ Nettoyage terminé.$(NC)"

clean-all: ## Nettoyer TOUT (images, volumes, etc.) ⚠️ DANGEREUX
	@echo "$(RED)⚠️  ATTENTION: Cela va supprimer TOUTES les données Docker non utilisées!$(NC)"
	@echo "$(RED)⚠️  Appuyez sur Ctrl+C pour annuler...$(NC)"
	@sleep 5
	@docker system prune -a --volumes -f
	@echo "$(GREEN)✅ Nettoyage complet terminé.$(NC)"

##@ Utilitaires

shell: ## Ouvrir un shell dans le conteneur camera.ui
	@$(COMPOSE) exec $(SERVICE) sh

shell-nginx: ## Ouvrir un shell dans le conteneur nginx
	@$(COMPOSE) exec $(NGINX) sh

shell-mqtt: ## Ouvrir un shell dans le conteneur MQTT
	@$(COMPOSE) exec $(MQTT) sh

config-test: ## Tester la configuration nginx
	@echo "$(GREEN)🧪 Test de la configuration nginx...$(NC)"
	@$(COMPOSE) exec $(NGINX) nginx -t

config-show: ## Afficher la config camera.ui actuelle
	@docker exec mvutu-camera-ui cat /app/data/config.json | jq .

mqtt-test: ## Tester la connexion MQTT
	@echo "$(GREEN)🧪 Test de la connexion MQTT...$(NC)"
	@docker exec mvutu-mqtt mosquitto_sub -t "$$SYS/#" -C 1 -v

disk-usage: ## Afficher l'utilisation du disque
	@echo "$(GREEN)💾 Utilisation du disque:$(NC)"
	@du -sh recordings/ 2>/dev/null || echo "$(YELLOW)Aucun enregistrement$(NC)"
	@docker system df

export-logs: ## Exporter les logs vers un fichier
	@echo "$(GREEN)📝 Export des logs...$(NC)"
	@$(COMPOSE) logs > logs-$$(date +%Y%m%d-%H%M%S).txt
	@echo "$(GREEN)✅ Logs exportés.$(NC)"

##@ Développement

dev-build: ## Build en mode développement (avec cache)
	@echo "$(GREEN)🔨 Build développement...$(NC)"
	@$(COMPOSE) build
	@echo "$(GREEN)✅ Build terminé.$(NC)"

dev-up: ## Démarrer en mode développement (avec logs)
	@echo "$(GREEN)🚀 Démarrage en mode développement...$(NC)"
	@$(COMPOSE) up

dev-restart: down dev-build up ## Redémarrage complet en dev

##@ Production

prod-deploy: backup build up ## Déploiement production complet
	@echo "$(GREEN)🚀 Déploiement en production...$(NC)"
	@echo "$(GREEN)✅ Déploiement terminé.$(NC)"
	@make status
	@make health

prod-rollback: ## Rollback vers la dernière sauvegarde
	@echo "$(RED)⚠️  Rollback vers la dernière sauvegarde...$(NC)"
	@LATEST=$$(ls -t backups/*.tar.gz 2>/dev/null | head -1); \
	if [ -z "$$LATEST" ]; then \
		echo "$(RED)❌ Aucune sauvegarde trouvée$(NC)"; \
		exit 1; \
	fi; \
	echo "$(YELLOW)Restauration de $$LATEST$(NC)"; \
	make restore FILE=$$(basename $$LATEST)

##@ Docker Compose

ps: ## Liste des conteneurs
	@$(COMPOSE) ps

pull: ## Télécharger les images
	@$(COMPOSE) pull

images: ## Liste des images
	@docker images | grep -E "camera-ui|nginx|mosquitto"

volumes: ## Liste des volumes
	@docker volume ls | grep camera

networks: ## Liste des réseaux
	@docker network ls | grep camera

