#!/usr/bin/env bash
# Create one short sandbox, exercise exec, copy, and snapshot, then stop it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SANDBOX_SH="${ROOT}/scripts/sandbox.sh"
EVIDENCE="${ROOT}/live-evidence"
mkdir -p "${EVIDENCE}"
SANDBOX_ID=""

cleanup() {
  if [ -n "${SANDBOX_ID}" ]; then
    bash "${SANDBOX_SH}" stop "${SANDBOX_ID}" >"${EVIDENCE}/stop.json" 2>"${EVIDENCE}/stop.err" || true
  fi
}
trap cleanup EXIT

created="$(bash "${SANDBOX_SH}" create --timeout 600 --network-policy deny-all)"
printf '%s\n' "${created}" > "${EVIDENCE}/create.json"
SANDBOX_ID="$(printf '%s' "${created}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"

bash "${SANDBOX_SH}" exec "${SANDBOX_ID}" -- mkdir -p /workspace
bash "${SANDBOX_SH}" exec "${SANDBOX_ID}" -- sh -c 'echo sandbox-roundtrip' > "${EVIDENCE}/exec.txt"
grep -q 'sandbox-roundtrip' "${EVIDENCE}/exec.txt"

printf 'copy-roundtrip' > "${EVIDENCE}/in.txt"
bash "${SANDBOX_SH}" copy "${EVIDENCE}/in.txt" "${SANDBOX_ID}:/workspace/in.txt"
bash "${SANDBOX_SH}" copy "${SANDBOX_ID}:/workspace/in.txt" "${EVIDENCE}/out.txt"
cmp "${EVIDENCE}/in.txt" "${EVIDENCE}/out.txt"

bash "${SANDBOX_SH}" snapshot "${SANDBOX_ID}" > "${EVIDENCE}/snapshot.json"
python3 -c 'import json,sys; data=json.load(open(sys.argv[1])); assert data["status"]=="available"' "${EVIDENCE}/snapshot.json"

python3 -c 'import json,sys; print(json.dumps({"sandbox_id":sys.argv[1],"exec":"pass","copy":"pass","snapshot":"pass"}))' "${SANDBOX_ID}" \
  > "${EVIDENCE}/summary.json"
cat "${EVIDENCE}/summary.json"
