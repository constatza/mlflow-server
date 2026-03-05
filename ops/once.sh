#!/usr/bin/env sh
set -eu

echo "[mlflow-gc-now] running one-shot mlflow gc"
printf "y\n" | mlflow gc \
  --tracking-uri "${MLFLOW_TRACKING_URI:?}" \
  --backend-store-uri "${MLFLOW_BACKEND_URI:?}"