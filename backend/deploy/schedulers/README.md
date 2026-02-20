# Scheduler Adapters (Phase B)

This folder contains platform scheduler adapters that invoke the same worker:

```bash
dart run bin/bpb_autoscan.dart run-once ...
```

## Linux

- `cron/bpb-autoscan.cron`
- `systemd/bpb-autoscan.service`
- `systemd/bpb-autoscan.timer`
- `systemd/bpb-autoscan.env.example`
- `run-once.sh` shared runner wrapper

## Windows

- `windows/register-task.ps1`
- `windows/run-once.cmd`

## Android

- `android/README.md` contains integration guidance using WorkManager.

## Notes

- All adapters call the same headless `run-once` command.
- Overlap protection is enforced by worker lock file (`run.lock`).
- Retry/backoff behavior is configured via worker flags:
  - `--scan-retries`
  - `--apply-retries`
  - `--initial-retry-delay-ms`

## Quick Setup (Linux systemd)

```bash
sudo cp backend/deploy/schedulers/systemd/bpb-autoscan.service /etc/systemd/system/
sudo cp backend/deploy/schedulers/systemd/bpb-autoscan.timer /etc/systemd/system/
sudo cp backend/deploy/schedulers/systemd/bpb-autoscan.env.example /etc/default/bpb-autoscan
sudo chmod +x /opt/bpb-automation/backend/deploy/schedulers/run-once.sh
sudo systemctl daemon-reload
sudo systemctl enable --now bpb-autoscan.timer
```
