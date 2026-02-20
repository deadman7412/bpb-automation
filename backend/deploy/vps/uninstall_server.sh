#!/usr/bin/env bash
set -euo pipefail

INSTALL_ROOT="${INSTALL_ROOT:-/opt/bpb-automation/server}"
STATE_DIR="${STATE_DIR:-/var/lib/bpb-automation}"
LOG_DIR="${LOG_DIR:-/var/log/bpb-automation}"
CONFIG_DIR="${CONFIG_DIR:-/etc/bpb-automation}"
REMOVE_NGINX_SITE="${REMOVE_NGINX_SITE:-true}"
NON_INTERACTIVE="${NON_INTERACTIVE:-false}"

usage() {
  cat <<EOF
Usage: sudo bash uninstall_server.sh [options]

Options:
  --keep-data                   Keep runtime data/log/config directories
  --keep-nginx-site             Keep /etc/nginx/sites-available/bpb-automation.conf
  --non-interactive             Do not prompt for confirmation
  -h, --help                    Show help
EOF
}

log() { printf "[uninstall] %s\n" "$1"; }
die() { printf "[uninstall][error] %s\n" "$1" >&2; exit 1; }

require_root() {
  [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "Run as root (sudo)."
}

KEEP_DATA="false"
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --keep-data) KEEP_DATA="true"; shift ;;
      --keep-nginx-site) REMOVE_NGINX_SITE="false"; shift ;;
      --non-interactive) NON_INTERACTIVE="true"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown argument: $1" ;;
    esac
  done
}

confirm() {
  if [[ "$NON_INTERACTIVE" == "true" ]]; then
    log "Non-interactive mode enabled; skipping prompt."
    return 0
  fi
  if [[ -r /dev/tty ]]; then
    printf "This will remove BPB server services and install files. Continue? [y/N] " >/dev/tty
    read -r ans </dev/tty
  else
    die "Interactive confirmation requires a TTY. Re-run with --non-interactive if intentional."
  fi
  [[ "$ans" == "y" || "$ans" == "Y" ]] || die "Aborted."
}

stop_services() {
  log "Stopping/disabling BPB services..."
  systemctl disable --now bpb-autoscan.timer >/dev/null 2>&1 || true
  systemctl disable --now bpb-autoscan.service >/dev/null 2>&1 || true
  systemctl disable --now bpb-api.service >/dev/null 2>&1 || true
  log "Service stop/disable step complete."
}

remove_units() {
  log "Removing BPB systemd unit files..."
  rm -f /etc/systemd/system/bpb-api.service
  rm -f /etc/systemd/system/bpb-autoscan.service
  rm -f /etc/systemd/system/bpb-autoscan.timer
  systemctl daemon-reload
  log "Systemd units removed and daemon reloaded."
}

remove_nginx_site() {
  if [[ "$REMOVE_NGINX_SITE" != "true" ]]; then
    log "Keeping nginx site files (--keep-nginx-site)."
    return 0
  fi
  log "Removing nginx BPB site files..."
  rm -f /etc/nginx/sites-enabled/bpb-automation.conf
  rm -f /etc/nginx/sites-available/bpb-automation.conf
  if command -v nginx >/dev/null 2>&1; then
    nginx -t >/dev/null 2>&1 && systemctl reload nginx >/dev/null 2>&1 || true
  fi
  log "Nginx site cleanup complete."
}

remove_files() {
  log "Removing install files under $INSTALL_ROOT..."
  rm -rf "$INSTALL_ROOT"
  if [[ "$KEEP_DATA" != "true" ]]; then
    log "Removing runtime data/log/config directories..."
    rm -rf "$STATE_DIR" "$LOG_DIR" "$CONFIG_DIR"
  else
    log "Keeping runtime data/log/config directories (--keep-data)."
  fi
  log "Filesystem cleanup complete."
}

main() {
  parse_args "$@"
  require_root
  log "Starting uninstall..."
  log "Install root: $INSTALL_ROOT"
  log "State dir: $STATE_DIR"
  log "Log dir: $LOG_DIR"
  log "Config dir: $CONFIG_DIR"
  confirm
  stop_services
  remove_units
  remove_nginx_site
  remove_files
  log "Uninstall complete."
  if [[ "$KEEP_DATA" == "true" ]]; then
    log "Data preserved at: $STATE_DIR $LOG_DIR $CONFIG_DIR"
  fi
}

main "$@"
