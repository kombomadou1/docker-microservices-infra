#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log_info()  { echo -e "\e[32m[INFO]\e[0m $*"; }
log_warn()  { echo -e "\e[33m[WARN]\e[0m $*"; }
log_error() { echo -e "\e[31m[ERROR]\e[0m $*"; }

log_info "[0/6] Chargement du fichier .env global (si présent)..."
if [ -f "$PROJECT_ROOT/.env" ]; then
  set -a
  . "$PROJECT_ROOT/.env"
  set +a
  log_info ".env chargé."
else
  log_warn "Aucun fichier .env trouvé, utilisation des valeurs par défaut des docker-compose."
fi

# Vérifier que DOMAIN_BASE est défini
if [ -z "${DOMAIN_BASE:-}" ]; then
  log_error "La variable DOMAIN_BASE n'est pas définie dans .env (ex: DOMAIN_BASE=domvm.istic.univ-rennes1.fr)."
  exit 1
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

install_nginx() {
  log_info "Installation de Nginx..."
  apt-get update -y
  apt-get install -y nginx
  log_info "Nginx installé avec succès."
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

# 2) Vérifier / installer Nginx
if ! command -v nginx >/dev/null 2>&1; then
  install_nginx
else
  log_info "Nginx déjà installé."
fi

# 3) Créer le réseau Docker externe si nécessaire
if ! docker network ls | grep -q "esir-net"; then
  log_info "Réseau Docker 'esir-net' absent, création..."
  docker network create esir-net
  log_info "Réseau 'esir-net' créé."
else
  log_info "Réseau Docker 'esir-net' déjà présent."
fi

# 4) Déploiement des configurations Nginx (HTTP uniquement)
log_info "[1/6] Déploiement des configurations Nginx (HTTP)..."

NGINX_SRC_DIR="$PROJECT_ROOT/configs/http"
NGINX_SITES_AVAILABLE="/etc/nginx/sites-available"
NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"

mkdir -p "$NGINX_SITES_AVAILABLE" "$NGINX_SITES_ENABLED"

install_site() {
  local name="$1"
  local src="$NGINX_SRC_DIR/$name.conf"
  local dst="$NGINX_SITES_AVAILABLE/$name.conf"

  if [ ! -f "$src" ]; then
    log_warn "Fichier Nginx $src manquant, site '$name' ignoré."
    return
  fi

  # On peut utiliser envsubst si tes confs contiennent ${DOMAIN_BASE} ou des ports
  # sinon un simple cp suffit
  envsubst '${DOMAIN_BASE} ${GITEA_HTTP_PORT} ${WORDPRESS_HTTP1_PORT} ${WORDPRESS_HTTP2_PORT} ${NEXTCLOUD_HTTP_PORT} ${SYNCTHING_HTTP_PORT} ${TRILIUM_HTTP_PORT} ${VAULTWARDEN_HTTP_PORT} ${WIKI_HTTP_PORT} ${MATTERMOST_APP_PORT} ${GRAFANA_HTTP_PORT}' \
    < "$src" > "$dst"

  if [ -L "$NGINX_SITES_ENABLED/$name.conf" ]; then
    rm -f "$NGINX_SITES_ENABLED/$name.conf"
  fi
  ln -s "$dst" "$NGINX_SITES_ENABLED/$name.conf"

  log_info "VHost Nginx '$name' installé et activé (HTTP)."
}

install_site "gitea"
install_site "wordpress"
install_site "nextcloud"
install_site "syncthing"
install_site "vaultwarden"
install_site "triliumnotes"
install_site "wiki"
install_site "mattermost"
install_site "grafana"

log_info "[2/6] Test de configuration Nginx..."
if nginx -t; then
  log_info "Configuration Nginx valide."
else
  log_error "Configuration Nginx invalide, corrige les erreurs ci-dessus."
  exit 1
fi

# 5) Démarrage des services Docker
log_info "[3/6] Démarrage des services Docker..."

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
start_compose "wordpress"      # WordPress1 + WordPress2 + MariaDB
start_compose "nextcloud"
start_compose "syncthing"
start_compose "triliumnotes"
start_compose "vaultwarden"
start_compose "wikijs"

# Mattermost (2 fichiers compose)
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

# 6) Rechargement Nginx
log_info "[4/6] Rechargement de Nginx..."
if systemctl reload nginx 2>/dev/null || service nginx reload 2>/dev/null; then
  log_info "Nginx rechargé avec succès."
else
  log_warn "Impossible de recharger Nginx, vérifie le service manuellement."
fi

DOMAIN="$DOMAIN_BASE"

log_info "[5/6] Récapitulatif des URLs exposées :"
echo "  - Gitea      : http://gitea.${DOMAIN}"
echo "  - WordPress  : http://wordpress.${DOMAIN} (LB Nginx → ${WORDPRESS_HTTP1_PORT:-8081} & ${WORDPRESS_HTTP2_PORT:-8087})"
echo "  - Nextcloud  : http://nextcloud.${DOMAIN}"
echo "  - Syncthing  : http://syncthing.${DOMAIN}"
echo "  - Vaultwarden: http://vaultwarden.${DOMAIN}"
echo "  - Trilium    : http://triliumnotes.${DOMAIN}"
echo "  - Wiki.js    : http://wiki.${DOMAIN}"
echo "  - Mattermost : http://mattermost.${DOMAIN}"
echo "  - Grafana    : http://grafana.${DOMAIN}"

log_info "[6/6] Déploiement terminé."


