# Instructor guide — Wazuh AiTM Lab

You build and **freeze** the dataset once per term; students only restore and
investigate it. Everything is synthetic — no real tenant, no credentials, no
external API, ever.

---

## 0. Each term: re-verify the pinned Wazuh version

Wazuh releases drift. Before a term:

1. Open https://github.com/wazuh/wazuh-docker/releases
2. Pick the **latest stable 4.x** tag (NOT a `5.0.0` beta/rc — those are
   pre-release).
3. Set it in `config.env`:
   ```
   WAZUH_TAG=v4.14.8
   ```

The scripts clone that exact tag, so a clean clone is reproducible.

---

## 1. Build a clean stack

```bash
git clone <repo> wazuh-aitm-lab && cd wazuh-aitm-lab
# make sure data/indexer-data.tgz does NOT exist yet, and DATASET_URL is blank
./setup.sh
```

This clones the pinned `wazuh-docker`, generates certs, and starts a clean
single-node Wazuh. Wait for `https://localhost` to come up.

---

## 2. Generate synthetic logs + ingest

```bash
bash datagen/generate.sh        # pure bash; writes datagen/output/*
bash scripts/ingest.sh          # loads rules/decoders, feeds logs, verifies
```

`datagen/generate.sh` is tunable via env vars (defaults give ~49k events):
```bash
N_SIGNIN=50000 N_MAILBOX=12000 N_ENDPOINT=8000 bash datagen/generate.sh
```

`scripts/ingest.sh` confirms the key rules fired (100102, 100111, 100122,
100150). If any show `[MISS]`, check that the JSON field names in
`datagen/generate.sh` still match `custom-rules/aitm_rules.xml` (shared schema).

---

## 3. Verify in the dashboard

1. Open `https://localhost`, log in.
2. Set the time range to cover **2025-04-01 … 2025-04-15** (ingestion stamps
   alerts with processing time, so also check **Today** if you just ingested).
3. Confirm you see the **level-15 "AiTM INCIDENT"** alert and the supporting
   detections for `j.rivera@northwind-trading.com`.
4. **Note the exact date range** you want students to use and keep it in sync
   with the README.

---

## 4. Freeze the dataset

```bash
./backup-dataset.sh
```

Produces:
- `data/indexer-data.tgz` — the indexer data volume (all indexed alerts)
- `data/certs.tgz` — the TLS certs matching that indexer node

Both usually exceed GitHub's 100 MB limit, so:

1. Upload **both** to a GitHub Release / school drive / Git LFS.
2. Put the base URL in `config.env`:
   ```
   DATASET_URL=https://github.com/you/wazuh-aitm-lab/releases/download/dataset-2025t1
   ```
   `setup.sh` will fetch `${DATASET_URL}/indexer-data.tgz` and `/certs.tgz`.
3. Commit `config.env`. Students now just run `./setup.sh`.

---

## 5. Test a clean clone on BOTH platforms

The two known pain points — test early:

- **macOS incl. Apple Silicon (M-series):** the official Wazuh images are
  multi-arch, but confirm the dashboard loads and cert restore works. If an
  image lacks an arm64 variant on your pinned tag, add `platform: linux/amd64`
  under each service in `wazuh-docker/single-node/docker-compose.yml` (runs via
  emulation — slower but works).
- **Low-RAM Windows laptop:** Docker Desktop → Settings → Resources → Memory
  ≥ 6 GB. The indexer JVM heap is capped in the compose file.

---

## How ingestion works (so you can tune detections)

- The JSON sources (`entra_signin.json`, `m365_mailbox.json`, `endpoint.json`)
  are read with `<log_format>json</log_format>`; every key becomes a field
  (e.g. `mfa_result`, `anonymizer`) you match in rules with `<field name=...>`.
- The evilginx access log is plain text and is parsed by
  `custom-decoders/aitm_decoders.xml` into fields (`srcip`, `user`, `portal`,
  `creds_relayed`, `session_cookie`, …).
- Localfile stanzas are appended to the manager's `ossec.conf` by
  `scripts/load-detection-content.sh` (idempotent).

**Golden rule:** the field names in `datagen/generate.sh` and the
`<field name=...>` matches in `custom-rules/aitm_rules.xml` must stay identical.
