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
        ROOT / ".codex-plugin" / "plugin.json",
        ROOT / ".agents" / "plugins" / "marketplace.json",
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

    description = re.search(r"^description:\s*(.+)$", match.group(1), re.MULTILINE)
    if not description:
        raise AssertionError("SKILL.md frontmatter is missing a description")
    if len(description.group(1).strip()) > 1024:
        raise AssertionError("SKILL.md description exceeds the 1024-character Agent Skills limit")

    plugin = json.loads((ROOT / ".claude-plugin" / "plugin.json").read_text(encoding="utf-8"))
    marketplace = json.loads((ROOT / ".claude-plugin" / "marketplace.json").read_text(encoding="utf-8"))
    codex_plugin = json.loads((ROOT / ".codex-plugin" / "plugin.json").read_text(encoding="utf-8"))
    codex_marketplace = json.loads((ROOT / ".agents" / "plugins" / "marketplace.json").read_text(encoding="utf-8"))
    if plugin["name"] != "everything-search":
        raise AssertionError("Claude plugin name does not match skill")
    if marketplace["plugins"][0]["name"] != plugin["name"]:
        raise AssertionError("Marketplace plugin name does not match plugin manifest")
    if codex_plugin["name"] != plugin["name"]:
        raise AssertionError("Codex and Claude plugin names do not match")
    if codex_plugin["skills"] != "./skills/":
        raise AssertionError("Codex plugin must include the skills directory")
    if codex_marketplace["plugins"][0]["name"] != codex_plugin["name"]:
        raise AssertionError("Codex marketplace plugin name does not match its manifest")

    for field in ("name", "version", "description"):
        if not codex_plugin.get(field):
            raise AssertionError(f"Codex plugin.json must define {field}")
    if not codex_plugin.get("author", {}).get("name"):
        raise AssertionError("Codex plugin.json must define author.name")
    if not re.fullmatch(r"\d+\.\d+\.\d+", codex_plugin["version"]):
        raise AssertionError("Codex plugin.json version must be strict semver")

    codex_entry = codex_marketplace["plugins"][0]
    policy = codex_entry.get("policy", {})
    if policy.get("installation") not in {"NOT_AVAILABLE", "AVAILABLE", "INSTALLED_BY_DEFAULT"}:
        raise AssertionError("Codex marketplace entry needs a valid policy.installation")
    if policy.get("authentication") not in {"ON_INSTALL", "ON_USE"}:
        raise AssertionError("Codex marketplace entry needs a valid policy.authentication")
    if not codex_entry.get("category"):
        raise AssertionError("Codex marketplace entry must define category")
    # A plugin shipped inside this repository resolves as a local source.
    if codex_entry.get("source", {}).get("source") != "local":
        raise AssertionError("Codex marketplace entry must use a local source for an in-repo plugin")

    for entry in marketplace["plugins"]:
        for field in ("name", "source", "description"):
            if not entry.get(field):
                raise AssertionError(f"Claude marketplace entry must define {field}")
    if not marketplace.get("owner", {}).get("name"):
        raise AssertionError("Claude marketplace.json must define owner.name")

    powershell = "\n".join(path.read_text(encoding="utf-8") for path in (SKILL / "scripts").glob("*.ps1"))
    if "Invoke-Expression" in powershell:
        raise AssertionError("Invoke-Expression is forbidden")
    if "https://www.voidtools.com/" not in powershell:
        raise AssertionError("Setup must use the official voidtools origin")
    for url in re.findall(r"https?://[^\s'\"]+", powershell):
        if not url.startswith("https://www.voidtools.com/"):
            raise AssertionError(f"Scripts may only reach the official voidtools origin: {url}")
    for server_flag in ("-enable_http_server", "-enable_etp_server", "http_server_enabled", "etp_server_enabled"):
        if server_flag in powershell:
            raise AssertionError(f"Scripts must never enable a network server: {server_flag}")

    tracked = sorted(
        path
        for path in ROOT.rglob("*")
        if path.is_file() and ".git" not in path.relative_to(ROOT).parts
    )

    forbidden_binaries = {".dll", ".exe", ".msi", ".zip", ".db", ".efu"}
    committed = [p.relative_to(ROOT).as_posix() for p in tracked if p.suffix.lower() in forbidden_binaries]
    if committed:
        raise AssertionError(f"Third-party/binary files must not be committed: {committed}")

    # This repository is public: refuse anything that leaks the authoring machine.
    private_patterns = {
        "expanded user profile path": re.compile(r"[A-Za-z]:\\Users\\[A-Za-z0-9._-]+", re.IGNORECASE),
        "expanded home path": re.compile(r"/(?:home|Users)/[A-Za-z0-9._-]+"),
        "computer or account name": re.compile(r"\\\\[A-Za-z0-9._-]{2,}\\[A-Za-z0-9$._-]+"),
        # Valid octets only, and not part of a longer dotted token such as a version string.
        "IPv4 address": re.compile(
            r"(?<![-\w.])(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)"
            r"(?:\.(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}(?![\w.-])"
        ),
        "GitHub token": re.compile(r"\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}|\bgithub_pat_[A-Za-z0-9_]{20,}"),
        "AWS access key": re.compile(r"\bAKIA[0-9A-Z]{16}\b"),
        "private key block": re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
    }
    text_suffixes = {".md", ".ps1", ".py", ".json", ".yaml", ".yml", ".txt", ""}
    for path in tracked:
        if path.suffix.lower() not in text_suffixes:
            continue
        content = path.read_text(encoding="utf-8", errors="ignore")
        for label, pattern in private_patterns.items():
            found = pattern.search(content)
            if found:
                relative = path.relative_to(ROOT).as_posix()
                raise AssertionError(f"Possible private data ({label}) in {relative}: {found.group(0)!r}")

    print(f"Repository validation passed ({len(tracked)} files checked).")


if __name__ == "__main__":
    main()
