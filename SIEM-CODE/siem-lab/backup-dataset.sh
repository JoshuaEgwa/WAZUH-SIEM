#!/usr/bin/env bash
# INSTRUCTOR ONLY: run after you have generated the attack data in your own lab.
# Produces data/indexer-data.tgz and data/certs.tgz for students.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data
(cd wazuh-docker/single-node && docker compose -p siemlab stop)
docker run --rm -v siemlab_wazuh-indexer-data:/data -v "$PWD/data":/backup alpine \
  sh -c "tar czf /backup/indexer-data.tgz -C /data ."
docker run --rm -v "$PWD":/work alpine \
  sh -c "tar czf /work/data/certs.tgz -C /work/wazuh-docker/single-node/config wazuh_indexer_ssl_certs"
(cd wazuh-docker/single-node && docker compose -p siemlab start)
ls -lh data/*.tgz
