# Troubleshooting

**Dashboard says "not ready yet" or the page won't load.** First start takes 3-5 minutes. Wait, then refresh.
Check containers with `docker ps` (all should be "Up"); logs with `docker compose -p siemlab logs wazuh.indexer` from `wazuh-docker/single-node`.

**Indexer keeps restarting.** Usually memory or `vm.max_map_count`.
- Raise Docker memory to 6 GB or more (Docker Desktop > Settings > Resources).
- Linux: `sudo sysctl -w vm.max_map_count=262144`
- Windows: run `wsl -d docker-desktop sysctl -w vm.max_map_count=262144` and re-run setup.

**Windows (WSL2) limited memory.** Create `%UserProfile%\.wslconfig`:
```
[wsl2]
memory=6GB
```
then run `wsl --shutdown` and restart Docker Desktop.

**"port is already allocated" (443, 9200, 55000, 1514...).** Another program is using the port. Close it (IIS, another web server, an old lab) or stop the old lab with `bash reset.sh`.

**Browser certificate warning.** Expected. The lab uses self-signed certificates.

**Dashboard shows no data.** Set the time range to the dataset dates listed in the README.

**`bad interpreter` or `\r` errors on Windows/Git Bash.** Line endings got converted. Run `git config core.autocrlf false`, re-clone, and use `setup.ps1` on Windows.

**Apple Silicon (M1/M2/M3...).** If images fail with a platform error, enable Rosetta emulation in Docker Desktop > Settings > General. Tell your instructor.

**Start over completely.** `bash reset.sh` (or `.\reset.ps1`). To also delete downloaded files, remove the `wazuh-docker` folder first.
