# Privacy

Last updated: 2026-08-16

Everything Search is a local Windows skill. This document describes what the
software in this repository does with your data.

## What the skill collects

Nothing. The scripts in this repository have no analytics, no telemetry, and no
account system. They do not create a user profile or a persistent log.

## What the skill does with search results

Searches run against the local [voidtools Everything](https://www.voidtools.com/)
index over Everything's local inter-process communication (IPC). Queries and
results stay on your computer as far as this repository's code is concerned.
The scripts print results to standard output and do nothing else with them.

The scripts never open, read the contents of, execute, move, rename, delete, or
upload a file that a search returns. They read file metadata only: path, name,
type, size, modification time, and attributes.

## Important limitation

**This skill cannot promise that data never leaves your computer.**

The skill runs inside a coding agent that you choose. When the agent reads a
search result, the file paths and metadata in that result are handled by that
agent and may be transmitted to and processed by its provider. That is outside
this project's control and is governed by your agent provider's own privacy
policy, not by this document. Treat file paths as data you are sharing with your
agent provider.

## Network activity

The skill performs no network requests when detecting Everything or running a
search.

`setup_backend.ps1` is the only script that uses the network. It runs only when
you invoke it, downloads only from `https://www.voidtools.com/`, and writes only
under `%LOCALAPPDATA%\EverythingAgent`. It sends no data about you.

The skill never enables Everything's HTTP or ETP server and never exposes
Everything over a network, an MCP server, or any other remote interface.

## Installation tooling

If you install with the Skills CLI (`npx skills add ...`), that tool is a
separate third-party project with its own telemetry, which it documents at
<https://www.skills.sh/docs/cli>. Installing through Claude Code plugins,
Codex plugins, or a manual copy does not involve it.

## Third parties

This project is not affiliated with, endorsed by, or sponsored by voidtools.
Everything is voidtools' software and has its own terms and privacy practices.

## Contact

Report a privacy concern at
<https://github.com/ravegoth/everything-agent-skill/issues>.
