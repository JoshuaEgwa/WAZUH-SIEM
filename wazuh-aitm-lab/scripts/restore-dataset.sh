#!/usr/bin/env bash
# =============================================================================
# scripts/restore-dataset.sh
# =============================================================================
# Restores the FROZEN AiTM dataset into the indexer volume + certs, so students
# see the pre-built incident without running any attack or datagen.
#
# Looks for data/indexer-data.tgz and data/certs.tgz. If missing and
# DATASET_URL is set in config.env, downloads them first.
#
# Must run BEFORE the indexer container starts for the first time (setup.sh
# calls it at the right point). Exits 0 (no-op) if no dataset is available —
# that's the instructor "fresh/clean" path.
# =============================================================================
set -euo pipefail
. "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"

DATA_DIR="$REPO_ROOT/data"
IDX_TGZ="$DATA_DIR/indexer-data.tgz"
CERTS_TGZ="$DATA_DIR/certs.tgz"
mkdir -p "$DATA_DIR"

# Download if needed.
if [ ! -f "$IDX_TGZ" ] && [ -n "${DATASET_URL:-}" ]; then
  log "Downloading frozen dataset from ${DATASET_URL} ..."
  curl -fL "${DATASET_URL%/}/indexer-data.tgz" -o "$IDX_TGZ" || { warn "could not download indexer-data.tgz"; rm -f "$IDX_TGZ"; }
  curl -fL "${DATASET_URL%/}/certs.tgz"        -o "$CERTS_TGZ" || warn "could not download certs.tgz (will generate fresh certs)"
fi

if [ ! -f "$IDX_TGZ" ]; then
  log "No frozen dataset found (data/indexer-data.tgz). Clean/instructor mode — run datagen/ then scripts/ingest.sh."
  exit 0
fi

# Restore certs (so the frozen indexer's node certs match).
if [ -f "$CERTS_TGZ" ]; then
  log "Restoring frozen certs..."
  rm -rf "$WAZUH_DOCKER_DIR/config/wazuh_indexer_ssl_certs"
  tar xzf "$CERTS_TGZ" -C "$WAZUH_DOCKER_DIR/config/"
fi

# Restore indexer data into the named volume via a throwaway helper container.
VOL="${COMPOSE_PROJECT_NAME}_wazuh-indexer-data"
log "Restoring frozen indexer data into volume ${VOL} ..."
docker volume create "$VOL" >/dev/null
docker run --rm -v "$VOL":/data -v "$DATA_DIR":/backup:ro alpine \
  sh -c "rm -rf /data/* && tar xzf /backup/indexer-data.tgz -C /data && echo restored"
log "Frozen dataset restored. The incident is dated ~2025-04-14 — set the dashboard time range accordingly."
