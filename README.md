# Minimal [MLflow](https://mlflow.org/) Tracking Server (Docker Compose)

A minimal, portable MLflow tracking server that:

- defaults to **SQLite** (zero configuration)
- optionally supports **PostgreSQL** (more robust backend)
- works on **Linux, WSL2, and Windows**
- runs as a **long-lived service** (auto-restarts after reboot)
- stores **artifacts on the host**; keeps the **DB in a Docker-managed volume**
- lets the **server manage artifact uploads/downloads** for new experiments
- keeps PostgreSQL **private by default** (no LAN/WAN exposure)
- runs **scheduled MLflow GC** and supports **on-demand GC** from anywhere

---

## Quick start

### 1) Install prerequisites
- Install [Docker](https://docs.docker.com/get-docker/)
- Install Git
- Install `make` (usually pre-installed on Linux/macOS; on Windows use WSL2)

### 2) Clone the repository
```bash
git clone https://github.com/constatza/mlflow-server.git
cd mlflow-server
```

### 3) Optional configuration
If you want to change ports, allowed hosts, artifact path, or DB backend:

```bash
cp .env.example .env
# edit .env
```

> Note: `.env` is intentionally not committed. Treat it as machine-local configuration
> (and secrets, if you enable Postgres auth).

### 4) Start
```bash
make up
```

This creates the artifacts directory on the host (if needed) and starts all services.

> **Always use `make up` for the first start**, not `docker compose up` directly. If Docker
> creates the artifacts directory itself it does so as root, making the files on the host
> unreadable/unwritable without `sudo`. `make init` (called automatically by `make up`)
> creates the directory as the current user before Docker starts.

> Note: `--build` is always included because this repo adds two small GC helper commands
> (`loop` and `once`) into a custom image.

### 5) Check status
```bash
docker compose ps
```

MLflow will show `(healthy)` once it is ready.

### 6) Run GC now (from anywhere)
```bash
make gc
# or directly:
docker exec -t mlflow-gc once
```

> Note: `docker exec` is used so you don't need to be in the repo directory.

---

## Makefile targets

| Target | Description |
|--------|-------------|
| `make init` | Create host directories (artifacts). Run once before first start. |
| `make up` | Build images and start all services (runs `init` first). |
| `make down` | Stop and remove containers (data is preserved). |
| `make logs` | Follow logs for all services. |
| `make restart` | Restart all services without rebuilding. |
| `make gc` | Run garbage collection immediately. |
| `make reset-db` | Stop the stack and delete the database volume (artifacts kept). |

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
```

---

## Storage

Data is split across two locations for reliability:

| What | Where | Why |
|------|-------|-----|
| `mlflow.db` | Docker named volume (`mlflow-server-db`) | Always available on Docker startup — no dependency on WSL2 or host filesystem initialization. Eliminates data loss after Windows reboots. |
| `artifacts/` | Host bind mount | You own it. Back it up, inspect it, move it. |
| `pgdata/` | Host bind mount (Postgres profile only) | Same reasoning as artifacts. |

### Artifacts path

If `MLFLOW_ARTIFACTS_DIR` is unset, artifacts default to
`$HOME/.local/share/mlflow-server/artifacts`. This works on Linux, WSL2, and Windows
(Docker Desktop resolves `$HOME` to `C:\Users\YourName` on Windows).

The default path uses Linux conventions (`.local/share`) so on Windows you may prefer to
set an explicit path:

```bash
# Linux / WSL2
MLFLOW_ARTIFACTS_DIR=${HOME}/mlflow-artifacts

# Windows (Docker Desktop — forward slashes, no quotes)
MLFLOW_ARTIFACTS_DIR=C:/Users/YourName/mlflow-artifacts
```

> **WSL2 note:** always run `make up` / `docker compose` from inside the WSL2 terminal,
> not from Windows PowerShell/CMD. Running from Windows can cause bind mounts to resolve
> to the wrong location. Also avoid `/mnt/c/...` or `/mnt/d/...` paths for artifacts —
> POSIX file locks are unreliable on NTFS via WSL2's 9P filesystem layer.

### Migrating an existing mlflow.db into the named volume

If you have an existing `mlflow.db` from a previous bind-mount setup:

```bash
docker compose down
docker volume create mlflow-server-db
docker run --rm \
  -v /path/to/old/data:/src \
  -v mlflow-server-db:/dst \
  alpine cp /src/mlflow.db /dst/mlflow.db
make up
```

### Custom artifact storage

- Local (default): `MLFLOW_ARTIFACTS_DESTINATION=file:/data/artifacts`
- Another mounted path: `MLFLOW_ARTIFACTS_DESTINATION=file:/data/external-artifacts`
- S3: `MLFLOW_ARTIFACTS_DESTINATION=s3://my-bucket/mlflow-artifacts`

For S3, provide AWS credentials in `.env`:

```bash
MLFLOW_ARTIFACTS_DESTINATION=s3://my-bucket/mlflow-artifacts
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
AWS_DEFAULT_REGION=us-east-1
```

For S3-compatible endpoints (MinIO, etc.):

```bash
MLFLOW_S3_ENDPOINT_URL=https://minio.example.internal
```

For new proxied experiments, clients only need `MLFLOW_TRACKING_URI` — they do not need
direct access to the artifact filesystem or S3 bucket.

> **Note:** MLflow stores the artifact root on each experiment at creation time. Existing
> experiments keep their original artifact root (legacy). Create new experiments to get
> fully server-managed artifact handling and GC support.

---

## SQLite vs Postgres

### SQLite (default)
Zero configuration. Good for local/single-node setups.

```bash
make up
```

### Postgres (optional)
Recommended for concurrent writers, shared usage, or production-grade reliability.

```bash
docker compose --profile pg up -d --build
```

Set the backend URI in `.env`:

```bash
MLFLOW_BACKEND_URI=postgresql://mlflow:mlflow@postgres:5432/mlflow
```

---

## Garbage collection (GC)

A dedicated sidecar container (`mlflow-gc`) handles cleanup:

- **Scheduled GC**: runs every `MLFLOW_GC_INTERVAL_SECONDS` (default: `86400`, once/day)
- **On-demand GC**: `make gc` or `docker exec -t mlflow-gc once`

GC only permanently deletes runs that have already been soft-deleted via the MLflow UI or API.
Active runs and experiments are never touched.

> GC runs as a separate container to keep the server process simple and allow independent
> lifecycle management.

---

## Single-instance disclaimer (intentional)

The GC container name is pinned to `mlflow-gc` so you can always run:

```bash
docker exec -t mlflow-gc once
```

from any directory without knowing where the compose file lives.

> Pinning a container name means you can't run a second copy of the stack on the same host
> without changing or removing that name. This repo is designed for the
> "one MLflow instance per host" workflow.

---

## Common operations

### Start / stop
```bash
make up
make down
```

### Logs
```bash
make logs
```

### Update
```bash
docker compose pull
make up
```

### Reset the database (delete mlflow.db, keep artifacts)
```bash
make reset-db
# Next `make up` starts fresh with an empty database
```

> The database lives in the Docker named volume `mlflow-server-db`.
> Artifacts on the host are untouched by this operation.
