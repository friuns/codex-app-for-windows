@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ============================================================================
REM Codex Desktop on Windows -- launch script
REM
REM Accepts any of:
REM   - No arguments     (auto-detects Codex.app or .dmg next to script)
REM   - Path to Codex.app folder
REM   - Path to a .dmg file (auto-extracted via 7-Zip)
REM
REM Missing tools (Node.js, 7-Zip, Python, VS Build Tools, @openai/codex)
REM are downloaded and installed automatically via winget / npm.
REM ============================================================================

set "SCRIPT_DIR=%~dp0"
set "CODEX_APP="
set "DMG_FILE="

REM ============================================================================
REM Phase 0: Ensure required tools are installed
REM ============================================================================
call :ensure_tools
if errorlevel 1 (
  echo [FATAL] Could not install required tools. Exiting.
  exit /b 1
)

REM ============================================================================
REM Phase 1: Locate Codex.app (from argument, .dmg, or auto-detect)
REM ============================================================================

REM ---- Check command-line argument ----
if not "%~1"=="" (
  REM Is it a .dmg file?
  if /I "%~x1"==".dmg" (
    if exist "%~1" (
      set "DMG_FILE=%~1"
      echo [INFO] DMG file supplied: !DMG_FILE!
      goto :extract_dmg
    ) else (
      echo [ERROR] DMG file not found: %~1
      goto :usage
    )
  )
  REM Is it a Codex.app folder?
  if exist "%~1\Contents\Resources\app.asar" (
    set "CODEX_APP=%~1"
    echo [INFO] Using supplied Codex.app: !CODEX_APP!
    goto :have_app
  )
  REM Is it a folder containing Codex.app?
  if exist "%~1\Codex.app\Contents\Resources\app.asar" (
    set "CODEX_APP=%~1\Codex.app"
    echo [INFO] Found Codex.app inside: !CODEX_APP!
    goto :have_app
  )
  echo [ERROR] "%~1" is not a valid Codex.app folder or .dmg file.
  goto :usage
)

REM ---- Auto-detect Codex.app next to script ----
if exist "%SCRIPT_DIR%Codex.app\Contents\Resources\app.asar" (
  set "CODEX_APP=%SCRIPT_DIR%Codex.app"
  echo [INFO] Found Codex.app next to script: !CODEX_APP!
  goto :have_app
)

REM ---- Auto-detect .dmg next to script ----
for %%F in ("%SCRIPT_DIR%*.dmg") do (
  if not defined DMG_FILE (
    set "DMG_FILE=%%~fF"
    echo [INFO] Found DMG next to script: !DMG_FILE!
  )
)
if defined DMG_FILE goto :extract_dmg

REM ---- Auto-detect .dmg in Downloads folder ----
for %%F in ("%USERPROFILE%\Downloads\Codex*.dmg") do (
  if not defined DMG_FILE (
    set "DMG_FILE=%%~fF"
    echo [INFO] Found DMG in Downloads: !DMG_FILE!
  )
)
if defined DMG_FILE goto :extract_dmg

REM ---- Nothing found -- download automatically ----
echo.
echo [INFO] Codex.app and .dmg not found locally. Downloading from OpenAI...
set "DMG_DOWNLOAD_URL=https://persistent.oaistatic.com/codex-app-prod/Codex.dmg"
set "DMG_FILE=%SCRIPT_DIR%Codex.dmg"
echo       URL: %DMG_DOWNLOAD_URL%
echo       Saving to: %DMG_FILE%
echo.
echo       Downloading... ^(this may take a minute^)
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; try { Invoke-WebRequest -Uri '%DMG_DOWNLOAD_URL%' -OutFile '%DMG_FILE%' -UseBasicParsing } catch { Write-Host \"[ERROR] Download failed: $_\"; exit 1 }"
if errorlevel 1 (
  echo [ERROR] Failed to download Codex.dmg.
  echo         Download manually from: https://openai.com/index/introducing-codex/
  echo         Then place the .dmg next to this script and re-run.
  exit /b 1
)
REM Verify the file was actually downloaded and has content
if not exist "%DMG_FILE%" (
  echo [ERROR] Download completed but file not found.
  exit /b 1
)
for %%S in ("%DMG_FILE%") do (
  if %%~zS LSS 1000000 (
    echo [ERROR] Downloaded file is too small ^(%%~zS bytes^). May be an error page.
    del "%DMG_FILE%" >nul 2>&1
    exit /b 1
  )
  echo       Downloaded successfully: %%~zS bytes
)
echo.
goto :extract_dmg

REM ---- Extract Codex.app from DMG ----
:extract_dmg
echo.
echo [DMG] Extracting Codex.app from: %DMG_FILE%
call :extract_dmg_file "%DMG_FILE%" "%SCRIPT_DIR%"
if errorlevel 1 (
  echo [ERROR] Failed to extract Codex.app from DMG.
  exit /b 1
)
if exist "%SCRIPT_DIR%Codex.app\Contents\Resources\app.asar" (
  set "CODEX_APP=%SCRIPT_DIR%Codex.app"
  echo [DMG] Extracted successfully: !CODEX_APP!
) else (
  echo [ERROR] Codex.app not found after DMG extraction.
  exit /b 1
)

:have_app
REM ============================================================================
REM Phase 2: Set up working directory and run the porting steps
REM ============================================================================
set "WORKDIR=%TEMP%\codex-electron-win"
set "APP_DIR=%WORKDIR%\app"
set "APP_ASAR=%CODEX_APP%\Contents\Resources\app.asar"
set "ELECTRON_PACKAGE=electron"
set "EXIT_CODE=1"

mkdir "%WORKDIR%" >nul 2>&1

REM ============================================================================
REM Step 1: Unpack app.asar (skip if done)
REM ============================================================================
echo.
echo [1/4] Checking app unpack...
if exist "%APP_DIR%\package.json" (
  echo       Already unpacked, skipping
) else (
  call :extract_asar "%APP_ASAR%" "%APP_DIR%"
  if errorlevel 1 ( echo [ERROR] Could not unpack app.asar & goto :fail )
)

REM ============================================================================
REM Step 2: Detect Electron version
REM ============================================================================
echo [2/4] Detecting Electron version...
call :detect_electron_version "%APP_DIR%"
echo       Using: %ELECTRON_PACKAGE%

REM ============================================================================
REM Step 3: Install precompiled native modules for Windows (skip if done)
REM ============================================================================
echo [3/4] Checking native modules...
set "REBUILD_MARKER=%APP_DIR%\.win-natives-ok"
if exist "%REBUILD_MARKER%" (
  echo       Native modules already installed, skipping
) else (
  call :install_native_modules "%APP_DIR%"
  if errorlevel 1 ( echo [ERROR] Native module installation failed & goto :fail )
)

REM ---- Patch renderer for Windows (process polyfill) ----
set "PATCH_MARKER=%APP_DIR%\.win-process-patched"
if exist "%PATCH_MARKER%" (
  echo       Windows renderer patch already applied, skipping
) else (
  echo       Applying Windows renderer patches...
  call :patch_renderer "%APP_DIR%"
  if errorlevel 1 ( echo [WARN] Renderer patch failed, app may crash )
)

REM ============================================================================
REM Step 4: Launch with Electron
REM ============================================================================
echo [4/4] Launching app with Electron...
call :launch_electron "%APP_DIR%"
set "EXIT_CODE=%ERRORLEVEL%"
echo.
echo Electron exited with code: %EXIT_CODE%
goto :done

REM ============================================================================
REM SUBROUTINES
REM ============================================================================

REM --------------------------------------------------------------------------
REM :ensure_tools -- Check and auto-install all required tools
REM --------------------------------------------------------------------------
:ensure_tools

REM ---- Check for winget (needed to install everything else) ----
where winget >nul 2>&1
if errorlevel 1 (
  echo [ERROR] winget is not available. It ships with Windows 10 1709+ and Windows 11.
  echo         Please install App Installer from the Microsoft Store.
  exit /b 1
)

REM ---- Node.js ----
where node >nul 2>&1
if errorlevel 1 (
  echo [SETUP] Node.js not found. Installing via winget...
  winget install --id OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements -e
  if errorlevel 1 (
    echo [ERROR] Failed to install Node.js. Install manually: https://nodejs.org
    exit /b 1
  )
  REM Refresh PATH and add common Node.js install locations as fallback
  call :refresh_path
  set "PATH=C:\Program Files\nodejs;%APPDATA%\npm;!PATH!"
  where node >nul 2>&1
  if errorlevel 1 (
    echo [ERROR] Node.js installed but not in PATH. Please restart your terminal and re-run.
    exit /b 1
  )
  echo [SETUP] Node.js installed successfully.
)

REM ---- npx (comes with Node.js, but verify) ----
where npx >nul 2>&1
if errorlevel 1 (
  echo [ERROR] npx not found. It should come with Node.js.
  echo         Try reinstalling Node.js: winget install OpenJS.NodeJS.LTS
  exit /b 1
)

REM ---- 7-Zip (needed for DMG extraction) ----
where 7z >nul 2>&1
if errorlevel 1 (
  echo [SETUP] 7-Zip not found. Installing via winget...
  winget install --id 7zip.7zip --accept-source-agreements --accept-package-agreements -e
  if errorlevel 1 (
    echo [WARN] Failed to install 7-Zip. DMG extraction won't work.
    echo        Install manually: https://www.7-zip.org
  ) else (
    call :refresh_path
    call :add_7zip_to_path
    echo [SETUP] 7-Zip installed successfully.
  )
)

REM ---- Python (needed by node-gyp for native module compilation) ----
where python >nul 2>&1
if errorlevel 1 (
  echo [SETUP] Python not found. Installing via winget...
  winget install --id Python.Python.3.12 --accept-source-agreements --accept-package-agreements -e
  if errorlevel 1 (
    echo [WARN] Failed to install Python. Native module compilation may fail.
    echo        Install manually: https://www.python.org
  ) else (
    call :refresh_path
    set "PATH=C:\Program Files\Python312;C:\Program Files\Python312\Scripts;%LOCALAPPDATA%\Programs\Python\Python312;%LOCALAPPDATA%\Programs\Python\Python312\Scripts;!PATH!"
    echo [SETUP] Python installed successfully.
  )
)

REM ---- Ensure Python is in PATH (common install locations) ----
set "PATH=C:\Program Files\Python312;C:\Program Files\Python312\Scripts;%LOCALAPPDATA%\Programs\Python\Python312;%LOCALAPPDATA%\Programs\Python\Python312\Scripts;%PATH%"

REM ---- @openai/codex CLI ----
set "_CODEX_FOUND="
call :find_codex_cli
if not defined CODEX_CLI_PATH (
  echo [SETUP] @openai/codex CLI not found. Installing via npm...
  call npm install -g @openai/codex
  if errorlevel 1 (
    echo [WARN] Failed to install @openai/codex CLI.
    echo        Install manually: npm install -g @openai/codex
  ) else (
    echo [SETUP] @openai/codex CLI installed successfully.
  )
)

REM ---- Visual Studio Build Tools (optional, for node-pty) ----
call :check_vctools

if not defined HAS_VCTOOLS (
  echo [SETUP] Visual Studio Build Tools not found.
  echo         Installing via winget ^(needed for terminal/PTY support^)...
  winget install --id Microsoft.VisualStudio.2022.BuildTools --accept-source-agreements --accept-package-agreements -e --override "--quiet --wait --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
  if errorlevel 1 (
    echo [WARN] VS Build Tools install failed or was cancelled.
    echo        Terminal/PTY features may not work without C++ build tools.
    echo        Install manually: https://aka.ms/vs/17/release/vs_BuildTools.exe
    echo        Select the Desktop development with C++ workload.
  ) else (
    echo [SETUP] VS Build Tools installed successfully.
  )
)

echo [SETUP] All tools checked.
exit /b 0

REM --------------------------------------------------------------------------
REM :refresh_path -- Reload PATH from the registry (picks up new installs)
REM --------------------------------------------------------------------------
:refresh_path
set "SYS_PATH="
set "USR_PATH="
for /f "usebackq tokens=2,*" %%A in (`reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v PATH 2^>nul`) do set "SYS_PATH=%%B"
for /f "usebackq tokens=2,*" %%A in (`reg query "HKCU\Environment" /v PATH 2^>nul`) do set "USR_PATH=%%B"
if defined SYS_PATH (
  if defined USR_PATH (
    set "PATH=!USR_PATH!;!SYS_PATH!"
  ) else (
    set "PATH=!SYS_PATH!"
  )
)
exit /b 0

REM --------------------------------------------------------------------------
REM :add_7zip_to_path -- Add common 7-Zip install locations to PATH
REM   (Separated to avoid parentheses in "Program Files (x86)" breaking blocks)
REM --------------------------------------------------------------------------
:add_7zip_to_path
set "PATH=C:\Program Files\7-Zip;C:\Program Files (x86)\7-Zip;%PATH%"
exit /b 0

REM --------------------------------------------------------------------------
REM :check_vctools -- Check if Visual Studio Build Tools are installed
REM   Sets HAS_VCTOOLS=1 if found, clears it otherwise.
REM   (Separated to avoid parentheses in "Program Files (x86)" breaking blocks)
REM --------------------------------------------------------------------------
:check_vctools
set "HAS_VCTOOLS="
if exist "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC" set "HAS_VCTOOLS=1"
if exist "C:\Program Files\Microsoft Visual Studio\2022\BuildTools\VC" set "HAS_VCTOOLS=1"
if exist "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC" set "HAS_VCTOOLS=1"
if exist "C:\Program Files\Microsoft Visual Studio\2022\Community\VC" set "HAS_VCTOOLS=1"
if exist "C:\Program Files\Microsoft Visual Studio\2022\Professional\VC" set "HAS_VCTOOLS=1"
if exist "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC" set "HAS_VCTOOLS=1"
exit /b 0

REM --------------------------------------------------------------------------
REM :extract_dmg_file -- Extract Codex.app from a .dmg using 7-Zip
REM   %1 = path to .dmg file
REM   %2 = destination directory (Codex.app will be placed here)
REM --------------------------------------------------------------------------
:extract_dmg_file
set "DMG_SRC=%~1"
set "DMG_DEST=%~2"
set "DMG_WORK=%TEMP%\codex-dmg-extract"

where 7z >nul 2>&1
if errorlevel 1 (
  echo [ERROR] 7-Zip is required to extract DMG files but was not found.
  exit /b 1
)

REM Clean previous extraction
if exist "%DMG_WORK%" rd /s /q "%DMG_WORK%" >nul 2>&1
mkdir "%DMG_WORK%" >nul 2>&1

echo       Step 1/3: Extracting DMG outer layer...
7z x -y -o"%DMG_WORK%\dmg-layer1" "%DMG_SRC%" >nul 2>&1
if errorlevel 1 (
  echo [ERROR] 7-Zip failed to extract the DMG file.
  exit /b 1
)

REM DMGs often contain an HFS+ image file (e.g. "2.hfs", "3.hfs", or similar)
REM Try to find and extract it
set "HFS_FILE="
for /r "%DMG_WORK%\dmg-layer1" %%H in (*.hfs) do (
  if not defined HFS_FILE set "HFS_FILE=%%~fH"
)

if defined HFS_FILE (
  echo       Step 2/3: Extracting HFS+ filesystem...
  7z x -y -o"%DMG_WORK%\dmg-layer2" "!HFS_FILE!" >nul 2>&1
  if errorlevel 1 (
    echo [WARN] HFS extraction failed, trying direct search...
    set "DMG_SEARCH=%DMG_WORK%\dmg-layer1"
  ) else (
    set "DMG_SEARCH=%DMG_WORK%\dmg-layer2"
  )
) else (
  REM No HFS found -- the first extraction might have gotten the files directly
  set "DMG_SEARCH=%DMG_WORK%\dmg-layer1"
)

REM Find Codex.app inside the extracted content
echo       Step 3/3: Locating Codex.app...
set "FOUND_APP="
for /f "delims=" %%D in ('dir /s /b /ad "!DMG_SEARCH!\Codex.app" 2^>nul') do (
  if not defined FOUND_APP (
    if exist "%%~fD\Contents\Resources\app.asar" (
      set "FOUND_APP=%%~fD"
    )
  )
)

if not defined FOUND_APP (
  REM Try looking for app.asar directly (some DMG structures differ)
  for /f "delims=" %%A in ('dir /s /b "!DMG_SEARCH!\app.asar" 2^>nul') do (
    if not defined FOUND_APP (
      REM Walk up to find the .app folder
      for %%P in ("%%~dpA..\..\..") do (
        if exist "%%~fP\Contents\Resources\app.asar" (
          set "FOUND_APP=%%~fP"
        )
      )
    )
  )
)

if not defined FOUND_APP (
  echo [ERROR] Could not find Codex.app inside the DMG.
  echo         Contents of extraction:
  dir /s /b "!DMG_SEARCH!" 2>nul | findstr /I "\.app .asar" 2>nul
  rd /s /q "%DMG_WORK%" >nul 2>&1
  exit /b 1
)

REM Copy Codex.app to destination
echo       Copying Codex.app to: %DMG_DEST%
if exist "%DMG_DEST%Codex.app" rd /s /q "%DMG_DEST%Codex.app" >nul 2>&1
xcopy "!FOUND_APP!" "%DMG_DEST%Codex.app\" /E /I /H /Y /Q >nul
if errorlevel 1 (
  echo [ERROR] Failed to copy Codex.app
  rd /s /q "%DMG_WORK%" >nul 2>&1
  exit /b 1
)

REM Clean up temp extraction
rd /s /q "%DMG_WORK%" >nul 2>&1
echo       DMG extraction complete.
exit /b 0

REM --------------------------------------------------------------------------
REM :extract_asar -- Unpack app.asar into a directory
REM --------------------------------------------------------------------------
:extract_asar
set "ASAR_FILE=%~1"
set "ASAR_OUT=%~2"
if exist "%ASAR_OUT%" rd /s /q "%ASAR_OUT%" >nul 2>&1
echo       Unpacking with @electron/asar...
call npx -y @electron/asar extract "%ASAR_FILE%" "%ASAR_OUT%"
if errorlevel 1 ( echo [ERROR] asar extract failed & exit /b 1 )
echo       Unpacked successfully
exit /b 0

REM --------------------------------------------------------------------------
REM :detect_electron_version -- Read Electron version from package.json
REM --------------------------------------------------------------------------
:detect_electron_version
set "DETECT_DIR=%~1"
set "DETECTED_ELECTRON="
set "ELECTRON_PACKAGE=electron"
for /f "usebackq delims=" %%V in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=Join-Path '%DETECT_DIR%' 'package.json'; if(Test-Path $p){try{$j=Get-Content -Raw $p|ConvertFrom-Json;$v=$null;if($j.devDependencies -and $j.devDependencies.electron){$v=[string]$j.devDependencies.electron}elseif($j.dependencies -and $j.dependencies.electron){$v=[string]$j.dependencies.electron};if($v){$m=[regex]::Match($v,'[0-9]+(\.[0-9]+){0,2}');if($m.Success){$m.Value}}}catch{}}"`) do (
  if not defined DETECTED_ELECTRON set "DETECTED_ELECTRON=%%V"
)
if defined DETECTED_ELECTRON (
  set "ELECTRON_PACKAGE=electron@%DETECTED_ELECTRON%"
  echo       Detected version: %DETECTED_ELECTRON%
) else (
  echo       Using latest electron
)
exit /b 0

REM --------------------------------------------------------------------------
REM :install_native_modules -- Replace Mac native modules with Windows ones
REM --------------------------------------------------------------------------
:install_native_modules
set "RB_DIR=%~1"

REM Get Electron module ABI version
echo       Getting Electron ABI version...
set "ELECTRON_ABI="
for /f "usebackq delims=" %%M in (`npx -y electron@40.0.0 -e "console.log(process.versions.modules)" 2^>nul`) do (
  if not defined ELECTRON_ABI set "ELECTRON_ABI=%%M"
)
if not defined ELECTRON_ABI set "ELECTRON_ABI=143"
echo       Electron ABI: v%ELECTRON_ABI%

REM ---- better-sqlite3: download precompiled binary from GitHub ----
echo.
echo       === better-sqlite3 (precompiled download) ===
set "BSQ_DIR=%RB_DIR%\node_modules\better-sqlite3"
if exist "%BSQ_DIR%" (
  REM Clean old Mac artifacts
  if exist "%BSQ_DIR%\build" rd /s /q "%BSQ_DIR%\build" >nul 2>&1
  if exist "%BSQ_DIR%\prebuilds" rd /s /q "%BSQ_DIR%\prebuilds" >nul 2>&1

  REM v12.6.2 has prebuilt for electron-v143-win32-x64
  set "BSQ_PREBUILD_VER=12.6.2"
  set "BSQ_URL=https://github.com/WiseLibs/better-sqlite3/releases/download/v!BSQ_PREBUILD_VER!/better-sqlite3-v!BSQ_PREBUILD_VER!-electron-v%ELECTRON_ABI%-win32-x64.tar.gz"
  set "BSQ_TGZ=%WORKDIR%\bsq-prebuild.tar.gz"

  echo       Downloading prebuilt: v!BSQ_PREBUILD_VER! for electron-v%ELECTRON_ABI%-win32-x64
  powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -Uri '!BSQ_URL!' -OutFile '!BSQ_TGZ!'"
  if errorlevel 1 (
    echo [ERROR] Failed to download better-sqlite3 prebuilt
    exit /b 1
  )

  REM Extract: prebuild tarballs contain build/Release/better_sqlite3.node
  echo       Extracting prebuilt binary...
  mkdir "%BSQ_DIR%\build\Release" >nul 2>&1
  pushd "%BSQ_DIR%"
  tar -xzf "!BSQ_TGZ!" 2>nul
  popd

  REM Verify the .node file exists
  if exist "%BSQ_DIR%\build\Release\better_sqlite3.node" (
    echo       better-sqlite3: OK ^(precompiled^)
  ) else (
    echo [ERROR] better_sqlite3.node not found after extraction
    exit /b 1
  )

  REM Update package.json version to match the prebuild we downloaded
  powershell -NoProfile -ExecutionPolicy Bypass -Command "$f='%BSQ_DIR%\package.json';$j=Get-Content -Raw $f|ConvertFrom-Json;$j.version='!BSQ_PREBUILD_VER!';$j|ConvertTo-Json -Depth 10|Set-Content $f -Encoding UTF8"
)

REM ---- node-pty: compile from source with @electron/rebuild ----
echo.
echo       === node-pty ===
set "NPTY_DIR=%RB_DIR%\node_modules\node-pty"
if not exist "%NPTY_DIR%" goto :npty_skip

REM Clean old Mac artifacts
if exist "%NPTY_DIR%\build" rd /s /q "%NPTY_DIR%\build" >nul 2>&1
if exist "%NPTY_DIR%\prebuilds" rd /s /q "%NPTY_DIR%\prebuilds" >nul 2>&1

REM Check for VS Build Tools
call :check_vctools
if not defined HAS_VCTOOLS (
  echo [WARN] Visual Studio Build Tools not found.
  echo       node-pty cannot be compiled. PTY/terminal features may not work.
  goto :npty_skip
)

echo       Building node-pty with @electron/rebuild...
pushd "%RB_DIR%"
call npx -y @electron/rebuild --version 40.0.0 --module-dir node_modules/node-pty --force 2>&1
set "NPTY_RC=%ERRORLEVEL%"
popd

if !NPTY_RC! == 0 (
  echo       node-pty: OK (compiled^)
) else (
  echo [WARN] node-pty build failed. PTY features may not work.
)

:npty_skip

REM ---- Clean up stale Mac files ----
echo.
echo       Cleaning stale Mac-only files...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -Path '%RB_DIR%\node_modules' -Recurse -Include '*.dylib' -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue"

REM Write marker so we skip on re-run
echo ok > "%RB_DIR%\.win-natives-ok"
echo       Native modules ready
exit /b 0

REM --------------------------------------------------------------------------
REM :patch_renderer -- Inject process polyfill into the renderer
REM --------------------------------------------------------------------------
:patch_renderer
set "PATCH_DIR=%~1"
set "PRELOAD_FILE=%PATCH_DIR%\.vite\build\preload.js"
set "INDEX_HTML=%PATCH_DIR%\webview\index.html"

REM ---- Patch preload.js: expose process shim to renderer ----
if not exist "%PRELOAD_FILE%" (
  echo [WARN] preload.js not found, skipping patch
  exit /b 0
)
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$f='%PRELOAD_FILE%';$c=Get-Content -Raw $f -Encoding UTF8;" ^
  "if($c -match '__processShim'){Write-Host '      preload.js already patched';exit 0};" ^
  "$shim='const _cwd=typeof process.cwd===\"function\"?process.cwd():\"C:\\\\\";const _platform=process.platform||\"win32\";const _version=process.version||\"\";const _arch=process.arch||\"x64\";const _pid=process.pid||0;const _execPath=process.execPath||\"\";const _envSrc=process.env||{};const _env={NODE_ENV:_envSrc.NODE_ENV||\"production\",HOME:_envSrc.HOME||_envSrc.USERPROFILE||\"\",APPDATA:_envSrc.APPDATA||\"\",SHELL:_envSrc.SHELL||_envSrc.COMSPEC||\"\",TERM:_envSrc.TERM||\"\",PATH:_envSrc.PATH||\"\",CODEX_CLI_PATH:_envSrc.CODEX_CLI_PATH||\"\"};const _versions=process.versions?{...process.versions}:{};';" ^
  "$expose='n.contextBridge.exposeInMainWorld(\"__processShim\",{cwd:_cwd,platform:_platform,version:_version,arch:_arch,pid:_pid,execPath:_execPath,env:_env,versions:_versions,type:\"renderer\"});';" ^
  "$c=$c.TrimEnd();$c=$c+\"`n\"+$shim+\"`n\"+$expose+\"`n\";" ^
  "Set-Content $f $c -Encoding UTF8 -NoNewline;" ^
  "Write-Host '      preload.js patched'"
if errorlevel 1 ( echo [WARN] preload.js patch failed & exit /b 1 )

REM ---- Patch index.html: inject process polyfill + update CSP ----
if not exist "%INDEX_HTML%" (
  echo [WARN] index.html not found, skipping patch
  exit /b 0
)
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$f='%INDEX_HTML%';$c=Get-Content -Raw $f -Encoding UTF8;" ^
  "if($c -match '__processShim'){Write-Host '      index.html already patched';exit 0};" ^
  "$polyfill='<script>window.process={...window.__processShim,cwd:function(){return window.__processShim.cwd},nextTick:function(cb){setTimeout(cb,0)},browser:false,argv:[],on:function(){return this},off:function(){return this},emit:function(){return this},removeListener:function(){return this},addListener:function(){return this},once:function(){return this},removeAllListeners:function(){return this},listeners:function(){return[]}};</script>';" ^
  "$cspHash=\"'sha256-vUPPGezjwtwyPhhV6Lin1VeVqqLmju8YuY479tgImwU='\";" ^
  "$c=$c -replace '<title>Codex</title>',('<title>Codex</title>`n    '+$polyfill);" ^
  "$c=$c -replace \"'sha256-Z2/iFzh9VMlVkEOar1f/oSHWwQk3ve1qk/C2WdsC4Xk='\",\"'sha256-Z2/iFzh9VMlVkEOar1f/oSHWwQk3ve1qk/C2WdsC4Xk=' $cspHash\";" ^
  "Set-Content $f $c -Encoding UTF8 -NoNewline;" ^
  "Write-Host '      index.html patched'"
if errorlevel 1 ( echo [WARN] index.html patch failed & exit /b 1 )

echo ok > "%PATCH_DIR%\.win-process-patched"
echo       Renderer patches applied
exit /b 0

REM --------------------------------------------------------------------------
REM :launch_electron -- Start the app with Electron
REM --------------------------------------------------------------------------
:launch_electron
set "APP_TO_RUN=%~1"
set "ELECTRON_RUN_AS_NODE="
set "ELECTRON_FORCE_IS_PACKAGED=true"

REM ---- Resolve Codex CLI binary ----
call :find_codex_cli
if not defined CODEX_CLI_PATH (
  echo [WARN] Codex CLI binary not found. Attempting install...
  call npm install -g @openai/codex
  call :find_codex_cli
)
if not defined CODEX_CLI_PATH (
  echo [ERROR] Codex CLI binary not found even after install attempt.
  echo         Install manually: npm install -g @openai/codex
  exit /b 1
)
echo       Codex CLI: %CODEX_CLI_PATH%

echo       Running: npx %ELECTRON_PACKAGE% "%APP_TO_RUN%"
call npx -y %ELECTRON_PACKAGE% "%APP_TO_RUN%"
exit /b %ERRORLEVEL%

REM --------------------------------------------------------------------------
REM :find_codex_cli -- Locate the codex.exe binary
REM --------------------------------------------------------------------------
:find_codex_cli
set "CODEX_CLI_PATH="

REM Check npm global install: @openai/codex vendor binaries
set "_NPM_PREFIX="
for /f "delims=" %%P in ('npm prefix -g 2^>nul') do set "_NPM_PREFIX=%%P"
if defined _NPM_PREFIX (
  set "_CLI_EXE=%_NPM_PREFIX%\node_modules\@openai\codex\vendor\x86_64-pc-windows-msvc\codex\codex.exe"
  if exist "!_CLI_EXE!" (
    set "CODEX_CLI_PATH=!_CLI_EXE!"
    exit /b 0
  )
  REM ARM64 fallback
  set "_CLI_EXE=%_NPM_PREFIX%\node_modules\@openai\codex\vendor\aarch64-pc-windows-msvc\codex\codex.exe"
  if exist "!_CLI_EXE!" (
    set "CODEX_CLI_PATH=!_CLI_EXE!"
    exit /b 0
  )
)

REM Check if codex.exe is in PATH
for /f "delims=" %%C in ('where codex.exe 2^>nul') do (
  if not defined CODEX_CLI_PATH set "CODEX_CLI_PATH=%%~fC"
)
exit /b 0

REM ============================================================================
REM USAGE / EXIT
REM ============================================================================

:usage
echo.
echo Usage:
echo   %~nx0 [path\to\Codex.app ^| path\to\Codex.dmg]
echo.
echo   Runs the macOS Codex Desktop app on Windows via Electron.
echo   Everything is automatic -- tools, DMG download, extraction, patching.
echo.
echo   The script accepts:
echo     - No arguments: auto-detects locally, or downloads from OpenAI
echo     - A Codex.app folder
echo     - A .dmg file
echo.
echo Examples:
echo   %~nx0
echo   %~nx0 "C:\Downloads\Codex.app"
echo   %~nx0 "C:\Downloads\Codex.dmg"
echo.
echo Working directory: %TEMP%\codex-electron-win
echo   Delete this folder to force a fresh start.
exit /b 1

:fail
echo.
echo [FAILED] See errors above. Working dir: %WORKDIR%
exit /b 1

:done
exit /b %EXIT_CODE%
