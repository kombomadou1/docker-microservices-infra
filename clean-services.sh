#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log_info()  { echo -e "\e[32m[INFO]\e[0m $*"; }
log_warn()  { echo -e "\e[33m[WARN]\e[0m $*"; }
log_error() { echo -e "\e[31m[ERROR]\e[0m $*"; }

log_info "[0/5] Chargement du fichier .env global (si présent)..."
if [ -f "$PROJECT_ROOT/.env" ]; then
  set -a
  . "$PROJECT_ROOT/.env"
  set +a
  log_info ".env chargé."
else
  log_warn "Aucun fichier .env trouvé, utilisation des valeurs par défaut des docker-compose."
fi

# 1) Arrêter et supprimer les stacks Docker (conteneurs + réseaux + volumes du projet)
stop_compose() {
  local dir="$1"
  local extra_args="${2:-}"
  if [ -d "$PROJECT_ROOT/$dir" ]; then
    log_info "Arrêt et suppression du service '$dir'..."
    (
      cd "$PROJECT_ROOT/$dir"
      # down avec suppression des volumes définis dans le compose
      if docker compose $extra_args down --volumes --remove-orphans; then
        log_info "Service '$dir' supprimé (containers + réseaux du projet + volumes)."
      else
        log_warn "Échec de docker compose down pour '$dir' (peut-être jamais lancé)."
      fi
    )
  else
    log_warn "Dossier '$dir' introuvable, service ignoré."
  fi
}

log_info "[1/5] Arrêt et suppression de tous les services Docker du projet..."

stop_compose "gitea"
stop_compose "wordpress"
stop_compose "nextcloud"
stop_compose "syncthing"
stop_compose "triliumnotes"
stop_compose "vaultwarden"
stop_compose "wikijs"
stop_compose "monitoring"
stop_compose "joplin"
stop_compose "loadtesting"

# Mattermost (2 fichiers compose)
if [ -d "$PROJECT_ROOT/mattermost" ]; then
  log_info "Arrêt et suppression du service 'mattermost'..."
  (
    cd "$PROJECT_ROOT/mattermost"
    if docker compose -f docker-compose.yml -f docker-compose.without-nginx.yml down --volumes --remove-orphans; then
      log_info "Service 'mattermost' supprimé (containers + volumes)."
    else
      log_warn "Échec de docker compose down pour 'mattermost'."
    fi
  )
fi

# 2) Supprimer le réseau Docker esir-net s'il existe
log_info "[2/5] Nettoyage du réseau Docker 'esir-net'..."
if docker network ls | grep -q "esir-net"; then
  if docker network rm esir-net; then
    log_info "Réseau 'esir-net' supprimé."
  else
    log_warn "Impossible de supprimer le réseau 'esir-net' (encore utilisé ?)."
  fi
else
  log_info "Réseau 'esir-net' déjà absent."
fi

# 3) Nettoyage des configurations Nginx installées par le script de déploiement
log_info "[3/5] Suppression des configurations Nginx du projet..."

NGINX_SITES_AVAILABLE="/etc/nginx/sites-available"
NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"
NGINX_SRC_DIR="$PROJECT_ROOT/nginx"

remove_site() {
  local name="$1"
  local dst="$NGINX_SITES_AVAILABLE/$name.conf"
  local link="$NGINX_SITES_ENABLED/$name.conf"

  # Supprimer le lien dans sites-enabled
  if [ -L "$link" ]; then
    rm -f "$link"
    log_info "Lien sites-enabled pour '$name' supprimé."
  fi

  # Supprimer le fichier dans sites-available SEULEMENT s’il vient de ton projet
  if [ -f "$dst" ] && [ -d "$NGINX_SRC_DIR" ] && [ -f "$NGINX_SRC_DIR/$name.conf" ]; then
    # On suppose que le fichier a été copié depuis nginx/<name>.conf
    rm -f "$dst"
    log_info "Fichier sites-available pour '$name' supprimé."
  else
    log_warn "Fichier $dst non supprimé (n'existe pas ou ne vient pas du projet)."
  fi
}

remove_site "gitea"
remove_site "wordpress"
remove_site "nextcloud"
remove_site "syncthing"
remove_site "vaultwarden"
remove_site "triliumnotes"
remove_site "wiki"
remove_site "mattermost"
remove_site "grafana"

# 4) Recharger Nginx après suppression des sites
log_info "[4/5] Rechargement de Nginx après nettoyage..."
if command -v nginx >/dev/null 2>&1; then
  if nginx -t; then
    if systemctl reload nginx 2>/dev/null || service nginx reload 2>/dev/null; then
      log_info "Nginx rechargé avec succès."
    else
      log_warn "Impossible de recharger Nginx, vérifie le service manuellement."
    fi
  else
    log_warn "Configuration Nginx invalide après suppression, corrige /etc/nginx manuellement."
  fi
else
  log_warn "Nginx n'est pas installé, rien à recharger."
fi

log_info "[5/5] Nettoyage terminé."
echo "  - Tous les services Docker du projet ont été arrêtés et supprimés (avec leurs volumes)."
echo "  - Le réseau Docker 'esir-net' a été supprimé si possible."
echo "  - Les vhosts Nginx du projet ont été désactivés et, si issus du projet, supprimés."

