# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Projet

**Presse Claude** — Plateforme SaaS Frappe Press 100% locale sur Docker (dev).
Design complet: `docs/plans/2026-02-18-presse-claude-design.md`
Plan d'implémentation: `docs/plans/2026-02-18-implementation-plan.md`

## Commandes essentielles

```bash
make install         # Installation complète (première fois)
make start           # Démarrer tous les services
make stop            # Arrêter tous les services
make status          # État des containers
make logs            # Logs en temps réel
make press-shell     # Shell dans Press container
make server-shell    # Shell dans server container (Agent)
make setup-press     # Configurer Press Settings après démarrage
make register-server # Enregistrer server container dans Press
make dns             # Ajouter *.press.local dans /etc/hosts
make dns-remove      # Supprimer les entrées DNS
make clean           # Tout arrêter et supprimer les données
```

## Architecture

```
Traefik v3 (:14001 HTTP, :14002 HTTPS)
    ├── press.local → Press dashboard (presse_claude_press)
    ├── *.press.local → Sites clients
    ├── git.press.local → Forgejo
    ├── s3.press.local → Garage S3
    ├── monitor.press.local → Grafana
    └── ai.press.local → Open WebUI

Orchestration:
    presse_claude_press → SSH(:14021) → presse_claude_server
                        → Agent HTTP(:14022)

Infra:
    presse_claude_mariadb  (:14030) — Base de données (MariaDB 10.6)
    presse_claude_redis_*           — Cache + Queue (Redis 7)
    presse_claude_garage   (:14040) — S3 storage (Garage v1.0.0)
```

## Conventions impératives

1. **Préfixe `presse_claude_`** sur tous les containers, volumes, réseaux, images
2. **Ports 14000-14500** uniquement, tous définis dans `.env`
3. **Jamais de valeur en dur** — toujours `${VARIABLE}` depuis `.env`
4. **`.env` jamais commité** (dans `.gitignore`)
5. **Chemins relatifs** dans `compose/*.yml` : utiliser `../` pour remonter à la racine
6. **MariaDB uniquement** pour les sites clients (Press ne supporte pas PostgreSQL)
7. **Lire le design doc** avant toute modification architecturale

## Composants clés

| Fichier | Rôle |
|---|---|
| `compose/infra.yml` | Traefik v3, MariaDB 10.6, Redis 7 |
| `compose/press.yml` | Frappe Press (dashboard SaaS) |
| `compose/server.yml` | Container "server" Ubuntu+SSH+Agent |
| `compose/storage.yml` | Garage S3 (remplace MinIO/AWS S3) |
| `compose/git.yml` | Forgejo v14 (remplace GitHub) |
| `compose/mail.yml` | Stalwart Mail |
| `compose/monitoring.yml` | Prometheus + Grafana + Loki |
| `compose/ai.yml` | Ollama + Open WebUI |
| `docker/server/` | Dockerfile Ubuntu+SSH+bench+agent |
| `docker/press/` | Dockerfile Frappe Press V16 |
| `config/traefik/` | Config statique + TLS |
| `config/garage/` | Config Garage S3 |

## Décisions architecturales

| Décision | Choix | Raison |
|---|---|---|
| Provider server | Generic | Pas de dépendance Hetzner/AWS |
| Provider DNS | Generic | DNS via /etc/hosts |
| S3 storage | Garage v1.0.0 | MinIO en maintenance mode déc. 2025 |
| Git server | Forgejo v14 | Hard fork non-profit actif de Gitea |
| Email | Stalwart + frappe/mail | App officielle Frappe |
| Proxy | Traefik v3 | Service discovery Docker auto |
| Branch Press | master | Pas de branche version-16 dans Press |
| DB sites | MariaDB 10.6 | Seule option supportée par Press |
| Garage keys | Format GKxxxx | Généré par Garage (pas configurable) |
