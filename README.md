# mlflow-server

A self-hosted [MLflow](https://mlflow.org/) tracking server with Docker Compose. Zero-config by default (SQLite), optional PostgreSQL backend, server-managed artifacts, and a daily GC sidecar. Runs on Linux and WSL2.

---

## Features

- **Zero configuration** — SQLite out of the box, just `make up`
- **Server-managed artifacts** — upload and download through the server; no direct storage access needed on the client
- **Persistent storage** — DB in a Docker-managed volume; artifacts bind-mounted on the host
- **Automatic restarts** — `restart: unless-stopped` keeps the server alive after reboots
- **Scheduled GC** — daily cleanup of soft-deleted runs (configurable interval)
- **On-demand GC** — `make gc` from any directory; deletes both DB entries and artifact files
- **PostgreSQL option** — swap in Postgres with a single flag
- **S3 / MinIO support** — set credentials in `.env.local` to store artifacts in object storage
- **WSL2-aware** — named volume for the DB avoids host-filesystem race conditions on startup

---

## Requirements

- [Docker](https://docs.docker.com/get-docker/) with the Compose plugin (v2)
- `make`
- Git

> **WSL2:** always run `make`/`docker compose` from inside the WSL2 terminal. Avoid `/mnt/c/…` paths for artifacts — POSIX locks are unreliable on NTFS via 9P.

---

## Quick Start

```bash
git clone https://github.com/constatza/mlflow-server.git
cd mlflow-server
make up
```

The server is ready at **http://localhost:5000** once the container shows `(healthy)`.

```python
import mlflow
mlflow.set_tracking_uri("http://localhost:5000")
```

> **Use `make up`, not bare `docker compose up`.** The Makefile creates the artifact directory as your user first — if Docker creates it, it does so as root and the files become inaccessible.

---

## Configuration

Copy the example to `.env.local` and uncomment what you need:

```bash
cp .env.example .env.local
```

`.env` holds shared project defaults (safe to commit). `.env.local` holds machine-specific overrides — loaded on top and takes precedence. **Neither file is required.**

### Key variables

| Variable | Default | Description |
|----------|---------|-------------|
| `MLFLOW_ARTIFACTS_DIR` | `$HOME/.local/share/mlflow-server/artifacts` | Host path for artifact storage |
| `MLFLOW_PORT` | `5000` | Port exposed on the host |
| `MLFLOW_BACKEND_URI` | `sqlite:////data/db/mlflow.db` | Tracking store URI |
| `MLFLOW_ARTIFACTS_DESTINATION` | `file:/data/artifacts` | Artifact root inside the server |
| `MLFLOW_RUN_UID` | invoking user via `make` | Numeric UID for the MLflow server and GC sidecar |
| `MLFLOW_RUN_GID` | invoking group via `make` | Numeric GID for the MLflow server and GC sidecar |
| `MLFLOW_ALLOWED_HOSTS` | `localhost:*,127.0.0.1:*,mlflow:*` | MLflow 3.x host header allowlist |
| `MLFLOW_CORS_ALLOWED_ORIGINS` | `http://localhost:5000,…` | CORS origins for the UI |
| `MLFLOW_GC_INTERVAL_SECONDS` | `86400` | Seconds between scheduled GC runs |

See [`.env.example`](.env.example) for the full reference.

---

## Commands

| Command | Description |
|---------|-------------|
| `make up` | Pull images, build GC image, create dirs, start all services |
| `make down` | Stop and remove containers (data is preserved) |
| `make restart` | Restart all services without re-pulling images |
| `make logs` | Follow logs for all services |
| `make gc` | Run garbage collection immediately |
| `make purge` | **Destructive:** wipe DB volume and artifact directory together |

> `make up` always re-pulls the MLflow image (`--pull always`) to keep the server and GC sidecar on the same version. Use `make restart` when you don't want the pull overhead.

Recovery commands are in the [Upgrading](#upgrading) section.

---

## Storage

| Data | Location |
|------|----------|
| `mlflow.db` | Docker named volume `mlflow-server-db` |
| Artifacts | `$MLFLOW_ARTIFACTS_DIR` on the host (bind mount) |
| Postgres data | `$POSTGRES_DATA_DIR` on the host (Postgres profile only) |

> **Warning:** `docker compose down -v` and `docker system prune -v` destroy the DB volume. The Makefile `down` target intentionally omits `-v`.

The MLflow server and GC sidecar run as the host user's numeric UID/GID when
started through `make`. A short `mlflow-init` container runs as root first to
create the mounted data directories and hand ownership of the DB volume to
that UID/GID. It does not chown the artifacts directory — that's a host bind
mount, so a fresh directory is already owned by you. If you have artifacts
left over from before this change (written as root) or set `MLFLOW_RUN_UID`/
`MLFLOW_RUN_GID` to something other than your own user, fix ownership once
yourself: `chown -R "$(id -u):$(id -g)" "$MLFLOW_ARTIFACTS_DIR"`.

### Artifact path

Artifacts default to `$HOME/.local/share/mlflow-server/artifacts`. Override in `.env.local`:

```bash
# Custom local path
MLFLOW_ARTIFACTS_DIR=/data/mlflow-server/artifacts

# S3
MLFLOW_ARTIFACTS_DESTINATION=s3://my-bucket/mlflow-artifacts
AWS_ACCESS_KEY_ID=…
AWS_SECRET_ACCESS_KEY=…
AWS_DEFAULT_REGION=us-east-1

# S3-compatible (MinIO, etc.)
MLFLOW_S3_ENDPOINT_URL=https://minio.example.internal
```

---

## Backends

### SQLite (default)

Zero config, good for local and single-user setups.

### PostgreSQL

```bash
# .env.local
MLFLOW_BACKEND_URI=postgresql://mlflow:mlflow@postgres:5432/mlflow
POSTGRES_PASSWORD=change-me
```

```bash
docker compose --profile pg up -d --build --pull always
```

Postgres is not exposed on the host by default.

---

## Garbage Collection

A dedicated sidecar container (`mlflow-gc`) runs GC independently of the main server. GC permanently deletes runs that have been soft-deleted via the UI or API — including their artifact files on disk.

- Runs automatically every `MLFLOW_GC_INTERVAL_SECONDS` (default: 24 h)
- Trigger immediately from any directory:

```bash
make gc
# or:
docker exec -t mlflow-gc once
```

> The GC container name is pinned to `mlflow-gc` so `docker exec` works from any directory. This means only one instance of the stack can run per host.

---

## Upgrading

`make up` pulls the latest MLflow image on every run. After a major version bump the DB schema may need migration:

```bash
make db-upgrade
```

If that fails with `Can't locate revision` the schema is too old to migrate. You have two options:

```bash
# Keep artifact files on disk (they become orphaned — mlflow gc cannot clean them):
make reset-db
make up

# Clean slate — wipes DB and all artifact files:
make purge
make up
```

> `mlflow gc` only deletes runs that were soft-deleted through the UI or API. It does not scan the filesystem for orphaned directories left behind by `reset-db`. Use `make purge` when you want a fully clean restart.

### Import an existing mlflow.db

```bash
docker compose down
docker volume create mlflow-server-db
docker run --rm \
  -v /path/to/old/data:/src \
  -v mlflow-server-db:/dst \
  alpine cp /src/mlflow.db /dst/mlflow.db
make up
```

---

## Network / Security

MLflow 3.x validates host headers and CORS origins. Defaults are localhost-only. To open access on your LAN, set both in `.env.local`:

```bash
MLFLOW_ALLOWED_HOSTS=localhost:*,127.0.0.1:*,mlflow:*,192.168.1.10:*
MLFLOW_CORS_ALLOWED_ORIGINS=http://localhost:5000,http://192.168.1.10:5000
```

See [`.env.example`](.env.example) for more examples including hostname-based access.
