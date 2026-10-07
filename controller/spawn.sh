#!/usr/bin/env bash
# Start one Render Sandbox for one claimed Cursor pool request.
# The service-account key stays on the controller. The sandbox receives a
# claim session token through an env file, then the worker reads that token
# from a file inside the sandbox.
set -euo pipefail

: "${CURSOR_AGENT_WORKER_ID:?}"
: "${CURSOR_POOL:?}"
: "${CURSOR_AUTH_TOKEN:?}"
: "${CURSOR_REQUEST_ID:?}"
: "${WORKER_SNAPSHOT_ID:?}"
: "${RENDER_API_KEY:?}"
: "${RENDER_WORKSPACE:?}"

RENDER_BIN="${RENDER_BIN:-render}"
IDLE_RELEASE_TIMEOUT="${CURSOR_WORKER_IDLE_RELEASE_TIMEOUT:-600}"
SANDBOX_TIMEOUT_SECONDS="${SANDBOX_TIMEOUT_SECONDS:-7200}"
MONITOR_DIR="${MONITOR_DIR:-/tmp}"
export PATH="${PATH}:/usr/local/bin:${HOME}/.local/bin"

ENV_FILE=""
SANDBOX_ID=""

cleanup_env_file() {
  if [ -n "${ENV_FILE}" ]; then
    rm -f "${ENV_FILE}"
  fi
}
trap cleanup_env_file EXIT

release_claim() {
  if [ -z "${CURSOR_RELEASE_API_KEY:-}" ]; then
    echo "startup failed and CURSOR_RELEASE_API_KEY is unset; release ${CURSOR_REQUEST_ID} manually" >&2
    return 0
  fi
  local cfg
  cfg="$(mktemp)"
  chmod 600 "${cfg}"
  printf 'user = "%s:"\n' "${CURSOR_RELEASE_API_KEY}" > "${cfg}"
  curl --config "${cfg}" --silent --show-error --request POST \
    --url "https://api.cursor.com/v0/private-workers/claims/${CURSOR_REQUEST_ID}/release" \
    || true
  rm -f "${cfg}"
}

fail() {
  echo "spawn failed: $*" >&2
  if [ -n "${SANDBOX_ID}" ]; then
    "${RENDER_BIN}" ea sandboxes stop "${SANDBOX_ID}" --confirm >/dev/null 2>&1 || true
  fi
  release_claim
  exit 1
}

json_id() {
  python3 -c 'import json,sys
raw=sys.stdin.read()
start=raw.find("{")
if start < 0:
    raise SystemExit("missing JSON")
print(json.JSONDecoder().raw_decode(raw, start)[0]["id"])'
}

wait_until_running() {
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
    sleep 2
  done
  return 1
}

umask 077
ENV_FILE="$(mktemp)"
chmod 600 "${ENV_FILE}"
cat > "${ENV_FILE}" <<EOF
CURSOR_AGENT_WORKER_ID=${CURSOR_AGENT_WORKER_ID}
CURSOR_POOL=${CURSOR_POOL}
CURSOR_AUTH_TOKEN=${CURSOR_AUTH_TOKEN}
CURSOR_WORKER_IDLE_RELEASE_TIMEOUT=${IDLE_RELEASE_TIMEOUT}
EOF

CREATE="$("${RENDER_BIN}" ea sandboxes create \
  --snapshot-id "${WORKER_SNAPSHOT_ID}" \
  --timeout "${SANDBOX_TIMEOUT_SECONDS}" \
  --network-policy=allow-all \
  --env-file "${ENV_FILE}" \
  -o json)" || fail "create returned non-zero"
SANDBOX_ID="$(printf '%s' "${CREATE}" | json_id)"
echo "sandbox ${SANDBOX_ID} for ${CURSOR_REQUEST_ID}"
[[ "${SANDBOX_ID}" =~ ^sbx-[A-Za-z0-9_-]+$ ]] || fail "unexpected sandbox id"

wait_until_running "${SANDBOX_ID}" || fail "sandbox ${SANDBOX_ID} did not reach running"
rm -f "${ENV_FILE}"
ENV_FILE=""

# The remote shell expands the sandbox environment. The token is not interpolated here.
"${RENDER_BIN}" ea sandboxes exec "${SANDBOX_ID}" -- bash -lc '
  set -euo pipefail
  umask 077
  mkdir -p /run/cursor /workspace
  printf "%s" "$CURSOR_AUTH_TOKEN" > /run/cursor/token
  unset CURSOR_AUTH_TOKEN
  nohup agent worker \
    --pool "$CURSOR_POOL" \
    --worker-dir /workspace \
    --idle-release-timeout "$CURSOR_WORKER_IDLE_RELEASE_TIMEOUT" \
    --clone-git-repos \
    --auth-token-file /run/cursor/token \
    start >> /var/log/cursor-worker.log 2>&1 &
  echo $! > /var/run/cursor-worker.pid
' || fail "worker start exec failed"

"${RENDER_BIN}" ea sandboxes exec "${SANDBOX_ID}" -- bash -lc \
  'ps -p "$(cat /var/run/cursor-worker.pid)" >/dev/null' \
  || fail "worker process did not stay up"

if [ "${CURSOR_RENDER_MONITOR:-1}" != "0" ]; then
  cat > "${MONITOR_DIR}/cursor-render-monitor-${SANDBOX_ID}.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
id='${SANDBOX_ID}'
while ${RENDER_BIN} ea sandboxes exec "\$id" -- bash -lc 'ps -p "\$(cat /var/run/cursor-worker.pid)" >/dev/null'; do
  sleep 15
done
${RENDER_BIN} ea sandboxes stop "\$id" --confirm >/dev/null 2>&1 || true
EOF
  chmod +x "${MONITOR_DIR}/cursor-render-monitor-${SANDBOX_ID}.sh"
  nohup "${MONITOR_DIR}/cursor-render-monitor-${SANDBOX_ID}.sh" \
    >>"${MONITOR_DIR}/cursor-render-monitor.log" 2>&1 &
fi

exit 0
