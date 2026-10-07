---
name: render-sandboxes
description: >-
  Create, inspect, execute commands in, copy files to and from, snapshot, and
  stop Render Sandboxes. Use when the user wants an isolated Linux environment,
  a filesystem snapshot, or cleanup of a sandbox.
---

# Render Sandboxes

Run `scripts/sandbox.sh` from the plugin root. Do not invent a second client.

## When to use

- Run a command, test, or script away from the user's machine.
- Copy a file into a sandbox or bring a result back.
- Capture a filesystem snapshot, or restore one with `--snapshot-id`.
- List sandboxes and stop one that is finished.

For a Cursor Cloud Agent pool, use the `cursor-team-pool` skill instead of creating a worker by hand.

## Steps

1. Run `bash scripts/doctor.sh`. A failed `cursor_controller` check does not block ordinary sandbox use.
2. Run one operation from `references/operations.md`.
3. Prefer `--network-policy deny-all` and a timeout of 900 seconds or less.
4. Copy results out before stopping. Termination deletes the filesystem.
5. Run `bash scripts/sandbox.sh stop sbx-...` when the work is done.

## Limits

Oregon only. Maximum lifetime is 86400 seconds. `--plan` and `--region` do not change the early-access sandbox. Snapshots expire three days after capture unless a later SDK call sets `expires_at`. The CLI snapshot command cannot set that field.

## Failure

If create returns an id but the sandbox never reaches `running`, the script stops it. Do not create another sandbox until that stop finishes. If the CLI loses the exec stream, inspect the sandbox before running the command again.
