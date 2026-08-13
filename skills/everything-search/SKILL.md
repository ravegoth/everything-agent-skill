---
name: everything-search
description: Find files and folders instantly on a local Windows computer through voidtools Everything. Use when an agent needs to locate files by name, path, extension, size, date, attributes, or indexed content; inspect whether Everything and its SDK/CLI backend are installed; or return machine-readable search results for further coding work. Do not use on non-Windows systems or for remote computers.
---

# Everything Search

Use the bundled PowerShell scripts as the stable interface to Everything. Keep searches read-only unless the user separately authorizes a file mutation.

## Workflow

1. Confirm the session is running on Windows.
2. Locate this skill directory (the directory containing this `SKILL.md`). Use absolute paths when invoking scripts.
3. Run detection before every first search in a session:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\scripts\detect_everything.ps1" -Pretty
   ```

4. Inspect the JSON response:
   - `everything.installed=false`: explain that the Everything application is required and point to `https://www.voidtools.com/downloads/`. Do not install software without approval.
   - `everything.running=false`: start the detected `Everything.exe` only when the user asked to search or approved starting it, then rerun detection.
   - `backend.ready=true`: continue.
   - `backend.ready=false`: read [backend-setup.md](references/backend-setup.md). Ask before downloading the official SDK or ES CLI.
5. Translate the user's intent into Everything syntax. Read [search-syntax.md](references/search-syntax.md) for operators and examples.
6. Query through the wrapper:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\scripts\search_everything.ps1" -Query 'ext:ps1 dm:today' -MaxResults 100 -Pretty
   ```

7. Parse stdout as JSON. Treat stderr or a nonzero exit code as failure. Report the exact query and whether results were truncated.

## Backend selection

Prefer backends in this order:

1. `Everything64.dll` or `Everything32.dll` from the official Everything SDK.
2. `es.exe` from the official Everything command-line interface.

The wrapper selects automatically. Use `-Backend Dll` only when DLL behavior must be tested, or `-Backend Es` when diagnosing the CLI fallback.

For custom native integration, read [dll-api.md](references/dll-api.md). Prefer the bundled wrapper for ordinary searches because it handles architecture, request flags, Unicode paths, JSON serialization, and errors.

## Query rules

- Use filename/index queries first; they are effectively instant.
- Scope broad searches with a path, extension, size, or date.
- Use `content:` only when necessary. It can be slow and depends on Everything content indexing.
- Set a realistic `-MaxResults`; begin with 100 and raise it only when needed.
- Quote PowerShell arguments. Never concatenate untrusted text into a command string or call `Invoke-Expression`.
- Everything IPC is local-only. Never imply this skill can search another computer without a separately configured remote service.

## Safety

- Searching and reading metadata are allowed within the user's task.
- Do not open sensitive-looking files merely because a query found them; disclose paths minimally and ask when content access is not clearly authorized.
- Do not delete, move, rename, upload, or execute results unless the user explicitly asks.
- Do not enable Everything HTTP/ETP servers for this skill. The DLL and ES backends remain local.
