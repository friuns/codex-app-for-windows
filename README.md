# Codex Desktop on Windows

Run the [OpenAI Codex Desktop](https://openai.com/index/introducing-codex/) app on Windows -- ported from the official macOS Electron build.


https://github.com/user-attachments/assets/7fa4ffce-8639-4c80-b791-3b45126ee4a7


## Prerequisites

| Requirement | Install |
|---|---|
| **Node.js** v20+ | https://nodejs.org |
| **@openai/codex CLI** | `npm install -g @openai/codex` |
| **Visual Studio Build Tools 2022** *(optional, for terminal/PTY)* | [Download](https://aka.ms/vs/17/release/vs_BuildTools.exe) -- select **"Desktop development with C++"** |
| **Python 3.12** *(optional, for native compilation)* | https://www.python.org |

> VS Build Tools and Python are only needed if you want the built-in terminal to work. The app launches and functions without them (terminal features will be disabled).

## Quick Start

### 1. Get the Codex.app folder

Download the official Codex DMG from [OpenAI](https://openai.com/index/introducing-codex/).

Extract the `Codex.app` folder from the DMG:

- **On a Mac**: Double-click the `.dmg` to mount it, then drag `Codex.app` to a folder (e.g. a USB drive or shared folder).
- **On Windows**: Use [7-Zip](https://www.7-zip.org/) (free) to open the `.dmg` file and extract the `Codex.app` folder. Right-click the DMG > **7-Zip** > **Open archive**, then navigate inside and drag `Codex.app` out.

Place the `Codex.app` folder next to the launch script:

```
codexwin/
├── Codex.app/          <-- put it here
├── launch_codex_mac_on_windows.cmd
├── README.md
└── guide.md
```

### 2. Launch

```cmd
launch_codex_mac_on_windows.cmd
```

That's it. The script detects `Codex.app` automatically and handles everything:
- Unpacks the Electron app
- Detects the correct Electron version
- Downloads/compiles Windows-compatible native modules
- Patches the renderer for Windows compatibility
- Launches the app

You can also pass a path to `Codex.app` if it's located elsewhere:

```cmd
launch_codex_mac_on_windows.cmd "C:\Downloads\Codex.app"
```

On first run this takes a few minutes (downloading Electron + native modules). Subsequent launches take seconds -- all intermediate work is cached.

### 3. Sign in

The app opens a window. Sign in with your OpenAI / ChatGPT account. You need an active Codex subscription.

## Re-running

Just run the same command again:

```cmd
launch_codex_mac_on_windows.cmd
```

Every step is idempotent -- if it was already done, it's skipped.

## Updating Codex

When a new Codex version is released, download the new DMG and replace the `Codex.app` folder. Then force a fresh unpack:

```cmd
rmdir /s /q "%TEMP%\codex-electron-win"
launch_codex_mac_on_windows.cmd
```

Also update the CLI:

```cmd
npm install -g @openai/codex
```

## Troubleshooting

### App crashes immediately with "Oops, an error has occurred"

The renderer patch may need to be re-applied. Delete the patch marker:

```cmd
del "%TEMP%\codex-electron-win\app\.win-process-patched"
```

Then re-launch.

### "Codex CLI binary not found"

Install the Codex CLI globally:

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

The built-in terminal requires `node-pty`, which must be compiled from source using Visual Studio Build Tools. Install [VS Build Tools 2022](https://aka.ms/vs/17/release/vs_BuildTools.exe) with the **"Desktop development with C++"** workload, then force a re-build:

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

1. **Finding** the `Codex.app` folder (next to the script or from the command line) and unpacking the `app.asar` archive
2. **Replacing native modules** (`better-sqlite3`, `node-pty`) with Windows-compiled versions
3. **Patching the renderer** to provide a `process` global (required by the app but unavailable in Electron's sandboxed renderer on Windows)
4. **Launching** the unpacked app using the matching Electron version

See [guide.md](guide.md) for the full technical deep-dive.

## Files

| File | Description |
|---|---|
| `Codex.app/` | macOS app bundle (extracted from DMG by the user) |
| `launch_codex_mac_on_windows.cmd` | Main script -- unpacks, patches, and launches the app |
| `README.md` | This file |
| `guide.md` | Detailed technical guide on the porting process |

All cached/intermediate files live in `%TEMP%\codex-electron-win\` and are not part of this repo.
