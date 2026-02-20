#!/usr/bin/env bash
set -euo pipefail

REPO="${REPO:-deadman7412/bpb-automation}"
DOMAIN="${DOMAIN:-}"
CERTBOT_EMAIL="${CERTBOT_EMAIL:-}"
INSTALL_ROOT="${INSTALL_ROOT:-/opt/bpb-automation/server}"
STATE_DIR="${STATE_DIR:-/var/lib/bpb-automation}"
LOG_DIR="${LOG_DIR:-/var/log/bpb-automation}"
CONFIG_DIR="${CONFIG_DIR:-/etc/bpb-automation}"
ENV_FILE="${ENV_FILE:-$CONFIG_DIR/server.env}"
API_PORT="${API_PORT:-8787}"
TIMER_INTERVAL_HOURS="${TIMER_INTERVAL_HOURS:-6}"
NON_INTERACTIVE="${NON_INTERACTIVE:-false}"

usage() {
  cat <<EOF
Usage: sudo bash install_or_update_server.sh [options]

Options:
  --domain <name>                 Domain or subdomain for dashboard/API
  --email <addr>                  Email for Let's Encrypt/certbot notices (nginx mode)
  --repo <owner/repo>             GitHub repo (default: $REPO)
  --install-root <path>           Install root (default: $INSTALL_ROOT)
  --state-dir <path>              Runtime state dir (default: $STATE_DIR)
  --log-dir <path>                Runtime log dir (default: $LOG_DIR)
  --api-port <port>               Local API port (default: $API_PORT)
  --timer-hours <hours>           Scheduler interval (default: $TIMER_INTERVAL_HOURS)
  --non-interactive               Fail instead of prompting
  -h, --help                      Show help
EOF
}

log() { printf "[install] %s\n" "$1"; }
die() { printf "[install][error] %s\n" "$1" >&2; exit 1; }

require_root() {
  [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "Run as root (sudo)."
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --domain) DOMAIN="${2:-}"; shift 2 ;;
      --email) CERTBOT_EMAIL="${2:-}"; shift 2 ;;
      --repo) REPO="${2:-}"; shift 2 ;;
      --install-root) INSTALL_ROOT="${2:-}"; shift 2 ;;
      --state-dir) STATE_DIR="${2:-}"; shift 2 ;;
      --log-dir) LOG_DIR="${2:-}"; shift 2 ;;
      --api-port) API_PORT="${2:-}"; shift 2 ;;
      --timer-hours) TIMER_INTERVAL_HOURS="${2:-}"; shift 2 ;;
      --non-interactive) NON_INTERACTIVE="true"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown argument: $1" ;;
    esac
  done
}

install_packages() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y curl jq tar ca-certificates lsof
}

detect_web_stack() {
  local has_nginx="false" has_caddy="false"
  command -v nginx >/dev/null 2>&1 && has_nginx="true"
  command -v caddy >/dev/null 2>&1 && has_caddy="true"
  local caddy_active="false"
  systemctl is-active --quiet caddy && caddy_active="true" || true

  if [[ "$caddy_active" == "true" ]]; then
    WEB_STACK="caddy"
  elif [[ "$has_nginx" == "true" ]]; then
    WEB_STACK="nginx"
  else
    WEB_STACK="nginx"
  fi
  log "Web stack: $WEB_STACK"
}

check_port_80() {
  local port_users
  port_users="$(lsof -iTCP:80 -sTCP:LISTEN -n -P 2>/dev/null || true)"
  if [[ -z "$port_users" ]]; then
    return 0
  fi
  if echo "$port_users" | grep -Eq 'nginx|caddy'; then
    return 0
  fi
  printf "%s\n" "$port_users"
  die "Port 80 is busy by a non-nginx/caddy process."
}

prompt_domain() {
  if [[ -n "$DOMAIN" ]]; then
    return 0
  fi
  if [[ "$NON_INTERACTIVE" == "true" ]]; then
    die "--domain is required in non-interactive mode."
  fi
  read -r -p "Enter your domain or subdomain (e.g. scan.example.com): " DOMAIN
  [[ -n "$DOMAIN" ]] || die "Domain is required."
}

prompt_certbot_email_if_needed() {
  if [[ "$WEB_STACK" != "nginx" ]]; then
    return 0
  fi
  if [[ -n "$CERTBOT_EMAIL" ]]; then
    return 0
  fi
  if [[ "$NON_INTERACTIVE" == "true" ]]; then
    die "--email is required in non-interactive mode when using nginx/certbot."
  fi
  read -r -p "Enter email for Let's Encrypt notices: " CERTBOT_EMAIL
  [[ -n "$CERTBOT_EMAIL" ]] || die "Email is required for certbot registration."
}

fetch_latest_server_package() {
  local api_url="https://api.github.com/repos/$REPO/releases/latest"
  log "Fetching latest release from $REPO"
  local release_json
  release_json="$(curl -fsSL "$api_url")" || die "Failed to fetch release metadata."
  RELEASE_TAG="$(echo "$release_json" | jq -r '.tag_name')"
  ASSET_URL="$(echo "$release_json" | jq -r '.assets[] | select(.name | test("^BPB-Automation-Server-Linux-x64-.*\\.tar\\.gz$")) | .browser_download_url' | head -n1)"
  CHECKSUM_URL="$(echo "$release_json" | jq -r '.assets[] | select(.name | test("^BPB-Automation-Server-Linux-x64-.*\\.tar\\.gz\\.sha256$")) | .browser_download_url' | head -n1)"
  [[ -n "$ASSET_URL" && "$ASSET_URL" != "null" ]] || die "Server package asset not found in latest release."
  [[ -n "$CHECKSUM_URL" && "$CHECKSUM_URL" != "null" ]] || die "Server package checksum asset not found in latest release."

  local tmp_pkg="/tmp/bpb-server-${RELEASE_TAG}.tar.gz"
  local tmp_checksum="/tmp/bpb-server-${RELEASE_TAG}.tar.gz.sha256"
  curl -fL "$ASSET_URL" -o "$tmp_pkg" || die "Failed to download server package."
  curl -fL "$CHECKSUM_URL" -o "$tmp_checksum" || die "Failed to download checksum file."
  local expected_sha actual_sha
  expected_sha="$(awk '{print $1}' "$tmp_checksum" | tr -d '\r\n')"
  [[ -n "$expected_sha" ]] || die "Checksum file is empty or invalid."
  actual_sha="$(sha256sum "$tmp_pkg" | awk '{print $1}')"
  [[ "$actual_sha" == "$expected_sha" ]] || die "Checksum verification failed for downloaded server package."
  PACKAGE_PATH="$tmp_pkg"
  log "Downloaded package: $PACKAGE_PATH"
}

install_server_files() {
  local release_dir="$INSTALL_ROOT/releases/$RELEASE_TAG"
  mkdir -p "$release_dir" "$INSTALL_ROOT/releases"
  tar -xzf "$PACKAGE_PATH" -C "$release_dir" --strip-components=1
  ln -sfn "$release_dir" "$INSTALL_ROOT/current"
  log "Installed server files at $INSTALL_ROOT/current"
}

setup_user_and_dirs() {
  id -u bpb >/dev/null 2>&1 || useradd --system --home "$INSTALL_ROOT" --shell /usr/sbin/nologin bpb
  mkdir -p "$STATE_DIR" "$LOG_DIR" "$CONFIG_DIR"
  chown -R bpb:bpb "$STATE_DIR" "$LOG_DIR" "$INSTALL_ROOT"
}

generate_env_if_missing() {
  if [[ -f "$ENV_FILE" ]]; then
    return 0
  fi
  local token
  token="$(openssl rand -hex 24 2>/dev/null || od -An -N24 -tx1 /dev/urandom | tr -d ' \n')"
  [[ -n "$token" ]] || die "Failed to generate BPB internal token."
  cat >"$ENV_FILE" <<EOF
# BPB server runtime config
BPB_HOST_LABEL=$(hostname -s)
BPB_SCAN_CMD=
BPB_ENABLE_APPLY=false
BPB_APPLY_CMD=
BPB_INTERNAL_TOKEN=$token
BPB_SCAN_RETRIES=3
BPB_APPLY_RETRIES=3
BPB_MIN_WORKING_IPS=1
BPB_INITIAL_RETRY_DELAY_MS=1000
BPB_MAX_RETRY_DELAY_MS=60000
EOF
  chmod 600 "$ENV_FILE"
  chown bpb:bpb "$ENV_FILE"
  log "Created $ENV_FILE (edit BPB_SCAN_CMD before enabling scheduled updates)."
}

write_systemd_units() {
  cat >/etc/systemd/system/bpb-api.service <<EOF
[Unit]
Description=BPB Automation API
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=bpb
Group=bpb
EnvironmentFile=$ENV_FILE
ExecStart=$INSTALL_ROOT/current/bin/bpb_api --host 127.0.0.1 --port $API_PORT --state-dir $STATE_DIR --log-dir $LOG_DIR --internal-token \${BPB_INTERNAL_TOKEN} --allowed-trigger-ips 127.0.0.1,::1 --scan-retries \${BPB_SCAN_RETRIES} --apply-retries \${BPB_APPLY_RETRIES} --min-working-ips \${BPB_MIN_WORKING_IPS} --initial-retry-delay-ms \${BPB_INITIAL_RETRY_DELAY_MS} --max-retry-delay-ms \${BPB_MAX_RETRY_DELAY_MS} --host-label \${BPB_HOST_LABEL}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

  cat >/etc/systemd/system/bpb-autoscan.service <<EOF
[Unit]
Description=BPB Automation scheduled trigger
After=bpb-api.service
Wants=bpb-api.service

[Service]
Type=oneshot
EnvironmentFile=$ENV_FILE
ExecStart=/usr/bin/curl -fsS -X POST -H "x-internal-token: \${BPB_INTERNAL_TOKEN}" http://127.0.0.1:$API_PORT/internal/scheduler/run?trigger=scheduled
EOF

  cat >/etc/systemd/system/bpb-autoscan.timer <<EOF
[Unit]
Description=Run BPB autoscan every $TIMER_INTERVAL_HOURS hour(s)

[Timer]
OnBootSec=2min
OnUnitActiveSec=${TIMER_INTERVAL_HOURS}h
AccuracySec=1min
Persistent=true
Unit=bpb-autoscan.service

[Install]
WantedBy=timers.target
EOF
}

setup_nginx() {
  apt-get install -y nginx certbot python3-certbot-nginx
  cat >/etc/nginx/sites-available/bpb-automation.conf <<EOF
server {
  listen 80;
  server_name $DOMAIN;

  location /internal/ {
    return 403;
  }

  location / {
    proxy_pass http://127.0.0.1:$API_PORT;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
  }
}
EOF
  ln -sf /etc/nginx/sites-available/bpb-automation.conf /etc/nginx/sites-enabled/bpb-automation.conf
  nginx -t
  systemctl enable --now nginx
  certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$CERTBOT_EMAIL" --redirect
}

setup_caddy() {
  if ! command -v caddy >/dev/null 2>&1; then
    apt-get install -y caddy
  fi
  mkdir -p /etc/caddy
  cat >/etc/caddy/Caddyfile <<EOF
$DOMAIN {
  @internal path /internal/*
  respond @internal 403
  reverse_proxy 127.0.0.1:$API_PORT
}
EOF
  systemctl enable --now caddy
  systemctl reload caddy || true
}

main() {
  parse_args "$@"
  require_root
  install_packages
  prompt_domain
  detect_web_stack
  prompt_certbot_email_if_needed
  check_port_80
  fetch_latest_server_package
  install_server_files
  setup_user_and_dirs
  generate_env_if_missing
  write_systemd_units
  systemctl daemon-reload
  systemctl enable --now bpb-api.service
  systemctl enable --now bpb-autoscan.timer

  if [[ "$WEB_STACK" == "caddy" ]]; then
    setup_caddy
  else
    setup_nginx
  fi

  log "Install/update complete."
  log "Edit $ENV_FILE with real BPB_SCAN_CMD and (optional) BPB_APPLY_CMD."
  log "Then restart API: systemctl restart bpb-api.service"
  log "Status: systemctl status bpb-api.service bpb-autoscan.timer --no-pager"
}

main "$@"
