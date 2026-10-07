#!/usr/bin/env bash
# =============================================================================
# setup.sh  (macOS / Linux — including Apple Silicon)
# =============================================================================
# One command to stand up the Wazuh AiTM lab:
#   1. Set vm.max_map_count=262144 (Linux; auto on Docker Desktop VM).
#   2. Fetch the PINNED wazuh-docker single-node files (tag from config.env).
#   3. Generate TLS certs.
#   4. Start the single-node stack (indexer + manager + dashboard).
#   5. Load the AiTM detection content (custom rules + decoders).
#   6. Restore the FROZEN AiTM dataset (if available) OR leave clean for the
#      instructor to run datagen/ingest.
#   7. Wait for the dashboard.
#
# Student quick-start: ./setup.sh   then open https://localhost
# =============================================================================
set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

need_docker

# -- 1. kernel param ----------------------------------------------------------
log "Checking vm.max_map_count (needs >= 262144 for the indexer)..."
if [ "$(uname -s)" = "Linux" ]; then
  cur="$(sysctl -n vm.max_map_count 2>/dev/null || echo 0)"
  if [ "$cur" -lt 262144 ]; then
    if sysctl -w vm.max_map_count=262144 >/dev/null 2>&1; then
      log "  set vm.max_map_count=262144 (run as root to persist in /etc/sysctl.conf)."
    else
      warn "  could not set vm.max_map_count. Run: sudo sysctl -w vm.max_map_count=262144"
    fi
  fi
else
  log "  macOS: handled inside the Docker Desktop VM — nothing to do."
fi

# -- 2. fetch pinned wazuh-docker --------------------------------------------
if [ ! -d "$REPO_ROOT/wazuh-docker/.git" ]; then
  log "Cloning wazuh-docker at pinned tag ${WAZUH_TAG} ..."
  git clone --depth 1 --branch "$WAZUH_TAG" https://github.com/wazuh/wazuh-docker.git "$REPO_ROOT/wazuh-docker" \
    || die "git clone failed. Check network / that tag ${WAZUH_TAG} exists."
else
  log "wazuh-docker already present (pinned ${WAZUH_TAG}) — reusing."
fi
[ -d "$WAZUH_DOCKER_DIR" ] || die "single-node dir missing in wazuh-docker — tag layout changed?"

# Pin the images to our tag (the repo files sometimes track the branch tip).
if [ -f "$WAZUH_DOCKER_DIR/docker-compose.yml" ]; then
  sed -i.bak -E "s|(wazuh/wazuh-(manager|indexer|dashboard)):[^[:space:]]+|\1:${WAZUH_TAG_BARE}|g" \
    "$WAZUH_DOCKER_DIR/docker-compose.yml" || true
fi

# Apply the shared dashboard/indexer password from config.env.
if [ "${DASHBOARD_PASSWORD}" != "SecretPassword" ]; then
  grep -rl 'SecretPassword' "$WAZUH_DOCKER_DIR" 2>/dev/null | while read -r f; do
    sed -i.bak "s/SecretPassword/${DASHBOARD_PASSWORD}/g" "$f"
  done
fi

# -- 3. certs -----------------------------------------------------------------
if [ ! -f "$WAZUH_DOCKER_DIR/config/wazuh_indexer_ssl_certs/root-ca.pem" ]; then
  log "Generating TLS certificates..."
  compose -f generate-indexer-certs.yml run --rm generator \
    || die "cert generation failed."
fi

# -- 4/6. restore frozen dataset BEFORE first indexer start (if present) ------
"$REPO_ROOT/scripts/restore-dataset.sh" || warn "dataset restore skipped/failed — starting clean."

# -- 4. start stack -----------------------------------------------------------
log "Starting the Wazuh single-node stack..."
compose up -d || die "docker compose up failed."

# -- 5. load AiTM detection content ------------------------------------------
"$REPO_ROOT/scripts/load-detection-content.sh" || warn "could not load detection content yet; re-run scripts/load-detection-content.sh"

# -- 7. wait ------------------------------------------------------------------
wait_for_dashboard || true

cat <<EOF

--------------------------------------------------------------------------
  Wazuh AiTM lab is up.
  Open:   https://localhost   (accept the self-signed cert warning)
  Login:  ${DASHBOARD_USER} / ${DASHBOARD_PASSWORD}

  IMPORTANT — set the dashboard time range to the dataset's dates, or the
  dashboard looks EMPTY. The AiTM incident is dated around 2025-04-14
  (benign baseline spans 2025-04-01 .. 2025-04-14). If you re-ingested on a
  fresh stack, also widen the range to "today".

  Reset the lab:   ./reset.sh
--------------------------------------------------------------------------
EOF
