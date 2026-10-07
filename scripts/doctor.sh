#!/usr/bin/env bash
# Check the local CLIs and workspace without printing credentials.
set -euo pipefail

RENDER_BIN="${RENDER_BIN:-render}"
AGENT_BIN="${AGENT_BIN:-agent}"
checks='[]'

add_check() {
  checks="$(CHECKS="${checks}" python3 -c 'import json,os,sys
checks=json.loads(os.environ["CHECKS"])
checks.append(json.loads(sys.stdin.read()))
print(json.dumps(checks))' <<<"$1")"
}

version_ge() {
  python3 -c 'import sys
def parse(value):
    token=value.split()[-1].lstrip("vV")
    return tuple(int(part) for part in token.split(".")[:3])
sys.exit(0 if parse(sys.argv[1]) >= parse(sys.argv[2]) else 1)' "$1" "$2"
}

if command -v python3 >/dev/null 2>&1; then
  add_check '{"check":"python3","status":"pass"}'
else
  add_check '{"check":"python3","status":"failed"}'
fi

if render_version="$("${RENDER_BIN}" --version 2>&1)"; then
  render_line="$(printf '%s\n' "${render_version}" | head -n 1)"
  if version_ge "${render_line}" "2.28.0"; then
    add_check "$(python3 -c 'import json,sys; print(json.dumps({"check":"render_cli","status":"pass","version":sys.argv[1]}))' "${render_line}")"
  else
    add_check "$(python3 -c 'import json,sys; print(json.dumps({"check":"render_cli","status":"failed","version":sys.argv[1],"detail":"Install Render CLI 2.28.0 or later"}))' "${render_line}")"
  fi
else
  add_check '{"check":"render_cli","status":"failed","detail":"render --version failed"}'
fi

agent_help="$("${AGENT_BIN}" worker controller --help 2>&1 || true)"
if printf '%s' "${agent_help}" | grep -q -- '--spawn'; then
  add_check '{"check":"cursor_controller","status":"pass"}'
else
  add_check '{"check":"cursor_controller","status":"failed","detail":"Install the Cursor CLI lab channel: agent set-channel lab && agent update"}'
fi

if [ "${DOCTOR_OFFLINE:-}" = "1" ]; then
  add_check '{"check":"sandbox_group","status":"skipped","detail":"offline"}'
else
  if groups="$("${RENDER_BIN}" ea sandbox-groups list -o json 2>/dev/null)"; then
    add_check "$(printf '%s' "${groups}" | python3 -c 'import json,sys
rows=json.load(sys.stdin)
if not rows:
    print(json.dumps({"check":"sandbox_group","status":"missing","detail":"Sandbox Group is not enabled for this workspace"}))
else:
    print(json.dumps({"check":"sandbox_group","status":"pass","groups":[{"id":row["id"],"region":row["region"]} for row in rows]}))')"
  else
    add_check '{"check":"sandbox_group","status":"failed","detail":"Could not list sandbox groups"}'
  fi
fi

missing='[]'
for key in CURSOR_API_KEY CURSOR_POOL RENDER_API_KEY RENDER_WORKSPACE WORKER_SNAPSHOT_ID; do
  if [ -z "${!key:-}" ]; then
    missing="$(printf '%s' "${missing}" | python3 -c 'import json,sys; values=json.load(sys.stdin); values.append(sys.argv[1]); print(json.dumps(values))' "${key}")"
  fi
done
if [ "${missing}" = "[]" ]; then
  add_check '{"check":"controller_env","status":"configured_unverified"}'
else
  add_check "$(MISSING="${missing}" python3 -c 'import json,os; print(json.dumps({"check":"controller_env","status":"missing","missing":json.loads(os.environ["MISSING"])}))')"
fi

printf '{"checks":%s}\n' "${checks}"
if printf '%s' "${checks}" | python3 -c 'import json,sys
checks=json.load(sys.stdin)
sys.exit(0 if all(item["status"] not in {"failed","missing"} for item in checks) else 1)'; then
  exit 0
fi
exit 1
