# Presse Claude — Implementation Plan (Phase 1 : Core Platform)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:expert-quality-workflow to implement this plan task-by-task.

**Goal:** Déployer une plateforme SaaS Frappe Press 100% locale sur Docker, accessible sur `https://press.local`, avec multi-bench, multi-tenant, providers open-source (Garage, Forgejo, Stalwart, Traefik), préfixe `presse_claude_`, ports 14000-14500.

**Architecture:** Frappe Press (dashboard) orchestre un container "server" Ubuntu via SSH+Ansible+Agent. Traefik v3 route tous les sous-domaines `*.press.local`. Garage remplace S3, Forgejo remplace GitHub, Stalwart remplace Mailgun. Tout est configuré depuis `.env`.

**Tech Stack:** Docker Compose v2, Frappe Press (master), Frappe V16, frappe/agent, MariaDB 10.6, Redis 7, Traefik v3, Garage v1, Forgejo v14, Stalwart, Prometheus+Grafana+Loki, Ollama

---

## PHASE 1 — Infrastructure de base + Press fonctionnel

---

### Task 1 : Initialisation de la structure du projet

**Files:**
- Create: `.env`
- Create: `.env.example`
- Create: `.gitignore`
- Create: `docker-compose.yml`
- Create: `compose/infra.yml`
- Create: `compose/press.yml`
- Create: `compose/server.yml`
- Create: `compose/storage.yml`
- Create: `compose/git.yml`
- Create: `compose/mail.yml`
- Create: `compose/monitoring.yml`
- Create: `compose/ai.yml`

**Step 1: Créer la structure de répertoires**

```bash
mkdir -p compose config/traefik/dynamic config/garage config/forgejo \
         config/stalwart config/prometheus config/loki config/grafana \
         docker/server docker/press scripts apps docs/plans data
```

**Step 2: Créer .gitignore**

```bash
cat > .gitignore << 'EOF'
.env
data/
*.log
*.pem
*.key
*.crt
EOF
```

**Step 3: Créer .env.example**

Créer le fichier `.env.example` avec ce contenu exact :

```env
# ═══════════════════════════════════════════
# PRESSE CLAUDE — Configuration centrale
# ═══════════════════════════════════════════

# Prefix (tous containers, volumes, réseaux, images)
PREFIX=presse_claude_

# Domaine local
DOMAIN=press.local

# ─── Ports Traefik (entrée) ───────────────
PORT_HTTP=14001
PORT_HTTPS=14002
PORT_TRAEFIK_DASH=14003

# ─── Services infrastructure ──────────────
PORT_MARIADB=14030
PORT_REDIS=14031

# ─── Garage S3 ────────────────────────────
PORT_GARAGE_S3=14040
PORT_GARAGE_WEB=14041

# ─── Forgejo ──────────────────────────────
PORT_FORGEJO_HTTP=14050
PORT_FORGEJO_SSH=14051

# ─── Stalwart Mail ────────────────────────
PORT_STALWART_SMTP=14060
PORT_STALWART_IMAP=14061
PORT_STALWART_HTTP=14062

# ─── Monitoring ───────────────────────────
PORT_PROMETHEUS=14070
PORT_GRAFANA=14071
PORT_LOKI=14072

# ─── Server container (Agent) ─────────────
PORT_SERVER_SSH=14021
PORT_SERVER_AGENT=14022

# ─── IA ───────────────────────────────────
PORT_OLLAMA=14080
PORT_OPENWEBUI=14083

# ─── Credentials MariaDB ──────────────────
MARIADB_ROOT_PASSWORD=change_me_root_password_here
MARIADB_PRESS_DB=press
MARIADB_PRESS_USER=press
MARIADB_PRESS_PASSWORD=change_me_press_password_here

# ─── Press ────────────────────────────────
PRESS_SITE_NAME=press.local
PRESS_ADMIN_EMAIL=admin@press.local
PRESS_ADMIN_PASSWORD=change_me_press_admin_here

# ─── Garage S3 credentials ────────────────
GARAGE_ACCESS_KEY=pressclaudekey
GARAGE_SECRET_KEY=pressclaudesecretkey123
GARAGE_BUCKET_BACKUPS=press-backups
GARAGE_BUCKET_UPLOADS=press-uploads

# ─── Forgejo ──────────────────────────────
FORGEJO_ADMIN_USER=admin
FORGEJO_ADMIN_PASSWORD=change_me_forgejo_password_here
FORGEJO_ADMIN_EMAIL=admin@press.local

# ─── Stalwart ─────────────────────────────
STALWART_ADMIN_EMAIL=admin@press.local
STALWART_ADMIN_PASSWORD=change_me_stalwart_password_here
```

**Step 4: Copier et configurer .env**

```bash
cp .env.example .env
# Modifier les mots de passe dans .env
```

**Step 5: Vérifier la structure**

```bash
ls -la && ls compose/ && ls config/ && ls docker/
```

Expected: Tous les répertoires listés ci-dessus existent.

**Step 6: Commit**

```bash
git init
git add .gitignore .env.example docs/
git commit -m "feat: initialize presse_claude project structure"
```

---

### Task 2 : Réseau Docker et volumes communs

**Files:**
- Create: `compose/infra.yml`
- Create: `docker-compose.yml`

**Step 1: Créer compose/infra.yml** (réseau + volumes + MariaDB + Redis)

```yaml
# compose/infra.yml
networks:
  default:
    name: ${PREFIX}network
    driver: bridge

volumes:
  mariadb_data:
    name: ${PREFIX}mariadb_data
  redis_data:
    name: ${PREFIX}redis_data

services:
  mariadb:
    image: mariadb:10.6
    container_name: ${PREFIX}mariadb
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: ${MARIADB_ROOT_PASSWORD}
      MYSQL_DATABASE: ${MARIADB_PRESS_DB}
      MYSQL_USER: ${MARIADB_PRESS_USER}
      MYSQL_PASSWORD: ${MARIADB_PRESS_PASSWORD}
    volumes:
      - mariadb_data:/var/lib/mysql
    ports:
      - "127.0.0.1:${PORT_MARIADB}:3306"
    networks:
      - default
    command: >
      --character-set-server=utf8mb4
      --collation-server=utf8mb4_unicode_ci
      --skip-character-set-client-handshake
      --innodb-buffer-pool-size=512M
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost", "-u", "root", "-p${MARIADB_ROOT_PASSWORD}"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis-cache:
    image: redis:7-alpine
    container_name: ${PREFIX}redis_cache
    restart: unless-stopped
    volumes:
      - redis_data:/data
    ports:
      - "127.0.0.1:${PORT_REDIS}:6379"
    networks:
      - default
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 3s
      retries: 5

  redis-queue:
    image: redis:7-alpine
    container_name: ${PREFIX}redis_queue
    restart: unless-stopped
    networks:
      - default
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 3s
      retries: 5
```

**Step 2: Créer docker-compose.yml** (fichier principal qui inclut tout)

```yaml
# docker-compose.yml
include:
  - compose/infra.yml
  - compose/storage.yml
  - compose/press.yml
  - compose/server.yml
  - compose/git.yml
  - compose/mail.yml
  - compose/monitoring.yml
  - compose/ai.yml
```

**Step 3: Tester la syntaxe**

```bash
docker compose config --quiet
```

Expected: Pas d'erreur (ou seulement des warnings pour fichiers manquants).

**Step 4: Créer les fichiers compose vides** (pour éviter erreurs include)

```bash
for f in storage press server git mail monitoring ai; do
  echo "# compose/${f}.yml — TODO" > compose/${f}.yml
done
```

**Step 5: Démarrer MariaDB + Redis et vérifier**

```bash
docker compose up -d mariadb redis-cache redis-queue
sleep 5
docker compose ps
```

Expected:
```
NAME                        STATUS
presse_claude_mariadb       running (healthy)
presse_claude_redis_cache   running (healthy)
presse_claude_redis_queue   running (healthy)
```

**Step 6: Tester la connexion MariaDB**

```bash
docker exec presse_claude_mariadb mysqladmin ping -u root -p${MARIADB_ROOT_PASSWORD} -h localhost
```

Expected: `mysqld is alive`

**Step 7: Commit**

```bash
git add compose/infra.yml docker-compose.yml compose/
git commit -m "feat: add MariaDB, Redis, Docker network with presse_claude_ prefix"
```

---

### Task 3 : Traefik v3 — Reverse proxy multi-domaine

**Files:**
- Create: `config/traefik/traefik.yml`
- Create: `config/traefik/dynamic/tls.yml`
- Modify: `compose/infra.yml` (ajouter service traefik)

**Step 1: Créer config/traefik/traefik.yml**

```yaml
# config/traefik/traefik.yml — Configuration statique
api:
  dashboard: true
  insecure: false

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
  websecure:
    address: ":443"

providers:
  docker:
    exposedByDefault: false
    network: presse_claude_network
  file:
    directory: /etc/traefik/dynamic
    watch: true

log:
  level: INFO

accessLog: {}
```

**Step 2: Créer config/traefik/dynamic/tls.yml** (TLS self-signed pour dev)

```yaml
# config/traefik/dynamic/tls.yml
tls:
  options:
    default:
      minVersion: VersionTLS12

# Certificat self-signed pour *.press.local
# Traefik génère automatiquement en dev (ACME désactivé)
```

**Step 3: Ajouter Traefik dans compose/infra.yml**

Ajouter après le service `redis-queue` :

```yaml
  traefik:
    image: traefik:v3
    container_name: ${PREFIX}traefik
    restart: unless-stopped
    ports:
      - "127.0.0.1:${PORT_HTTP}:80"
      - "127.0.0.1:${PORT_HTTPS}:443"
      - "127.0.0.1:${PORT_TRAEFIK_DASH}:8080"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./config/traefik/traefik.yml:/etc/traefik/traefik.yml:ro
      - ./config/traefik/dynamic:/etc/traefik/dynamic:ro
      - traefik_certs:/certs
    networks:
      - default
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.traefik-dashboard.rule=Host(`traefik.${DOMAIN}`)"
      - "traefik.http.routers.traefik-dashboard.entrypoints=websecure"
      - "traefik.http.routers.traefik-dashboard.tls=true"
      - "traefik.http.routers.traefik-dashboard.service=api@internal"
    healthcheck:
      test: ["CMD", "traefik", "healthcheck"]
      interval: 10s
      timeout: 5s
      retries: 3
```

Ajouter dans la section `volumes` de infra.yml :
```yaml
  traefik_certs:
    name: ${PREFIX}traefik_certs
```

**Step 4: Démarrer Traefik**

```bash
docker compose up -d traefik
sleep 3
docker compose ps traefik
```

Expected: `presse_claude_traefik   running (healthy)`

**Step 5: Vérifier le dashboard Traefik**

```bash
curl -k https://127.0.0.1:14002 -I 2>&1 | head -5
```

Expected: `HTTP/2 404` ou redirect (Traefik répond)

**Step 6: Commit**

```bash
git add config/traefik/
git commit -m "feat: add Traefik v3 reverse proxy with *.press.local routing"
```

---

### Task 4 : DNS local — press.local dans /etc/hosts

**Files:**
- Create: `scripts/dns-setup.sh`
- Create: `scripts/dns-teardown.sh`

**Step 1: Créer scripts/dns-setup.sh**

```bash
#!/bin/bash
# scripts/dns-setup.sh — Ajoute les entrées DNS locales pour press.local

set -e
source "$(dirname "$0")/../.env"

HOSTS_FILE="/etc/hosts"
MARKER_START="# === presse_claude START ==="
MARKER_END="# === presse_claude END ==="
IP="127.0.0.1"

# Vérifier si déjà ajouté
if grep -q "$MARKER_START" "$HOSTS_FILE"; then
  echo "DNS press.local déjà configuré."
  exit 0
fi

echo "Ajout des entrées DNS dans $HOSTS_FILE (sudo requis)..."
sudo bash -c "cat >> $HOSTS_FILE << EOF

$MARKER_START
$IP ${DOMAIN}
$IP press.${DOMAIN}
$IP traefik.${DOMAIN}
$IP git.${DOMAIN}
$IP s3.${DOMAIN}
$IP monitor.${DOMAIN}
$IP mail.${DOMAIN}
$IP ai.${DOMAIN}
$MARKER_END
EOF"

echo "✓ DNS press.local configuré."
echo "  → https://press.local (Press dashboard)"
echo "  → https://git.press.local (Forgejo)"
echo "  → https://monitor.press.local (Grafana)"
```

```bash
chmod +x scripts/dns-setup.sh
```

**Step 2: Créer scripts/dns-teardown.sh**

```bash
#!/bin/bash
# scripts/dns-teardown.sh — Supprime les entrées DNS locales

MARKER_START="# === presse_claude START ==="
MARKER_END="# === presse_claude END ==="

echo "Suppression des entrées DNS presse_claude de /etc/hosts..."
sudo sed -i "/$MARKER_START/,/$MARKER_END/d" /etc/hosts
echo "✓ DNS supprimé."
```

```bash
chmod +x scripts/dns-teardown.sh
```

**Step 3: Exécuter le setup DNS**

```bash
./scripts/dns-setup.sh
```

Expected:
```
✓ DNS press.local configuré.
  → https://press.local (Press dashboard)
  → https://git.press.local (Forgejo)
  → https://monitor.press.local (Grafana)
```

**Step 4: Vérifier**

```bash
ping -c 1 press.local
ping -c 1 git.press.local
```

Expected: PING répondant sur 127.0.0.1

**Step 5: Commit**

```bash
git add scripts/
git commit -m "feat: add DNS setup scripts for press.local subdomains"
```

---

### Task 5 : Garage S3 — Stockage objet local

**Files:**
- Create: `config/garage/garage.toml`
- Create: `compose/storage.yml`
- Create: `scripts/setup-garage.sh`

**Step 1: Créer config/garage/garage.toml**

```toml
# config/garage/garage.toml
metadata_dir = "/var/lib/garage/meta"
data_dir = "/var/lib/garage/data"
db_engine = "lmdb"

replication_factor = 1  # Dev: 1 nœud. Prod: 3

[rpc_bind_addr]
addr = "0.0.0.0:3901"

[s3_api]
s3_region = "garage"
api_bind_addr = "0.0.0.0:3900"

[s3_web]
bind_addr = "0.0.0.0:3902"
root_domain = ".s3.press.local"
index = "index.html"

[admin]
api_bind_addr = "0.0.0.0:3903"
```

**Step 2: Créer compose/storage.yml**

```yaml
# compose/storage.yml
volumes:
  garage_data:
    name: ${PREFIX}garage_data
  garage_meta:
    name: ${PREFIX}garage_meta

services:
  garage:
    image: dxflrs/garage:v1
    container_name: ${PREFIX}garage
    restart: unless-stopped
    volumes:
      - ./config/garage/garage.toml:/etc/garage.toml:ro
      - garage_data:/var/lib/garage/data
      - garage_meta:/var/lib/garage/meta
    ports:
      - "127.0.0.1:${PORT_GARAGE_S3}:3900"
      - "127.0.0.1:${PORT_GARAGE_WEB}:3902"
    networks:
      - default
    environment:
      GARAGE_RPC_SECRET: ${GARAGE_SECRET_KEY}
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.garage-s3.rule=Host(`s3.${DOMAIN}`)"
      - "traefik.http.routers.garage-s3.entrypoints=websecure"
      - "traefik.http.routers.garage-s3.tls=true"
      - "traefik.http.services.garage-s3.loadbalancer.server.port=3900"
    healthcheck:
      test: ["CMD", "/garage", "status"]
      interval: 10s
      timeout: 5s
      retries: 5
```

**Step 3: Créer scripts/setup-garage.sh**

```bash
#!/bin/bash
# scripts/setup-garage.sh — Configure les buckets Garage S3 pour Press

set -e
source "$(dirname "$0")/../.env"

GARAGE="docker exec ${PREFIX}garage /garage"
NODE_ID=$($GARAGE node id -q 2>/dev/null | head -1)

echo "=== Configuration Garage S3 ==="
echo "Node ID: $NODE_ID"

# Layout (1 zone, 1 nœud pour dev)
echo "→ Configuration du layout..."
$GARAGE layout assign -z dc1 -c 1G "$NODE_ID"
$GARAGE layout apply --version 1

# Créer la clé d'accès
echo "→ Création de la clé d'accès..."
$GARAGE key create press-key 2>/dev/null || echo "Clé déjà existante"

KEY_ID=$($GARAGE key list | grep press-key | awk '{print $1}')
$GARAGE key info "$KEY_ID"

# Créer les buckets
for BUCKET in ${GARAGE_BUCKET_BACKUPS} ${GARAGE_BUCKET_UPLOADS}; do
  echo "→ Création bucket: $BUCKET"
  $GARAGE bucket create "$BUCKET" 2>/dev/null || echo "Bucket $BUCKET déjà existant"
  $GARAGE bucket allow --read --write --owner "$BUCKET" --key "$KEY_ID"
done

echo "✓ Garage S3 configuré."
echo "  Endpoint: http://s3.press.local:${PORT_HTTPS}"
echo "  Buckets: ${GARAGE_BUCKET_BACKUPS}, ${GARAGE_BUCKET_UPLOADS}"
```

```bash
chmod +x scripts/setup-garage.sh
```

**Step 4: Démarrer Garage**

```bash
docker compose up -d garage
sleep 5
docker compose ps garage
```

Expected: `presse_claude_garage   running (healthy)`

**Step 5: Configurer Garage**

```bash
./scripts/setup-garage.sh
```

Expected:
```
=== Configuration Garage S3 ===
Node ID: ...
→ Configuration du layout...
→ Création de la clé d'accès...
→ Création bucket: press-backups
→ Création bucket: press-uploads
✓ Garage S3 configuré.
```

**Step 6: Tester l'accès S3**

```bash
# Tester l'endpoint S3 avec curl
curl -s http://127.0.0.1:${PORT_GARAGE_S3} | head -5
```

Expected: Réponse XML ou JSON de l'API Garage

**Step 7: Commit**

```bash
git add compose/storage.yml config/garage/ scripts/setup-garage.sh
git commit -m "feat: add Garage S3 storage with press-backups bucket"
```

---

### Task 6 : Dockerfile Server (Ubuntu 22.04 + SSH + bench prereqs)

**Files:**
- Create: `docker/server/Dockerfile`
- Create: `docker/server/entrypoint.sh`
- Create: `docker/server/sshd_config`

**Step 1: Créer docker/server/Dockerfile**

```dockerfile
# docker/server/Dockerfile
# Container simulant un "serveur géré" Ubuntu pour Frappe Press
# Press s'y connecte via SSH + Ansible, comme sur un vrai VPS

FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive

# ── Système de base ──────────────────────────────────────────────
RUN apt-get update && apt-get install -y \
    openssh-server \
    sudo \
    curl \
    wget \
    git \
    python3 \
    python3-pip \
    python3-venv \
    # Prérequis Frappe/bench
    nodejs \
    npm \
    redis-tools \
    mariadb-client \
    nginx \
    wkhtmltopdf \
    xvfb \
    fonts-liberation \
    # Ansible prérequis
    python3-apt \
    # Utilitaires
    vim \
    htop \
    jq \
    && rm -rf /var/lib/apt/lists/*

# ── Utilisateur frappe (UID 1000 — standard Frappe Cloud Hybrid) ──
RUN useradd -m -u 1000 -s /bin/bash frappe && \
    echo "frappe ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers && \
    mkdir -p /home/frappe/{benches,archived,agent}

# ── SSH server ───────────────────────────────────────────────────
RUN mkdir -p /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config && \
    sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/#AuthorizedKeysFile/AuthorizedKeysFile/' /etc/ssh/sshd_config

COPY sshd_config /etc/ssh/sshd_config.d/frappe.conf

# ── frappe/agent ─────────────────────────────────────────────────
RUN pip3 install frappe-agent

# ── bench CLI ────────────────────────────────────────────────────
RUN pip3 install frappe-bench

# ── Répertoires ──────────────────────────────────────────────────
RUN mkdir -p /home/frappe/.ssh && \
    chown -R frappe:frappe /home/frappe

EXPOSE 22 8000

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
```

**Step 2: Créer docker/server/sshd_config**

```
# /etc/ssh/sshd_config.d/frappe.conf
AllowUsers frappe
PasswordAuthentication no
ChallengeResponseAuthentication no
X11Forwarding no
MaxAuthTries 3
```

**Step 3: Créer docker/server/entrypoint.sh**

```bash
#!/bin/bash
# entrypoint.sh — Démarre SSH + Agent Frappe

set -e

# Générer les clés SSH du host si absentes
ssh-keygen -A

# Injecter la clé publique Press (montée en volume ou env var)
if [ -n "$PRESS_PUBLIC_KEY" ]; then
  mkdir -p /home/frappe/.ssh
  echo "$PRESS_PUBLIC_KEY" >> /home/frappe/.ssh/authorized_keys
  chmod 700 /home/frappe/.ssh
  chmod 600 /home/frappe/.ssh/authorized_keys
  chown -R frappe:frappe /home/frappe/.ssh
fi

# Démarrer SSH en arrière-plan
/usr/sbin/sshd -D &

# Démarrer frappe-agent en foreground
echo "==> Démarrage de frappe-agent..."
cd /home/frappe/agent
exec sudo -u frappe agent start --port 8000
```

**Step 4: Créer compose/server.yml**

```yaml
# compose/server.yml
volumes:
  server_home:
    name: ${PREFIX}server_home
  server_benches:
    name: ${PREFIX}server_benches

services:
  server:
    build:
      context: ./docker/server
      dockerfile: Dockerfile
    image: ${PREFIX}server:latest
    container_name: ${PREFIX}server
    restart: unless-stopped
    hostname: server.press.local
    volumes:
      - server_home:/home/frappe
      - server_benches:/home/frappe/benches
    ports:
      - "127.0.0.1:${PORT_SERVER_SSH}:22"
      - "127.0.0.1:${PORT_SERVER_AGENT}:8000"
    networks:
      - default
    environment:
      PRESS_PUBLIC_KEY: ${PRESS_PUBLIC_KEY:-}
    depends_on:
      mariadb:
        condition: service_healthy
      redis-cache:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "ssh", "-o", "StrictHostKeyChecking=no", "-p", "22", "frappe@localhost", "echo ok"]
      interval: 15s
      timeout: 10s
      retries: 5
```

**Step 5: Builder l'image server**

```bash
docker compose build server
```

Expected: `✓ Built presse_claude/server:latest` (peut prendre 5-10 minutes)

**Step 6: Démarrer le container server**

```bash
docker compose up -d server
sleep 10
docker compose ps server
```

Expected: `presse_claude_server   running`

**Step 7: Vérifier SSH**

```bash
# Tester la connexion SSH (sans clé = accès refusé, c'est normal)
ssh -p 14021 -o StrictHostKeyChecking=no frappe@127.0.0.1 echo "SSH OK" 2>&1
```

Expected: `Permission denied (publickey)` — Normal, Press configurera la clé ensuite.

**Step 8: Commit**

```bash
git add docker/server/ compose/server.yml
git commit -m "feat: add server container Ubuntu+SSH+Agent for Press managed server"
```

---

### Task 7 : Frappe Press — Installation et configuration

**Files:**
- Create: `docker/press/Dockerfile`
- Create: `compose/press.yml`
- Create: `scripts/setup-press.sh`
- Create: `scripts/generate-ssh-keys.sh`

**Step 1: Créer scripts/generate-ssh-keys.sh**

```bash
#!/bin/bash
# Génère la paire de clés SSH Press → Server

set -e
KEY_DIR="./data/ssh"
mkdir -p "$KEY_DIR"

if [ ! -f "$KEY_DIR/press_id_rsa" ]; then
  ssh-keygen -t rsa -b 4096 -f "$KEY_DIR/press_id_rsa" -N "" -C "press@press.local"
  echo "✓ Clés SSH générées dans $KEY_DIR/"
fi

# Exporter la clé publique dans .env
PUBLIC_KEY=$(cat "$KEY_DIR/press_id_rsa.pub")
if ! grep -q "PRESS_PUBLIC_KEY" .env; then
  echo "" >> .env
  echo "# Clé publique Press (auto-générée)" >> .env
  echo "PRESS_PUBLIC_KEY=${PUBLIC_KEY}" >> .env
fi

echo "Clé publique:"
cat "$KEY_DIR/press_id_rsa.pub"
```

```bash
chmod +x scripts/generate-ssh-keys.sh
./scripts/generate-ssh-keys.sh
```

**Step 2: Créer docker/press/Dockerfile**

```dockerfile
# docker/press/Dockerfile
# Frappe Press — basé sur l'image officielle frappe_docker

FROM python:3.11-slim-bookworm

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    git \
    curl \
    nodejs \
    npm \
    mariadb-client \
    redis-tools \
    ansible \
    sshpass \
    openssh-client \
    && rm -rf /var/lib/apt/lists/*

# Install bench
RUN pip install frappe-bench

# User frappe
RUN useradd -m -u 1000 -s /bin/bash frappe
USER frappe
WORKDIR /home/frappe

# Créer le bench Press
RUN bench init --frappe-branch version-16 frappe-bench

WORKDIR /home/frappe/frappe-bench

# Installer l'app Press
RUN bench get-app press https://github.com/frappe/press --branch master

EXPOSE 8000 9000

COPY --chown=frappe:frappe entrypoint.sh /home/frappe/entrypoint.sh
RUN chmod +x /home/frappe/entrypoint.sh

ENTRYPOINT ["/home/frappe/entrypoint.sh"]
```

**Step 3: Créer compose/press.yml**

```yaml
# compose/press.yml
volumes:
  press_bench:
    name: ${PREFIX}press_bench
  press_sites:
    name: ${PREFIX}press_sites
  press_logs:
    name: ${PREFIX}press_logs
  press_ssh:
    name: ${PREFIX}press_ssh

services:
  press:
    build:
      context: ./docker/press
      dockerfile: Dockerfile
    image: ${PREFIX}press:latest
    container_name: ${PREFIX}press
    restart: unless-stopped
    volumes:
      - press_bench:/home/frappe/frappe-bench
      - press_sites:/home/frappe/frappe-bench/sites
      - press_logs:/home/frappe/frappe-bench/logs
      - ./data/ssh:/home/frappe/.ssh:ro
    ports:
      - "127.0.0.1:14010:8000"
    networks:
      - default
    environment:
      SITE_NAME: ${PRESS_SITE_NAME}
      ADMIN_EMAIL: ${PRESS_ADMIN_EMAIL}
      ADMIN_PASSWORD: ${PRESS_ADMIN_PASSWORD}
      DB_HOST: ${PREFIX}mariadb
      DB_PORT: 3306
      DB_USER: ${MARIADB_PRESS_USER}
      DB_PASSWORD: ${MARIADB_PRESS_PASSWORD}
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.press.rule=Host(`${DOMAIN}`)"
      - "traefik.http.routers.press.entrypoints=websecure"
      - "traefik.http.routers.press.tls=true"
      - "traefik.http.services.press.loadbalancer.server.port=8000"
    depends_on:
      mariadb:
        condition: service_healthy
      redis-cache:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/api/method/frappe.ping"]
      interval: 30s
      timeout: 10s
      retries: 10
      start_period: 120s
```

**Step 4: Créer scripts/setup-press.sh**

```bash
#!/bin/bash
# scripts/setup-press.sh — Configure Press Settings après installation

set -e
source "$(dirname "$0")/../.env"

BENCH="docker exec ${PREFIX}press bench"
SITE="${PRESS_SITE_NAME}"

echo "=== Configuration Press Settings ==="

# Créer le site Press (si pas encore créé)
$BENCH new-site "$SITE" \
  --mariadb-root-password "$MARIADB_ROOT_PASSWORD" \
  --admin-password "$PRESS_ADMIN_PASSWORD" \
  --no-mariadb-socket || echo "Site déjà existant"

# Installer l'app Press
$BENCH --site "$SITE" install-app press || echo "Press déjà installé"

# Migrer
$BENCH --site "$SITE" migrate

# Configurer Press Settings via frappe API
docker exec ${PREFIX}press bash -c "
  cd /home/frappe/frappe-bench
  bench --site ${SITE} execute press.api.server.setup_server_hostname --args \"['${DOMAIN}']\"
"

# Configurer via Python
docker exec ${PREFIX}press bash -c "
  cd /home/frappe/frappe-bench
  bench --site ${SITE} execute press.overrides.setup_press_settings << 'PYEOF'
import frappe

def setup_press_settings():
    settings = frappe.get_single('Press Settings')
    # DNS Provider: Generic (pas besoin de Route53)
    settings.dns_provider = 'Generic'
    # Server Provider: Generic (serveurs locaux)
    settings.server_provider = 'Generic'
    # S3 (Garage)
    settings.aws_s3_bucket = '${GARAGE_BUCKET_BACKUPS}'
    settings.aws_access_key_id = '${GARAGE_ACCESS_KEY}'
    settings.aws_secret_access_key = '${GARAGE_SECRET_KEY}'
    settings.aws_s3_endpoint_url = 'http://${PREFIX}garage:3900'
    settings.save()
    frappe.db.commit()
    print('Press Settings configuré.')
PYEOF
"

echo "✓ Press configuré sur https://${DOMAIN}"
```

```bash
chmod +x scripts/setup-press.sh
```

**Step 5: Builder l'image Press** (long — ~10-15 minutes)

```bash
docker compose build press
```

Expected: Image `presse_claude_press:latest` buildée sans erreur.

**Step 6: Démarrer Press**

```bash
docker compose up -d press
```

**Step 7: Suivre les logs jusqu'au démarrage**

```bash
docker compose logs -f press
```

Attendre: `Serving on http://0.0.0.0:8000`

**Step 8: Créer le site Press**

```bash
./scripts/setup-press.sh
```

Expected:
```
=== Configuration Press Settings ===
Installing press...
✓ Press configuré sur https://press.local
```

**Step 9: Tester l'accès**

```bash
curl -k https://press.local:14002/api/method/frappe.ping 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin))"
```

Expected: `{'message': 'pong'}`

**Step 10: Commit**

```bash
git add docker/press/ compose/press.yml scripts/setup-press.sh scripts/generate-ssh-keys.sh
git commit -m "feat: add Frappe Press app with Generic providers and Garage S3"
```

---

### Task 8 : Enregistrer le Server Container dans Press

**Files:**
- Create: `scripts/register-server.sh`

**Step 1: Créer scripts/register-server.sh**

```bash
#!/bin/bash
# scripts/register-server.sh — Enregistre le container "server" dans Press

set -e
source "$(dirname "$0")/../.env"

BENCH="docker exec ${PREFIX}press bench"
SITE="${PRESS_SITE_NAME}"
SERVER_IP=$(docker inspect ${PREFIX}server | python3 -c "import sys,json; data=json.load(sys.stdin); print(data[0]['NetworkSettings']['Networks']['${PREFIX}network']['IPAddress'])")
SERVER_HOST="server.press.local"

echo "=== Enregistrement du Server dans Press ==="
echo "Server IP: ${SERVER_IP}"
echo "Server host: ${SERVER_HOST}"

# Copier la clé publique dans le server container
PUBLIC_KEY=$(cat ./data/ssh/press_id_rsa.pub)
docker exec ${PREFIX}server bash -c "
  mkdir -p /home/frappe/.ssh
  echo '$PUBLIC_KEY' >> /home/frappe/.ssh/authorized_keys
  chmod 700 /home/frappe/.ssh
  chmod 600 /home/frappe/.ssh/authorized_keys
  chown -R frappe:frappe /home/frappe/.ssh
"

# Tester la connexion SSH
ssh -i ./data/ssh/press_id_rsa \
    -o StrictHostKeyChecking=no \
    -p ${PORT_SERVER_SSH} \
    frappe@127.0.0.1 \
    "echo 'SSH OK'"

echo "✓ SSH opérationnel vers le server container"

# Enregistrer dans Press via frappe
docker exec ${PREFIX}press bash -c "
cd /home/frappe/frappe-bench
bench --site ${SITE} execute 'press.press.doctype.server.server.create_server' --args \"['${SERVER_HOST}', '${SERVER_IP}', '${PORT_SERVER_SSH}']\"
" 2>/dev/null || echo "Note: Enregistrement manuel requis via interface Press"

echo ""
echo "✓ Configuration terminée."
echo "  → Se connecter sur https://press.local"
echo "  → Infrastructure > Servers > New Server"
echo "    IP: ${SERVER_IP}"
echo "    Hostname: server.press.local"
echo "    SSH Port: 22 (interne Docker)"
```

```bash
chmod +x scripts/register-server.sh
```

**Step 2: Exécuter le script**

```bash
./scripts/register-server.sh
```

Expected:
```
=== Enregistrement du Server dans Press ===
Server IP: 172.20.0.X
✓ SSH opérationnel vers le server container
✓ Configuration terminée.
```

**Step 3: Enregistrer manuellement le server dans Press** (via UI)

```
1. Ouvrir https://press.local
2. Infrastructure > Servers > New
3. Renseigner:
   - Hostname: server.press.local
   - IP: [IP du container server]
   - SSH Port: 22
   - SSH User: frappe
4. Save → Press va se connecter et configurer via Ansible
```

**Step 4: Vérifier le server dans Press**

```
Infrastructure > Servers → Status: "Active"
```

**Step 5: Commit**

```bash
git add scripts/register-server.sh
git commit -m "feat: add register-server script and SSH key injection for Press"
```

---

### Task 9 : Script d'installation global

**Files:**
- Create: `scripts/install.sh`
- Create: `Makefile`

**Step 1: Créer scripts/install.sh**

```bash
#!/bin/bash
# scripts/install.sh — Installation guidée complète de Presse Claude

set -e
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║       PRESSE CLAUDE — Installation       ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# ── Prérequis ────────────────────────────────────────────────────
info "Vérification des prérequis..."
command -v docker >/dev/null 2>&1 || error "Docker non installé"
command -v git >/dev/null 2>&1 || error "Git non installé"
docker compose version >/dev/null 2>&1 || error "docker compose v2 non installé"

DOCKER_MEM=$(docker system info --format '{{.MemTotal}}' 2>/dev/null || echo 0)
if [ "$DOCKER_MEM" -lt 6000000000 ]; then
  warn "RAM recommandée: 8GB. Détectée: $(($DOCKER_MEM/1024/1024/1024))GB"
fi
info "Prérequis OK"

# ── Fichier .env ──────────────────────────────────────────────────
if [ ! -f ".env" ]; then
  cp .env.example .env
  warn ".env créé depuis .env.example — MODIFIEZ LES MOTS DE PASSE avant de continuer!"
  warn "Éditez .env puis relancez: ./scripts/install.sh"
  exit 0
fi
source .env

# ── SSH Keys ──────────────────────────────────────────────────────
info "Génération des clés SSH Press→Server..."
./scripts/generate-ssh-keys.sh

# ── DNS ───────────────────────────────────────────────────────────
info "Configuration DNS locale (press.local)..."
./scripts/dns-setup.sh

# ── Infrastructure ────────────────────────────────────────────────
info "Démarrage de l'infrastructure (MariaDB, Redis, Traefik)..."
docker compose up -d mariadb redis-cache redis-queue traefik

info "Attente que MariaDB soit prêt..."
for i in {1..30}; do
  docker exec ${PREFIX}mariadb mysqladmin ping -u root -p${MARIADB_ROOT_PASSWORD} -h localhost --silent 2>/dev/null && break
  sleep 2
done
info "MariaDB prêt"

# ── Garage S3 ─────────────────────────────────────────────────────
info "Démarrage Garage S3..."
docker compose up -d garage
sleep 10
./scripts/setup-garage.sh

# ── Server container ──────────────────────────────────────────────
info "Build du container serveur (peut prendre 5-10 min)..."
docker compose build server
docker compose up -d server
sleep 10

# ── Press ─────────────────────────────────────────────────────────
info "Build de Press (peut prendre 10-15 min)..."
docker compose build press
docker compose up -d press

info "Attente du démarrage de Press (jusqu'à 5 minutes)..."
for i in {1..60}; do
  curl -sk https://press.local:${PORT_HTTPS}/api/method/frappe.ping >/dev/null 2>&1 && break
  sleep 5
done

./scripts/setup-press.sh

# ── Enregistrement server ─────────────────────────────────────────
./scripts/register-server.sh

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║      Installation Terminée ! ✓           ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "  Press Dashboard: https://press.local"
echo "  Login:           ${PRESS_ADMIN_EMAIL}"
echo "  Mot de passe:    [voir .env PRESS_ADMIN_PASSWORD]"
echo ""
echo "Prochaines étapes:"
echo "  1. Ouvrir https://press.local (accepter le certificat self-signed)"
echo "  2. Infrastructure > Servers > Vérifier que 'server' est Active"
echo "  3. Release Groups > New > Créer un Release Group Frappe V16"
echo "  4. Sites > New > Créer votre premier site"
```

```bash
chmod +x scripts/install.sh
```

**Step 2: Créer Makefile**

```makefile
# Makefile — Commandes rapides Presse Claude
.PHONY: install start stop restart logs status clean

install:
	./scripts/install.sh

start:
	docker compose up -d

stop:
	docker compose stop

restart:
	docker compose restart

logs:
	docker compose logs -f --tail=50

status:
	docker compose ps

press-shell:
	docker exec -it ${PREFIX}press bash

server-shell:
	docker exec -it ${PREFIX}server bash

clean:
	docker compose down -v
	./scripts/dns-teardown.sh
	@echo "⚠️  Toutes les données supprimées"
```

**Step 3: Tester le script en mode dry-run**

```bash
# Vérifier la syntaxe bash
bash -n scripts/install.sh && echo "Syntaxe OK"
bash -n scripts/setup-press.sh && echo "Syntaxe OK"
bash -n scripts/register-server.sh && echo "Syntaxe OK"
```

Expected: `Syntaxe OK` pour chaque script

**Step 4: Tester make status**

```bash
make status
```

Expected: Liste des containers avec leur statut

**Step 5: Commit**

```bash
git add scripts/install.sh Makefile
git commit -m "feat: add install.sh orchestrator and Makefile shortcuts"
```

---

### Task 10 : CLAUDE.md — Documentation pour Claude Code

**Files:**
- Create: `CLAUDE.md`

**Step 1: Créer CLAUDE.md**

```markdown
# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Projet

Presse Claude — Plateforme SaaS Frappe Press 100% locale sur Docker.
Design: `docs/plans/2026-02-18-presse-claude-design.md`

## Commandes essentielles

```bash
make install      # Installation complète (première fois)
make start        # Démarrer tous les services
make stop         # Arrêter tous les services
make status       # Voir l'état des containers
make logs         # Voir les logs
make press-shell  # Shell dans le container Press
make server-shell # Shell dans le container server (Agent)
```

## Architecture

- Préfixe: `presse_claude_` (containers, volumes, réseaux, images)
- Domaine: `press.local` (sous-domaines: `*.press.local`)
- Ports: plage 14000-14500 (configurables dans `.env`)
- Config centrale: `.env` (jamais committer)

## Composants clés

- `compose/infra.yml` — Traefik, MariaDB, Redis
- `compose/press.yml` — Frappe Press (dashboard SaaS)
- `compose/server.yml` — Container "server" Ubuntu+SSH+Agent
- `compose/storage.yml` — Garage S3
- `compose/git.yml` — Forgejo (Git server)
- `compose/mail.yml` — Stalwart (email)
- `compose/monitoring.yml` — Prometheus + Grafana + Loki
- `compose/ai.yml` — Ollama + Open WebUI

## Règles impératives

1. **Ne jamais modifier .env** — utiliser .env.example comme référence
2. **Préfixer** tous nouveaux containers/volumes/réseaux avec `${PREFIX}`
3. **Tous les ports** dans la plage 14000-14500, définis dans `.env`
4. **Lire le design doc** avant toute modification: `docs/plans/2026-02-18-presse-claude-design.md`
5. **Ne jamais toucher** aux autres containers/projets sur la machine
6. **MariaDB seulement** pour les sites clients (Press ne supporte pas PostgreSQL pour les sites)

## Decisions architecturales clés

- Provider server: `Generic` (pas Hetzner/AWS)
- Provider DNS: `Generic` (pas Route53)
- S3: Garage (pas MinIO — maintenance mode depuis déc. 2025)
- Git: Forgejo v14 (pas Gitea — hard fork non-profit)
- Press version: branche `master` (pas de branche version-16 dans Press)
```

**Step 2: Vérifier la structure finale du projet**

```bash
find . -type f -not -path './.git/*' -not -path './data/*' | sort
```

Expected: Tous les fichiers du plan listés ci-dessus

**Step 3: Commit final Phase 1**

```bash
git add CLAUDE.md
git commit -m "docs: add CLAUDE.md with architecture guide and commands"
git tag -a v0.1.0-phase1-infra -m "Phase 1: Infrastructure core ready"
```

---

## PHASE 2 — Services complémentaires (tâches de haut niveau)

Ces tâches suivront le même pattern que la Phase 1 :

### Task 11 : Forgejo — Git server pour apps Frappe
- Déployer Forgejo v14 dans `compose/git.yml`
- Créer les repos des apps Frappe (erpnext, hrms, crm, etc.)
- Configurer Press pour utiliser Forgejo comme source d'apps
- Créer le premier Release Group "Frappe V16"

### Task 12 : Stalwart — Email self-hosted
- Déployer Stalwart dans `compose/mail.yml`
- Configurer frappe/mail app dans Press
- Tester envoi email (nouveau site créé → email de confirmation)

### Task 13 : Monitoring — Prometheus + Grafana + Loki
- Déployer la stack dans `compose/monitoring.yml`
- Dashboards: containers, Press metrics, sites metrics
- Alertes: container down, disk > 80%, MariaDB lent

### Task 14 : Premier site client — Validation end-to-end
- Créer un Release Group "Frappe V16" dans Press
- Ajouter les apps: frappe, erpnext, crm
- Créer le site `demo.press.local`
- Vérifier l'accès sur `https://demo.press.local`
- Valider le Use Case Admin complet

### Task 15 : Plans & Marketplace
- Créer les plans: Starter, Pro, Enterprise
- Associer apps aux plans
- Tester le Use Case Client (auto-inscription)

### Task 16 : Apps Phase 2 (ERP officiel)
- erpnext, hrms, crm, helpdesk, lms, drive, insights, wiki, gameplan
- Ajouter chaque app dans Forgejo + Release Groups Press

### Task 17 : Ollama + Open WebUI (IA locale)
- Déployer Ollama + Open WebUI dans `compose/ai.yml`
- Installer frappe/llm app dans Press
- Configurer provider Ollama dans Press Settings

---

## Vérification Phase 1 complète

```bash
# Tous les services up
docker compose ps

# Press accessible
curl -k https://press.local -I 2>/dev/null | grep "200\|302"

# Garage S3 répond
curl http://127.0.0.1:14040 -I 2>/dev/null | head -3

# SSH vers server OK
ssh -i ./data/ssh/press_id_rsa -p 14021 frappe@127.0.0.1 echo "OK"

# MariaDB
docker exec presse_claude_mariadb mysqladmin ping -u root -p$(grep MARIADB_ROOT_PASSWORD .env | cut -d= -f2) --silent
```

Expected: Toutes les commandes réussissent.
