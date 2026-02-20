# BPB Autoscan Worker

Headless worker for scheduled server-side runs.

## Commands

```bash
dart run bin/bpb_autoscan.dart run-once [options]
dart run bin/bpb_autoscan.dart cleanup [options]
dart run bin/bpb_api.dart [options]
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
- `--host-label <name>` default `server-host`
- `--update-mode <name>` default `command`
- `--scan-cmd <cmd>` shell command that returns JSON on stdout
- `--apply` enable apply step after successful scan
- `--apply-cmd <cmd>` apply shell command
- `--scan-retries <n>` default `3`
- `--apply-retries <n>` default `3`
- `--initial-retry-delay-ms <n>` default `1000`

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
`--scan-cmd` is required for `run-once`.

## Apply Command Contract

When `--apply` is set, worker executes `--apply-cmd` and provides:

- `BPB_WORKING_IPS_JSON` environment variable (JSON array of selected IPs)

Example:

```bash
dart run bin/bpb_autoscan.dart run-once \
  --state-dir /tmp/bpb-state \
  --log-dir /tmp/bpb-logs \
  --trigger scheduled \
  --update-mode cloudflare_api \
  --scan-cmd "echo '{\"status\":\"success\",\"phase1_passed\":12,\"phase2_tested\":10,\"working_ips\":[\"1.1.1.1\"]}'"
```

## API Server

Start local API:

```bash
dart run bin/bpb_api.dart \
  --host 127.0.0.1 \
  --port 8787 \
  --state-dir /tmp/bpb-state \
  --log-dir /tmp/bpb-logs \
  --internal-token local-dev-token \
  --scan-retries 3 \
  --apply-retries 3 \
  --initial-retry-delay-ms 1000 \
  --scan-cmd "echo '{\"status\":\"success\",\"phase1_passed\":3,\"phase2_tested\":2,\"working_ips\":[\"1.1.1.1\"]}'"
```

Endpoints:

- `GET /health`
- `GET /api/status`
- `GET /api/results?page=1&page_size=20`
- `GET /api/results/latest`
- `GET /api/results/{run_id}`
- `GET /api/logs/latest?lines=200`
- `POST /internal/scheduler/run?trigger=api` (requires token)

Trigger example:

```bash
curl -X POST \
  -H "Authorization: Bearer local-dev-token" \
  "http://127.0.0.1:8787/internal/scheduler/run?trigger=api"
```
