# docker/press/Dockerfile
# Frappe Press — Plateforme SaaS sur Frappe V16
# Le bench est initialisé au premier démarrage via entrypoint.sh

FROM python:3.12-slim-bookworm

ARG DEBIAN_FRONTEND=noninteractive

# Fix GPG signature validation issues (Docker environment / date drift)
RUN printf 'Acquire::AllowInsecureRepositories "true";\nAcquire::AllowDowngradeToInsecureRepositories "true";\nAcquire::Check-Valid-Until "false";\n' \
    > /etc/apt/apt.conf.d/99docker-insecure

# ── Système : toutes les dépendances Frappe (cf. frappe.io/docs/installation) ─
RUN apt-get update -o Acquire::AllowInsecureRepositories=true && apt-get install -y --allow-unauthenticated \
    # Outils de base
    git \
    curl \
    wget \
    sudo \
    vim \
    jq \
    # pkg-config (requis par bench init pour compiler certains packages)
    pkg-config \
    # SSL / crypto
    libssl-dev \
    libffi-dev \
    # nginx (reverse proxy pour assets statiques + redirects)
    nginx \
    # MariaDB client + headers (requis par PyMySQL/mysqlclient)
    mariadb-client \
    default-libmysqlclient-dev \
    # Redis tools
    redis-tools \
    # SSH (Press se connecte aux servers via SSH)
    openssh-client \
    sshpass \
    # Ansible (Press l'utilise pour provisioner les servers)
    ansible \
    # wkhtmltopdf (PDF generation)
    wkhtmltopdf \
    # Build tools
    build-essential \
    python3-dev \
    # Dépendances supplémentaires
    libpq-dev \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ── Node.js 24 + yarn (Frappe v16 requiert Node >= 24) ────────────────────────
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - && \
    apt-get install -y nodejs && \
    npm install -g yarn && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# ── Utilisateur frappe ────────────────────────────────────────────────────────
RUN useradd -m -u 1000 -s /bin/bash frappe && \
    echo "frappe ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/frappe && \
    chmod 0440 /etc/sudoers.d/frappe

USER frappe
WORKDIR /home/frappe

# ── bench CLI ─────────────────────────────────────────────────────────────────
RUN pip install --user frappe-bench uuid6

# Ajouter ~/.local/bin au PATH
ENV PATH="/home/frappe/.local/bin:${PATH}"

# ── Répertoires ───────────────────────────────────────────────────────────────
RUN mkdir -p /home/frappe/.ssh && \
    chmod 700 /home/frappe/.ssh

EXPOSE 8000

# NOTE: Copier l'entrypoint hors de /home/frappe pour éviter
# qu'il soit masqué par le volume press_home monté sur /home/frappe
USER root
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER frappe
ENTRYPOINT ["/entrypoint.sh"]
