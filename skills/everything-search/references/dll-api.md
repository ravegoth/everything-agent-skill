# Everything SDK integration

Official documentation:

- SDK overview: `https://www.voidtools.com/support/everything/sdk/`
- IPC: `https://www.voidtools.com/support/everything/sdk/ipc/`
- Query: `https://www.voidtools.com/support/everything/sdk/everything_query/`
- Search syntax: `https://www.voidtools.com/support/everything/searching/`

Everything's SDK DLL is a local IPC client. It does not contain the index and cannot query unless Everything is running.

## Minimal call order

1. Load the DLL matching the process architecture.
2. Call `Everything_Reset`.
3. Call `Everything_SetSearchW` with Unicode search text.
4. Call `Everything_SetMax` and `Everything_SetRequestFlags`.
5. Call `Everything_QueryW(TRUE)`.
6. Check `Everything_GetNumResults` and `Everything_GetTotResults`.
7. Read each result using `Everything_GetResultFullPathNameW` and requested metadata getters.
8. On failure, call `Everything_GetLastError`.

## Request flags used by the wrapper

| Flag | Value | Getter |
|---|---:|---|
| file name | `0x00000001` | `Everything_GetResultFileNameW` |
| full path | `0x00000004` | `Everything_GetResultFullPathNameW` |
| size | `0x00000010` | `Everything_GetResultSize` |
| modified date | `0x00000040` | `Everything_GetResultDateModified` |
| attributes | `0x00000100` | `Everything_GetResultAttributes` |

Use wide (`W`) functions consistently for Windows Unicode paths. Convert returned modification dates from Windows `FILETIME` to UTC. Allocate path buffers large enough for extended Windows paths; the wrapper uses 32,768 UTF-16 characters.

Do not expose the SDK through a network listener merely to make it agent-accessible. Invoke the local wrapper from the coding agent's normal shell tool.
