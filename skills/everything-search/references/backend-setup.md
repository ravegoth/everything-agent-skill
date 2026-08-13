# Backend setup

Everything must be installed and running in the same Windows user session as the agent. The full Everything application is available from `https://www.voidtools.com/downloads/`.

The skill does not bundle third-party binaries. It detects two official query backends:

- Everything SDK: the architecture-matched `Everything64.dll`, `Everything32.dll`, `EverythingARM64.dll`, or `EverythingARM.dll`
- Everything CLI: `es.exe`

## Preferred SDK setup

Ask the user before downloading. Then run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\scripts\setup_backend.ps1" -Component Sdk -Confirm
```

The script downloads `https://www.voidtools.com/Everything-SDK.zip` and extracts it under `%LOCALAPPDATA%\EverythingAgent\SDK`. Detection checks this location automatically.

Use `-WhatIf` to show the planned destination without changing the machine.

## CLI fallback

Ask the user before downloading. Then run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\scripts\setup_backend.ps1" -Component Es -Confirm
```

The script selects the official ES archive for the current Windows architecture and extracts it under `%LOCALAPPDATA%\EverythingAgent\CLI`.

## Troubleshooting

- `Everything is installed but is not currently running`: start the detected executable and retry.
- IPC error: ensure Everything and PowerShell run in the same interactive user session. A service alone is not the GUI/IPC server.
- Wrong DLL architecture: match the PowerShell process to `Everything64.dll`, `Everything32.dll`, `EverythingARM64.dll`, or `EverythingARM.dll`.
- Everything 1.5 custom instance: the SDK defaults to the standard instance. Disable the alpha instance or deliberately configure a compatible instance before retrying.
- Lite edition: use the full Everything application. Some integrations do not support Lite.
