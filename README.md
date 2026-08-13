# Everything Search Agent Skill

Give Claude Code, Codex, and other Agent Skills-compatible coding agents instant, structured access to the local [voidtools Everything](https://www.voidtools.com/) index on Windows.

The skill detects Everything before use, prefers the official SDK DLL over local IPC, falls back to the official `es.exe` CLI, and returns JSON containing paths and metadata. It does not bundle Everything binaries, expose a network service, or mutate search results.

## What agents can do

- Detect full and portable Everything installations, running processes, SDK DLLs, and `es.exe`.
- Search by filename, directory, extension, size, dates, attributes, regex, or indexed content.
- Receive Unicode-safe JSON with full paths, file/folder type, size, modification time, attributes, and truncation state.
- Use the architecture-matched Everything SDK DLL on x86, x64, ARM, or ARM64 without rewriting P/Invoke code.
- Install the official SDK or CLI into a user-local directory after explicit approval.

## Requirements

- Windows 10 or 11
- The full Everything application installed and running
- Windows PowerShell 5.1 or PowerShell 7+
- For structured queries: the official Everything SDK DLL (preferred) or `es.exe`

Everything itself and its SDK/CLI remain subject to voidtools' terms. This repository contains only original integration scripts and instructions.

## Give this repository to an agent

Use this prompt with the private or public Git URL:

```text
Install the `everything-search` Agent Skill from <GIT_URL>. Read README.md and
AGENTS.md first. Copy only `skills/everything-search` into your user skill
directory for this agent host, preserve its relative files, validate SKILL.md,
then run detect_everything.ps1. Do not download or install Everything, its SDK,
or ES without asking me first. Report the detected backend and run a harmless
test query limited to 10 results.
```

The repository follows the open Agent Skills structure (`SKILL.md` plus optional `scripts`, `references`, and `agents`). Host-specific installation paths are below.

## Install for Codex

Codex discovers personal skills under `$HOME/.agents/skills`.

```powershell
$repo = Join-Path $env:TEMP 'everything-agent-skill'
git clone <GIT_URL> $repo
New-Item -ItemType Directory -Force "$HOME\.agents\skills" | Out-Null
Copy-Item "$repo\skills\everything-search" "$HOME\.agents\skills\everything-search" -Recurse -Force
```

Open Codex and invoke it explicitly with `$everything-search`, or ask naturally to find a local Windows file.

## Install for Claude Code

Claude Code discovers personal skills under `$HOME/.claude/skills`.

```powershell
$repo = Join-Path $env:TEMP 'everything-agent-skill'
git clone <GIT_URL> $repo
New-Item -ItemType Directory -Force "$HOME\.claude\skills" | Out-Null
Copy-Item "$repo\skills\everything-search" "$HOME\.claude\skills\everything-search" -Recurse -Force
```

Invoke it with `/everything-search` or let Claude select it from the description.

### Claude Code marketplace installation

This repository is also a Claude Code plugin marketplace:

```text
/plugin marketplace add ravegoth/everything-agent-skill
/plugin install everything-search@everything-agent-skills
```

For a private repository, Claude Code uses your existing Git credentials. GitHub shorthand prefers SSH; set `CLAUDE_CODE_PLUGIN_PREFER_HTTPS=1` if your credentials are configured for HTTPS.

## Other Agent Skills hosts

Copy the complete `skills/everything-search` directory into the host's user or project skills directory. Do not copy only `SKILL.md`: the scripts and references are required. A host that implements the open Agent Skills standard can read the manifest even if it ignores the optional OpenAI or Claude metadata.

There is no honest universal install command because hosts choose different skill directories. The package itself is portable; only its destination changes.

## First run

Detection is read-only:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\skills\everything-search\scripts\detect_everything.ps1" -Pretty
```

Expected shape:

```json
{
  "platform": { "windows": true, "process_bitness": 64 },
  "everything": { "installed": true, "running": true },
  "backend": { "ready": true, "preferred": "dll" },
  "message": "Everything is ready through the dll backend."
}
```

Search:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\skills\everything-search\scripts\search_everything.ps1" `
  -Query 'file: path:"D:\Music\" ext:wav;flac size:>100mb' `
  -MaxResults 50 `
  -Pretty
```

## Backend setup

The skill never downloads a backend during detection. After reviewing the destination, install the official SDK with:

```powershell
.\skills\everything-search\scripts\setup_backend.ps1 -Component Sdk -WhatIf
.\skills\everything-search\scripts\setup_backend.ps1 -Component Sdk -Confirm
```

The SDK goes to `%LOCALAPPDATA%\EverythingAgent\SDK`; the repository stays binary-free. Use `-Component Es` for the CLI fallback.

## Design

```text
agent request
  -> SKILL.md workflow
  -> detect_everything.ps1
  -> search_everything.ps1
      -> Everything SDK DLL -> local Everything IPC/index
      -> es.exe fallback    -> local Everything IPC/index
  -> JSON results
```

The SDK DLL is a client library, not the index. Everything must be running in the same interactive Windows session.

## Validation

```powershell
python .\tests\validate_repo.py
Get-ChildItem . -Filter '*.ps1' -Recurse | ForEach-Object {
    [void][scriptblock]::Create((Get-Content $_.FullName -Raw))
}
```

CI performs manifest/repository checks on Linux and parses every PowerShell script on Windows.

## Security model

- Local IPC only; no HTTP or ETP server is enabled.
- Search is read-only. Opening, moving, deleting, uploading, or executing results requires a separate user request.
- No `Invoke-Expression` and no command-string interpolation of user queries.
- No third-party DLL or executable is committed.
- Setup downloads only from `https://www.voidtools.com/` and supports `-WhatIf`/`-Confirm`.

## Upstream documentation

- [Everything downloads](https://www.voidtools.com/downloads/)
- [Everything SDK](https://www.voidtools.com/support/everything/sdk/)
- [Everything IPC](https://www.voidtools.com/support/everything/sdk/ipc/)
- [Search syntax](https://www.voidtools.com/support/everything/searching/)
- [Claude Code skills](https://code.claude.com/docs/en/skills)
- [OpenAI Codex skills](https://learn.chatgpt.com/docs/build-skills)

## License

MIT. See [LICENSE](LICENSE).
