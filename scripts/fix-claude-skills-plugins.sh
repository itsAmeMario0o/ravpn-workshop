#!/usr/bin/env bash
set -euo pipefail

# Patches the alirezarezvani/claude-skills plugin manifests so Claude Code
# loads their skills. Upstream ships "skills": "./" which the loader rejects
# as a path escape. This rewrites each plugin.json with an explicit array of
# every subdirectory that contains a SKILL.md.
#
# Run after `/plugin marketplace update` if the engineering-skills or
# engineering-advanced-skills plugins stop loading.

[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1 || DRY_RUN=0

python3 - "$DRY_RUN" <<'PY'
import json, os, sys
from pathlib import Path

dry = sys.argv[1] == "1"

targets = [
    "~/.claude/plugins/marketplaces/claude-code-skills/engineering",
    "~/.claude/plugins/marketplaces/claude-code-skills/engineering-team",
    "~/.claude/plugins/cache/claude-code-skills/engineering-advanced-skills/2.3.0",
    "~/.claude/plugins/cache/claude-code-skills/engineering-skills/2.2.0",
]

for t in targets:
    root = Path(os.path.expanduser(t))
    manifest = root / ".claude-plugin" / "plugin.json"
    if not manifest.exists():
        print(f"[WARN] no manifest: {root}")
        continue

    skills = sorted(
        f"./{p.name}"
        for p in root.iterdir()
        if p.is_dir()
        and not p.name.startswith(".")
        and (p / "SKILL.md").exists()
    )

    data = json.loads(manifest.read_text())
    if data.get("skills") == skills:
        print(f"[INFO] already patched: {manifest}")
        continue

    if dry:
        print(f"[DRY] would patch ({len(skills)} skills): {manifest}")
        continue

    data["skills"] = skills
    manifest.write_text(json.dumps(data, indent=2) + "\n")
    print(f"[INFO] patched ({len(skills)} skills): {manifest}")
PY

echo "[INFO] done. run /reload-plugins in Claude Code to apply."
