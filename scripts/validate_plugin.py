#!/usr/bin/env python3
"""Validate the Cursor plugin manifest and component frontmatter."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NAME = re.compile(r"^[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?$")
FRONTMATTER = re.compile(r"\A---\n(.*?)\n---\n", re.DOTALL)


def fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def frontmatter(path: Path) -> dict[str, str]:
    match = FRONTMATTER.match(path.read_text())
    if not match:
        fail(f"{path.relative_to(ROOT)} is missing frontmatter")
    fields: dict[str, str] = {}
    for line in match.group(1).splitlines():
        if not line.strip() or line.startswith(" "):
            continue
        key, _, value = line.partition(":")
        fields[key.strip()] = value.strip()
    return fields


def main() -> None:
    manifest_path = ROOT / ".cursor-plugin" / "plugin.json"
    manifest = json.loads(manifest_path.read_text())
    if not NAME.match(manifest.get("name", "")):
        fail("plugin name must be kebab-case")
    for field in ("description", "version", "license", "logo"):
        if not manifest.get(field):
            fail(f"manifest missing {field}")
    logo = ROOT / manifest["logo"]
    if not logo.is_file():
        fail("logo path does not exist")
    for component in ("skills", "rules", "agents", "commands"):
        directory = ROOT / manifest[component]
        if not directory.is_dir():
            fail(f"missing {component} directory")

    skills = list((ROOT / "skills").glob("*/SKILL.md"))
    if len(skills) < 2:
        fail("expected the sandbox and team-pool skills")
    for path in skills:
        fields = frontmatter(path)
        if not fields.get("name") or not fields.get("description"):
            fail(f"{path} needs name and description")

    for path in (ROOT / "rules").glob("*.mdc"):
        fields = frontmatter(path)
        if "description" not in fields or "alwaysApply" not in fields:
            fail(f"{path} needs description and alwaysApply")

    for directory in ("commands", "agents"):
        paths = list((ROOT / directory).glob("*.md"))
        if not paths:
            fail(f"missing {directory}")
        for path in paths:
            fields = frontmatter(path)
            if not fields.get("name") or not fields.get("description"):
                fail(f"{path} needs name and description")

    readme = (ROOT / "README.md").read_text()
    if "https://github.com/ojusave/render-sandboxes-plugin" not in readme:
        fail("README is missing the GitHub repository")
    if "render.yaml" in readme or "render.com/deploy" in readme or "render.com/register" in readme:
        fail("README includes a deploy button, signup link, or controller Blueprint")

    secret = re.compile(r"rnd_[A-Za-z0-9]|key_[A-Za-z0-9]{16,}")
    for path in ROOT.rglob("*"):
        if not path.is_file() or path.suffix in {".svg", ".png"}:
            continue
        if secret.search(path.read_text(errors="ignore")):
            fail(f"possible secret in {path.relative_to(ROOT)}")
    print("plugin manifest ok")


if __name__ == "__main__":
    main()
