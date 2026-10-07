---
name: sandbox
description: Create, inspect, execute, copy, snapshot, or stop a Render Sandbox.
---

# Sandbox

Use the plugin's `scripts/sandbox.sh`. Do not call the Render HTTP API directly.

1. Run `bash scripts/doctor.sh`.
2. Run the operation the user asked for. The command list is `skills/render-sandboxes/references/operations.md`.
3. Copy results out before `bash scripts/sandbox.sh stop sbx-...`.
