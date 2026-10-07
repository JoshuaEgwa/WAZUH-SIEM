# Wazuh AiTM Lab

A self-contained **Wazuh single-node SIEM lab** for investigating an
**Adversary-in-the-Middle (AiTM) phishing → session-cookie replay → account
takeover → lateral movement** incident.

You investigate a **frozen, pre-built synthetic dataset** inside the live Wazuh
dashboard. Nothing attacks anything — the whole AiTM chain is already baked into
the data. 100% synthetic (fictional company *Northwind Trading*), no real M365/
Entra tenant, no cloud cost, fully reproducible.

> Same Docker-per-laptop model as `siem-lab-starter`, re-themed from brute-force
> to AiTM.

> **Ships ready to run.** The repo already includes the pre-generated synthetic
> logs in `datagen/output/`, so `setup.sh` stands up Wazuh *and* ingests the
> AiTM dataset in one step — no separate data build needed on the student side.

---

## Student quick-start

**Prerequisites**
- Docker Desktop (give it **≥ 6 GB RAM** — Settings → Resources) + Git.
- ~8 GB free RAM, ~5 GB free disk.
- Stay **off public Wi-Fi** while running — the lab opens local ports (443, 1514, 1515, 55000) with a shared default login.

**Run it**

macOS / Linux:
```bash
git clone <this-repo> wazuh-aitm-lab
cd wazuh-aitm-lab
./setup.sh
```

Windows (PowerShell):
```powershell
git clone <this-repo> wazuh-aitm-lab
cd wazuh-aitm-lab
.\setup.ps1
```

Then:
1. Open **https://localhost** and accept the self-signed certificate warning.
2. Log in with the credentials printed by the script (default `admin` / `SecretPassword`, from `config.env`).
3. **Set the dashboard time range to the dataset's dates** — the incident is around **2025-04-14** (benign baseline spans **2025-04-01 … 2025-04-14**). If you skip this, *the dashboard looks empty.*
4. Explore the alerts. Start over any time with `./reset.sh` (`.\reset.ps1`).

> ⚠️ **Apple Silicon (M-series) & low-RAM Windows** are the two most common
> trouble spots. See `docs/troubleshooting.md`.

---

## What's in the dataset

A ~2-week benign baseline (~49k events across sign-ins, mailbox activity,
endpoint processes and portal hits) with **one buried AiTM incident**:

| Stage | What to look for | MITRE |
|-------|------------------|-------|
| Initial access | Victim hits a look-alike reverse-proxy portal (`login.northwind-trading.com.secure-access.io`); credentials **relayed** | T1557 |
| Cookie theft | Live session cookie **captured** at the proxy | T1550.004 |
| MFA bypass | Sign-in where **MFA is "satisfied" with no prompt** (replayed token), from an anonymizer IP, with **impossible travel** + **reused session ID** | T1550.004 / T1078 |
| Account takeover | Repeated anonymizer-IP sign-ins for the same user | T1078 |
| Persistence | Attacker creates a **hidden inbox-forwarding rule** to an external address | T1114.003 |
| Recon / lateral movement | **Suspicious PowerShell** + directory recon under the compromised identity | T1087 / T1059.001 |

The correlation rule stitches these into one **critical (level 15) "AiTM
INCIDENT"** alert, so there is a clear high-severity finding to anchor the hunt.

The victim is `j.rivera@northwind-trading.com`.

---

## Repo layout

```
wazuh-aitm-lab/
├── config.env                # WAZUH_TAG (pinned 4.x) + DATASET_URL + login
├── setup.sh / setup.ps1      # stand up the whole lab
├── reset.sh / reset.ps1      # wipe volumes + reload the frozen dataset
├── backup-dataset.sh         # INSTRUCTOR: freeze indexer volume + certs
├── custom-rules/             # AiTM detection rules (XML)
├── custom-decoders/          # evilginx access-log decoder (XML)
├── datagen/                  # INSTRUCTOR: pure-bash synthetic log generator
├── scripts/                  # helpers (restore, ingest, load detection content)
├── lib/common.sh             # shared bash helpers
├── data/                     # frozen dataset lands here (.tgz, git-ignored)
└── docs/                     # INSTRUCTOR.md + troubleshooting.md
```

The heavy `data/*.tgz` files are **not** committed (they exceed GitHub's 100 MB
limit). The instructor hosts them and sets `DATASET_URL`; `setup.sh` downloads
them automatically. See `docs/INSTRUCTOR.md`.

---

## Detection content

- **`custom-decoders/aitm_decoders.xml`** — parses the text evilginx access log.
  The JSON sources (sign-in / mailbox / endpoint) use Wazuh's built-in `json`
  decoder.
- **`custom-rules/aitm_rules.xml`** — rule IDs `100100–100199`, including the
  MFA-token-replay tell-tale, impossible travel, session reuse, mailbox
  persistence, suspicious PowerShell, and the `100150` critical correlation
  rule.

The data generator and the rules share **one field schema**, so detections
match reliably.

---

## Notes

- **Path B per-laptop only.** No shared server, no live attacks, no student VMs.
- Pinned to a **stable 4.x** Wazuh tag (`config.env:WAZUH_TAG`). The scripts
  clone that exact release tag, never `main`.
