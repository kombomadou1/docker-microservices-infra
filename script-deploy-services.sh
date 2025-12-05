#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[0/5] Chargement du fichier .env global (si présent)..."
if [ -f "$PROJECT_ROOT/.env" ]; then
  set -a
  . "$PROJECT_ROOT/.env"
  set +a
fi

# 1) Vérifier Docker / docker compose / nginx
if ! command -v docker >/dev/null 2>&1; then
  echo "Docker n'est pas installé. Installe-le avant de lancer ce script."
  exit 1
fi
if ! docker compose version >/dev/null 2>&1; then
  echo "La commande 'docker compose' n'est pas disponible."
  exit 1
fi
if ! command -v nginx >/dev/null 2>&1; then
  echo "Nginx n'est pas installé. Installe-le avant de lancer ce script."
  exit 1
fi

echo "[1/5] Déploiement des configurations Nginx..."

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

  # Copier (ou mettre à jour) dans sites-available
  cp "$src" "$dst"

  # Créer le lien dans sites-enabled
  if [ -L "$NGINX_SITES_ENABLED/$name.conf" ]; then
    rm -f "$NGINX_SITES_ENABLED/$name.conf"
  fi
  ln -s "$dst" "$NGINX_SITES_ENABLED/$name.conf"
}

# Installer les vhosts dont tu disposes
install_site "gitea"
install_site "wordpress"      # contient déjà l'upstream wordpress_backend
install_site "nextcloud"
install_site "syncthing"
install_site "vaultwarden"
install_site "triliumnotes"
install_site "wiki"
install_site "mattermost"
install_site "grafana"

echo "[2/5] Test de configuration Nginx..."
nginx -t

echo "[3/5] Démarrage des services Docker..."

# Gitea
if [ -d "$PROJECT_ROOT/gitea" ]; then
  (
    cd "$PROJECT_ROOT/gitea"
    docker compose up -d
  )
fi

# WordPress (load balancing côté Nginx entre 8081 et 8087)
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

# Trilium Notes
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

# Mattermost (une instance, sans load balancing)
if [ -d "$PROJECT_ROOT/mattermost" ]; then
  (
    cd "$PROJECT_ROOT/mattermost"
    docker compose -f docker-compose.yml -f docker-compose.without-nginx.yml up -d
  )
fi

# Monitoring (Prometheus + Grafana + exporters)
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

# Load testing (k6)
if [ -d "$PROJECT_ROOT/loadtesting" ]; then
  (
    cd "$PROJECT_ROOT/loadtesting"
    docker compose up -d
  )
fi

echo "[4/5] Rechargement de Nginx..."
systemctl reload nginx

DOMAIN="${DOMAIN_BASE:-tpdocker.istic.univ-rennes1.fr}"

echo "[5/5] Déploiement terminé. Services accessibles via :"
echo "  - Gitea      : http://gitea.${DOMAIN}"
echo "  - WordPress  : http://wordpress.${DOMAIN} (LB Nginx → 8081 & 8087)"
echo "  - Nextcloud  : http://nextcloud.${DOMAIN}"
echo "  - Syncthing  : http://syncthing.${DOMAIN}"
echo "  - Vaultwarden: http://vaultwarden.${DOMAIN}"
echo "  - Trilium    : http://triliumnotes.${DOMAIN}"
echo "  - Wiki.js    : http://wiki.${DOMAIN}"
echo "  - Mattermost : http://mattermost.${DOMAIN}"
echo "  - Grafana    : http://grafana.${DOMAIN}"

