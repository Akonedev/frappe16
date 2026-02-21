# docker/press/Dockerfile
# Frappe Press — Plateforme SaaS sur Frappe V16
# Le bench est initialisé au premier démarrage via entrypoint.sh

FROM python:3.11-slim-bookworm

ARG DEBIAN_FRONTEND=noninteractive

# ── Système ───────────────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y \
    # Outils de base
    git \
    curl \
    wget \
    sudo \
    vim \
    jq \
    # Node.js 18+
    nodejs \
    npm \
    # MariaDB client
    mariadb-client \
    # Redis tools
    redis-tools \
    # SSH (Press se connecte aux servers via SSH)
    openssh-client \
    sshpass \
    # Ansible (Press l'utilise pour provisioner les servers)
    ansible \
    # wkhtmltopdf
    wkhtmltopdf \
    # Build tools
    build-essential \
    python3-dev \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ── Utilisateur frappe ────────────────────────────────────────────────────────
RUN useradd -m -u 1000 -s /bin/bash frappe && \
    echo "frappe ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/frappe && \
    chmod 0440 /etc/sudoers.d/frappe

USER frappe
WORKDIR /home/frappe

# ── bench CLI ─────────────────────────────────────────────────────────────────
RUN pip install --user frappe-bench

# Ajouter ~/.local/bin au PATH
ENV PATH="/home/frappe/.local/bin:${PATH}"

# ── Répertoires ───────────────────────────────────────────────────────────────
RUN mkdir -p /home/frappe/.ssh && \
    chmod 700 /home/frappe/.ssh

EXPOSE 8000

COPY --chown=frappe:frappe entrypoint.sh /home/frappe/entrypoint.sh
RUN chmod +x /home/frappe/entrypoint.sh

ENTRYPOINT ["/home/frappe/entrypoint.sh"]
