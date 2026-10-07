<#
=============================================================================
 setup.ps1  (Windows PowerShell — Docker Desktop)
=============================================================================
 Windows equivalent of setup.sh. Run from an elevated-ish PowerShell:
     .\setup.ps1
 then open https://localhost
=============================================================================
#>
$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$WazuhDir = Join-Path $RepoRoot "wazuh-docker\single-node"

function Log  ($m) { Write-Host "[aitm] $m" -ForegroundColor Cyan }
function Warn ($m) { Write-Host "[aitm][warn] $m" -ForegroundColor Yellow }
function Die  ($m) { Write-Host "[aitm][fatal] $m" -ForegroundColor Red; exit 1 }

# ---- load config.env --------------------------------------------------------
$cfg = @{}
Get-Content (Join-Path $RepoRoot "config.env") | ForEach-Object {
  if ($_ -match '^\s*#' -or $_ -notmatch '=') { return }
  $k,$v = $_ -split '=',2
  $cfg[$k.Trim()] = $v.Trim()
}
$WAZUH_TAG   = $cfg["WAZUH_TAG"]
$TAG_BARE    = $WAZUH_TAG.TrimStart('v')
$DASH_USER   = $cfg["DASHBOARD_USER"]
$DASH_PASS   = $cfg["DASHBOARD_PASSWORD"]
$DATASET_URL = $cfg["DATASET_URL"]

# ---- docker check -----------------------------------------------------------
docker info *> $null; if ($LASTEXITCODE -ne 0) { Die "Docker daemon not reachable. Start Docker Desktop and give it >= 6 GB RAM." }

# ---- fetch pinned wazuh-docker ---------------------------------------------
if (-not (Test-Path (Join-Path $RepoRoot "wazuh-docker\.git"))) {
  Log "Cloning wazuh-docker at pinned tag $WAZUH_TAG ..."
  git clone --depth 1 --branch $WAZUH_TAG https://github.com/wazuh/wazuh-docker.git (Join-Path $RepoRoot "wazuh-docker")
  if ($LASTEXITCODE -ne 0) { Die "git clone failed." }
} else { Log "wazuh-docker already present — reusing." }
if (-not (Test-Path $WazuhDir)) { Die "single-node dir missing in wazuh-docker." }

# pin image tags + apply password
$compose = Join-Path $WazuhDir "docker-compose.yml"
if (Test-Path $compose) {
  (Get-Content $compose) -replace '(wazuh/wazuh-(manager|indexer|dashboard)):\S+', ('$1:' + $TAG_BARE) |
    Set-Content $compose
}
if ($DASH_PASS -ne "SecretPassword") {
  Get-ChildItem -Recurse -File $WazuhDir | ForEach-Object {
    (Get-Content $_.FullName -Raw) -replace 'SecretPassword', $DASH_PASS | Set-Content $_.FullName
  }
}

Push-Location $WazuhDir
try {
  # ---- certs ----------------------------------------------------------------
  if (-not (Test-Path "config\wazuh_indexer_ssl_certs\root-ca.pem")) {
    Log "Generating TLS certificates..."
    docker compose -f generate-indexer-certs.yml run --rm generator
    if ($LASTEXITCODE -ne 0) { Die "cert generation failed." }
  }

  # ---- restore frozen dataset (if available) --------------------------------
  $dataDir = Join-Path $RepoRoot "data"
  New-Item -ItemType Directory -Force -Path $dataDir | Out-Null
  $idxTgz = Join-Path $dataDir "indexer-data.tgz"
  if (-not (Test-Path $idxTgz) -and $DATASET_URL) {
    Log "Downloading frozen dataset..."
    try {
      Invoke-WebRequest "$($DATASET_URL.TrimEnd('/'))/indexer-data.tgz" -OutFile $idxTgz
      Invoke-WebRequest "$($DATASET_URL.TrimEnd('/'))/certs.tgz" -OutFile (Join-Path $dataDir "certs.tgz")
    } catch { Warn "dataset download failed — starting clean." }
  }
  if (Test-Path $idxTgz) {
    Log "Restoring frozen dataset into indexer volume..."
    $certsTgz = Join-Path $dataDir "certs.tgz"
    if (Test-Path $certsTgz) {
      Remove-Item -Recurse -Force "config\wazuh_indexer_ssl_certs" -ErrorAction SilentlyContinue
      tar xzf $certsTgz -C "config"
    }
    $vol = "$($cfg['COMPOSE_PROJECT_NAME'])_wazuh-indexer-data"
    docker volume create $vol | Out-Null
    docker run --rm -v "${vol}:/data" -v "${dataDir}:/backup:ro" alpine sh -c "rm -rf /data/* && tar xzf /backup/indexer-data.tgz -C /data"
  } else {
    Log "No frozen dataset — clean/instructor mode."
  }

  # ---- start ---------------------------------------------------------------
  Log "Starting the Wazuh single-node stack..."
  docker compose up -d
  if ($LASTEXITCODE -ne 0) { Die "docker compose up failed." }

  # ---- load detection content ----------------------------------------------
  $mgr = (docker ps --format '{{.Names}}' | Select-String 'wazuh.manager' | Select-Object -First 1).ToString().Trim()
  if ($mgr) {
    Log "Loading AiTM detection content into $mgr ..."
    docker cp (Join-Path $RepoRoot "custom-decoders\aitm_decoders.xml") "${mgr}:/var/ossec/etc/decoders/aitm_decoders.xml"
    docker cp (Join-Path $RepoRoot "custom-rules\aitm_rules.xml") "${mgr}:/var/ossec/etc/rules/aitm_rules.xml"
    $out = Join-Path $RepoRoot "datagen\output"
    if (Test-Path $out) {
      docker exec $mgr mkdir -p /var/log/aitm
      foreach ($f in @("entra_signin.json","m365_mailbox.json","endpoint.json","evilginx.log")) {
        $p = Join-Path $out $f
        if (Test-Path $p) { docker cp $p "${mgr}:/var/log/aitm/$f" }
      }
    }
    docker exec $mgr /var/ossec/bin/wazuh-control restart *> $null
  }
}
finally { Pop-Location }

# ---- wait for dashboard -----------------------------------------------------
Log "Waiting for the dashboard at https://localhost (2-4 min on first run)..."
for ($i=0; $i -lt 60; $i++) {
  try {
    $r = Invoke-WebRequest https://localhost -SkipCertificateCheck -TimeoutSec 5 -UseBasicParsing
    if ($r.StatusCode -in 200,302) { break }
  } catch {}
  Start-Sleep 10
}

Write-Host ""
Write-Host "--------------------------------------------------------------------------"
Write-Host "  Wazuh AiTM lab is up.  Open: https://localhost  (accept the cert warning)"
Write-Host "  Login: $DASH_USER / $DASH_PASS"
Write-Host "  SET the dashboard time range to ~2025-04-14 (dataset dates) or it looks EMPTY."
Write-Host "  Reset: .\reset.ps1"
Write-Host "--------------------------------------------------------------------------"
