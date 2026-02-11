# Porting Codex Mac Electron App to Windows

## Overview

This guide documents the process of porting the **OpenAI Codex Desktop** application
(originally built for macOS) to run on Windows. The Mac app is an Electron-based
desktop application. Since Electron is cross-platform, the core JavaScript code
runs on Windows -- but native (C/C++) Node.js modules bundled for macOS must be
replaced with Windows-compatible equivalents.

The entire workflow is automated by `launch_codex_mac_on_windows.cmd`.

---

## Prerequisites

| Tool | Purpose | Install |
|------|---------|---------|
| **Node.js** (v20+) | JavaScript runtime + npm/npx | https://nodejs.org |
| **Python 3.12** | Required by node-gyp for native compilation | https://www.python.org |
| **Visual Studio Build Tools 2022** | C++ compiler for native Node.js addons | https://aka.ms/vs/17/release/vs_BuildTools.exe (select "Desktop development with C++") |
| **@openai/codex CLI** | The Codex CLI binary the app communicates with | `npm install -g @openai/codex` |

---

## Architecture

```
Codex-mac-full.zip           (Mac archive, downloaded or local)
  └── Codex.app/
       └── Contents/Resources/
            └── app.asar      (Electron archive containing the full app)

app.asar  ──(npx @electron/asar extract)──►  unpacked app/
  ├── package.json            (Electron entry point, dependencies)
  ├── .vite/build/
  │    ├── main-BLcwFbOH.js   (main process - Node.js)
  │    └── preload.js          (bridge between main ↔ renderer)
  ├── webview/
  │    ├── index.html          (renderer HTML entry)
  │    └── assets/
  │         └── index-*.js     (bundled React app)
  └── node_modules/
       ├── better-sqlite3/     (native: SQLite bindings)
       ├── node-pty/           (native: pseudo-terminal)
       └── ...
```

**Key insight**: The JavaScript code is cross-platform. Only the **native modules**
(`.node` files compiled from C/C++) are platform-specific. Replace those and the
app runs on Windows.

---

## Step-by-Step Porting Process

### Step 1: Acquire the Mac Archive

The script accepts either a local `.zip` path or an HTTPS URL. It caches the
archive at `%TEMP%\codex-electron-win\codex-mac.zip` so subsequent runs skip
the download.

```
launch_codex_mac_on_windows.cmd "C:\Downloads\Codex-mac-full.zip"
```

### Step 2: Extract the Archive

PowerShell `Expand-Archive` unzips the `.zip` into `%TEMP%\codex-electron-win\extracted\`.
The script looks for the `Codex.app` bundle inside.

### Step 3: Locate and Unpack `app.asar`

The core application code lives in `Codex.app/Contents/Resources/app.asar`.
This is Electron's archive format. We unpack it with:

```
npx -y @electron/asar extract <app.asar path> <output dir>
```

This produces a full `app/` directory with `package.json`, source bundles,
and `node_modules/`.

### Step 4: Detect Electron Version

The script reads `package.json` to find the exact Electron version used by the
app (e.g. `electron@40.0.0`). This is critical because native modules must be
compiled against the same **ABI (Application Binary Interface)** version.

### Step 5: Replace Native Modules

This is the hardest part. The Mac archive ships with `.dylib` and Darwin `.node`
binaries that won't load on Windows.

#### better-sqlite3

**Strategy**: Download precompiled Windows binaries from GitHub Releases.

The [better-sqlite3](https://github.com/WiseLibs/better-sqlite3) project
publishes prebuilt `.node` files for various platform/ABI combinations:

```
better-sqlite3-v12.6.2-electron-v143-win32-x64.tar.gz
```

Steps:
1. Delete the Mac `build/` and `prebuilds/` directories
2. Download the correct tarball from GitHub
3. Extract it into `node_modules/better-sqlite3/build/Release/`
4. Verify `better_sqlite3.node` exists

#### node-pty

**Strategy**: Install a fresh Windows-compatible version.

`node-pty` provides pseudo-terminal (PTY) support. The Mac version ships with
Darwin-only `spawn-helper` and `pty.node`. On Windows, node-pty needs either
ConPTY (modern) or WinPTY (legacy) support.

**Approach A** -- Isolated npm install (what worked):
```
mkdir %TEMP%\npty-install
cd %TEMP%\npty-install
npm init -y
npm install node-pty@1.1.0
xcopy node_modules\node-pty <app>\node_modules\node-pty /E /I /Y
```

This avoids conflicts with `workspace:*` dependencies in the app's
`package.json` and provides a fully compiled Windows binary with ConPTY support.

**Approach B** -- `@electron/rebuild` (may fail if Mac source lacks `winpty.gyp`):
```
npx -y @electron/rebuild --version 40.0.0 --module-dir node_modules/node-pty --force
```

This failed because the Mac-packaged source didn't include `deps/winpty/src/winpty.gyp`.

#### Other Mac-only Files

- `*.dylib` files are removed (macOS shared libraries)
- `sparkle.node` (Mac auto-update framework) is ignored
- `fsevents` (Mac filesystem watcher) is not needed on Windows

### Step 5b: Patch the Renderer (Process Polyfill)

The webview (renderer process) references `process.platform`, `process.cwd()`,
and other Node.js globals that Electron sandboxes away. We patch two files:

**preload.js** -- Append code that exposes a `__processShim` via
`contextBridge.exposeInMainWorld()`:

```javascript
n.contextBridge.exposeInMainWorld("__processShim", {
  cwd: process.cwd(),
  platform: process.platform,
  version: process.version,
  arch: process.arch,
  env: { NODE_ENV: process.env.NODE_ENV, ... }
});
```

**webview/index.html** -- Inject a `<script>` tag that creates a full
`window.process` object from the shim:

```html
<script>
window.process = {
  ...window.__processShim,
  cwd: function() { return window.__processShim.cwd },
  nextTick: function(cb) { setTimeout(cb, 0) },
  // ... event emitter stubs
};
</script>
```

The Content-Security-Policy header is also updated with the script's hash.

### Step 6: Resolve the Codex CLI

The app expects a `codex.exe` binary to communicate with. The script looks in:
1. `CODEX_CLI_PATH` environment variable
2. npm global prefix: `node_modules/@openai/codex/vendor/x86_64-pc-windows-msvc/codex/codex.exe`
3. `where codex.exe` (PATH search)

If not found, install with: `npm install -g @openai/codex`

### Step 7: Launch with Electron

```
npx -y electron@40.0.0 "%TEMP%\codex-electron-win\app"
```

Environment variables set:
- `CODEX_CLI_PATH` -- path to `codex.exe`
- `ELECTRON_FORCE_IS_PACKAGED=true` -- tells Electron this is a packaged app

---

## Current Status

| Feature | Status | Notes |
|---------|--------|-------|
| Archive extraction | Working | Cached, skips on re-run |
| app.asar unpacking | Working | Uses `@electron/asar` |
| Electron version detection | Working | Reads from `package.json` |
| better-sqlite3 | Working | Precompiled binary from GitHub |
| node-pty | Working | Compiled via `@electron/rebuild` (requires VS Build Tools) |
| Codex CLI resolution | Working | Found via npm global prefix |
| App launch | **Working** | Window opens, authenticates, loads full UI |
| Renderer process polyfill | **Working** | `process` shim injected into renderer |
| Terminal/PTY | Working | Terminal attaches and shell spawns |
| Thread management | Working | Conversations load, create, archive |
| Authentication | Working | ChatGPT auth flow completes |
| Git integration | Partial | Fails gracefully if workspace is not a git repo |

The app is fully functional on Windows.

### Resolved: "Oops, an error has occurred" Crash

The original crash (`[ErrorBoundary:AppRoutes] error(name=ReferenceError)`) was
caused by the renderer process referencing the Node.js `process` global, which
is not available in Electron's sandboxed renderer context.

**Diagnosis method**: Setting `ELECTRON_ENABLE_LOGGING=true` surfaced the full
error in the terminal:

```
"ReferenceError: process is not defined"
  source: app://-/assets/index-BnRAGF7J.js (176)
```

**Root cause**: The Codex Desktop webview code accesses `process.cwd()`,
`process.platform`, and other Node.js globals. In the official Mac Electron
build these are available (likely via `nodeIntegration` or a build-time
polyfill), but when running through a standalone Windows Electron via `npx`,
the renderer is sandboxed and `process` is `undefined`.

**Fix** (automated in step 5b of the launch script):

1. **preload.js** -- Append code that captures `process` data in the preload
   context (where Node.js is available) and exposes it to the renderer via
   `contextBridge.exposeInMainWorld("__processShim", {...})`.

2. **webview/index.html** -- Inject an inline `<script>` before the app bundle
   that reconstructs `window.process` from the shim, including:
   - `cwd()` as a function returning the captured working directory
   - `nextTick()` shimmed via `setTimeout`
   - Event emitter stubs (`on`, `off`, `emit`, etc.)

3. **CSP update** -- The Content-Security-Policy `script-src` directive is
   updated with the SHA-256 hash of the injected script so it passes the
   integrity check.

Both patches are idempotent (check for `__processShim` before applying) and
cached via a `.win-process-patched` marker file.

---

## File Structure

```
codexwin/
├── launch_codex_mac_on_windows.cmd   (main porting script)
├── README.md                          (quick-start instructions)
├── guide.md                           (this file -- deep technical guide)
└── .gitignore                         (excludes binaries and temp files)
```

Working directory (cached, not in repo):
```
%TEMP%\codex-electron-win/
├── codex-mac.zip              (cached archive)
├── extracted/
│   └── Codex.app/             (extracted Mac bundle)
├── app/                       (unpacked asar -- the actual app code)
│   ├── package.json
│   ├── .vite/build/           (main process + preload)
│   ├── webview/               (renderer / React UI)
│   ├── node_modules/          (with replaced native modules)
│   ├── .win-natives-ok        (marker: native modules installed)
│   └── .win-process-patched   (marker: renderer patched)
└── bsq-prebuild.tar.gz       (cached better-sqlite3 download)
```

---

## Troubleshooting

### "Unable to locate the Codex CLI binary"
Install the CLI: `npm install -g @openai/codex`

### Native module errors (MODULE_NOT_FOUND, DLOPEN_FAILED)
Delete the marker file and re-run:
```
del "%TEMP%\codex-electron-win\app\.win-natives-ok"
launch_codex_mac_on_windows.cmd "C:\Downloads\Codex-mac-full.zip"
```

### Force a completely fresh start
```
rmdir /s /q "%TEMP%\codex-electron-win"
launch_codex_mac_on_windows.cmd "C:\Downloads\Codex-mac-full.zip"
```

### Disk cache errors
`[ERROR:disk_cache.cc] Unable to create cache` -- cosmetic only, does not
affect functionality. Caused by multiple Electron instances sharing cache dirs.

### "Oops, an error has occurred" / ReferenceError: process is not defined
This was the main porting blocker. It is now fixed by the renderer patch
(step 5b). If it reappears after a Codex update changes the webview bundle:
```
del "%TEMP%\codex-electron-win\app\.win-process-patched"
```
Then re-run the launch script to re-apply patches.

### Renderer patch not applying
If the CSP blocks the inline script (console shows "Refused to execute inline
script"), the app bundle was updated and the CSP hash changed. Delete the
patch marker and the app directory, then re-run from scratch:
```
del "%TEMP%\codex-electron-win\app\.win-process-patched"
rmdir /s /q "%TEMP%\codex-electron-win\app"
```

---

## Tools & Versions Used

- Node.js 22.15.0
- npm 10.9.2
- Electron 40.0.0 (matched from app's `package.json`)
- Python 3.12 (for node-gyp / native compilation)
- Visual Studio Build Tools 2022 (C++ workload)
- `@electron/asar` (asar extraction)
- `@electron/rebuild` (attempted for node-pty)
- `better-sqlite3@12.6.2` (prebuilt for electron-v143-win32-x64)
- `node-pty@1.1.0` (installed via isolated npm)
- `@openai/codex` (CLI binary)

---

## Lessons Learned

1. **Electron ABI mismatch is the #1 killer.** Node.js ABI 127 != Electron 40 ABI 143.
   Native modules compiled for one won't load in the other. Always use prebuilds
   tagged with the exact Electron ABI or rebuild with `@electron/rebuild`.

2. **Mac-packaged native modules strip Windows build deps.** The `node-pty` in
   the Mac archive didn't include `deps/winpty/`, so `@electron/rebuild` failed.
   Solution: install a fresh copy from npm in an isolated directory.

3. **`workspace:*` in `package.json` breaks `npm install`.** The Mac app uses
   monorepo `workspace:*` dependencies. Running `npm install` inside the
   unpacked app dir fails with `EUNSUPPORTEDPROTOCOL`. Workaround: install
   modules in a separate temp directory and copy them over.

4. **Electron's `-e` flag doesn't output to console on Windows.** Unlike Node.js,
   `electron -e "console.log(...)"` doesn't write to the parent terminal.
   Write to a file instead for testing.

5. **Precompiled binaries save hours.** `better-sqlite3` publishes prebuilds
   on GitHub Releases for every Electron ABI. Downloading a 2 MB tarball is
   infinitely faster than setting up a full C++ toolchain.

6. **Renderer sandboxing matters.** The webview can't access `process` directly.
   A preload script + `contextBridge.exposeInMainWorld()` is the correct way
   to pass Node.js data to the renderer. But `contextBridge` only serializes
   plain data -- functions are stripped. The workaround is a two-stage approach:
   expose data from the preload, then reconstruct the API (with functions) via
   an inline script in the HTML.

7. **`ELECTRON_ENABLE_LOGGING=true` is essential for debugging.** Electron's
   default logging truncates renderer console output. Setting this env var
   surfaces full `console.error()` messages from the webview in the terminal,
   which was the key to identifying `ReferenceError: process is not defined`.

8. **CSP hashes must match exactly.** When injecting inline scripts into an
   Electron app with a Content-Security-Policy, the SHA-256 hash of the script
   content must be added to the `script-src` directive. Even a single byte
   difference (whitespace, newline) will cause the script to be blocked.
