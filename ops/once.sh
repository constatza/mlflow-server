#!/usr/bin/env sh
set -eu

echo "[mlflow-gc-now] $(date -u +%Y-%m-%dT%H:%M:%SZ) running one-shot mlflow gc"
gc_exit=0
printf "y\n" | mlflow gc \
  --tracking-uri "${MLFLOW_TRACKING_URI:?}" \
  --backend-store-uri "${MLFLOW_BACKEND_URI:?}" \
  || gc_exit=$?

if [ "$gc_exit" -eq 0 ]; then
  echo "[mlflow-gc-now] SUCCESS"
else
  echo "[mlflow-gc-now] FAILED (exit code $gc_exit)" >&2
  exit "$gc_exit"
fi
