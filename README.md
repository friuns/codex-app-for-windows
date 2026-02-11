# Codex Desktop on Windows

Run the [OpenAI Codex Desktop](https://openai.com/index/introducing-codex/) app on Windows -- ported from the official macOS Electron build.


https://github.com/user-attachments/assets/7fa4ffce-8639-4c80-b791-3b45126ee4a7


## Prerequisites

| Requirement | Auto-installed? | Notes |
|---|---|---|
| **Windows 10 1709+** or **Windows 11** | -- | Needed for `winget` |
| **winget** (App Installer) | Ships with Windows | Used to install everything else |
| **Node.js** v20+ | Yes (via winget) | Core runtime |
| **7-Zip** | Yes (via winget) | For DMG extraction |
| **@openai/codex CLI** | Yes (via npm) | Backend CLI binary |
| **Python 3.12** *(optional)* | Yes (via winget) | For native module compilation |
| **VS Build Tools 2022** *(optional)* | Yes (via winget) | For terminal/PTY support |

> **All tools are installed automatically** on first run if missing. You only need `winget` (pre-installed on modern Windows). The script will prompt for confirmation if elevated installs are needed.

## Quick Start

### 1. Launch

```cmd
launch_codex_mac_on_windows.cmd
```

That's it. **No manual downloads needed.** The script handles everything automatically:
- Downloads the Codex DMG from OpenAI if not found locally (~144 MB)
- Installs missing tools (Node.js, 7-Zip, Python, VS Build Tools, Codex CLI)
- Extracts `Codex.app` from the DMG (via 7-Zip)
- Unpacks the Electron app
- Detects the correct Electron version
- Downloads/compiles Windows-compatible native modules
- Patches the renderer for Windows compatibility
- Launches the app

You can also provide a DMG or Codex.app manually if you prefer:

```cmd
REM Pass a .dmg file you already downloaded
launch_codex_mac_on_windows.cmd "C:\Downloads\Codex.dmg"

REM Pass a Codex.app folder
launch_codex_mac_on_windows.cmd "C:\Downloads\Codex.app"
```

> The script also checks next to itself and your `Downloads` folder for existing `.dmg` files before downloading.

On first run this takes a few minutes (downloading Electron + native modules). Subsequent launches take seconds -- all intermediate work is cached.

### 2. Sign in

The app opens a window. Sign in with your OpenAI / ChatGPT account. You need an active Codex subscription.

## Re-running

Just run the same command again:

```cmd
launch_codex_mac_on_windows.cmd
```

Every step is idempotent -- if it was already done, it's skipped.

## Updating Codex

When a new Codex version is released, download the new DMG and drop it next to the script (replacing the old one). Then force a fresh unpack:

```cmd
rmdir /s /q "%TEMP%\codex-electron-win"
launch_codex_mac_on_windows.cmd
```

The script will re-extract the DMG, re-patch, and update the CLI automatically.

## Troubleshooting

### App crashes immediately with "Oops, an error has occurred"

The renderer patch may need to be re-applied. Delete the patch marker:

```cmd
del "%TEMP%\codex-electron-win\app\.win-process-patched"
```

Then re-launch.

### "Codex CLI binary not found"

The script tries to install it automatically. If that fails, install manually:

```cmd
npm install -g @openai/codex
```

### Native module errors (MODULE_NOT_FOUND, DLOPEN_FAILED)

Re-install native modules:

```cmd
del "%TEMP%\codex-electron-win\app\.win-natives-ok"
launch_codex_mac_on_windows.cmd
```

### Terminal not working

The built-in terminal requires `node-pty`, which must be compiled from source using Visual Studio Build Tools. The script tries to install VS Build Tools automatically via winget. If that fails, install [VS Build Tools 2022](https://aka.ms/vs/17/release/vs_BuildTools.exe) manually with the **"Desktop development with C++"** workload, then force a re-build:

```cmd
del "%TEMP%\codex-electron-win\app\.win-natives-ok"
launch_codex_mac_on_windows.cmd
```

### Disk cache warnings

Messages like `Unable to move the cache: Access is denied` are cosmetic and don't affect functionality. They occur when a previous Electron instance is still using the cache directory.

### Force a completely fresh start

```cmd
rmdir /s /q "%TEMP%\codex-electron-win"
launch_codex_mac_on_windows.cmd
```

## How It Works

The launch script ports the macOS Codex Electron app to Windows by:

1. **Auto-installing** any missing tools (Node.js, 7-Zip, Python, VS Build Tools, Codex CLI) via `winget` and `npm`
1. **Extracting** `Codex.app` from a `.dmg` file using 7-Zip (if a DMG is provided instead of a pre-extracted app)
1. **Finding** the `Codex.app` folder (next to the script, in Downloads, or from the command line) and unpacking the `app.asar` archive
2. **Replacing native modules** (`better-sqlite3`, `node-pty`) with Windows-compiled versions
3. **Patching the renderer** to provide a `process` global (required by the app but unavailable in Electron's sandboxed renderer on Windows)
4. **Launching** the unpacked app using the matching Electron version

See [guide.md](guide.md) for the full technical deep-dive.

## Files

| File | Description |
|---|---|
| `Codex.app/` | macOS app bundle (extracted from DMG automatically or by the user) |
| `Codex*.dmg` | *(optional)* macOS DMG -- auto-extracted on first run |
| `launch_codex_mac_on_windows.cmd` | Main script -- installs tools, extracts DMG, unpacks, patches, and launches |
| `README.md` | This file |
| `guide.md` | Detailed technical guide on the porting process |

All cached/intermediate files live in `%TEMP%\codex-electron-win\` and are not part of this repo.
