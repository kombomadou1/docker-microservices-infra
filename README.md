# ESIR-as-a-Service-2025

Plateforme de services auto‑hébergés pour les projets ESIR : forge Git, wiki, chat, cloud de fichiers, gestion de mots de passe et monitoring, déployés sur une VM Ubuntu via Docker / Nginx / Ansible.


## Getting started

Ce dépôt contient tout le nécessaire pour :

- déployer une stack complète de services en Docker,
- soit en accès direct par IP:PORT (sans reverse proxy),
- soit derrière Nginx via des sous‑domaines HTTP/HTTPS,
- provisionner ou rejouer le déploiement via Ansible.

### Cloner le projet

```
git clone https://gitlab2.istic.univ-rennes1.fr/esir-as-a-service-2025-docker/esir-as-a-service-2025.git
cd esir-as-a-service-2025
```

---

## Project structure

Vue d’ensemble de l’arborescence :

```
.
├── README.md
├── deploy-without-nginx.sh   # Déploiement Docker sans reverse proxy (IP:PORT)
├── deploy-services.sh        # Déploiement Docker avec Nginx (vhosts http/https)
├── clean-services.sh         # Arrêt + nettoyage complet des services et vhosts
├── configs/                  # Configurations Nginx (HTTP/HTTPS)
├── gitea/                    # Forge Git (Gitea)
├── wordpress/                # WordPress (2 instances + MariaDB)
├── nextcloud/                # Cloud de fichiers (Nextcloud)
├── syncthing/                # Syncthing (sync P2P)
├── triliumnotes/             # Trilium Notes (base de connaissances)
├── vaultwarden/              # Vaultwarden (mots de passe)
├── wikijs/                   # Wiki.js (wiki projet)
├── mattermost/               # Mattermost + Postgres + Nginx local
├── monitoring/               # Prometheus, Node Exporter, cAdvisor, Grafana
├── loadtesting/              # k6 pour tests de charge
├── playbooks_ansible/        # Playbooks Ansible par service
├── deploy-all.yml            # Playbook Ansible global (squelette)
└── inventory.ini             # Inventaire Ansible exemple
```

---

## Services

Chaque service est isolé dans son dossier avec un `docker-compose.yml` et des volumes de données.

- **Gitea (`gitea/`)**  
  Forge Git légère : dépôts de code, issues, pull requests, gestion d’utilisateurs.

- **WordPress (`wordpress/`)**  
  Deux instances WordPress (WordPress1 / WordPress2) + MariaDB. En mode avec Nginx, un vhost agit comme load‑balancer HTTP.

- **Nextcloud (`nextcloud/`)**  
  Cloud de fichiers (WebDAV, clients desktop/mobile), partage de documents et extensions (apps Nextcloud).

- **Syncthing (`syncthing/`)**  
  Synchronisation de dossiers en pair‑à‑pair, avec interface web de gestion.

- **Trilium Notes (`triliumnotes/`)**  
  Base de connaissances et prise de notes hiérarchique.

- **Vaultwarden (`vaultwarden/`)**  
  Gestionnaire de mots de passe compatible Bitwarden (serveur auto‑hébergé).

- **Wiki.js (`wikijs/`)**  
  Wiki moderne (Markdown, WYSIWYG, rôles) pour la documentation du projet.

- **Mattermost (`mattermost/`)**  
  Messagerie d’équipe type Slack : salons, messages directs, intégrations.

- **Monitoring (`monitoring/`)**  
  - Prometheus : collecte des métriques de la VM et des conteneurs.  
  - Node Exporter : métriques système (CPU, RAM, disque).  
  - cAdvisor : métriques Docker.  
  - Grafana : visualisation via dashboards.

- **Load testing (`loadtesting/`)**  
  Conteneur k6 exécutant un script de test de charge (`loadtesting/k6/script.js`).

---

## Requirements

- VM Ubuntu Server (22.04+ recommandé).
- Accès `sudo`.
- Ports réseau ouverts vers les services ou vers Nginx (selon le mode).
- Git installé.

---

## Configuration

### Fichier `.env`

Un fichier `.env` à la racine centralise :

- `DOMAIN_BASE` : domaine principal (ex. `tpdocker.istic.univ-rennes1.fr`).
- Ports exposés pour chaque service (HTTP, HTTPS le cas échéant).
- Variables Mattermost / Postgres (`POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`, `MM_SQLSETTINGS_DATASOURCE`).
- Autres options propres aux services.

Adapter `.env` avant le premier déploiement :

```
cp env.example .env    # si présent
nano .env
```

Vérifier les ports déjà utilisés :

```
sudo ss -lnt
```

---

## Installation

### 0. Rendre les scripts exécutables

```
chmod +x deploy-without-nginx.sh
chmod +x deploy-services.sh
chmod +x clean-services.sh
```

### 1. Mode sans Nginx (accès IP:PORT)

Ce mode publie chaque service directement sur un port de la VM.

```
cd esir-as-a-service-2025
sudo ./deploy-without-nginx.sh
```

Le script :

1. Charge `.env`.
2. Installe Docker + `docker compose` si nécessaire.
3. Crée le réseau Docker `esir-net`.
4. Adapte les URLs pour un accès direct :
   - Trilium : `APP_BASE_URL = http://VM_IP:TRILIUM_HTTP_PORT`
   - Vaultwarden : `DOMAIN = http://VM_IP:VAULTWARDEN_HTTP_PORT`
5. Corrige un cas connu sur le volume WordPress (`wp-content/themes`).
6. Lance les services via `docker compose up -d` dans :
   `gitea`, `wordpress`, `nextcloud`, `syncthing`, `triliumnotes`,
   `vaultwarden`, `wikijs`, `mattermost`, `monitoring`, `loadtesting`.
7. Affiche un récapitulatif des URLs, par ex. :

- `http://IP_VM:8083` → Gitea  
- `http://IP_VM:8081` → WordPress1  
- `http://IP_VM:8087` → WordPress2  
- `http://IP_VM:8080` → Nextcloud  
- `http://IP_VM:<SYNCTHING_HTTP_PORT>` → Syncthing  
- `http://IP_VM:<TRILIUM_HTTP_PORT>` → Trilium  
- `http://IP_VM:<VAULTWARDEN_HTTP_PORT>` → Vaultwarden  
- `http://IP_VM:8082` → Wiki.js  
- `http://IP_VM:<MATTERMOST_APP_PORT>` → Mattermost  
- `http://IP_VM:<PROMETHEUS_HTTP_PORT>` → Prometheus  
- `http://IP_VM:3000` → Grafana  

Exemple de test rapide depuis la VM :

```
curl -I http://localhost:8083    # Gitea
curl -I http://localhost:8080    # Nextcloud
```

### 2. Mode avec Nginx (reverse proxy)

Ce mode expose les services via Nginx en utilisant `DOMAIN_BASE` et les fichiers de `configs/http` et `configs/https`.

```
cd esir-as-a-service-2025
sudo ./deploy-services.sh
```

Le script :

1. Charge `.env`.
2. Installe Docker, `docker compose` et Nginx si besoin.
3. Crée le réseau `esir-net`.
4. Copie les vhosts depuis `configs/http/` vers `/etc/nginx/sites-available/` et crée les liens dans `/etc/nginx/sites-enabled/`.
5. Vérifie la configuration (`nginx -t`) et recharge Nginx.
6. Lance tous les services Docker.

Exemples de vhosts HTTP :

- `http://gitea.DOMAIN_BASE` → Gitea  
- `http://wordpress.DOMAIN_BASE` → WordPress  
- `http://nextcloud.DOMAIN_BASE` → Nextcloud  
- `http://syncthing.DOMAIN_BASE` → Syncthing  
- `http://triliumnotes.DOMAIN_BASE` → Trilium  
- `http://vaultwarden.DOMAIN_BASE` → Vaultwarden  
- `http://wiki.DOMAIN_BASE` → Wiki.js  
- `http://mattermost.DOMAIN_BASE` → Mattermost  
- `http://grafana.DOMAIN_BASE` → Grafana  

Les fichiers `configs/https/*.conf` sont prêts pour activer le HTTPS avec des certificats (ex. Let’s Encrypt, via Certbot ou scripts de `mattermost/scripts`).

---

## Usage – arrêt et nettoyage

Pour arrêter et nettoyer tous les services, ainsi que le réseau Docker et les vhosts Nginx du projet :

```
cd esir-as-a-service-2025
sudo ./clean-services.sh
```

Ce script :

1. Charge `.env` si présent.
2. Fait un `docker compose down --volumes --remove-orphans` dans :
   `gitea`, `wordpress`, `nextcloud`, `syncthing`, `triliumnotes`,
   `vaultwarden`, `wikijs`, `monitoring`, `joplin`, `loadtesting`,
   et `mattermost` (avec `docker-compose.yml` + `docker-compose.without-nginx.yml`).
3. Supprime le réseau Docker `esir-net` si possible.
4. Supprime les vhosts du projet dans :
   `/etc/nginx/sites-available` et `/etc/nginx/sites-enabled` pour
   `gitea`, `wordpress`, `nextcloud`, `syncthing`, `vaultwarden`,
   `triliumnotes`, `wiki`, `mattermost`, `grafana` (avec vérification qu’ils viennent bien du projet).
5. Recharge Nginx si installé et configuration valide.

Attention : les volumes définis dans les `docker-compose` sont supprimés, ce qui efface les données (bases, fichiers, configs internes).

---

## Ansible

Le dossier `playbooks_ansible/` contient un playbook par service :

- `gitea.yml`, `wordpress.yml`, `nextcloud.yml`, `syncthing.yml`,
  `triliumnotes.yml`, `vaultwarden.yml`, `wikijs.yml`,
  `mattermost.yml`, `monitoring.yml`, `loadtesting.yml`.

`inventory.ini` fournit un inventaire d’exemple et `deploy-all.yml` un squelette de playbook global.

Exemple de commande (à adapter) :

```
ansible-playbook -i inventory.ini playbooks_ansible/gitea.yml
```

Cette partie peut être enrichie pour :

- préparer la VM (paquets, utilisateurs, firewall),
- cloner le dépôt, copier `.env`,
- puis appeler `deploy-without-nginx.sh` ou `deploy-services.sh`.

---

## Troubleshooting

- **Port déjà occupé**

  ```
  sudo ss -lnt
  ```

  Adapter les ports dans `.env` et relancer le script de déploiement.


---

## Authors

- BEHI ET KOMBO – Projet AL 2025.

## Project status

Projet pédagogique actif pour l’année 2025 ; la stack reste utilisable comme base de déploiement pour des environnements de développement ou de test.
```
