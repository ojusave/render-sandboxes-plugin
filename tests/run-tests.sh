#!/usr/bin/env bash
# Manifest, lifecycle, spawn, and doctor tests. No live Render calls.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 "${ROOT}/scripts/validate_plugin.py"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_not_contains() {
  local file="$1" needle="$2"
  if grep -F -q -- "${needle}" "${file}"; then
    fail "${file} contains secret material"
  fi
}

new_fake_render() {
  local dir="$1"
  cat > "${dir}/render" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${FAKE_LOG}"
prev=""
for arg in "$@"; do
  if [ "${prev}" = "--env-file" ]; then
    cp "${arg}" "${FAKE_ENV_COPY}"
  fi
  prev="${arg}"
done
case "$*" in
  "--version")
    echo "render v2.28.0"
    ;;
  *"sandboxes create"*)
    [ "${FAKE_CREATE_FAIL:-0}" = "1" ] && exit 1
    echo '{"id":"sbx-test"}'
    ;;
  *"sandboxes list"*)
    if [ "${FAKE_STATUS:-running}" = "delay" ]; then
      echo '[]'
      echo running > "${FAKE_STATUS_FILE}"
      exit 0
    fi
    status="${FAKE_STATUS:-running}"
    printf '[{"id":"sbx-test","status":"%s"}]\n' "${status}"
    ;;
  *"snapshots create"*)
    echo '{"id":"snp-test","status":"creating"}'
    ;;
  *"snapshots get"*)
    echo '{"id":"snp-test","status":"available"}'
    ;;
  *"sandboxes exec"*|*"sandboxes copy"*|*"sandboxes stop"*|*"sandbox-groups list"*)
    [ "${FAKE_EXEC_FAIL:-0}" = "1" ] && [[ "$*" == *"sandboxes exec"* ]] && exit 1
    echo '{"ok":true}'
    ;;
  *)
    echo "unexpected render args: $*" >&2
    exit 1
    ;;
esac
EOF
  chmod +x "${dir}/render"
}

new_fake_agent() {
  local dir="$1" mode="$2"
  cat > "${dir}/agent" <<EOF
#!/usr/bin/env bash
if [ "\$*" = "worker controller --help" ]; then
  if [ "${mode}" = "spawn" ]; then
    echo "--spawn"
    exit 0
  fi
  echo "no controller"
  exit 0
fi
exit 1
EOF
  chmod +x "${dir}/agent"
}

new_fake_curl() {
  local dir="$1"
  cat > "${dir}/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${FAKE_CURL_LOG}"
exit 0
EOF
  chmod +x "${dir}/curl"
}

setup_dir() {
  DIR="$(mktemp -d)"
  unset FAKE_CREATE_FAIL FAKE_EXEC_FAIL FAKE_STATUS
  export FAKE_LOG="${DIR}/render.log"
  export FAKE_CURL_LOG="${DIR}/curl.log"
  export FAKE_ENV_COPY="${DIR}/env.copy"
  : > "${FAKE_LOG}"
  : > "${FAKE_CURL_LOG}"
  new_fake_render "${DIR}"
  new_fake_curl "${DIR}"
  export PATH="${DIR}:${PATH}"
  export RENDER_BIN="${DIR}/render"
  export POLL_SECONDS=0
  export POLL_ATTEMPTS=3
}

test_sandbox_roundtrip() {
  local output
  setup_dir
  output="$(bash "${ROOT}/scripts/sandbox.sh" create --timeout 60 --network-policy deny-all)"
  printf '%s' "${output}" | grep -q '"id":"sbx-test"' || fail "create output"
  bash "${ROOT}/scripts/sandbox.sh" exec sbx-test -- echo hello >/dev/null
  bash "${ROOT}/scripts/sandbox.sh" copy ./a.txt sbx-test:/workspace/a.txt >/dev/null
  bash "${ROOT}/scripts/sandbox.sh" snapshot sbx-test >/dev/null
  bash "${ROOT}/scripts/sandbox.sh" stop sbx-test >/dev/null
  grep -q 'stop sbx-test --confirm' "${FAKE_LOG}" || fail "stop did not confirm"
  grep -q 'network-policy deny-all' "${FAKE_LOG}" || fail "network policy was not forwarded"
  rm -rf "${DIR}"
}

test_sandbox_create_failure_stops() {
  setup_dir
  export FAKE_STATUS=errored
  if bash "${ROOT}/scripts/sandbox.sh" create --timeout 60 >/dev/null 2>"${DIR}/err"; then
    fail "errored sandbox should fail"
  fi
  grep -q 'stop sbx-test --confirm' "${FAKE_LOG}" || fail "failed create was not stopped"
  rm -rf "${DIR}"
}

test_spawn_success_hides_token() {
  local token="session-token-secret" release="release-key-secret"
  setup_dir
  export CURSOR_RENDER_MONITOR=0
  export CURSOR_AGENT_WORKER_ID=worker-1
  export CURSOR_POOL=render-sandboxes
  export CURSOR_AUTH_TOKEN="${token}"
  export CURSOR_REQUEST_ID=req-1
  export WORKER_SNAPSHOT_ID=snp-worker
  export RENDER_API_KEY=render-key-secret
  export RENDER_WORKSPACE=tea-test
  export CURSOR_RELEASE_API_KEY="${release}"
  bash "${ROOT}/controller/spawn.sh" >"${DIR}/out" 2>"${DIR}/err"
  assert_not_contains "${DIR}/out" "${token}"
  assert_not_contains "${DIR}/err" "${token}"
  assert_not_contains "${FAKE_LOG}" "${token}"
  assert_not_contains "${FAKE_LOG}" "${release}"
  grep -q 'CURSOR_AUTH_TOKEN=session-token-secret' "${FAKE_ENV_COPY}" || fail "token was not passed in the env file"
  grep -q 'snapshot-id snp-worker' "${FAKE_LOG}" || fail "snapshot was not used"
  [ ! -s "${FAKE_CURL_LOG}" ] || fail "success path released the claim"
  rm -rf "${DIR}"
}

test_spawn_create_failure_releases() {
  setup_dir
  export FAKE_CREATE_FAIL=1
  export CURSOR_RENDER_MONITOR=0
  export CURSOR_AGENT_WORKER_ID=worker-1
  export CURSOR_POOL=render-sandboxes
  export CURSOR_AUTH_TOKEN=session-token-secret
  export CURSOR_REQUEST_ID=req-1
  export WORKER_SNAPSHOT_ID=snp-worker
  export RENDER_API_KEY=render-key-secret
  export RENDER_WORKSPACE=tea-test
  export CURSOR_RELEASE_API_KEY=release-key-secret
  if bash "${ROOT}/controller/spawn.sh" >"${DIR}/out" 2>"${DIR}/err"; then
    fail "create failure should exit non-zero"
  fi
  assert_not_contains "${DIR}/out" "session-token-secret"
  assert_not_contains "${DIR}/err" "release-key-secret"
  grep -q 'claims/req-1/release' "${FAKE_CURL_LOG}" || fail "claim was not released"
  if grep -q 'user =' "${FAKE_CURL_LOG}"; then
    fail "release key leaked onto the curl command"
  fi
  rm -rf "${DIR}"
}

test_snapshot_script() {
  setup_dir
  export RENDER_API_KEY=render-key-secret
  export RENDER_WORKSPACE=tea-test
  bash "${ROOT}/controller/snapshot.sh" >"${DIR}/out"
  grep -q 'snapshot snp-test' "${DIR}/out" || fail "snapshot id was not printed"
  grep -q 'bootstrap-worker.sh' "${FAKE_LOG}" || fail "bootstrap was not copied"
  grep -q 'stop sbx-test --confirm' "${FAKE_LOG}" || fail "build sandbox was not stopped"
  rm -rf "${DIR}"
}

test_doctor() {
  local dir
  dir="$(mktemp -d)"
  new_fake_render "${dir}"
  new_fake_agent "${dir}" spawn
  export PATH="${dir}:${PATH}"
  export RENDER_BIN="${dir}/render"
  export AGENT_BIN="${dir}/agent"
  export DOCTOR_OFFLINE=1
  export FAKE_LOG="${dir}/render.log"
  export CURSOR_API_KEY=present
  export CURSOR_POOL=render-sandboxes
  export RENDER_API_KEY=present
  export RENDER_WORKSPACE=tea-test
  export WORKER_SNAPSHOT_ID=snp-test
  : > "${FAKE_LOG}"
  bash "${ROOT}/scripts/doctor.sh" >"${dir}/doctor.json"
  python3 -c 'import json,sys; data=json.load(open(sys.argv[1])); assert all(item["status"] in {"pass","configured_unverified","skipped"} for item in data["checks"])' "${dir}/doctor.json"

  new_fake_agent "${dir}" missing
  if bash "${ROOT}/scripts/doctor.sh" >"${dir}/missing.json"; then
    fail "missing controller should fail doctor"
  fi
  python3 -c 'import json,sys; data=json.load(open(sys.argv[1])); found=[item for item in data["checks"] if item["check"]=="cursor_controller"]; assert found and found[0]["status"]=="failed"' "${dir}/missing.json"
  assert_not_contains "${dir}/doctor.json" "present"
  rm -rf "${dir}"
}

test_sandbox_roundtrip
test_sandbox_create_failure_stops
test_spawn_success_hides_token
test_spawn_create_failure_releases
test_snapshot_script
test_doctor
echo "tests passed"
