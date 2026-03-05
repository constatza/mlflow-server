# Minimal [MLflow](https://mlflow.org/) Tracking Server (Docker Compose)

A minimal, portable MLflow tracking server that:

- defaults to **SQLite** (zero configuration)
- optionally supports **PostgreSQL** (more robust backend)
- works on **Linux and Windows**
- runs as a **long-lived service** (auto-restarts after reboot)
- stores all data under **$HOME by default**
- keeps PostgreSQL **private by default** (no LAN/WAN exposure)
- runs **scheduled MLflow GC** and supports **on-demand GC** from anywhere

---

## Quick start

### 1) Install prerequisites
- Install [Docker](https://docs.docker.com/get-docker/)
- Install Git

### 2) Clone the repository
```bash
git clone https://github.com/constatza/mlflow-server.git
cd mlflow-server
```

### 3) Optional configuration
If you want to change ports / allowed hosts / CORS / DB backend:

```bash
cp .env.example .env
# edit .env
```

> Note: `.env` is intentionally not committed. Treat it as machine-local configuration (and secrets, if you enable Postgres auth).

### 4) Start
```bash
docker compose up -d --build
```

> Note: `--build` is important because this repo adds two small GC helper commands (`loop` and `once`) into a custom image. That makes the on-demand GC command work consistently across OSes.

### 5) Check status
```bash
docker compose ps
```

### 6) Run GC now (from anywhere)
```bash
docker exec -t mlflow-gc once
```

> Note: This intentionally uses `docker exec` instead of `docker compose exec/run` so you don’t need to be in the repo directory (and don’t need to care where the compose file lives).

---

## Architecture

```
Client machines (Linux / Windows)
        |
        |  HTTP (MLFLOW_TRACKING_URI)
        v
+-----------------------+
|   MLflow Server       |  <-- exposed on port 5000
|  (container)          |
+-----------------------+
        |
        |  internal network
        v
+-----------------------+
| Postgres (optional)   |  <-- NOT exposed by default
|  (container)          |
+-----------------------+

Artifacts & DB files
stored on host via bind mount
```

---

## Storage

All persistent data is stored on the host via a bind mount:

- Default: `${HOME}/.local/share/mlflow-server` (or `$XDG_DATA_HOME/mlflow-server` when set)
- Override: set `MLFLOW_DATA_DIR`

You’ll find:
- `mlflow.db` (SQLite backend, default)
- `artifacts/` (artifact store)
- `pgdata/` (Postgres data dir, if enabled)

---

## SQLite vs Postgres

### SQLite (default)
Use this for local/single-node setups:

```bash
docker compose up -d --build
```

### Postgres (optional)
Enable the Postgres profile:

```bash
docker compose --profile pg up -d --build
```

> Note: Postgres is recommended when you have concurrent writers, shared usage, or want DB-grade ops (backups, tuning, migrations).

---

## Garbage collection (GC)

This stack runs GC in a dedicated sidecar container (`mlflow-gc`):

- **Scheduled GC**: runs every `MLFLOW_GC_INTERVAL_SECONDS` (default: `86400`, once/day)
- **On-demand GC**: run immediately with:
  ```bash
  docker exec -t mlflow-gc once
  ```

> Note: GC is split into a separate container to keep the server process simple and to allow independent restarts/behavior without mixing multiple long-lived processes in one container.

---

## Single-instance disclaimer (intentional)

The GC container name is pinned to `mlflow-gc` so you can always run:

```bash
docker exec -t mlflow-gc once
```

> Note: Pinning a container name means you can’t run a second copy of the stack on the same host without changing/removing that name. This repo optimizes for the “one MLflow instance per host” workflow.

---

## Common operations

### Start / stop
```bash
docker compose up -d --build
docker compose down
```

### Logs
```bash
docker compose logs -f --tail=200
```

### Update
```bash
docker compose pull
docker compose up -d --build
```