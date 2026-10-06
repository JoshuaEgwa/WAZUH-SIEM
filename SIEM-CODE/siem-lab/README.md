# SIEM Lab (Wazuh in Docker)

## Before you start
- Install **Docker Desktop** (https://www.docker.com/products/docker-desktop) and **Git**.
- Give Docker at least **6 GB RAM** (Settings > Resources). 16 GB total on your laptop is recommended.
- About 10 GB of free disk space.

## Start the lab
**Mac / Linux**
```
git clone <YOUR-REPO-URL> siem-lab
cd siem-lab
bash setup.sh
```
**Windows (PowerShell 7 recommended)**
```
git clone <YOUR-REPO-URL> siem-lab
cd siem-lab
.\setup.ps1
```
Then open https://localhost and sign in with `admin` / `SecretPassword`.
Your browser will warn about the certificate. That is expected for a local lab; choose Advanced > Proceed.

## Seeing the data
The dataset covers **<FILL IN DATES>**. In the dashboard, set the time range (top right) to that window or you will see nothing.

## Reset or stop
- Reset everything to the original data: `bash reset.sh` (or `.\reset.ps1`)
- Pause the lab: `docker compose -p siemlab stop` from `wazuh-docker/single-node`
- Having trouble? See `docs/troubleshooting.md`.

Labs live in `labs/`.
