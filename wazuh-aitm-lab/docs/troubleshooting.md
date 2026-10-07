# Troubleshooting — Wazuh AiTM Lab

## The dashboard is empty / "No results match your search"
**99% of the time this is the time range.** The incident is dated around
**2025-04-14** and the benign baseline spans **2025-04-01 … 2025-04-14**.
Set the dashboard time picker to cover that window (try **2025-03-25 →
2025-04-16** to be safe). If you just re-ingested on a fresh stack, also try
**Today / Last 24 hours**, because freshly ingested alerts are stamped with the
processing time.

## `vm.max_map_count` too low (indexer won't start, exits with code 78)
Linux hosts only (Docker Desktop handles it inside its VM):
```bash
sudo sysctl -w vm.max_map_count=262144
# persist:
echo 'vm.max_map_count=262144' | sudo tee -a /etc/sysctl.conf
```

## Indexer / dashboard keeps restarting or OOM-kills
Give Docker more memory: **Docker Desktop → Settings → Resources → Memory ≥ 6 GB**,
then `cd wazuh-docker/single-node && docker compose down && docker compose up -d`.

## Apple Silicon (M1/M2/M3) — image won't run / "exec format error"
The official images are multi-arch, but if your pinned tag is missing an arm64
build, force emulation by adding this under each service in
`wazuh-docker/single-node/docker-compose.yml`:
```yaml
    platform: linux/amd64
```
Then `docker compose up -d`. It's slower (Rosetta/QEMU) but works.

## Browser warns about the certificate
Expected — the lab uses self-signed certs. Click **Advanced → Proceed to
localhost**. (Chrome: you can type `thisisunsafe` on the warning page.)

## Login fails
Default is `admin` / `SecretPassword` (see `config.env:DASHBOARD_PASSWORD`).
If you changed the password in `config.env`, re-run `./setup.sh` on a fresh
stack (`./reset.sh`) so it propagates to the indexer security config.

## Port 443 already in use
Something else owns 443 (another web server, Skype, etc.). Stop it, or edit the
`wazuh.dashboard` port mapping in `wazuh-docker/single-node/docker-compose.yml`
from `443:5601` to e.g. `8443:5601` and open `https://localhost:8443`.

## Cert mismatch after restoring a frozen dataset
The frozen `certs.tgz` must match the frozen indexer volume. `setup.sh` restores
both together. If you restored only one, run `./reset.sh` to wipe and restore
both cleanly.

## Checking logs
```bash
cd wazuh-docker/single-node
docker compose ps
docker compose logs wazuh.indexer | tail -50
docker compose logs wazuh.dashboard | tail -50
docker exec $(docker ps --format '{{.Names}}' | grep wazuh.manager) tail -50 /var/ossec/logs/ossec.log
```

## Rules not firing after re-ingest (instructor)
Field-name drift between `datagen/generate.sh` and `custom-rules/aitm_rules.xml`.
Test a single line:
```bash
MGR=$(docker ps --format '{{.Names}}' | grep wazuh.manager)
echo 'evilginx: ts=2025-04-14T09:10:02Z src=203.0.113.45 method=POST uri=/login status=302 portal=login.northwind-trading.com.secure-access.io user=j.rivera@northwind-trading.com creds=1 cookie=ESTSAUTH_captured_x ua="Mozilla/5.0"' \
  | docker exec -i $MGR /var/ossec/bin/wazuh-logtest
```
You should see it match decoder `evilginx` and rule `100122`.

## Start completely over
```bash
./reset.sh            # or .\reset.ps1 on Windows
```
