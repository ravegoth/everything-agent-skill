# Security Policy

## Supported versions

The latest release on `main` is supported. Please reproduce issues against it
before reporting.

## Reporting a vulnerability

Report privately through GitHub Security Advisories:

<https://github.com/ravegoth/everything-agent-skill/security/advisories/new>

Please do not open a public issue for an unpatched vulnerability. Include the
affected script, your Windows and PowerShell versions, the Everything version,
and the steps to reproduce. Use synthetic paths in your report rather than real
file names from your machine.

Expect an initial response within 14 days. This is a volunteer project and no
formal service level is promised.

## Known risks and how they are handled

**Search results are untrusted input.** File and folder names are chosen by
whoever created them, so a result can carry text aimed at an AI agent. This is
inherent to every file search tool and cannot be removed, only contained.
`SKILL.md` instructs the agent to treat every result as data to report and
never as an instruction, and the wrapper passes queries to the backend as
arguments rather than building a command string, so a query cannot become a
command. Review results before acting on them.

**Optional downloads run executable code.** `setup_backend.ps1` fetches the
official Everything SDK DLL or `es.exe`. It runs only when you invoke it,
downloads only over HTTPS from `https://www.voidtools.com/`, and installs a
file only after Windows confirms a valid Authenticode signature naming
voidtools. Anything unsigned, tampered with, or signed by another publisher is
refused and nothing is installed. Only the DLLs and `es.exe` are extracted; the
example projects in the SDK archive, which include unsigned sample
executables, are never installed. You can skip the script entirely and point
`-DllPath` or `-EsPath` at files you obtained yourself.

**Execution policy.** The documented commands use
`-ExecutionPolicy RemoteSigned`, which applies to that single process and
changes no machine or user setting. The skill creates, starts, stops, and
modifies no Windows service. If a host blocks the scripts because they came
from a downloaded archive, run `Unblock-File` on them rather than weakening the
policy.

## Security design

- **Read-only.** The scripts read file metadata from the Everything index. They
  never open file contents, execute, move, rename, delete, or upload a result.
- **Local only.** Queries use Everything's local IPC. The skill never enables
  Everything's HTTP or ETP server and ships no MCP or other network server.
- **No bundled binaries.** No third-party executables, DLLs, or archives are
  committed. `setup_backend.ps1` downloads only from `https://www.voidtools.com/`
  and only when you invoke it, and CI fails the build if any script references
  another origin.
- **No dynamic evaluation.** `Invoke-Expression` is prohibited and enforced by
  `tests/validate_repo.py`. Queries are passed to backends as arguments, never
  concatenated into a command string.
- **Privacy checks in CI.** `tests/validate_repo.py` rejects committed binaries,
  archives, Everything databases, and anything matching a user profile path,
  home directory, UNC host, token, or private key.

## Scope

The skill runs with the same permissions as the agent that invokes it. It can
reveal the existence and metadata of any file the current user can see through
Everything's index. Treat returned paths as sensitive, and note that your coding
agent's provider may process them — see [PRIVACY.md](PRIVACY.md).
