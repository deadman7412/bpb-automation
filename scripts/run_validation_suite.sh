#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

log() {
  printf "[validate] %s\n" "$1"
}

pass() {
  printf "[validate][PASS] %s\n" "$1"
}

fail() {
  printf "[validate][FAIL] %s\n" "$1"
  exit 1
}

log "Running backend analyzer"
(cd backend && dart analyze)
pass "backend analyze"

log "Running flutter analyzer"
flutter analyze --no-fatal-infos
pass "flutter analyze"

log "Running flutter tests"
flutter test
pass "flutter test"

log "Running isolated backend/API smoke checks"
TMP_ROOT="$(mktemp -d /tmp/bpb-validate-XXXXXX)"
STATE_DIR="$TMP_ROOT/state"
LOG_DIR="$TMP_ROOT/logs"
mkdir -p "$STATE_DIR" "$LOG_DIR"

cleanup() {
  if [[ -n "${API_PID:-}" ]]; then
    kill "$API_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

PORT=8799
(
  cd backend
  dart run bin/bpb_api.dart \
    --host 127.0.0.1 \
    --port "$PORT" \
    --state-dir "$STATE_DIR" \
    --log-dir "$LOG_DIR" \
    --internal-token testtoken \
    --allowed-trigger-ips '127.0.0.1' \
    --scan-cmd 'sleep 1; printf "{\"status\":\"success\",\"phase1_passed\":1,\"phase2_tested\":1,\"working_ips\":[\"1.1.1.1\"]}"'
) >/tmp/bpb-validate-api.log 2>&1 &
API_PID=$!
sleep 1.2

code="$(curl -s -o /tmp/bpb-path.txt -w "%{http_code}" \
  "http://127.0.0.1:${PORT}/api/results/%2e%2e%2f%2e%2e%2fetc%2fpasswd")"
[[ "$code" == "400" ]] || fail "path traversal guard"
pass "path traversal guard"

curl -s -X POST -H 'x-internal-token: testtoken' \
  "http://127.0.0.1:${PORT}/internal/scheduler/run?trigger=api" >/tmp/bpb-r1.json &
sleep 0.1
code="$(curl -s -o /tmp/bpb-r2.json -w "%{http_code}" -X POST \
  -H 'x-internal-token: testtoken' \
  "http://127.0.0.1:${PORT}/internal/scheduler/run?trigger=api")"
[[ "$code" == "409" ]] || fail "trigger race conflict"
pass "trigger race conflict"

acao="$(curl -s -D - -o /dev/null -H 'Origin: https://evil.example' \
  "http://127.0.0.1:${PORT}/api/status" \
  | tr -d '\r' | awk -F': ' 'tolower($1)=="access-control-allow-origin"{print $2}')"
[[ -z "$acao" ]] || fail "cors default deny"
pass "cors default deny"

pass "all validation checks"
log "Validation suite completed successfully"
