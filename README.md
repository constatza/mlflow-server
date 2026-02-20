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

```
${MLFLOW_DATA_DIR:-${HOME}/mlflow-data}
```

Contents:

- `mlflow.db` — SQLite backend (default)
- `artifacts/` — models, plots, checkpoints
- `pgdata/` — PostgreSQL data directory (if enabled)

### Why `$HOME`
- writable by normal users
- portable across machines
- works on Linux and Windows
- avoids `/var/lib` permission issues

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

## What is a Compose profile?

A **profile** is an opt-in group of services.

In this repo:
- default → only `mlflow` runs (SQLite)
- `pg` profile → `mlflow + postgres` run

This avoids maintaining multiple compose files.

---

## Security model (important)

### PostgreSQL credentials
Postgres credentials are:

- used **only between containers**
- irrelevant for security **unless Postgres is exposed**
- internal plumbing, not user-facing secrets

By default:
- PostgreSQL has **no published ports**
- it is unreachable from LAN/WAN
- only MLflow can connect

> The real security boundary is **network isolation**, not the password.

If you expose Postgres (`ports: 5432:5432`):
- credentials become real security credentials
- TLS, strong passwords, and access control matter

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
- **must NOT be committed**

Add to `.gitignore`:
```
.env
```

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

