#!/bin/bash
# entrypoint.sh — Démarre SSH server + frappe-agent

set -e

# Générer les clés SSH du host si absentes
ssh-keygen -A 2>/dev/null || true

# Injecter la clé publique Press si fournie
if [ -n "${PRESS_PUBLIC_KEY:-}" ]; then
  mkdir -p /home/frappe/.ssh
  echo "${PRESS_PUBLIC_KEY}" >> /home/frappe/.ssh/authorized_keys
  sort -u /home/frappe/.ssh/authorized_keys > /tmp/auth_keys_sorted
  mv /tmp/auth_keys_sorted /home/frappe/.ssh/authorized_keys
  chmod 700 /home/frappe/.ssh
  chmod 600 /home/frappe/.ssh/authorized_keys
  chown -R frappe:frappe /home/frappe/.ssh
fi

# Démarrer SSH en arrière-plan
/usr/sbin/sshd

echo "==> SSH server démarré"
echo "==> Démarrage de frappe-agent sur port 8000..."

# Démarrer frappe-agent en tant que frappe (avec fallback SSH-only)
if [ -x /home/frappe/.venv/bin/agent ]; then
  exec sudo -u frappe /home/frappe/.venv/bin/agent start --port 8000
elif command -v agent >/dev/null 2>&1; then
  exec sudo -u frappe agent start --port 8000
else
  echo "frappe-agent non disponible, container en mode SSH uniquement"
  exec tail -f /dev/null
fi
