#!/bin/bash
# scripts/generate-ssh-keys.sh — Génère la paire SSH Press → Server
# Usage: ./scripts/generate-ssh-keys.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
KEY_DIR="${PROJECT_DIR}/data/ssh"

mkdir -p "${KEY_DIR}"
chmod 700 "${KEY_DIR}"

if [ -f "${KEY_DIR}/press_id_rsa" ]; then
  echo "Clés SSH déjà générées dans ${KEY_DIR}/"
  echo "Clé publique: $(cat "${KEY_DIR}/press_id_rsa.pub")"
  exit 0
fi

echo "→ Génération des clés SSH Press→Server..."
ssh-keygen -t rsa -b 4096 \
  -f "${KEY_DIR}/press_id_rsa" \
  -N "" \
  -C "press@press.local"

chmod 600 "${KEY_DIR}/press_id_rsa"
chmod 644 "${KEY_DIR}/press_id_rsa.pub"

PUBLIC_KEY=$(cat "${KEY_DIR}/press_id_rsa.pub")

# Ajouter PRESS_PUBLIC_KEY dans .env si absent
if ! grep -q "^PRESS_PUBLIC_KEY=" "${PROJECT_DIR}/.env"; then
  echo "" >> "${PROJECT_DIR}/.env"
  echo "# SSH key Press->Server (auto-générée)" >> "${PROJECT_DIR}/.env"
  echo "PRESS_PUBLIC_KEY=${PUBLIC_KEY}" >> "${PROJECT_DIR}/.env"
  echo "✓ PRESS_PUBLIC_KEY ajoutée dans .env"
fi

echo ""
echo "✓ Clés SSH générées:"
echo "  Privée: ${KEY_DIR}/press_id_rsa"
echo "  Publique: ${KEY_DIR}/press_id_rsa.pub"
