# Development commands. `make help` lists everything.
#
# `docker compose`, not `docker-compose`: the hyphenated v1 binary is
# end-of-life, is not installed by current Docker Desktop, and silently reads a
# slightly different .env. Every target below goes through the v2 plugin.

.DEFAULT_GOAL := help
COMPOSE := docker compose
RB := $(COMPOSE) exec -T rb

# The port compose actually published. Make does not read .env the way compose
# does, so without this the URL printed below would keep naming 8282 while a
# second checkout's stack answers somewhere else -- a wrong URL is worse than
# no URL.
HTTP_PORT := $(shell sed -n 's/^HTTP_PORT=//p' .env 2>/dev/null | tail -1)
HTTP_PORT := $(if $(HTTP_PORT),$(HTTP_PORT),8282)

# ---------------------------------------------------------------- lifecycle

.PHONY: help
help:  ## show this list
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

.PHONY: up
up: infra  ## start all containers
	$(COMPOSE) up -d
	@$(MAKE) --no-print-directory url

# MySQL and Redis live in ../dev-infra and are shared with every other project
# on this machine. Compose's own message for a missing external network --
# "network apps_local declared as external, but could not be found" -- reads
# like a broken compose file rather than a stack that is simply not up.
.PHONY: infra
infra:  ## check the shared dev-infra stack is running
	@docker network inspect apps_local >/dev/null 2>&1 || { \
	  echo "The shared stack is not running. Start it with:"; \
	  echo "  cd ../dev-infra && docker compose up -d"; exit 1; }

.PHONY: start
start: up  ## alias for `make up`

.PHONY: url
url:  ## print the local and LAN URLs
	@echo "  local: http://localhost:$(HTTP_PORT)"
	@ip=$$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null \
	  || hostname -I 2>/dev/null | awk '{print $$1}'); \
	  [ -n "$$ip" ] && echo "  phone: http://$$ip:$(HTTP_PORT)" \
	                || echo "  phone: (no LAN address found)"

.PHONY: build
build:  ## rebuild images
	$(COMPOSE) build

.PHONY: stop
stop:  ## stop containers, keep them
	$(COMPOSE) stop

.PHONY: down
down:  ## stop and remove containers
	$(COMPOSE) down

.PHONY: restart
restart:  ## stop then start
	$(COMPOSE) stop
	$(COMPOSE) up -d

# No target destroys the database. It lives on the shared server in
# ../dev-infra alongside every other project's, so `down -v` here would take
# out work that is not this repository's -- drop the schema by name instead:
#
#   make db
#   DROP DATABASE <app>_development;

# ------------------------------------------------------------------ working

.PHONY: logs
logs:  ## follow app logs
	$(COMPOSE) logs -f rb

.PHONY: sh
sh:  ## shell in the app container
	$(COMPOSE) exec rb bash

.PHONY: console
console:  ## rails console
	$(COMPOSE) exec rb bin/rails console

.PHONY: db
db:  ## mysql shell on the shared dev server
	docker exec -it dev-db-mysql mysql -uroot -pdev12345

# db:prepare, not db:migrate. The database server is shared and creates
# nothing on its own, so a first run has no <app>_development to migrate.
# db:prepare creates it if it is missing and then migrates, and is a no-op on
# every run after that.
.PHONY: migrate
migrate:  ## create the database if missing, then migrate
	$(RB) bin/rails db:prepare

.PHONY: bundle
bundle:  ## install gems
	$(RB) bundle install

# ------------------------------------------------------------------- checks

# The same three things CI runs, in the same order, so a green run here means a
# green run there.
.PHONY: check
check: lint test scan  ## everything CI runs

.PHONY: test
test:  ## run the test suite
	$(RB) bin/rails db:test:prepare test

.PHONY: lint
lint:  ## rubocop
	$(RB) bin/rubocop

.PHONY: lint-fix
lint-fix:  ## rubocop -a
	$(RB) bin/rubocop -a

.PHONY: scan
scan:  ## brakeman + bundler-audit + importmap audit
	$(RB) bin/brakeman --no-pager
	$(RB) bin/bundler-audit
	$(RB) bin/importmap audit
