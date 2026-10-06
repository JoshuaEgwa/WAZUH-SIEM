# Windows (PowerShell): builds the Wazuh lab and loads the frozen dataset. Safe to re-run.
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
Get-Content config.env | ForEach-Object {
  if ($_ -match '^\s*([A-Z_]+)=(.*)$') { Set-Variable -Name $Matches[1] -Value $Matches[2] }
}
$Project = "siemlab"; $ComposeDir = "wazuh-docker\single-node"; $Vol = "${Project}_wazuh-indexer-data"
function Run { & $args[0] $args[1..($args.Count-1)]; if ($LASTEXITCODE -ne 0) { throw "Command failed: $args" } }
function Say($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }

Say "Checking requirements"
if (-not (Get-Command git -ErrorAction SilentlyContinue))    { throw "git is not installed." }
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw "Docker Desktop is not installed." }
docker info *> $null
if ($LASTEXITCODE -ne 0) { throw "Docker is not running. Start Docker Desktop and retry." }
$mem = [int64](docker info --format '{{.MemTotal}}')
if ($mem -lt 6000000000) { Write-Warning "Docker has less than 6 GB RAM. Edit %UserProfile%\.wslconfig (see docs/troubleshooting.md)." }

Say "Setting kernel parameter (best effort)"
try { wsl -d docker-desktop sysctl -w vm.max_map_count=262144 | Out-Null } catch { Write-Warning "Could not set vm.max_map_count; see troubleshooting." }

Say "Getting Wazuh Docker files ($WAZUH_TAG)"
if (-not (Test-Path wazuh-docker)) { Run git clone --depth 1 --branch $WAZUH_TAG https://github.com/wazuh/wazuh-docker.git }

Say "Getting the lab dataset"
New-Item -ItemType Directory -Force data | Out-Null
if ($DATASET_URL) {
  foreach ($f in "indexer-data.tgz","certs.tgz") {
    if (-not (Test-Path "data\$f")) { Invoke-WebRequest "$DATASET_URL/$f" -OutFile "data\$f" }
  }
}

Say "Preparing certificates"
if (-not (Test-Path wazuh-docker\.certs-ready)) {
  if (Test-Path data\certs.tgz) {
    Run docker run --rm -v "${PWD}:/work" alpine sh -c "tar xzf /work/data/certs.tgz -C /work/wazuh-docker/single-node/config"
  } else {
    Push-Location $ComposeDir
    Run docker compose -f generate-indexer-certs.yml run --rm generator
    Pop-Location
  }
  New-Item wazuh-docker\.certs-ready -ItemType File | Out-Null
}

docker volume inspect $Vol *> $null
if ((Test-Path data\indexer-data.tgz) -and ($LASTEXITCODE -ne 0)) {
  Say "Loading dataset"
  Run docker volume create $Vol
  Run docker run --rm -v "${Vol}:/data" -v "${PWD}\data:/backup" alpine sh -c "cd /data && tar xzf /backup/indexer-data.tgz"
}

Say "Starting Wazuh (first start takes a few minutes)"
Push-Location $ComposeDir
Run docker compose -p $Project up -d
Pop-Location

Write-Host "Waiting for the dashboard" -NoNewline
for ($i = 0; $i -lt 90; $i++) {
  try { $r = Invoke-WebRequest https://localhost -SkipCertificateCheck -MaximumRedirection 0 -ErrorAction Stop; break }
  catch { if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -in 200,302) { break } }
  Write-Host "." -NoNewline; Start-Sleep 5
}
Write-Host "`n`nReady. Open https://localhost (accept the browser certificate warning)."
Write-Host "Login: admin / SecretPassword"
