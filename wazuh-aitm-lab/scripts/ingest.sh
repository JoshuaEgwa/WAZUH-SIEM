#!/usr/bin/env bash
# =============================================================================
# scripts/ingest.sh  (INSTRUCTOR-ONLY)
# =============================================================================
# Feeds the synthetic logs produced by datagen/generate.sh into the running
# manager and confirms the AiTM alerts fire. Run this on a CLEAN stack (no
# frozen dataset) to build the dataset, then freeze it with backup-dataset.sh.
# =============================================================================
set -euo pipefail
. "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"

[ -f "$REPO_ROOT/datagen/output/entra_signin.json" ] || die "No generated logs. Run: bash datagen/generate.sh"

MGR="$(manager_container)"
[ -n "$MGR" ] || die "manager not running. Run ./setup.sh first."

log "Loading detection content + copying logs into the manager..."
"$REPO_ROOT/scripts/load-detection-content.sh"

log "Waiting for the manager to process the logs..."
sleep 20

HITS=$(docker exec "$MGR" sh -c 'grep -c "\"rule\":{\"level\"" /var/ossec/logs/alerts/alerts.json 2>/dev/null || grep -c "Rule:" /var/ossec/logs/alerts/alerts.log 2>/dev/null || echo 0')
log "Alerts recorded so far: ${HITS}"

log "Checking the key AiTM detections fired..."
for rid in 100102 100111 100122 100150; do
  if docker exec "$MGR" sh -c "grep -q '\"id\":\"$rid\"' /var/ossec/logs/alerts/alerts.json 2>/dev/null || grep -q 'Rule: $rid ' /var/ossec/logs/alerts/alerts.log 2>/dev/null"; then
    log "  [OK] rule $rid fired"
  else
    warn "  [MISS] rule $rid not found yet (may need a few more seconds / check field schema)"
  fi
done
log "Ingestion complete. Verify in the dashboard, note the date range, then run ./backup-dataset.sh"
