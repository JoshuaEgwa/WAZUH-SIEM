#!/usr/bin/env bash
# =============================================================================
# lib/common.sh — shared helpers for the AiTM lab bash scripts
# =============================================================================
set -euo pipefail

# Resolve repo root regardless of where the script is called from.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WAZUH_DOCKER_DIR="$REPO_ROOT/wazuh-docker/single-node"

# Load config.env
if [ -f "$REPO_ROOT/config.env" ]; then
  set -a; # shellcheck disable=SC1091
  . "$REPO_ROOT/config.env"; set +a
else
  echo "FATAL: config.env not found in $REPO_ROOT" >&2; exit 1
fi

# Bare tag (strip leading v) used by docker image tags: v4.14.8 -> 4.14.8
export WAZUH_TAG_BARE="${WAZUH_TAG#v}"

log()  { printf '\033[1;36m[aitm]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[aitm][warn]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[aitm][fatal]\033[0m %s\n' "$*" >&2; exit 1; }

# Pick the right compose invocation (plugin v2 preferred, legacy fallback).
compose() {
  if docker compose version >/dev/null 2>&1; then
    ( cd "$WAZUH_DOCKER_DIR" && docker compose "$@" )
  elif command -v docker-compose >/dev/null 2>&1; then
    ( cd "$WAZUH_DOCKER_DIR" && docker-compose "$@" )
  else
    die "docker compose not found. Install Docker Desktop (Mac/Win) or the compose plugin (Linux)."
  fi
}

need_docker() {
  command -v docker >/dev/null 2>&1 || die "Docker not found. Install Docker Desktop and start it."
  docker info >/dev/null 2>&1 || die "Docker daemon not reachable. Start Docker Desktop and retry."
}

manager_container() {
  docker ps --format '{{.Names}}' | grep -m1 'wazuh.manager' || true
}

wait_for_dashboard() {
  log "Waiting for the Wazuh dashboard at https://localhost (can take 2-4 min on first run)..."
  local tries=0
  until curl -sk -o /dev/null -w '%{http_code}' https://localhost 2>/dev/null | grep -qE '200|302'; do
    tries=$((tries+1)); [ $((tries % 6)) -eq 0 ] && log "  ...still starting (${tries}0s)"
    [ "$tries" -ge 60 ] && { warn "Dashboard not up after ~10 min. Check: cd wazuh-docker/single-node && docker compose logs wazuh.dashboard"; return 1; }
    sleep 10
  done
  log "Dashboard is UP -> https://localhost  (user: ${DASHBOARD_USER} / pass: ${DASHBOARD_PASSWORD})"
}
