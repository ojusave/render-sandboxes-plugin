#!/usr/bin/env bash
# Build a filesystem snapshot that already contains the Cursor CLI.
# Run this on an admin machine. It does not belong in the controller image.
set -euo pipefail

: "${RENDER_API_KEY:?}"
: "${RENDER_WORKSPACE:?}"

RENDER_BIN="${RENDER_BIN:-render}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
SANDBOX_ID=""

fail() {
  echo "snapshot failed: $*" >&2
  if [ -n "${SANDBOX_ID}" ]; then
    "${RENDER_BIN}" ea sandboxes stop "${SANDBOX_ID}" --confirm >/dev/null 2>&1 || true
  fi
  exit 1
}

json_field() {
  local field="$1"
  python3 -c 'import json,sys
raw=sys.stdin.read()
start=raw.find("{")
if start < 0:
    raise SystemExit("missing JSON")
print(json.JSONDecoder().raw_decode(raw, start)[0][sys.argv[1]])' "${field}"
}

wait_running() {
  local id="$1" status="" _
  for _ in $(seq 1 60); do
    status="$("${RENDER_BIN}" ea sandboxes list --status creating --status running --status errored -o json \
      | SID="${id}" python3 -c 'import json,os,sys
rows=json.load(sys.stdin)
sid=os.environ["SID"]
match=[r for r in rows if r.get("id")==sid]
print(match[0]["status"] if match else "missing")')"
    case "${status}" in
      running) return 0 ;;
      errored|terminated) return 1 ;;
    esac
    sleep "${POLL_SECONDS:-2}"
  done
  return 1
}

wait_snapshot() {
  local id="$1" status="" _
  for _ in $(seq 1 60); do
    status="$("${RENDER_BIN}" ea sandboxes snapshots get "${id}" -o json | json_field status)"
    case "${status}" in
      available) return 0 ;;
      failed) return 1 ;;
    esac
    sleep "${POLL_SECONDS:-2}"
  done
  return 1
}

CREATE="$("${RENDER_BIN}" ea sandboxes create \
  --timeout=1800 \
  --network-policy=allow-all \
  -o json)" || fail "create returned non-zero"
SANDBOX_ID="$(printf '%s' "${CREATE}" | json_field id)"
echo "building snapshot in ${SANDBOX_ID}"
[[ "${SANDBOX_ID}" =~ ^sbx-[A-Za-z0-9_-]+$ ]] || fail "unexpected sandbox id"

wait_running "${SANDBOX_ID}" || fail "sandbox ${SANDBOX_ID} did not reach running"
"${RENDER_BIN}" ea sandboxes copy "${ROOT}/bootstrap-worker.sh" "${SANDBOX_ID}:/tmp/bootstrap-worker.sh" \
  || fail "copy bootstrap failed"
"${RENDER_BIN}" ea sandboxes exec "${SANDBOX_ID}" -- bash /tmp/bootstrap-worker.sh \
  || fail "bootstrap failed"

SNAP="$("${RENDER_BIN}" ea sandboxes snapshots create "${SANDBOX_ID}" --kind filesystem -o json)" \
  || fail "snapshot create failed"
SNAPSHOT_ID="$(printf '%s' "${SNAP}" | json_field id)"
wait_snapshot "${SNAPSHOT_ID}" || fail "snapshot ${SNAPSHOT_ID} did not become available"
"${RENDER_BIN}" ea sandboxes stop "${SANDBOX_ID}" --confirm >/dev/null
echo "snapshot ${SNAPSHOT_ID}"
