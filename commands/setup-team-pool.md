---
name: setup-team-pool
description: Set up the Cursor self-hosted pool that runs workers in Render Sandboxes.
---

# Set up the team pool

Follow `skills/cursor-team-pool/SKILL.md` in order.

1. Run `bash scripts/doctor.sh` and stop on a failed `render_cli`, `sandbox_group`, or `cursor_controller` check.
2. Register the pool named `render-sandboxes`.
3. Run `bash controller/snapshot.sh` and keep the printed snapshot id.
4. Deploy the root `render.yaml` Background Worker and set the secret env vars in the Dashboard.
5. Tell the user to pick **Any repo**, then `render-sandboxes`, at cursor.com/agents.
