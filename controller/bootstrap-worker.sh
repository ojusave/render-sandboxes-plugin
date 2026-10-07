#!/usr/bin/env bash
# Install the Cursor CLI into a sandbox before snapshotting the worker image.
set -euo pipefail

curl -fsSL "https://cursor.com/install?channel=lab" | bash
ln -sfn "${HOME}/.local/bin/agent" /usr/local/bin/agent
if [ -x "${HOME}/.local/bin/cursor-agent" ]; then
  ln -sfn "${HOME}/.local/bin/cursor-agent" /usr/local/bin/cursor-agent
fi
mkdir -p /workspace
agent --version
git --version
