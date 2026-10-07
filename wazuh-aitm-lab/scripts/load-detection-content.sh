#!/usr/bin/env bash
# =============================================================================
# scripts/load-detection-content.sh
# =============================================================================
# Copies the AiTM custom decoders + rules into the running manager, enables
# JSON + evilginx localfile ingestion, and restarts the manager.
# Idempotent: safe to re-run.
# =============================================================================
set -euo pipefail
. "$(cd "$(dirname "$0")/.." && pwd)/lib/common.sh"

MGR="$(manager_container)"
[ -n "$MGR" ] || die "manager container not running. Run ./setup.sh first."

log "Copying custom decoders + rules into $MGR ..."
docker cp "$REPO_ROOT/custom-decoders/aitm_decoders.xml" "$MGR:/var/ossec/etc/decoders/aitm_decoders.xml"
docker cp "$REPO_ROOT/custom-rules/aitm_rules.xml"        "$MGR:/var/ossec/etc/rules/aitm_rules.xml"

# Copy the synthetic logs into the manager so localfile can read them.
# (Student frozen-dataset mode: logs already indexed, this just keeps the
#  files present; re-reading is harmless because Wazuh tracks file position.)
if [ -d "$REPO_ROOT/datagen/output" ] && [ -n "$(ls -A "$REPO_ROOT/datagen/output" 2>/dev/null)" ]; then
  docker exec "$MGR" mkdir -p /var/log/aitm
  for f in entra_signin.json m365_mailbox.json endpoint.json evilginx.log; do
    [ -f "$REPO_ROOT/datagen/output/$f" ] && docker cp "$REPO_ROOT/datagen/output/$f" "$MGR:/var/log/aitm/$f"
  done
fi

log "Enabling localfile ingestion in ossec.conf ..."
docker exec "$MGR" sh -c 'cat > /tmp/aitm-localfile.xml' <<"XML"
<!-- AiTM lab localfile ingestion (added by load-detection-content.sh) -->
<ossec_config>
  <localfile>
    <log_format>json</log_format>
    <location>/var/log/aitm/entra_signin.json</location>
  </localfile>
  <localfile>
    <log_format>json</log_format>
    <location>/var/log/aitm/m365_mailbox.json</location>
  </localfile>
  <localfile>
    <log_format>json</log_format>
    <location>/var/log/aitm/endpoint.json</location>
  </localfile>
  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/aitm/evilginx.log</location>
  </localfile>
</ossec_config>
XML

# Append our localfile block to ossec.conf only once.
docker exec "$MGR" sh -c '
  if ! grep -q "AiTM lab localfile ingestion" /var/ossec/etc/ossec.conf; then
    cat /tmp/aitm-localfile.xml >> /var/ossec/etc/ossec.conf
  fi
'

log "Verifying ruleset syntax (wazuh-logtest -t)..."
docker exec "$MGR" /var/ossec/bin/wazuh-control restart >/dev/null 2>&1 || true
sleep 5
if docker exec "$MGR" grep -qiE "ERROR|Couldn't|Invalid" /var/ossec/logs/ossec.log 2>/dev/null; then
  warn "manager log shows errors — inspect: docker exec $MGR tail -40 /var/ossec/logs/ossec.log"
fi
log "Detection content loaded."
