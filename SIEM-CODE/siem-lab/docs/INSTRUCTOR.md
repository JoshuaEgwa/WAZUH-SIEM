# Instructor guide: building the frozen dataset (once per term)

1. Run `bash setup.sh` with `data/` empty and `DATASET_URL` blank. This gives you a fresh Wazuh.
2. Change nothing in the compose project name; the scripts rely on `siemlab`.
3. Create a Windows evaluation VM (Microsoft Evaluation Center) and a Kali VM on a host-only network.
   Install the Wazuh agent (manager address = your host's IP) and Sysmon with the SwiftOnSecurity config.
4. Generate data: Atomic Red Team tests, a Kali brute-force script, plus scheduled "normal user" noise.
5. Confirm events in the dashboard. Note the date range and put it in README.md.
6. Run `bash backup-dataset.sh`. This creates `data/indexer-data.tgz` and `data/certs.tgz`.
7. Host both files (GitHub Release, school drive, or Git LFS) and put the folder URL in `config.env` as DATASET_URL.
   Plain Git rejects files over 100 MB.
8. Test on a clean machine for each OS you support: clone, run setup, verify the data appears, run reset.
9. Each term: re-check the latest `wazuh-docker` release tag, update `WAZUH_TAG`, rebuild the dataset, retest.
