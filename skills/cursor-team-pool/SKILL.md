---
name: cursor-team-pool
description: >-
  Set up a Cursor Enterprise self-hosted Team Pool whose workers run in Render
  Sandboxes. Use when an admin wants Cloud Agent tool calls to execute in
  Render, or when configuring the pool controller, worker snapshot, or spawn hook.
---

# Cursor team pool on Render Sandboxes

An administrator does this once. Developers then choose the `render-sandboxes` pool and send a normal Cloud Agent task. This plugin does not replace Cursor's chat UI or claim scheduler.

## Before you start

Confirm all of these. The plugin cannot click through the Cursor dashboard.

1. The team is on Cursor Enterprise.
2. A team admin has enabled Self-Hosted Machines and GitHub token minting.
3. The Cursor GitHub App is installed for every repository the pool will clone.
4. `CURSOR_API_KEY` is a service-account key. Personal, team-admin, and organization keys cannot start pool workers.
5. The Render workspace shows **Sandbox Group** under **+ New**.
6. `bash scripts/doctor.sh` reports `render_cli` and `sandbox_group` as pass. `cursor_controller` must be pass before the controller starts. The lab channel command is `agent set-channel lab && agent update`.

## Setup

1. Export `RENDER_API_KEY`, `RENDER_WORKSPACE` (the `tea-...` workspace id), and `CURSOR_API_KEY`. Do not write the values into the repository.
2. Register the pool:

```bash
curl --request POST \
  --url "https://api.cursor.com/v0/private-workers/pools" \
  --user "${CURSOR_API_KEY}:" \
  --header "Content-Type: application/json" \
  --data '{"scope":"team","poolName":"render-sandboxes"}'
```

3. Build the worker snapshot: `bash controller/snapshot.sh`. Save the printed `snp-...` id as `WORKER_SNAPSHOT_ID`. Rebuild it before three days, because a CLI snapshot expires.
4. Deploy the controller with the Deploy to Render button in the repository README, or apply the root `render.yaml` as a Background Worker. Set the `sync: false` values in the Dashboard. `CURSOR_RELEASE_API_KEY` is the same service-account key. Run one instance. The button deploys that worker only. It does not install this plugin.
5. Send a task at [cursor.com/agents](https://cursor.com/agents). Choose **Any repo**, then `render-sandboxes`.

The controller image runs `agent worker controller --spawn /opt/cursor-render/spawn.sh --session-token`. `controller/spawn.sh` creates one sandbox per claim and releases the claim if startup fails.

## After a deploy

In-flight sandboxes keep running when the controller restarts. Their monitors die with the old instance. List running sandboxes and stop any session that has already finished:

```bash
bash scripts/sandbox.sh inspect
bash scripts/sandbox.sh stop sbx-...
```

## Docs

- https://render.com/docs/sandboxes
- https://cursor.com/docs/cloud-agent/self-hosted
- https://cursor.com/docs/cloud-agent/self-hosted/pool
- Troubleshooting table: `references/troubleshooting.md`
