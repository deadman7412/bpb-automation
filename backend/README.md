# BPB Autoscan Worker

Headless worker for scheduled server-side runs.

## Commands

```bash
dart run bin/bpb_autoscan.dart run-once [options]
dart run bin/bpb_autoscan.dart rollback [options]
dart run bin/bpb_autoscan.dart cleanup [options]
dart run bin/bpb_api.dart [options]
```

## VPS Installer (Ubuntu)

One-command install/update from latest GitHub Release:

```bash
curl -fsSL https://raw.githubusercontent.com/deadman7412/bpb-automation/main/backend/deploy/vps/install_or_update_server.sh \
  | sudo bash -s -- --domain scan.example.com --email admin@example.com
```

If DNS/port-80 is not ready yet, skip TLS first:

```bash
curl -fsSL https://raw.githubusercontent.com/deadman7412/bpb-automation/main/backend/deploy/vps/install_or_update_server.sh \
  | sudo bash -s -- --domain scan.example.com --email admin@example.com --skip-tls
```

The installer will:
- download latest server package artifact
- download latest web UI package artifact
- install/update backend files in `/opt/bpb-automation/server/current`
- install/update web files in `/opt/bpb-automation/web/current`
- create/enable `bpb-api.service` and `bpb-autoscan.timer`
- configure nginx/caddy reverse proxy for your domain
- block `/internal/*` endpoints at reverse-proxy layer
- verify downloaded server package with SHA-256 checksum asset
- if UFW is active and 80/443 are closed, ask permission to open them

For non-interactive installs with UFW active:

```bash
curl -fsSL https://raw.githubusercontent.com/deadman7412/bpb-automation/main/backend/deploy/vps/install_or_update_server.sh \
  | sudo bash -s -- --domain scan.example.com --email admin@example.com --allow-firewall --non-interactive
```

After install, set real runtime commands in:
- `/etc/bpb-automation/server.env`

Retry certbot later:

```bash
sudo certbot --nginx -d scan.example.com --agree-tos -m admin@example.com --redirect
```

## VPS Uninstall (Ubuntu)

Easy uninstall:

```bash
curl -fsSL https://raw.githubusercontent.com/deadman7412/bpb-automation/main/backend/deploy/vps/uninstall_server.sh \
  | sudo bash
```

Keep state/log/config while uninstalling services/binaries:

```bash
curl -fsSL https://raw.githubusercontent.com/deadman7412/bpb-automation/main/backend/deploy/vps/uninstall_server.sh \
  | sudo bash -s -- --keep-data
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
- Writes retention verification metadata:
  - `cleanup_status.json`
- Keeps apply snapshots for rollback:
  - `current_applied.json`
  - `rollback_candidate.json`
- Writes internal action audit trail:
  - `audit.jsonl`

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
- `--min-working-ips <n>` default `1` (apply guardrail)
- `--requested-by <id>` audit caller label
- `--request-ip <ip>` caller IP metadata

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
- `GET /api/auth/status`
- `POST /api/auth/login`
- `GET /api/status`
- `GET /api/results?page=1&page_size=20`
- `GET /api/results/latest`
- `GET /api/results/{run_id}`
- `GET /api/logs/latest?lines=200`
- `POST /internal/scheduler/run?trigger=api` (requires token)
- `POST /internal/scheduler/rollback` (requires token)
- `GET /api/logs?page=1&page_size=200`
- `GET /api/maintenance/log-retention`

Optional web auth flags (JWT):

- `--web-auth-username <user>` bootstrap username (stored as hashed credentials in `state-dir/web_auth.json`)
- `--web-auth-password <pass>` bootstrap password (hashed + salted with PBKDF2-HMAC-SHA256)
- `--jwt-secret <secret>` required when web auth is enabled
- `--jwt-ttl-seconds <n>` JWT lifetime in seconds (default `86400`)

When web auth is enabled, all `/api/*` endpoints require `Authorization: Bearer <jwt>` except `/api/auth/login` and `/api/auth/status`.

Hardening flags:

- `--allowed-trigger-ips <csv>` source IP allowlist for internal endpoints
- `--trust-forwarded-for` trust `x-forwarded-for` when API is behind reverse proxy
- `--min-working-ips <n>` prevent apply when working IP count is below threshold

Trigger example:

```bash
curl -X POST \
  -H "Authorization: Bearer local-dev-token" \
  "http://127.0.0.1:8787/internal/scheduler/run?trigger=api"
```

Rollback example:

```bash
curl -X POST \
  -H "Authorization: Bearer local-dev-token" \
  "http://127.0.0.1:8787/internal/scheduler/rollback"
```
