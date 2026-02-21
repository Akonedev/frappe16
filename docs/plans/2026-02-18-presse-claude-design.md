# Presse Claude — Design Document

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:writing-plans to implement this design task-by-task.

**Goal:** Déployer une plateforme SaaS Cloud multi-tenant 100% locale basée sur Frappe Press, permettant de créer et gérer des sites Frappe/ERPNext pour des clients B2B et B2C, avec dashboard Press, multi-bench, 30+ apps, et intégration IA locale.

**Architecture:** Frappe Press (orchestrateur) + container "server" Ubuntu (Agent) + services infra open-source. Approche Frappe Cloud Hybrid adaptée en local Docker. Aucune dépendance cloud externe.

**Tech Stack:** Frappe Press (master/develop) + Frappe V16 + frappe/agent + MariaDB 10.6+ + Redis + Traefik v3 + Garage S3 + Forgejo v14 + Stalwart Mail + Prometheus/Grafana/Loki + Ollama

---

## Contexte & Contraintes

- **Environnement** : 100% local Docker, développement uniquement
- **Base de données** : MariaDB (standard Frappe — Press ne supporte pas PostgreSQL pour les sites)
- **Préfixe** : `presse_claude_` sur tous containers, volumes, réseaux, images, builds
- **Domaine local** : `press.local` (base), sous-domaines pour services et sites
- **Ports** : plage 14000–14500 uniquement, configurables depuis `.env`
- **Providers** : Generic (server + DNS) — aucune clé cloud requise
- **Paiement** : désactivé en dev (mode Manual billing)
- **SSL** : certificats self-signed via Traefik (dev) ou mkcert

---

## Architecture Globale

```
ENTRÉE
  Traefik v3 :14001 (HTTP) / :14002 (HTTPS)
  • press.local              → Press dashboard
  • *.press.local            → Sites clients (routing dynamique)
  • git.press.local          → Forgejo
  • s3.press.local           → Garage S3
  • monitor.press.local      → Grafana
  • traefik.press.local      → Traefik dashboard
  • ai.press.local           → Open WebUI

CONTRÔLE
  presse_claude_press (Frappe Press app)
  • Dashboard admin + client
  • Orchestration via SSH+Ansible → Agent API
  • Billing, Plans, Marketplace, Backups

SERVEUR GÉRÉ (simule un VPS)
  presse_claude_server (Ubuntu 22.04 container)
  • SSH :14021 (Press s'y connecte)
  • frappe/agent Flask :8000 (interne)
  • Benches + Sites clients

INFRASTRUCTURE
  MariaDB     :14030   DB Press + tous sites
  Redis       :14031   Cache + queue
  Garage      :14040   S3 object storage (backups, uploads)
  Forgejo     :14050   Git repos apps Frappe
  Stalwart    :14060   Email SMTP/JMAP
  Prometheus  :14070   Métriques
  Grafana     :14071   Monitoring UI
  Loki        :14072   Logs agrégés
  Ollama      :14080   LLM local
  Open WebUI  :14083   Interface IA
```

---

## Convention de nommage

```
Containers : presse_claude_<service>
             ex: presse_claude_press, presse_claude_mariadb
Volumes    : presse_claude_<service>_data
             ex: presse_claude_mariadb_data
Networks   : presse_claude_network
Images     : presse_claude/<service>:<tag>
             ex: presse_claude/server:latest
Builds     : presse_claude_build_<service>
```

---

## Domaines & Ports

```
DOMAINE BASE : press.local

Service              Sous-domaine              Port externe
─────────────────────────────────────────────────────────
Press dashboard      press.local               14002 (HTTPS)
Traefik UI           traefik.press.local       14002 (HTTPS)
Forgejo              git.press.local           14002 (HTTPS)
Garage S3            s3.press.local            14002 (HTTPS)
Grafana              monitor.press.local       14002 (HTTPS)
Open WebUI           ai.press.local            14002 (HTTPS)
Stalwart Admin       mail.press.local          14002 (HTTPS)

Sites clients        <nom>.press.local         14002 (HTTPS)

Accès directs (debug uniquement)
MariaDB              localhost                 14030
Redis                localhost                 14031
Garage S3 raw        localhost                 14040
Forgejo SSH          localhost                 14051
Server SSH           localhost                 14021
Prometheus           localhost                 14070
```

Tous les sous-domaines `*.press.local` requièrent une entrée dans `/etc/hosts` ou un DNS local (dnsmasq/CoreDNS).

---

## Structure du Projet

```
presse_claude/
├── .env                          ← config maître (ports, prefix, domaines, secrets)
├── .env.example                  ← template
├── .gitignore                    ← .env, data/, etc.
├── docker-compose.yml            ← compose principal (inclut tous les modules)
│
├── compose/
│   ├── infra.yml                 ← Traefik, MariaDB, Redis
│   ├── storage.yml               ← Garage S3
│   ├── press.yml                 ← Press app
│   ├── server.yml                ← Server container (Agent)
│   ├── git.yml                   ← Forgejo
│   ├── mail.yml                  ← Stalwart
│   ├── monitoring.yml            ← Prometheus, Grafana, Loki
│   └── ai.yml                    ← Ollama, Open WebUI
│
├── config/
│   ├── traefik/
│   │   ├── traefik.yml           ← config statique
│   │   └── dynamic/              ← routes custom
│   ├── garage/
│   │   └── garage.toml
│   ├── forgejo/
│   │   └── app.ini
│   ├── stalwart/
│   │   └── config.toml
│   ├── prometheus/
│   │   └── prometheus.yml
│   └── loki/
│       └── loki.yml
│
├── docker/
│   ├── server/
│   │   ├── Dockerfile            ← Ubuntu 22.04 + SSH + bench prereqs
│   │   └── entrypoint.sh
│   └── press/
│       └── Dockerfile            ← Press sur frappe_docker base
│
├── scripts/
│   ├── install.sh                ← installation guidée complète
│   ├── dns-setup.sh              ← ajoute *.press.local dans /etc/hosts
│   ├── setup-press.sh            ← configure Press Settings (providers Generic)
│   ├── register-server.sh        ← enregistre server container dans Press
│   └── backup.sh
│
├── apps/
│   └── README.md                 ← liste des apps à installer dans Forgejo
│
└── docs/
    └── plans/
        └── 2026-02-18-presse-claude-design.md   ← ce fichier
```

---

## Configuration .env

```env
# Prefix
PREFIX=presse_claude_

# Domaine
DOMAIN=press.local

# Ports HTTP/HTTPS (Traefik)
PORT_HTTP=14001
PORT_HTTPS=14002
PORT_TRAEFIK_DASH=14003

# Services
PORT_MARIADB=14030
PORT_REDIS=14031
PORT_GARAGE_S3=14040
PORT_GARAGE_WEB=14041
PORT_FORGEJO_HTTP=14050
PORT_FORGEJO_SSH=14051
PORT_STALWART_SMTP=14060
PORT_STALWART_IMAP=14061
PORT_STALWART_HTTP=14062
PORT_PROMETHEUS=14070
PORT_GRAFANA=14071
PORT_LOKI=14072
PORT_SERVER_SSH=14021
PORT_SERVER_AGENT=14022
PORT_OLLAMA=14080
PORT_OPENWEBUI=14083

# Credentials (à modifier)
MARIADB_ROOT_PASSWORD=change_me_root
MARIADB_PRESS_PASSWORD=change_me_press
REDIS_PASSWORD=

# Press
PRESS_ADMIN_EMAIL=admin@press.local
PRESS_ADMIN_PASSWORD=change_me_admin
PRESS_SITE_NAME=press.local

# Garage S3
GARAGE_ACCESS_KEY=pressclaudekey
GARAGE_SECRET_KEY=pressclaudesecret
GARAGE_BUCKET=press-backups

# Forgejo
FORGEJO_ADMIN_USER=admin
FORGEJO_ADMIN_PASSWORD=change_me_forgejo

# Stalwart
STALWART_ADMIN_EMAIL=admin@press.local
STALWART_ADMIN_PASSWORD=change_me_stalwart
```

---

## Flux d'Installation

```
1. Prérequis vérifiés (Docker 24+, docker-compose v2, 8GB RAM min)
2. cp .env.example .env && nano .env
3. ./scripts/dns-setup.sh
   → Ajoute dans /etc/hosts:
     127.0.0.1 press.local *.press.local git.press.local ...
4. docker-compose up -d (infra: traefik, mariadb, redis, garage)
5. docker-compose up -d press
   → bench init + bench new-site press.local
   → bench install-app press
6. docker-compose up -d server
   → Ubuntu container SSH prêt
7. ./scripts/setup-press.sh
   → Press Settings: Generic server + DNS, Garage S3, Forgejo
8. ./scripts/register-server.sh
   → Enregistre presse_claude_server dans Press comme "server"
9. Accès: https://press.local (accepter cert self-signed)
```

---

## Use Cases Fonctionnels

### Admin — Créer un site client

1. Login → `https://press.local`
2. Teams > New Team → renseigner données client
3. Sites > New Site → choisir bench, apps du plan, template/thème
4. Valider → Press déclenche Agent → site créé
5. Client accède à `https://nomclient.press.local`

### Client — Auto-inscription

1. `https://press.local/signup`
2. Renseigner infos → choisir plan → payer (désactivé dev)
3. Sélectionner apps incluses + template + thème
4. Valider → création automatique du site

---

## Plans & Apps

```
Plan Starter:  frappe, erpnext, crm, helpdesk
               → bench partagé
Plan Pro:      frappe, erpnext, crm, helpdesk, hrms, lms, drive
               → bench partagé
Plan Enterprise: toutes apps disponibles
               → bench isolé (container dédié)
```

---

## Roadmap Apps (par phases)

```
Phase 1 — Core (semaine 1-2)
  frappe (v16), press

Phase 2 — ERP officiel (semaine 3-4)
  erpnext, hrms, crm, helpdesk, lms, drive, insights, wiki, gameplan

Phase 3 — Communication & outils
  frappe/mail, raven (The Commit Co.), frappe/builder,
  frappe/print_designer, frappe/meeting

Phase 4 — Métier sectoriel
  education, hospitality, lending, non_profit, webshop

Phase 5 — Community apps
  frappe_whatsapp, frappe_paystack, raven, bench_manager

Phase 6 — IA (scope futur)
  frappe/llm, Ollama, WhisperLiveKit, TTS, Open WebUI,
  génération vidéo/image
```

---

## Sécurité & Réseau (dev local)

- Réseau Docker isolé `presse_claude_network` (subnet 172.20.0.0/16)
- Ports exposés sur `127.0.0.1` uniquement (pas `0.0.0.0`)
- SSL self-signed via Traefik (dev) — remplacer par mkcert pour éviter warnings navigateur
- Secrets dans `.env` (dans `.gitignore`)
- SSH Press→Server via clé générée à l'install (jamais de mot de passe)

---

## Décisions Architecturales Clés

| Décision | Choix | Raison |
|---|---|---|
| Approche | Frappe Cloud Hybrid local | Architecture officielle, upgradable |
| Provider server | Generic | Pas de dépendance cloud |
| Provider DNS | Generic | DNS local /etc/hosts |
| DB sites | MariaDB | Seule option supportée par Press |
| S3 storage | Garage (pas MinIO) | MinIO en maintenance mode déc. 2025 |
| Git server | Forgejo v14 | Hard fork actif non-profit de Gitea |
| Reverse proxy | Traefik v3 | Service discovery Docker auto |
| Email | Stalwart + frappe/mail | App officielle Frappe multi-tenant |
| Monitoring | Prometheus+Loki+Grafana | Stack CNCF standard |
| LLM local | Ollama | API OpenAI-compatible, multi-modèles |

---

## Notes Importantes

1. **PostgreSQL** : Press gère les sites uniquement en MariaDB. PostgreSQL n'est pas supporté par Press pour les sites clients.
2. **Agent** : `frappe/agent` est le composant officiel — pas de fork ni custom requis.
3. **Press version** : branche `master` ou `develop` (pas de branche version-16 spécifique dans Press).
4. **Mises à jour** : l'architecture standard permet les mises à jour Press via `bench update` sans friction.
5. **MinIO** : ne pas utiliser — Garage est le remplacement recommandé (maintenance mode depuis déc. 2025).
