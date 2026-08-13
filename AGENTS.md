# Agent instructions

This repository distributes one read-only Windows Agent Skill at `skills/everything-search`.

When asked to install it:

1. Read `README.md` and `skills/everything-search/SKILL.md` before executing scripts.
2. Identify the current host's documented personal or project skill directory.
3. Copy the complete `skills/everything-search` directory. Preserve `scripts`, `references`, and `agents` relative to `SKILL.md`.
4. Validate that the installed `SKILL.md` frontmatter contains only `name` and `description` and that its name is `everything-search`.
5. Run `scripts/detect_everything.ps1 -Pretty` first.
6. Do not download or install Everything, the SDK, or ES without explicit user approval.
7. Use a harmless query with `-MaxResults 10` to smoke-test a ready backend.
8. Never enable a network server or mutate a search result as part of installation.

Host locations documented by their vendors:

- Codex personal: `$HOME/.agents/skills/everything-search`
- Claude Code personal: `$HOME/.claude/skills/everything-search`
- Claude plugin: use this repository's `.claude-plugin/marketplace.json`

When modifying this repository, keep the skill host-neutral. Put OpenAI-specific UI metadata only in `agents/openai.yaml` and Claude distribution metadata only in `.claude-plugin`.
