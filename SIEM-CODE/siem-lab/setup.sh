#!/usr/bin/env bash
# Mac/Linux: builds the Wazuh lab and loads the frozen dataset. Safe to re-run.
set -euo pipefail
cd "$(dirname "$0")"
source ./config.env

PROJECT=siemlab
COMPOSE_DIR="wazuh-docker/single-node"
VOL="${PROJECT}_wazuh-indexer-data"
say() { printf '\n==> %s\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

say "Checking requirements"
command -v git >/dev/null    || die "git is not installed."
command -v docker >/dev/null || die "Docker is not installed."
docker info >/dev/null 2>&1  || die "Docker is not running. Start Docker Desktop and retry."
docker compose version >/dev/null 2>&1 || die "Docker Compose v2 not found. Update Docker."
mem=$(docker info --format '{{.MemTotal}}')
[ "$mem" -ge 6000000000 ] || echo "WARNING: Docker has less than 6 GB RAM. Raise it in Docker Desktop > Settings > Resources."

if [ "$(uname -s)" = "Linux" ]; then
  say "Setting kernel parameter for the indexer"
  if [ "$(sysctl -n vm.max_map_count)" -lt 262144 ]; then
    sudo sysctl -w vm.max_map_count=262144
    echo "vm.max_map_count=262144" | sudo tee /etc/sysctl.d/99-wazuh.conf >/dev/null
  fi
fi

say "Getting Wazuh Docker files ($WAZUH_TAG)"
[ -d wazuh-docker ] || git clone --depth 1 --branch "$WAZUH_TAG" https://github.com/wazuh/wazuh-docker.git

say "Getting the lab dataset"
mkdir -p data
if [ -n "${DATASET_URL:-}" ]; then
  for f in indexer-data.tgz certs.tgz; do
    [ -f "data/$f" ] || curl -fL -o "data/$f" "$DATASET_URL/$f" || { rm -f "data/$f"; die "Could not download $f"; }
  done
fi

say "Preparing certificates"
if [ ! -f wazuh-docker/.certs-ready ]; then
  if [ -f data/certs.tgz ]; then
    docker run --rm -v "$PWD":/work alpine sh -c "tar xzf /work/data/certs.tgz -C /work/$COMPOSE_DIR/config"
  else
    (cd "$COMPOSE_DIR" && docker compose -f generate-indexer-certs.yml run --rm generator)
  fi
  touch wazuh-docker/.certs-ready
fi

if [ -f data/indexer-data.tgz ] && ! docker volume inspect "$VOL" >/dev/null 2>&1; then
  say "Loading dataset"
  docker volume create "$VOL" >/dev/null
  docker run --rm -v "$VOL":/data -v "$PWD/data":/backup alpine sh -c "cd /data && tar xzf /backup/indexer-data.tgz"
fi

say "Starting Wazuh (first start takes a few minutes)"
(cd "$COMPOSE_DIR" && docker compose -p "$PROJECT" up -d)

printf 'Waiting for the dashboard'
for i in $(seq 1 90); do
  code=$(curl -k -s -o /dev/null -w '%{http_code}' https://localhost || true)
  case "$code" in 200|302) break;; esac
  printf '.'; sleep 5
done
printf '\n\nReady. Open https://localhost (accept the browser certificate warning).\n'
echo "Login: admin / SecretPassword  (change this if you edit it in the lab)"
