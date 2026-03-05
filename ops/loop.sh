#!/usr/bin/env sh
set -eu

interval="${MLFLOW_GC_INTERVAL_SECONDS:-86400}"
case "$interval" in (""|*[!0-9]*) interval=86400;; esac

while true; do
  echo "[mlflow-gc] running mlflow gc"
  printf "y\n" | mlflow gc \
    --tracking-uri "${MLFLOW_TRACKING_URI:?}" \
    --backend-store-uri "${MLFLOW_BACKEND_URI:?}" \
    || true

  echo "[mlflow-gc] sleeping ${interval} seconds"
  sleep "$interval"
done