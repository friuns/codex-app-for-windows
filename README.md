# Codex Desktop on Windows

Run the [OpenAI Codex Desktop](https://openai.com/index/introducing-codex/) app on Windows by porting the official macOS Electron build.

https://github.com/user-attachments/assets/7fa4ffce-8639-4c80-b791-3b45126ee4a7

## Captured Frames

| 30s frame | Last frame |
|---|---|
| ![Frame at 30 seconds](images/Cursor_giCQLZ2ZHl_40s_frame_30s.png) | ![Last frame](images/Cursor_giCQLZ2ZHl_40s_frame_last.png) |

## TL;DR

```cmd
launch_codex_mac_on_windows.cmd
```

The launcher auto-installs dependencies, extracts/unpacks Codex, patches for Windows, and runs the app.

## Prerequisites

| Requirement | Auto-installed? | Notes |
|---|---|---|
| **Windows 10 (1709+) / Windows 11** | No | Required for `winget` |
| **winget** (App Installer) | Ships with Windows | Used for package installs |
| **Node.js v20+** | Yes | Runtime |
| **7-Zip** | Yes | DMG extraction |
| **@openai/codex CLI** | Yes | Backend CLI |
| **Python 3.12** *(optional)* | Yes | Native module builds |
| **VS Build Tools 2022** *(optional)* | Yes | `node-pty` compilation |

> First run can take a few minutes. Later runs are fast due to caching in `%TEMP%\codex-electron-win\`.

## Quick Start

### 1. Launch

```cmd
launch_codex_mac_on_windows.cmd
```

Optional inputs:

```cmd
REM Use a DMG you already downloaded
launch_codex_mac_on_windows.cmd "C:\Downloads\Codex.dmg"

REM Use a pre-extracted Codex.app
launch_codex_mac_on_windows.cmd "C:\Downloads\Codex.app"
```

### 2. Sign in

Sign in with your OpenAI / ChatGPT account (active Codex subscription required).

## Re-run

```cmd
launch_codex_mac_on_windows.cmd
```

The script is idempotent and skips completed steps.

## Update Codex

Replace with a newer DMG, then force a clean unpack:

```cmd
rmdir /s /q "%TEMP%\codex-electron-win"
launch_codex_mac_on_windows.cmd
```

## Troubleshooting

### App crashes ("Oops, an error has occurred")

```cmd
del "%TEMP%\codex-electron-win\app\.win-process-patched"
launch_codex_mac_on_windows.cmd
```

### "Codex CLI binary not found"

```cmd
npm install -g @openai/codex
```

### Native module errors (`MODULE_NOT_FOUND`, `DLOPEN_FAILED`)

```cmd
del "%TEMP%\codex-electron-win\app\.win-natives-ok"
launch_codex_mac_on_windows.cmd
```

### Terminal not working (`node-pty`)

Install [VS Build Tools 2022](https://aka.ms/vs/17/release/vs_BuildTools.exe) with **Desktop development with C++**, then rebuild:

```cmd
del "%TEMP%\codex-electron-win\app\.win-natives-ok"
launch_codex_mac_on_windows.cmd
```

### Disk cache warnings

`Unable to move the cache: Access is denied` is usually cosmetic and safe to ignore.

### Fully reset everything

```cmd
rmdir /s /q "%TEMP%\codex-electron-win"
launch_codex_mac_on_windows.cmd
```

## How It Works

The launcher:

1. Installs missing dependencies via `winget`/`npm`.
2. Extracts `Codex.app` from DMG (if needed).
3. Unpacks `app.asar`.
4. Rebuilds/replaces native modules for Windows (`better-sqlite3`, `node-pty`).
5. Patches renderer process compatibility.
6. Starts the app with the matching Electron version.

See [guide.md](guide.md) for implementation details.

## Repository Files

| Path | Purpose |
|---|---|
| `launch_codex_mac_on_windows.cmd` | Main launcher/patcher |
| `Codex.app/` | Optional local macOS app bundle |
| `Codex*.dmg` | Optional DMG input |
| `guide.md` | Technical deep dive |
| `README.md` | Usage overview |
| `images/` | README screenshots |
