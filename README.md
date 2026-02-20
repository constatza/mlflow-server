# Minimal MLflow Tracking Server (Docker Compose)

This repository provides a **minimal, portable MLflow tracking server** that:

- defaults to **SQLite** (zero configuration)
- optionally supports **PostgreSQL** (more robust backend)
- works on **Linux and Windows (Docker Desktop)**
- runs as a **long-lived service** (auto-restarts after reboot)
- stores all data under **$HOME by default**
- keeps PostgreSQL **private by default** (no LAN/WAN exposure)

---

## Architecture Overview

```
Client machines (Linux / Windows)
        |
        |  HTTP (MLFLOW_TRACKING_URI)
        v
+-----------------------+
|   MLflow Server       |  <-- exposed on port 5000
|  (Docker container)   |
+-----------------------+
        |
        |  internal Docker network
        v
+-----------------------+
| PostgreSQL (optional) |  <-- NOT exposed by default
|  (Docker container)  |
+-----------------------+

Artifacts & DB files
stored on host via bind mount
```

### Key design principle
**Clients talk only to MLflow.**  
They never talk directly to PostgreSQL or the filesystem.

---

## Service behavior

This setup behaves like a system service:

- starts with `docker compose up -d`
- restarts on crashes
- restarts automatically after machine reboot
- stops only if you explicitly stop it

This is achieved via:

```yaml
restart: unless-stopped
```

Docker itself must be configured to start on boot  
(Linux default; Windows via Docker Desktop).

---

## Storage model

All persistent data lives on the host via a bind mount:

```bash
${MLFLOW_DATA_DIR: $XDG_DATA_HOME}
```

Contents:

- `mlflow.db` — SQLite backend (default)
- `artifacts/` — models, plots, checkpoints
- `pgdata/` — PostgreSQL data directory (if enabled)

s

---

## SQLite vs PostgreSQL

### SQLite (default)
- single-user friendly
- zero configuration
- often *faster* for local, low-concurrency usage
- stored as a single file

Start:
```bash
docker compose up -d
```

### PostgreSQL (optional)
- more robust
- better for concurrency
- avoids SQLite locking issues on network filesystems

Start:
```bash
docker compose --profile pg up -d
```

---

## Configuration files

### `docker-compose.yml`
- committed
- defines the application

### `.env.example`
- committed
- documents configuration options
- contains **placeholders only**

### `.env`
- per-machine
- contains real values
- **must remain private for security**

---

## Typical workflows

### Single machine, minimal
```bash
docker compose up -d
```

### PostgreSQL backend
```bash
cp .env.example .env
# edit .env
docker compose --profile pg up -d
```

### Check status
```bash
docker compose ps
```

### Logs
```bash
docker compose logs -f
```

