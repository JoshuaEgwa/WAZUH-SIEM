#!/usr/bin/env bash
# Wipes the lab and reloads the original dataset.
set -euo pipefail
cd "$(dirname "$0")"
(cd wazuh-docker/single-node && docker compose -p siemlab down -v)
bash ./setup.sh
