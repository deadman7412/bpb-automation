#!/usr/bin/env bash
set -euo pipefail

WORKSPACE=""
ENV_FILE=""
INTERVAL_HOURS="${INTERVAL_HOURS:-6}"
LOG_DIR="${LOG_DIR:-$HOME/Library/Logs/bpb-automation}"
LABEL="com.bpb.automation.autoscan"
PLIST_DST="$HOME/Library/LaunchAgents/$LABEL.plist"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLIST_TEMPLATE="$SCRIPT_DIR/com.bpb.automation.autoscan.plist"

usage() {
  cat <<EOF
Usage: install-launchd.sh --workspace <path> --env-file <path> [--interval-hours <n>] [--log-dir <path>]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace) WORKSPACE="${2:-}"; shift 2 ;;
    --env-file) ENV_FILE="${2:-}"; shift 2 ;;
    --interval-hours) INTERVAL_HOURS="${2:-}"; shift 2 ;;
    --log-dir) LOG_DIR="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

[[ -n "$WORKSPACE" ]] || { echo "--workspace is required" >&2; exit 1; }
[[ -n "$ENV_FILE" ]] || { echo "--env-file is required" >&2; exit 1; }
[[ -f "$PLIST_TEMPLATE" ]] || { echo "Template not found: $PLIST_TEMPLATE" >&2; exit 1; }
[[ -d "$WORKSPACE" ]] || { echo "Workspace not found: $WORKSPACE" >&2; exit 1; }
[[ -f "$ENV_FILE" ]] || { echo "Env file not found: $ENV_FILE" >&2; exit 1; }
[[ "$INTERVAL_HOURS" =~ ^[0-9]+$ ]] || { echo "--interval-hours must be integer" >&2; exit 1; }
(( INTERVAL_HOURS >= 1 )) || { echo "--interval-hours must be >= 1" >&2; exit 1; }

mkdir -p "$HOME/Library/LaunchAgents" "$LOG_DIR"

INTERVAL_SECONDS=$((INTERVAL_HOURS * 3600))
python3 -c "
import pathlib
import sys

template = pathlib.Path(sys.argv[1]).read_text()
pairs = list(zip(sys.argv[2::2], sys.argv[3::2]))
for key, value in pairs:
    template = template.replace(key, value)
pathlib.Path(sys.argv[-1]).write_text(template)
" "$PLIST_TEMPLATE" \
  "__WORKSPACE__" "$WORKSPACE" \
  "__ENV_FILE__" "$ENV_FILE" \
  "__INTERVAL_SECONDS__" "$INTERVAL_SECONDS" \
  "__LOG_DIR__" "$LOG_DIR" \
  "$PLIST_DST"

launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_DST"
launchctl enable "gui/$(id -u)/$LABEL"
launchctl kickstart -k "gui/$(id -u)/$LABEL"

echo "Installed $LABEL"
echo "Plist: $PLIST_DST"
echo "Interval: ${INTERVAL_HOURS}h"
