# Everything Search Agent Skill

Fast Windows file search for Claude Code, Codex, and other Agent Skills-compatible coding agents, powered by the local [voidtools Everything](https://www.voidtools.com/) index.

This skill detects Everything automatically, queries it through the official SDK DLL or `es.exe`, and returns structured, Unicode-safe JSON. Searches stay local and read-only.

## Install

One command installs the skill interactively for Codex, Claude Code, Cursor, OpenCode, and other supported agents:

```powershell
npx skills add ravegoth/everything-agent-skill -g
```

Install globally for every detected agent without prompts:

```powershell
npx skills add ravegoth/everything-agent-skill -g --all
```

Or give your agent the repository directly:

```text
Install the everything-search skill from https://github.com/ravegoth/everything-agent-skill.git.
Read README.md and AGENTS.md, install skills/everything-search in my user skill
directory, preserve its scripts and references, validate SKILL.md, then run the
detection script. Ask before downloading Everything, its SDK, or es.exe. Finish
with a harmless search limited to 10 results and report the selected backend.
```

The repository uses the open Agent Skills layout, so Git-based skill installers can discover `skills/everything-search/SKILL.md` directly.

## Agent-specific install

### Codex

```powershell
npx skills add ravegoth/everything-agent-skill -g -a codex -y
```

Invoke with `$everything-search` or ask Codex to find a local file.

### Claude Code

```powershell
npx skills add ravegoth/everything-agent-skill -g -a claude-code -y
```

Or install it as a Claude Code plugin:

```text
/plugin marketplace add ravegoth/everything-agent-skill
/plugin install everything-search@everything-agent-skills
```

### Codex plugin marketplace

```text
codex plugin marketplace add ravegoth/everything-agent-skill
```

Then open `/plugins`, select **Everything Agent Skills**, and install **Everything Search**.

### Other agents

Copy the complete `skills/everything-search` directory into the host's user or project skills directory. Keep `scripts`, `references`, and `agents` beside `SKILL.md`.

## Requirements

- Windows 10 or 11
- Full Everything application installed and running in the same user session
- Windows PowerShell 5.1 or PowerShell 7+
- Official Everything SDK DLL (preferred) or `es.exe`

No Everything binaries are included in this repository.

## Use

Detect the Everything installation and available backend:

```powershell
.\skills\everything-search\scripts\detect_everything.ps1 -Pretty
```

Search the local index:

```powershell
.\skills\everything-search\scripts\search_everything.ps1 `
  -Query 'file: path:"D:\Music\" ext:wav;flac size:>100mb' `
  -MaxResults 50 -Pretty
```

Results include the full path, item type, size, modification time, attributes, and truncation metadata.

If no query backend is detected, preview and install the official SDK after approval:

```powershell
.\skills\everything-search\scripts\setup_backend.ps1 -Component Sdk -WhatIf
.\skills\everything-search\scripts\setup_backend.ps1 -Component Sdk -Confirm
```

The setup script downloads only from `voidtools.com` into `%LOCALAPPDATA%\EverythingAgent`. Use `-Component Es` for the CLI fallback.

## Features

- Detects installed, portable, and running Everything instances
- Searches by name, path, extension, size, date, attributes, regex, or indexed content
- Supports x86, x64, ARM, and ARM64 SDK DLLs
- Returns stable JSON for further agent actions
- Uses local Everything IPC; no HTTP or ETP server
- Never opens, moves, deletes, uploads, or executes search results

## Validate

```powershell
python .\tests\validate_repo.py
Get-ChildItem . -Filter '*.ps1' -Recurse | ForEach-Object {
  [void][scriptblock]::Create((Get-Content $_.FullName -Raw))
}
```

`validate_repo.py` checks the repository layout, the skill and plugin manifests, and refuses to pass if a binary or anything resembling private machine data is committed.

GitHub Actions runs on Linux and Windows and needs no Everything installation: it validates the repository, parses every script under both Windows PowerShell 5.1 and PowerShell 7, asserts the detection and failure contracts, exercises a path containing spaces, and confirms the skill is discoverable by the Skills CLI.

## Documentation

- [Everything downloads](https://www.voidtools.com/downloads/)
- [Everything SDK](https://www.voidtools.com/support/everything/sdk/)
- [Everything search syntax](https://www.voidtools.com/support/everything/searching/)
- [Claude Code skills](https://code.claude.com/docs/en/skills)
- [Claude Code plugin marketplaces](https://code.claude.com/docs/en/plugin-marketplaces)
- [OpenAI Codex skills](https://learn.chatgpt.com/docs/build-skills)
- [OpenAI Codex plugins](https://developers.openai.com/codex/plugins/build)

## Project

- [Privacy](PRIVACY.md) — the skill collects nothing, but your coding agent's provider may process the paths it returns
- [Terms](TERMS.md)
- [Security policy](SECURITY.md)
- [Report an issue](https://github.com/ravegoth/everything-agent-skill/issues)

## License

[MIT](LICENSE)

Unofficial and independent. Not affiliated with, endorsed by, or sponsored by voidtools. Everything is voidtools' software and is not included in this repository.
