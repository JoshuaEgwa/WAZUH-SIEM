<#
=============================================================================
 reset.ps1  (Windows PowerShell)
=============================================================================
 Wipes lab volumes and reloads the original frozen AiTM dataset.
=============================================================================
#>
$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$WazuhDir = Join-Path $RepoRoot "wazuh-docker\single-node"

$cfg = @{}
Get-Content (Join-Path $RepoRoot "config.env") | ForEach-Object {
  if ($_ -match '^\s*#' -or $_ -notmatch '=') { return }
  $k,$v = $_ -split '=',2; $cfg[$k.Trim()] = $v.Trim()
}

Write-Host "[aitm][warn] This DELETES all lab volumes and reloads the original AiTM dataset." -ForegroundColor Yellow
$ans = Read-Host "Continue? [y/N]"
if ($ans -notin @('y','Y')) { Write-Host "Aborted."; exit 0 }

Push-Location $WazuhDir
try {
  docker compose down -v
  # restore
  $dataDir = Join-Path $RepoRoot "data"
  $idxTgz  = Join-Path $dataDir "indexer-data.tgz"
  if (Test-Path $idxTgz) {
    $certsTgz = Join-Path $dataDir "certs.tgz"
    if (Test-Path $certsTgz) {
      Remove-Item -Recurse -Force "config\wazuh_indexer_ssl_certs" -ErrorAction SilentlyContinue
      tar xzf $certsTgz -C "config"
    }
    $vol = "$($cfg['COMPOSE_PROJECT_NAME'])_wazuh-indexer-data"
    docker volume create $vol | Out-Null
    docker run --rm -v "${vol}:/data" -v "${dataDir}:/backup:ro" alpine sh -c "rm -rf /data/* && tar xzf /backup/indexer-data.tgz -C /data"
  }
  docker compose up -d
}
finally { Pop-Location }

Write-Host "[aitm] Reset complete. Open https://localhost and set the time range to ~2025-04-14." -ForegroundColor Cyan
