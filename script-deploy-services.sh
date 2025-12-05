#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[0/6] Chargement du fichier .env global (si présent)..."
if [ -f "$PROJECT_ROOT/.env" ]; then
  set -a
  . "$PROJECT_ROOT/.env"
  set +a
fi

install_docker() {
  echo "Docker n'est pas installé. Installation en cours (Ubuntu/Debian)..."
  apt-get update
  apt-get install -y ca-certificates curl gnupg lsb-release

  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list

  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

install_nginx() {
  echo "Nginx n'est pas installé. Installation en cours..."
  apt-get update
  apt-get install -y nginx
}

# 1) Vérifier / installer Docker
if ! command -v docker >/dev/null 2>&1; then
  install_docker
fi
if ! docker compose version >/dev/null 2>&1; then
  echo "La sous-commande 'docker compose' n'est pas disponible (version trop ancienne ?)."
  echo "Vérifie l'installation de Docker Desktop / moteur Docker."
  exit 1
fi

# 2) Vérifier / installer Nginx
if ! command -v nginx >/dev/null 2>&1; then
  install_nginx
fi

echo "[1/6] Déploiement des configurations Nginx..."

NGINX_SITES_AVAILABLE="/etc/nginx/sites-available"
NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"
NGINX_SRC_DIR="$PROJECT_ROOT/nginx"

mkdir -p "$NGINX_SITES_AVAILABLE" "$NGINX_SITES_ENABLED"

install_site() {
  local name="$1"
  local src="$NGINX_SRC_DIR/$name.conf"
  local dst="$NGINX_SITES_AVAILABLE/$name.conf"

  if [ ! -f "$src" ]; then
    echo "Avertissement : fichier Nginx $src manquant, site '$name' ignoré."
    return
  fi

  cp "$src" "$dst"

  if [ -L "$NGINX_SITES_ENABLED/$name.conf" ]; then
    rm -f "$NGINX_SITES_ENABLED/$name.conf"
  fi
  ln -s "$dst" "$NGINX_SITES_ENABLED/$name.conf"
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

echo "[2/6] Test de configuration Nginx..."
nginx -t

echo "[3/6] Démarrage des services Docker..."

# Gitea
if [ -d "$PROJECT_ROOT/gitea" ]; then
  (
    cd "$PROJECT_ROOT/gitea"
    docker compose up -d
  )
fi

# WordPress (load balancing via Nginx)
if [ -d "$PROJECT_ROOT/wordpress" ]; then
  (
    cd "$PROJECT_ROOT/wordpress"
    docker compose up -d
  )
fi

# Nextcloud
if [ -d "$PROJECT_ROOT/nextcloud" ]; then
  (
    cd "$PROJECT_ROOT/nextcloud"
    docker compose up -d
  )
fi

# Syncthing
if [ -d "$PROJECT_ROOT/syncthing" ]; then
  (
    cd "$PROJECT_ROOT/syncthing"
    docker compose up -d
  )
fi

# Trilium
if [ -d "$PROJECT_ROOT/triliumnotes" ]; then
  (
    cd "$PROJECT_ROOT/triliumnotes"
    docker compose up -d
  )
fi

# Vaultwarden
if [ -d "$PROJECT_ROOT/vaultwarden" ]; then
  (
    cd "$PROJECT_ROOT/vaultwarden"
    docker compose up -d
  )
fi

# Wiki.js
if [ -d "$PROJECT_ROOT/wikijs" ]; then
  (
    cd "$PROJECT_ROOT/wikijs"
    docker compose up -d
  )
fi

# Mattermost
if [ -d "$PROJECT_ROOT/mattermost" ]; then
  (
    cd "$PROJECT_ROOT/mattermost"
    docker compose -f docker-compose.yml -f docker-compose.without-nginx.yml up -d
  )
fi

# Monitoring
if [ -d "$PROJECT_ROOT/monitoring" ]; then
  (
    cd "$PROJECT_ROOT/monitoring"
    docker compose up -d
  )
fi

# Joplin (si présent)
if [ -d "$PROJECT_ROOT/joplin" ] && [ -f "$PROJECT_ROOT/joplin/docker-compose.yml" ]; then
  (
    cd "$PROJECT_ROOT/joplin"
    docker compose up -d
  )
fi

# Loadtesting
if [ -d "$PROJECT_ROOT/loadtesting" ]; then
  (
    cd "$PROJECT_ROOT/loadtesting"
    docker compose up -d
  )
fi

echo "[4/6] Rechargement de Nginx..."
systemctl reload nginx || service nginx reload

DOMAIN="${DOMAIN_BASE:-tpdocker.istic.univ-rennes1.fr}"

echo "[5/6] Récapitulatif des URLs :"
echo "  - Gitea      : http://gitea.${DOMAIN}"
echo "  - WordPress  : http://wordpress.${DOMAIN} (LB Nginx entre 8081 et 8087)"
echo "  - Nextcloud  : http://nextcloud.${DOMAIN}"
echo "  - Syncthing  : http://syncthing.${DOMAIN}"
echo "  - Vaultwarden: http://vaultwarden.${DOMAIN}"
echo "  - Trilium    : http://triliumnotes.${DOMAIN}"
echo "  - Wiki.js    : http://wiki.${DOMAIN}"
echo "  - Mattermost : http://mattermost.${DOMAIN}"
echo "  - Grafana    : http://grafana.${DOMAIN}"

echo "[6/6] Déploiement terminé."

