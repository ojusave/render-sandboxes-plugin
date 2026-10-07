#!/usr/bin/env bash
# Create, inspect, execute, copy, snapshot, and stop Render Sandboxes.
set -euo pipefail

RENDER_BIN="${RENDER_BIN:-render}"
POLL_SECONDS="${POLL_SECONDS:-2}"
POLL_ATTEMPTS="${POLL_ATTEMPTS:-60}"

die() {
  echo "error: $*" >&2
  exit 1
}

usage() {
  cat >&2 <<'EOF'
usage:
  sandbox.sh groups
  sandbox.sh create --timeout SECONDS [--network-policy allow-all|deny-all] [--snapshot-id snp-...]
  sandbox.sh inspect [sbx-...]
  sandbox.sh exec sbx-... -- COMMAND...
  sandbox.sh copy SRC DST
  sandbox.sh snapshot sbx-... [--kind filesystem|runtime]
  sandbox.sh stop sbx-...
EOF
  exit 2
}

require_sandbox() {
  [[ "${1:-}" =~ ^sbx-[A-Za-z0-9_-]+$ ]] || die "expected a sandbox id starting with sbx-"
}

sandbox_status() {
  local id="$1"
  "${RENDER_BIN}" ea sandboxes list --status creating --status running --status errored --status terminated -o json \
    | SID="${id}" python3 -c 'import json,os,sys
payload=json.load(sys.stdin)
rows=payload if isinstance(payload, list) else payload.get("sandboxes", [])
sid=os.environ["SID"]
match=[r for r in rows if r.get("id")==sid]
print(match[0]["status"] if match else "missing")'
}

wait_running() {
  local id="$1" status="" _
  for _ in $(seq 1 "${POLL_ATTEMPTS}"); do
    status="$(sandbox_status "${id}")"
    case "${status}" in
      running) return 0 ;;
      errored|terminated) return 1 ;;
    esac
    sleep "${POLL_SECONDS}"
  done
  return 1
}

stop_sandbox() {
  "${RENDER_BIN}" ea sandboxes stop "$1" --confirm -o json >/dev/null || true
}

cmd_groups() {
  "${RENDER_BIN}" ea sandbox-groups list -o json
}

cmd_create() {
  local timeout="" policy="deny-all" snapshot=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --timeout) timeout="$2"; shift 2 ;;
      --network-policy) policy="$2"; shift 2 ;;
      --snapshot-id) snapshot="$2"; shift 2 ;;
      *) die "unknown create option: $1" ;;
    esac
  done
  [[ "${timeout}" =~ ^[0-9]+$ ]] || die "create requires --timeout SECONDS"
  [ "${timeout}" -ge 1 ] && [ "${timeout}" -le 86400 ] || die "timeout must be 1..86400"
  [[ "${policy}" == "allow-all" || "${policy}" == "deny-all" ]] || die "invalid network policy"
  local args=(ea sandboxes create --timeout "${timeout}" --network-policy "${policy}" -o json)
  if [ -n "${snapshot}" ]; then
    [[ "${snapshot}" =~ ^snp-[A-Za-z0-9_-]+$ ]] || die "expected a snapshot id starting with snp-"
    args+=(--snapshot-id "${snapshot}")
  fi
  local created id
  created="$("${RENDER_BIN}" "${args[@]}")" || die "create failed"
  id="$(printf '%s' "${created}" | python3 -c 'import json,sys
raw=sys.stdin.read()
start=raw.find("{")
print(json.JSONDecoder().raw_decode(raw, start)[0]["id"])')"
  require_sandbox "${id}"
  if ! wait_running "${id}"; then
    stop_sandbox "${id}"
    die "sandbox ${id} did not reach running"
  fi
  printf '{"id":"%s","status":"running"}\n' "${id}"
}

cmd_inspect() {
  if [ $# -eq 0 ]; then
    "${RENDER_BIN}" ea sandboxes list -o json
    return
  fi
  require_sandbox "$1"
  "${RENDER_BIN}" ea sandboxes list --all -o json \
    | SID="$1" python3 -c 'import json,os,sys
payload=json.load(sys.stdin)
rows=payload if isinstance(payload, list) else payload.get("sandboxes", [])
sid=os.environ["SID"]
match=[r for r in rows if r.get("id")==sid]
print(json.dumps(match[0] if match else {"id":sid,"status":"missing"}))'
}

cmd_exec() {
  [ $# -ge 3 ] && [ "$2" = "--" ] || usage
  require_sandbox "$1"
  local id="$1"
  shift 2
  wait_running "${id}" || die "sandbox ${id} is not running"
  "${RENDER_BIN}" ea sandboxes exec "${id}" -- "$@"
}

cmd_copy() {
  [ $# -eq 2 ] || usage
  "${RENDER_BIN}" ea sandboxes copy "$1" "$2"
}

cmd_snapshot() {
  require_sandbox "$1"
  local id="$1" kind="filesystem"
  shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --kind) kind="$2"; shift 2 ;;
      *) die "unknown snapshot option: $1" ;;
    esac
  done
  [[ "${kind}" == "filesystem" || "${kind}" == "runtime" ]] || die "invalid snapshot kind"
  wait_running "${id}" || die "sandbox ${id} is not running"
  local created snap status _
  created="$("${RENDER_BIN}" ea sandboxes snapshots create "${id}" --kind "${kind}" -o json)"
  snap="$(printf '%s' "${created}" | python3 -c 'import json,sys
raw=sys.stdin.read()
start=raw.find("{")
print(json.JSONDecoder().raw_decode(raw, start)[0]["id"])')"
  [[ "${snap}" =~ ^snp-[A-Za-z0-9_-]+$ ]] || die "unexpected snapshot id"
  for _ in $(seq 1 "${POLL_ATTEMPTS}"); do
    status="$("${RENDER_BIN}" ea sandboxes snapshots get "${snap}" -o json \
      | python3 -c 'import json,sys
raw=sys.stdin.read()
start=raw.find("{")
print(json.JSONDecoder().raw_decode(raw, start)[0]["status"])')"
    case "${status}" in
      available)
        printf '{"id":"%s","status":"available","sandbox_id":"%s"}\n' "${snap}" "${id}"
        return 0
        ;;
      failed) die "snapshot ${snap} failed" ;;
    esac
    sleep "${POLL_SECONDS}"
  done
  die "snapshot ${snap} is not available yet"
}

cmd_stop() {
  require_sandbox "$1"
  "${RENDER_BIN}" ea sandboxes stop "$1" --confirm -o json
}

[ $# -ge 1 ] || usage
case "$1" in
  groups) shift; [ $# -eq 0 ] || usage; cmd_groups ;;
  create) shift; cmd_create "$@" ;;
  inspect) shift; [ $# -le 1 ] || usage; cmd_inspect "$@" ;;
  exec) shift; cmd_exec "$@" ;;
  copy) shift; cmd_copy "$@" ;;
  snapshot) shift; cmd_snapshot "$@" ;;
  stop) shift; [ $# -eq 1 ] || usage; cmd_stop "$@" ;;
  *) usage ;;
esac
