#!/bin/bash
# scripts/dns-teardown.sh — Supprime les entrées DNS presse_claude de /etc/hosts
# Usage: ./scripts/dns-teardown.sh

set -euo pipefail

HOSTS_FILE="/etc/hosts"
MARKER_START="# === presse_claude START ==="
MARKER_END="# === presse_claude END ==="

if ! grep -q "$MARKER_START" "$HOSTS_FILE" 2>/dev/null; then
  echo "Aucune entrée presse_claude dans ${HOSTS_FILE}."
  exit 0
fi

echo "Suppression des entrées presse_claude de ${HOSTS_FILE} (sudo requis)..."
sudo sed -i "/${MARKER_START}/,/${MARKER_END}/d" "$HOSTS_FILE"
# Nettoyer la ligne vide laissée avant le bloc
sudo sed -i '/^$/N;/^\n$/d' "$HOSTS_FILE" 2>/dev/null || true
echo "✓ Entrées DNS presse_claude supprimées."
