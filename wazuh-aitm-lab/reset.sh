#!/usr/bin/env bash
# =============================================================================
# reset.sh  (macOS / Linux)
# =============================================================================
# Wipes all lab volumes and reloads the original frozen AiTM dataset, giving a
# fresh start. (Keeps the cloned wazuh-docker + generated certs.)
# =============================================================================
set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

need_docker
warn "This will DELETE all lab data volumes and reload the original AiTM dataset."
printf "Continue? [y/N] "; read -r ans
case "$ans" in y|Y) ;; *) log "Aborted."; exit 0;; esac

log "Stopping stack and removing volumes..."
compose down -v || true

log "Re-restoring the frozen dataset..."
"$REPO_ROOT/scripts/restore-dataset.sh" || warn "restore skipped (no frozen dataset present)."

log "Starting stack again..."
compose up -d
"$REPO_ROOT/scripts/load-detection-content.sh" || true
wait_for_dashboard || true
log "Reset complete. Open https://localhost and set the time range to the dataset dates (~2025-04-14)."
