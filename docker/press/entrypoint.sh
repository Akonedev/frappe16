#!/bin/bash
# entrypoint.sh — Initialise et démarre Frappe Press

set -euo pipefail

BENCH_DIR="/home/frappe/frappe-bench"
SITE_NAME="${SITE_NAME:-press.local}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin}"

echo "=== Presse Claude — Démarrage Press ==="

# ── Initialiser bench si pas encore fait ──────────────────────────────────────
if [ ! -f "${BENCH_DIR}/apps/frappe/frappe/__init__.py" ]; then
  echo "→ Initialisation du bench Frappe V16 (première fois, ~10 minutes)..."
  cd /home/frappe
  bench init --frappe-branch version-16 --skip-redis-config-generation frappe-bench
  cd "${BENCH_DIR}"

  echo "→ Installation de l'app Press (branche master)..."
  bench get-app press https://github.com/frappe/press --branch master

  echo "→ Création du site ${SITE_NAME}..."
  bench new-site "${SITE_NAME}" \
    --mariadb-root-password "${MARIADB_ROOT_PASSWORD:-}" \
    --admin-password "${ADMIN_PASSWORD}" \
    --db-host "${DB_HOST:-mariadb}" \
    --db-port "${DB_PORT:-3306}" \
    --no-mariadb-socket \
    2>/dev/null || echo "Site déjà existant"

  echo "→ Installation de Press..."
  bench --site "${SITE_NAME}" install-app press 2>/dev/null || echo "Press déjà installé"

  echo "→ Migration..."
  bench --site "${SITE_NAME}" migrate
fi

# ── Configurer le site par défaut ─────────────────────────────────────────────
cd "${BENCH_DIR}"
bench use "${SITE_NAME}" 2>/dev/null || true

echo "→ Démarrage de Press sur http://0.0.0.0:8000..."
exec bench serve --port 8000
