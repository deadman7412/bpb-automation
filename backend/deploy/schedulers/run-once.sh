#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${BPB_STATE_DIR:-/var/lib/bpb-automation}"
LOG_DIR="${BPB_LOG_DIR:-/var/log/bpb-automation}"
HOST_LABEL="${BPB_HOST_LABEL:-server-host}"
UPDATE_MODE="${BPB_UPDATE_MODE:-command}"
SCAN_RETRIES="${BPB_SCAN_RETRIES:-3}"
APPLY_RETRIES="${BPB_APPLY_RETRIES:-3}"
RETRY_DELAY_MS="${BPB_RETRY_DELAY_MS:-1000}"
SCAN_CMD="${BPB_SCAN_CMD:-}"
APPLY_CMD="${BPB_APPLY_CMD:-}"
TRIGGER="${1:-scheduled}"

if [[ -z "$SCAN_CMD" ]]; then
  echo "BPB_SCAN_CMD is required" >&2
  exit 1
fi

cd /opt/bpb-automation/backend

cmd=(
  dart run bin/bpb_autoscan.dart run-once
  --state-dir "$STATE_DIR"
  --log-dir "$LOG_DIR"
  --trigger "$TRIGGER"
  --host-label "$HOST_LABEL"
  --update-mode "$UPDATE_MODE"
  --scan-retries "$SCAN_RETRIES"
  --apply-retries "$APPLY_RETRIES"
  --initial-retry-delay-ms "$RETRY_DELAY_MS"
  --scan-cmd "$SCAN_CMD"
)

if [[ -n "$APPLY_CMD" ]]; then
  cmd+=(--apply --apply-cmd "$APPLY_CMD")
fi

"${cmd[@]}"
