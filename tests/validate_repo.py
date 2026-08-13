from __future__ import annotations

import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SKILL = ROOT / "skills" / "everything-search"


def require(path: Path) -> None:
    if not path.is_file():
        raise AssertionError(f"Missing required file: {path.relative_to(ROOT)}")


def main() -> None:
    required = [
        ROOT / "README.md",
        ROOT / "AGENTS.md",
        ROOT / "LICENSE",
        ROOT / ".claude-plugin" / "plugin.json",
        ROOT / ".claude-plugin" / "marketplace.json",
        SKILL / "SKILL.md",
        SKILL / "agents" / "openai.yaml",
        SKILL / "scripts" / "detect_everything.ps1",
        SKILL / "scripts" / "search_everything.ps1",
        SKILL / "scripts" / "setup_backend.ps1",
        SKILL / "references" / "backend-setup.md",
        SKILL / "references" / "dll-api.md",
        SKILL / "references" / "search-syntax.md",
    ]
    for path in required:
        require(path)

    manifest = (SKILL / "SKILL.md").read_text(encoding="utf-8")
    match = re.match(r"\A---\n(.*?)\n---\n", manifest, re.DOTALL)
    if not match:
        raise AssertionError("SKILL.md frontmatter is missing or malformed")

    keys = [line.split(":", 1)[0].strip() for line in match.group(1).splitlines() if line.strip()]
    if keys != ["name", "description"]:
        raise AssertionError(f"Unexpected SKILL.md frontmatter keys/order: {keys}")
    if "name: everything-search" not in match.group(1):
        raise AssertionError("Skill name must be everything-search")
    if "TODO" in manifest:
        raise AssertionError("SKILL.md contains unfinished TODO text")

    plugin = json.loads((ROOT / ".claude-plugin" / "plugin.json").read_text(encoding="utf-8"))
    marketplace = json.loads((ROOT / ".claude-plugin" / "marketplace.json").read_text(encoding="utf-8"))
    if plugin["name"] != "everything-search":
        raise AssertionError("Claude plugin name does not match skill")
    if marketplace["plugins"][0]["name"] != plugin["name"]:
        raise AssertionError("Marketplace plugin name does not match plugin manifest")

    powershell = "\n".join(path.read_text(encoding="utf-8") for path in (SKILL / "scripts").glob("*.ps1"))
    if "Invoke-Expression" in powershell:
        raise AssertionError("Invoke-Expression is forbidden")
    if "https://www.voidtools.com/" not in powershell:
        raise AssertionError("Setup must use the official voidtools origin")

    forbidden_binaries = {".dll", ".exe", ".msi", ".zip"}
    committed = [path for path in ROOT.rglob("*") if path.is_file() and path.suffix.lower() in forbidden_binaries]
    if committed:
        raise AssertionError(f"Third-party/binary files must not be committed: {committed}")

    print("Repository validation passed.")


if __name__ == "__main__":
    main()
