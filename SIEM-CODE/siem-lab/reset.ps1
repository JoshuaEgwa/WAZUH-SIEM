# Wipes the lab and reloads the original dataset.
Set-Location $PSScriptRoot
Push-Location wazuh-docker\single-node
docker compose -p siemlab down -v
Pop-Location
.\setup.ps1
