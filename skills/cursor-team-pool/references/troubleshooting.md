# Troubleshooting

| What you see | What to check |
| --- | --- |
| Sandbox Group is missing | Sandboxes is not enabled. Send the workspace id to your Render contact. |
| `cursor_controller` failed | The CLI is not on the lab channel. Run `agent set-channel lab && agent update`. |
| Pool workers reject the key | The key is not a service-account key. |
| The pool is missing in the picker | Register `render-sandboxes`, start the controller, then pick **Any repo**. |
| The request stays queued | The controller is running, `CURSOR_POOL` matches, and the workspace is under 100 concurrent sandboxes. |
| `exec` fails immediately after create | The sandbox was still `creating`. `scripts/sandbox.sh` waits; a raw CLI call might not. |
| The worker never connects | The worker sandbox network policy must be `allow-all`. Outbound HTTPS to `api2.cursor.sh` and `api2direct.cursor.sh` must be open. |
| Clone fails | GitHub token minting is on, the GitHub App can see the repo, and the pool name is not `default`. |
| Artifacts missing | Outbound HTTPS to `cloud-agent-artifacts.s3.us-east-1.amazonaws.com` is blocked. The session still runs. |
| Sandboxes still running after a deploy | The monitor died with the controller. Stop finished sandboxes. |
| Snapshot restore fails | The snapshot expired, failed, or belongs to another workspace. Capture a new one and update `WORKER_SNAPSHOT_ID`. |
