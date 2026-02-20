# BPB Autoscan Worker

Headless worker for scheduled server-side runs.

## Commands

```bash
dart run bin/bpb_autoscan.dart run-once [options]
dart run bin/bpb_autoscan.dart cleanup [options]
```

## Key Behavior

- Acquires exclusive lock (`run.lock`) to prevent overlapping runs
- Persists run history:
  - `runs/<run_id>.json`
  - `runs_index.jsonl`
  - `latest.json`
  - `status.json`
- Writes daily log files:
  - `app-YYYY-MM-DD.log`
- Deletes log files older than `--retention-days` (default: 7)

## Options

- `--state-dir <path>` default `/var/lib/bpb-automation`
- `--log-dir <path>` default `/var/log/bpb-automation`
- `--retention-days <n>` default `7`
- `--trigger <name>` default `manual`
- `--host-label <name>` default local hostname
- `--scan-cmd <cmd>` shell command that returns JSON on stdout
- `--apply` enable apply step after successful scan
- `--apply-cmd <cmd>` apply shell command

## Scan Command Contract

`--scan-cmd` must print JSON to stdout:

```json
{
  "status": "success",
  "phase1_passed": 120,
  "phase2_tested": 50,
  "working_ips": ["1.1.1.1", "1.0.0.1"],
  "error_summary": null
}
```

If `status` is not `success`, worker records a failed run.

## Apply Command Contract

When `--apply` is set, worker executes `--apply-cmd` and provides:

- `BPB_WORKING_IPS_JSON` environment variable (JSON array of selected IPs)

Example:

```bash
dart run bin/bpb_autoscan.dart run-once \
  --state-dir /tmp/bpb-state \
  --log-dir /tmp/bpb-logs \
  --trigger scheduled \
  --scan-cmd "echo '{\"status\":\"success\",\"phase1_passed\":12,\"phase2_tested\":10,\"working_ips\":[\"1.1.1.1\"]}'"
```
