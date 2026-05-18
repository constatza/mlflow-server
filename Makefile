ENVFILE   := $(if $(wildcard .env.local),--env-file .env.local,)
COMPOSE   := docker compose $(ENVFILE)
# Mirror the artifacts path resolution from docker-compose.yml
ARTIFACTS := $(or $(MLFLOW_ARTIFACTS_DIR),$(addsuffix /artifacts,$(or $(MLFLOW_DATA_DIR),$(or $(XDG_DATA_HOME),$(HOME)/.local/share)/mlflow-server)))

.PHONY: init up down logs restart gc

## Create required host directories before first start.
init:
	mkdir -p "$(ARTIFACTS)"

## Build images and start all services (runs init first).
up: init
	$(COMPOSE) up -d --build

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

## Stop the stack and delete the database volume (artifacts are preserved).
reset-db: down
	docker volume rm -f mlflow-server-db
