# Makefile — Presse Claude: commandes rapides
.PHONY: install start stop restart logs status clean \
        press-shell server-shell setup-press register-server dns dns-remove webhooks mkcert

ENV=--env-file .env

install:
	./scripts/install.sh

start:
	docker compose $(ENV) up -d

stop:
	docker compose $(ENV) stop

restart:
	docker compose $(ENV) restart

logs:
	docker compose $(ENV) logs -f --tail=50

status:
	docker compose $(ENV) ps

press-shell:
	docker exec -it $(PREFIX)press bash

server-shell:
	docker exec -it $(PREFIX)server bash

setup-press:
	./scripts/setup-press.sh

register-server:
	./scripts/register-server.sh

webhooks:
	./scripts/setup_forgejo_webhooks.sh

mkcert:
	./scripts/setup-mkcert.sh

dns:
	./scripts/dns-setup.sh

dns-remove:
	./scripts/dns-teardown.sh

clean:
	docker compose $(ENV) down -v
	./scripts/dns-teardown.sh 2>/dev/null || true
	@echo "⚠  Données supprimées"
