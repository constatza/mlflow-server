#!/usr/bin/env sh
set -eu

interval="${MLFLOW_GC_INTERVAL_SECONDS:-86400}"
case "$interval" in
  (""|*[!0-9]*)
    echo "[mlflow-gc] WARNING: invalid MLFLOW_GC_INTERVAL_SECONDS='$interval'; using 86400" >&2
    interval=86400
    ;;
esac

trap 'echo "[mlflow-gc] shutting down"; exit 0' TERM INT

while true; do
  echo "[mlflow-gc] $(date -u +%Y-%m-%dT%H:%M:%SZ) running mlflow gc"
  gc_exit=0
  printf "y\n" | mlflow gc \
    --tracking-uri "${MLFLOW_TRACKING_URI:?}" \
    --backend-store-uri "${MLFLOW_BACKEND_URI:?}" \
    || gc_exit=$?
  if [ "$gc_exit" -ne 0 ]; then
    echo "[mlflow-gc] WARNING: mlflow gc exited with code $gc_exit" >&2
  fi

  echo "[mlflow-gc] sleeping ${interval}s"
  sleep "$interval" &
  wait $! || true
done
