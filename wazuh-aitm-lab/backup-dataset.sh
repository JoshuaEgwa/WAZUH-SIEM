#!/usr/bin/env bash
# =============================================================================
# backup-dataset.sh  (INSTRUCTOR-ONLY)
# =============================================================================
# Freezes the finished AiTM dataset so students can restore it:
#   - data/indexer-data.tgz : the whole indexer data volume (indexed alerts)
#   - data/certs.tgz        : the TLS certs that match that indexer node
#
# Run AFTER you have verified the AiTM incident in the dashboard. Then host
# the two .tgz files (GitHub Release / school drive / Git LFS — they exceed
# GitHub's 100 MB limit) and put the base URL in config.env:DATASET_URL.
# =============================================================================
set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

DATA_DIR="$REPO_ROOT/data"
mkdir -p "$DATA_DIR"

VOL="${COMPOSE_PROJECT_NAME}_wazuh-indexer-data"
docker volume inspect "$VOL" >/dev/null 2>&1 || die "indexer volume $VOL not found — is the stack up?"

log "Flushing the indexer so all alerts are on disk..."
curl -sk -u "${DASHBOARD_USER}:${DASHBOARD_PASSWORD}" -X POST "https://localhost:9200/_flush" >/dev/null 2>&1 || true

log "Freezing indexer data volume -> data/indexer-data.tgz ..."
docker run --rm -v "$VOL":/data:ro -v "$DATA_DIR":/backup alpine \
  sh -c "tar czf /backup/indexer-data.tgz -C /data ."

log "Freezing certs -> data/certs.tgz ..."
tar czf "$DATA_DIR/certs.tgz" -C "$WAZUH_DOCKER_DIR/config" wazuh_indexer_ssl_certs

SZ_IDX=$(du -h "$DATA_DIR/indexer-data.tgz" | cut -f1)
SZ_CRT=$(du -h "$DATA_DIR/certs.tgz" | cut -f1)
cat <<EOF

--------------------------------------------------------------------------
  Frozen dataset created:
    data/indexer-data.tgz   (${SZ_IDX})
    data/certs.tgz          (${SZ_CRT})

  Next:
    1. Upload BOTH files to a GitHub Release / school drive / Git LFS.
    2. Set DATASET_URL in config.env to the base URL that serves them, e.g.
         DATASET_URL=https://github.com/you/wazuh-aitm-lab/releases/download/dataset-2025t1
       (setup.sh will fetch \${DATASET_URL}/indexer-data.tgz and /certs.tgz)
    3. Commit config.env. Students just run ./setup.sh.
--------------------------------------------------------------------------
EOF
