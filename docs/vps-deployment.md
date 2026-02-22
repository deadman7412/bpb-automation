# VPS Deployment (Web + Server Backend)

Use this guide when deploying BPB Automation on Ubuntu VPS with:
- Web dashboard for any device
- Server-side scheduled scans
- Automatic apply via backend worker

WIP status:
- Server backend, web control flows, and trigger/rollback endpoints are currently **WIP / Experimental** and not guaranteed stable in all environments.

## Architecture

1. Flutter web UI is served as static files.
2. Backend API runs on localhost (`127.0.0.1:8787` by default).
3. Scheduler timer triggers backend runs through internal endpoint.
4. Reverse proxy (nginx/caddy) exposes web + `/api/*` publicly and blocks `/internal/*`.

## Recommended: One-Command Install/Update

```bash
curl -fsSL https://raw.githubusercontent.com/deadman7412/bpb-automation/main/backend/deploy/vps/install_or_update_server.sh \
  | sudo bash -s -- --domain scan.example.com --email admin@example.com
```

If DNS/port 80 is not ready yet:

```bash
curl -fsSL https://raw.githubusercontent.com/deadman7412/bpb-automation/main/backend/deploy/vps/install_or_update_server.sh \
  | sudo bash -s -- --domain scan.example.com --email admin@example.com --skip-tls
```

Non-interactive with UFW auto-open:

```bash
curl -fsSL https://raw.githubusercontent.com/deadman7412/bpb-automation/main/backend/deploy/vps/install_or_update_server.sh \
  | sudo bash -s -- --domain scan.example.com --email admin@example.com --allow-firewall --non-interactive
```

## What Installer Configures

- Server files: `/opt/bpb-automation/server/current`
- Web files: `/opt/bpb-automation/web/current`
- Runtime config: `/etc/bpb-automation/server.env`
- State: `/var/lib/bpb-automation`
- Logs: `/var/log/bpb-automation`
- Services:
  - `bpb-api.service`
  - `bpb-autoscan.timer`
- Reverse proxy:
  - nginx + certbot OR caddy
- Public protection:
  - `/internal/*` blocked at proxy layer

## Post-Install Steps

1. Edit runtime env:

```bash
sudo nano /etc/bpb-automation/server.env
```

Set at least:
- `BPB_SCAN_CMD=<your real scan command>`
- Optional: `BPB_ENABLE_APPLY=true` and `BPB_APPLY_CMD=<your apply command>`

2. Restart API:

```bash
sudo systemctl restart bpb-api.service
```

3. Check status:

```bash
systemctl status bpb-api.service bpb-autoscan.timer --no-pager
```

4. Open dashboard:

```text
https://scan.example.com
```

## Correct Run Commands (Manual/Debug)

For packaged VPS install, do not run `dart run ...` in `/opt`.  
Use the installed executable:

```bash
sudo -u bpb /opt/bpb-automation/server/current/bin/bpb_api \
  --host 127.0.0.1 \
  --port 8787 \
  --state-dir /var/lib/bpb-automation \
  --log-dir /var/log/bpb-automation \
  --internal-token "CHANGE_ME" \
  --allowed-trigger-ips "127.0.0.1,::1" \
  --scan-cmd "YOUR_REAL_SCAN_COMMAND"
```

Web UI is static content under `/opt/bpb-automation/web/current` and is served by nginx/caddy. There is no separate web process to run.

## Optional Web Login (JWT)

Enable API login for browser clients:

```bash
sudo -u bpb /opt/bpb-automation/server/current/bin/bpb_api \
  ... \
  --web-auth-username admin \
  --web-auth-password "CHANGE_ME" \
  --jwt-secret "LONG_RANDOM_SECRET"
```

Notes:
- When enabled, `/api/*` requires Bearer JWT except `/api/auth/login` and `/api/auth/status`.
- Password is stored hashed+salted in `state-dir/web_auth.json`.

## Uninstall

Remove services and installed files:

```bash
curl -fsSL https://raw.githubusercontent.com/deadman7412/bpb-automation/main/backend/deploy/vps/uninstall_server.sh \
  | sudo bash
```

Keep state/log/config:

```bash
curl -fsSL https://raw.githubusercontent.com/deadman7412/bpb-automation/main/backend/deploy/vps/uninstall_server.sh \
  | sudo bash -s -- --keep-data
```

## TLS Troubleshooting (nginx + certbot)

If certbot fails with timeout:
1. Confirm domain A record points to VPS public IP.
2. Confirm inbound TCP/80 is open in cloud firewall/security group.
3. Retry:

```bash
sudo certbot --nginx -d scan.example.com --agree-tos -m admin@example.com --redirect
```
