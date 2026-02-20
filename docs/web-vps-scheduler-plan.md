# Web + VPS Scheduler Plan (Ubuntu LTS)

This document defines the recommended architecture for:

- Web UI access from any device
- Scheduled automatic scans
- Automatic clean IP upload to BPB backend
- Result history visibility for users
- Server-side log retention with automatic cleanup

It is designed for Ubuntu LTS hosts.

## 1) Feasibility Summary

This is feasible with a Linux backend worker.  
It is **not** feasible in a browser-only deployment because the current scan logic uses:

- raw sockets (`dart:io` network primitives)
- local process execution (Xray phase)
- filesystem access

Those are unavailable in web browsers.

## 2) Recommended Architecture (Option A)

Use a split architecture:

1. Web frontend (Flutter web build)
2. Backend API service (Linux process)
3. Scheduler adapter (cron/systemd/Task Scheduler/WorkManager)
4. Local state/log storage on VPS

Flow:

1. Scheduler triggers backend job (`run once`)
2. Backend fetches latest subscription config
3. Backend runs scan pipeline (Phase 1 + Phase 2)
4. Backend applies best IP set using configured update mode
5. Backend stores per-run result history and logs
6. Web UI reads status/history/results from backend API

## 3) Important Network Constraint

Scan quality depends on the network path of the scanner host.

- If scanner host is behind VPN/tunnel, results may be invalid for non-tunneled users.
- If users are on home ISP and backend runs on remote cloud VPS, results may not match home ISP routing.

If your goal is "IPs that work best for my home/mobile network", run scheduler on a host in that same network without tunnel routing.

## 4) Ubuntu LTS Deployment Baseline

Install runtime packages:

```bash
sudo apt update
sudo apt install -y nginx curl jq ca-certificates
```

Suggested directories:

- `/opt/bpb-automation/web` (static web files)
- `/opt/bpb-automation/backend` (backend binary/service files)
- `/var/lib/bpb-automation` (runtime data)
- `/var/log/bpb-automation` (logs)

## 5) Scheduler Strategy (All Platforms)

Scheduling must be supported on all builds, but the scheduling mechanism is
platform-specific. The scan logic must stay in one reusable "run once" worker.

### Core Principle

- Build one headless command: `bpb-autoscan run-once`
- Every scheduler calls that same command
- This keeps behavior consistent across Linux/Windows/Android/web-backend hosts

### Recommended adapters

- Linux: cron (preferred) or systemd timer
- Windows: Task Scheduler
- Android: WorkManager / platform background task API
- macOS: launchd
- iOS: BGTaskScheduler (best-effort, OS controlled)
- Web browser: no reliable native scheduler; use backend scheduler (VPS/LAN host)

### Linux cron example (preferred)

Run every 6 hours:

```cron
0 */6 * * * /opt/bpb-automation/backend/bin/bpb-autoscan run-once >> /var/log/bpb-automation/cron.log 2>&1
```

### Linux systemd timer example (optional)

`/etc/systemd/system/bpb-autoscan.service`

```ini
[Unit]
Description=BPB Automation scheduled scan and auto-apply
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=bpb
Group=bpb
WorkingDirectory=/opt/bpb-automation/backend
Environment=BPB_ENV=production
ExecStart=/opt/bpb-automation/backend/bin/bpb-autoscan run-once
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
```

`/etc/systemd/system/bpb-autoscan.timer`

```ini
[Unit]
Description=Run BPB autoscan every 6 hours

[Timer]
OnBootSec=3min
OnUnitActiveSec=6h
AccuracySec=1min
Persistent=true
Unit=bpb-autoscan.service

[Install]
WantedBy=timers.target
```

Enable:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now bpb-autoscan.timer
systemctl list-timers | grep bpb-autoscan
```

## 6) Run History and Dashboard Model

Do not show only last result. Persist history and expose it in UI/API.

Per-run record (minimum):

- `run_id`
- `started_at`, `finished_at`, `duration_ms`
- `trigger` (`manual`, `scheduled`, `api`)
- `host_label` (for multi-device deployments)
- `phase1_passed`, `phase2_tested`, `working_count`
- `selected_ips` (or checksum + detail ref)
- `applied` (`true/false`)
- `update_mode` (`panel_api`, `cloudflare_api`)
- `status` (`success`, `partial`, `failed`)
- `error_summary` (nullable)

Recommended storage:

- SQLite table for metadata/history queries
- JSON artifact per run for detailed payload

## 7) Server Logging and Retention

Persist logs to file with rotation and retention.

Policy:

- Rotate daily (`app-YYYY-MM-DD.log`)
- Keep 7 days
- Delete files older than 7 days automatically
- Optionally gzip archived logs

Guidelines:

- Redact secrets before writing
- Keep run-summary logs separate from verbose debug logs
- Keep a small API to read latest redacted logs for dashboard troubleshooting

## 8) Security Requirements

1. Do not expose scheduler trigger endpoints publicly.
2. Keep API tokens only on backend host, not in browser JS.
3. Restrict backend bind to localhost and reverse-proxy only required UI/API routes.
4. Add request authentication for any write/trigger endpoint.
5. Add scan lock to prevent overlapping runs.
6. Add upload guardrails:
   - only apply if minimum `N` working IPs found
   - keep previous IP set snapshot for rollback

## 9) API Contract (Backend)

Minimum endpoints:

- `POST /internal/scheduler/run` (manual run trigger; admin-auth only)
- `GET /api/status` (running/idle, last run time, next run)
- `GET /api/results` (paginated history)
- `GET /api/results/latest` (latest scan summary + selected IPs)
- `GET /api/results/{run_id}` (single run detail)
- `GET /api/logs` (paginated logs; redacted)
- `GET /api/logs/latest` (recent logs; redacted)

## 10) Implementation Phases

Phase A:

- Build backend "run-once" command (headless scan + update + lock)
- Persist per-run result JSON + history metadata

Phase B:

- Add scheduler adapters:
  - cron profile for Linux
  - systemd timer profile for Linux (optional)
  - Windows Task Scheduler integration docs/script
  - Android scheduling integration plan
- Add retry + backoff + overlapping-run protection

Phase C:

- Add history/status/result endpoints
- Replace single "last result" UI with history table and run detail view
- Add logs view (redacted + paginated)

Phase D:

- Add hardening (auth, firewall, audit logs, rollback)
- Add automatic log retention cleanup verification

### Phase Completion Status

As of 2026-02-20:

- Phase A: COMPLETE
  - Implemented headless `run-once` worker command
  - Added exclusive lock (`run.lock`) to prevent overlapping runs
  - Added daily file logging with 7-day cleanup
  - Added per-run persistence (`runs/*.json`, `runs_index.jsonl`, `latest.json`, `status.json`)
  - Added explicit run metadata (`trigger`, `host_label`, `update_mode`, `status`, `error_summary`)
  - Added `partial` status when scan succeeds but apply fails
- Phase B: COMPLETE
  - Added scheduler adapter artifacts:
    - Linux cron template
    - Linux systemd service/timer + env example
    - Windows Task Scheduler registration script + runner
    - Android WorkManager integration plan
  - Added scan/apply retry with exponential backoff in worker
  - Added overlap protection via lock file for all adapter-invoked runs
- Phase C: COMPLETE
- Phase D: NOT STARTED

## 11) Success Criteria

- Scheduled jobs run reliably on configured scheduler (cron/timer/etc.) and survive reboot
- No overlapping scans
- Auto-apply only when quality threshold passes
- Result history visible from web UI
- Server logs rotate and retain only last 7 days
- Tokens never exposed to frontend
