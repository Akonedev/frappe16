# docker/server/Dockerfile
# Container "serveur géré" Ubuntu pour Frappe Press
# Simule un VPS Ubuntu sur lequel Press déploie des benches et sites via SSH+Ansible+Agent

FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive

# ── Système de base ──────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y \
    # SSH server
    openssh-server \
    # Outils système
    sudo \
    curl \
    wget \
    git \
    vim \
    htop \
    jq \
    # Python
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    # Node.js (requis par bench/frappe)
    nodejs \
    npm \
    # MariaDB client (pour bench new-site)
    mariadb-client \
    # Redis tools
    redis-tools \
    # Nginx (géré par bench)
    nginx \
    # wkhtmltopdf (PDF generation)
    wkhtmltopdf \
    # Prérequis Ansible
    python3-apt \
    # Supervision
    supervisor \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ── Utilisateur frappe (UID 1000 — standard Frappe Cloud Hybrid) ─────────────
RUN useradd -m -u 1000 -s /bin/bash frappe && \
    echo "frappe ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/frappe && \
    chmod 0440 /etc/sudoers.d/frappe && \
    mkdir -p /home/frappe/{benches,archived,.ssh}

# ── SSH server config ─────────────────────────────────────────────────────────
RUN mkdir -p /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config && \
    sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/^#AuthorizedKeysFile/AuthorizedKeysFile/' /etc/ssh/sshd_config

COPY sshd_config /etc/ssh/sshd_config.d/frappe.conf

# ── Virtual environment Python pour frappe ───────────────────────────────────
USER frappe
WORKDIR /home/frappe

RUN python3 -m venv /home/frappe/.venv && \
    /home/frappe/.venv/bin/pip install --upgrade pip

# ── frappe-bench CLI ─────────────────────────────────────────────────────────
RUN /home/frappe/.venv/bin/pip install frappe-bench

# ── frappe-agent ─────────────────────────────────────────────────────────────
RUN /home/frappe/.venv/bin/pip install frappe-agent || true

# ── Permissions finales ───────────────────────────────────────────────────────
USER root
RUN chown -R frappe:frappe /home/frappe && \
    ln -sf /home/frappe/.venv/bin/bench /usr/local/bin/bench || true && \
    ln -sf /home/frappe/.venv/bin/agent /usr/local/bin/agent || true

# Expose SSH et Agent
EXPOSE 22 8000

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
