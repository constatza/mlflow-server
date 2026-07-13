ENVFILE   := $(if $(wildcard .env),--env-file .env,) $(if $(wildcard .env.local),--env-file .env.local,)
HOST_UID  := $(shell id -u)
HOST_GID  := $(shell id -g)
COMPOSE   := HOST_UID=$(HOST_UID) HOST_GID=$(HOST_GID) docker compose $(ENVFILE)
# Mirror the artifacts path from docker-compose.yml, honouring .env then .env.local.
ARTIFACTS := $(shell [ -f .env ] && . ./.env; [ -f .env.local ] && . ./.env.local; echo "$${MLFLOW_ARTIFACTS_DIR:-$${XDG_DATA_HOME:-$$HOME/.local/share}/mlflow-server/artifacts}")

# Usage: $(call confirm,prompt text)
# Single line so the @-prefix suppresses the full command regardless of Make version.
define confirm
@printf "$(1) [y/N] "; read ans; case "$${ans}" in [yY]|[yY][eE][sS]) ;; *) echo "Aborted."; exit 1;; esac
endef

.PHONY: init up down logs restart gc db-upgrade reset-db purge

## Create required data directories and assign them to the MLflow runtime user.
init:
	$(COMPOSE) run --rm mlflow-init

## Build images and (re)start all services, always matching the current .env config.
## --force-recreate guarantees this even if only .env/.env.local changed (e.g. a
## storage path) and containers were left running from before that change --
## otherwise they'd keep their stale bind mounts indefinitely.
up:
	$(COMPOSE) up -d --build --pull always --force-recreate

## Stop and remove containers (data is preserved).
down:
	$(COMPOSE) down

## Follow logs for all services.
logs:
	$(COMPOSE) logs -f

## Restart all services without rebuilding.
restart:
	$(COMPOSE) restart

## Run garbage collection immediately (on-demand).
gc:
	docker exec -t mlflow-gc once

## Upgrade the MLflow database schema after a version bump (SQLite only).
## For PostgreSQL, run: mlflow db upgrade "$MLFLOW_BACKEND_URI" directly.
## If this fails with "Can't locate revision", the schema is too old -- use reset-db or purge.
db-upgrade:
	$(call confirm,Upgrade the MLflow DB schema? The stack will be stopped first.)
	@$(COMPOSE) down
	@docker run --rm -v mlflow-server-db:/data/db \
		--user "$(HOST_UID):$(HOST_GID)" \
		ghcr.io/mlflow/mlflow:latest \
		mlflow db upgrade "sqlite:////data/db/mlflow.db?timeout=30&journal_mode=WAL"
	@printf "Schema upgraded. Run 'make up' to restart.\n"

## Delete the database volume (artifacts are preserved but become orphaned).
## WARNING: mlflow gc cannot clean up orphaned artifact directories left on disk.
## Use 'make purge' for a fully clean slate (DB + artifacts).
reset-db:
	@printf "WARNING: artifact files under $(ARTIFACTS)\n"
	@printf "will be orphaned and cannot be cleaned by mlflow gc.\n"
	@printf "Use 'make purge' instead for a clean slate.\n"
	$(call confirm,Delete DB only?)
	@$(COMPOSE) down
	@docker volume rm -f mlflow-server-db

## DESTRUCTIVE: permanently wipe the DB volume AND all artifacts on disk.
purge:
	@printf "WARNING: this will permanently delete the DB volume and all artifacts under\n"
	@printf "  $(ARTIFACTS)\n"
	@printf "All experiments, runs, and logged files will be lost.\n"
	$(call confirm,Continue?)
	@$(COMPOSE) down
	@docker volume rm -f mlflow-server-db
	@rm -rf "$(ARTIFACTS)"
