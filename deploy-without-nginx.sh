#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log_info()  { echo -e "\e[32m[INFO]\e[0m $*"; }
log_warn()  { echo -e "\e[33m[WARN]\e[0m $*"; }
log_error() { echo -e "\e[31m[ERROR]\e[0m $*"; }

log_info "[0/3] Chargement du fichier .env global (si présent)..."
if [ -f "$PROJECT_ROOT/.env" ]; then
  set -a
  . "$PROJECT_ROOT/.env"
  set +a
  log_info ".env chargé."
else
  log_warn "Aucun fichier .env trouvé, utilisation des valeurs par défaut des docker-compose."
fi

# Récupérer l'adresse IP principale de la VM
VM_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
if [ -z "${VM_IP:-}" ]; then
  VM_IP="127.0.0.1"
  log_warn "Impossible de détecter l'IP de la VM, utilisation de ${VM_IP}."
else
  log_info "Adresse IP détectée : ${VM_IP}"
fi

install_docker() {
  log_info "Installation de Docker (Ubuntu/Debian)..."
  apt-get update -y
  apt-get install -y ca-certificates curl gnupg lsb-release

  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
$(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list

  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  log_info "Docker installé avec succès."
}

# 1) Vérifier / installer Docker
if ! command -v docker >/dev/null 2>&1; then
  install_docker
else
  log_info "Docker déjà installé."
fi

if ! docker compose version >/dev/null 2>&1; then
  log_error "La sous-commande 'docker compose' n'est pas disponible (version trop ancienne ?)."
  exit 1
fi

# 2) Créer le réseau Docker externe si nécessaire
if ! docker network ls | grep -q "esir-net"; then
  log_info "Réseau Docker 'esir-net' absent, création..."
  docker network create esir-net
  log_info "Réseau 'esir-net' créé."
else
  log_info "Réseau Docker 'esir-net' déjà présent."
fi

# 2bis) Adapter les URLs externes pour le mode sans Nginx

# On utilise directement les ports définis dans .env
SYNCTHING_HTTP_PORT="${SYNCTHING_HTTP_PORT:-8384}"
TRILIUM_HTTP_PORT="${TRILIUM_HTTP_PORT:-8180}"
VAULTWARDEN_HTTP_PORT="${VAULTWARDEN_HTTP_PORT:-4044}"

if [ -d "$PROJECT_ROOT/triliumnotes" ]; then
  log_info "Adaptation de Trilium pour un accès direct (sans Nginx)..."
  export APP_BASE_URL="http://${VM_IP}:${TRILIUM_HTTP_PORT}"
fi

if [ -d "$PROJECT_ROOT/vaultwarden" ]; then
  log_info "Adaptation de Vaultwarden pour un accès direct (sans Nginx)..."
  export DOMAIN="http://${VM_IP}:${VAULTWARDEN_HTTP_PORT}"
fi

# 2ter) Nettoyage préventif du volume WordPress app (wp-content/themes cassé)
if docker volume ls --format '{{.Name}}' | grep -q '^wordpress_wordpress_app_data$'; then
  log_warn "Volume wordpress_wordpress_app_data déjà présent, vérification du contenu..."
  WP_VOL_PATH="$(docker volume inspect wordpress_wordpress_app_data --format '{{ .Mountpoint }}')"
  if [ -n "${WP_VOL_PATH}" ] && [ -d "${WP_VOL_PATH}/wp-content" ]; then
    if [ -f "${WP_VOL_PATH}/wp-content/themes" ]; then
      log_warn "wp-content/themes est un fichier, suppression pour éviter l'erreur Docker."
      sudo rm -f "${WP_VOL_PATH}/wp-content/themes"
    fi
  fi
fi

# 3) Démarrage des services Docker (sans toucher à Nginx)
log_info "[1/3] Démarrage des services Docker (sans Nginx)..."

start_compose() {
  local dir="$1"
  local extra_args="${2:-}"
  if [ -d "$PROJECT_ROOT/$dir" ]; then
    log_info "Démarrage du service '$dir'..."
    (
      cd "$PROJECT_ROOT/$dir"
      if docker compose $extra_args up -d; then
        log_info "Service '$dir' démarré avec succès."
      else
        log_error "Échec du démarrage du service '$dir'."
      fi
    )
  else
    log_warn "Dossier '$dir' introuvable, service ignoré."
  fi
}

start_compose "gitea"
start_compose "wordpress"
start_compose "nextcloud"
start_compose "syncthing"
start_compose "triliumnotes"
start_compose "vaultwarden"
start_compose "wikijs"

# Mattermost (docker-compose.yml + docker-compose.without-nginx.yml)
if [ -d "$PROJECT_ROOT/mattermost" ]; then
  log_info "Démarrage du service 'mattermost'..."
  (
    cd "$PROJECT_ROOT/mattermost"
    if docker compose -f docker-compose.yml -f docker-compose.without-nginx.yml up -d; then
      log_info "Service 'mattermost' démarré avec succès."
    else
      log_error "Échec du démarrage du service 'mattermost'."
    fi
  )
fi

start_compose "monitoring"
start_compose "loadtesting"

log_info "[2/3] Tous les services Docker définis ont été démarrés (ou tentés)."

echo
log_info "Récapitulatif des URLs accessibles SANS reverse proxy :"
echo "  (depuis la VM)    : http://localhost:PORT"
echo "  (depuis l'extérieur, si ports ouverts) : http://${VM_IP}:PORT"
echo
echo "  - Gitea      : http://${VM_IP}:${GITEA_HTTP_PORT:-8083}"
echo "  - WordPress1 : http://${VM_IP}:${WORDPRESS_HTTP1_PORT:-8081}"
echo "  - WordPress2 : http://${VM_IP}:${WORDPRESS_HTTP2_PORT:-8087}"
echo "  - Nextcloud  : http://${VM_IP}:${NEXTCLOUD_HTTP_PORT:-8080}"
echo "  - Syncthing  : http://${VM_IP}:${SYNCTHING_HTTP_PORT}"
echo "  - Trilium    : http://${VM_IP}:${TRILIUM_HTTP_PORT}"
echo "  - Vaultwarden: http://${VM_IP}:${VAULTWARDEN_HTTP_PORT}"
echo "  - Wiki.js    : http://${VM_IP}:${WIKI_HTTP_PORT:-8082}"
echo "  - Mattermost : http://${VM_IP}:${MATTERMOST_APP_PORT:-8065}"
echo "  - Prometheus : http://${VM_IP}:${PROMETHEUS_HTTP_PORT:-8086}"
echo "  - Grafana    : http://${VM_IP}:${GRAFANA_HTTP_PORT:-3000}"
echo "  - Node Exporter : http://${VM_IP}:${NODE_EXPORTER_HTTP_PORT:-8084}"
echo "  - cAdvisor   : http://${VM_IP}:${CADVISOR_HTTP_PORT:-8085}"

log_info "[3/3] Déploiement sans Nginx terminé."

