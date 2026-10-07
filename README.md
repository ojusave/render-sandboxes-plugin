# Render Sandboxes

Run Cursor Cloud Agent tool calls in [Render Sandboxes](https://render.com/docs/sandboxes), and manage sandbox lifecycle from Cursor: create, execute, copy files, snapshot, inspect, and clean up.

This is a new Cursor Marketplace plugin. It is separate from the [Render plugin](https://github.com/render-oss/render-cursor-plugin), which deploys and monitors Render services. This plugin does not add a second MCP server. Sandbox operations go through the Render CLI so credentials stay in your Render login or environment.

[![Deploy to Render](https://render.com/images/deploy-to-render-button.svg)](https://render.com/deploy?repo=https://github.com/ojusave/render-sandboxes-plugin)

[Sign up on Render](https://render.com/register?utm_source=github&utm_medium=referral&utm_campaign=ojus_demos&utm_content=hero_cta)

GitHub repository: [ojusave/render-sandboxes-plugin](https://github.com/ojusave/render-sandboxes-plugin)

The Deploy button deploys the pool controller from this repository.

## What you can do

1. Create an isolated Linux sandbox, run a command, copy files in or out, snapshot the filesystem, and stop the sandbox.
2. An Enterprise admin can run a Cursor self-hosted Team Pool. Each Cloud Agent claim gets its own sandbox. The service-account key stays on a Render Background Worker.

Sandboxes are early access: Oregon only, 24 hours maximum, 2 CPU, 4 GB memory, 10 GB disk, and 100 concurrent sandboxes per workspace.

## Install for local testing

1. Copy this directory to `~/.cursor/plugins/local/render-sandboxes`.
2. Reload Cursor.
3. Open Customize and confirm the `render-sandboxes` and `cursor-team-pool` skills.

Marketplace submission is a public Git repository reviewed at [cursor.com/marketplace/publish](https://cursor.com/marketplace/publish).

## Use a sandbox

```bash
bash scripts/doctor.sh
bash scripts/sandbox.sh create --timeout 900 --network-policy deny-all
bash scripts/sandbox.sh exec sbx-... -- echo ok
bash scripts/sandbox.sh stop sbx-...
```

Command details are in `skills/render-sandboxes/references/operations.md`.

## Set up the pool

Follow `skills/cursor-team-pool/SKILL.md`. The controller Blueprint is the root `render.yaml`. Secret values are entered in the Render Dashboard. They are not stored in this repository.

## Test

```bash
bash tests/run-tests.sh
```

That suite uses fake CLIs. It does not create a sandbox. To exercise a real workspace:

```bash
bash scripts/live-roundtrip.sh
```

The live script creates one sandbox, copies a file, snapshots it, and stops it.

## Controller

| Piece | Render service |
| --- | --- |
| Pool controller | Background Worker (`render.yaml`) |
| One worker per claim | Render Sandbox, created by `controller/spawn.sh` |
| Worker image | Filesystem snapshot from `controller/snapshot.sh` |

A Background Worker is the right host because it stays up and only needs outbound HTTPS. A sandbox cannot host the controller: sandboxes end at their timeout. Render Postgres and Key Value are not required for claim-then-spawn. Cursor keeps the queue, and Render keeps the sandbox record.

[Sign up on Render](https://render.com/register?utm_source=github&utm_medium=referral&utm_campaign=ojus_demos&utm_content=footer_link)

[Render docs](https://render.com/docs) · [Deploy to Render button](https://render.com/docs/deploy-to-render-button)
