@echo off
setlocal EnableExtensions EnableDelayedExpansion

if "%~1"=="" goto :usage

set "SOURCE=%~1"

REM ============================================================================
REM Persistent working directory - reuse previous extraction on re-run
REM ============================================================================
set "WORKDIR=%TEMP%\codex-electron-win"
set "ARCHIVE=%WORKDIR%\codex-mac.zip"
set "EXTRACT_DIR=%WORKDIR%\extracted"
set "APP_DIR=%WORKDIR%\app"
set "APP_ASAR="
set "ELECTRON_PACKAGE=electron"
set "EXIT_CODE=1"

REM Ensure Python + build tools are in PATH
set "PATH=C:\Program Files\Python312;C:\Program Files\Python312\Scripts;%PATH%"

REM Check required tools
where node >nul 2>&1 || ( echo [ERROR] Node.js is required in PATH. & exit /b 1 )
where npx >nul 2>&1  || ( echo [ERROR] npx is required in PATH. & exit /b 1 )

REM ============================================================================
REM Step 1: Acquire archive (skip if already present)
REM ============================================================================
echo [1/6] Checking archive...
if exist "%ARCHIVE%" (
  echo       Archive already cached, skipping
) else (
  mkdir "%WORKDIR%" >nul 2>&1
  call :acquire_archive "%SOURCE%" "%ARCHIVE%"
  if errorlevel 1 goto :fail
)

REM ============================================================================
REM Step 2: Extract archive + find app.asar (skip if done)
REM ============================================================================
echo [2/6] Checking extraction...
if exist "%EXTRACT_DIR%\Codex.app" (
  echo       Already extracted, skipping
  call :find_app_asar "%EXTRACT_DIR%"
) else (
  mkdir "%EXTRACT_DIR%" >nul 2>&1
  call :extract_and_find_asar "%ARCHIVE%" "%EXTRACT_DIR%"
  if errorlevel 1 goto :fail
)
if not defined APP_ASAR ( echo [ERROR] app.asar not found & goto :fail )

REM ============================================================================
REM Step 3: Unpack app.asar (skip if done)
REM ============================================================================
echo [3/6] Checking app unpack...
if exist "%APP_DIR%\package.json" (
  echo       Already unpacked, skipping
) else (
  call :extract_asar "%APP_ASAR%" "%APP_DIR%"
  if errorlevel 1 ( echo [ERROR] Could not unpack app.asar & goto :fail )
)

REM ============================================================================
REM Step 4: Detect Electron version
REM ============================================================================
echo [4/6] Detecting Electron version...
call :detect_electron_version "%APP_DIR%"
echo       Using: %ELECTRON_PACKAGE%

REM ============================================================================
REM Step 5: Install precompiled native modules for Windows (skip if done)
REM ============================================================================
echo [5/6] Checking native modules...
set "REBUILD_MARKER=%APP_DIR%\.win-natives-ok"
if exist "%REBUILD_MARKER%" (
  echo       Native modules already installed, skipping
) else (
  call :install_native_modules "%APP_DIR%"
  if errorlevel 1 ( echo [ERROR] Native module installation failed & goto :fail )
)

REM ============================================================================
REM Step 5b: Patch renderer for Windows (process polyfill)
REM ============================================================================
set "PATCH_MARKER=%APP_DIR%\.win-process-patched"
if exist "%PATCH_MARKER%" (
  echo       Windows renderer patch already applied, skipping
) else (
  echo       Applying Windows renderer patches...
  call :patch_renderer "%APP_DIR%"
  if errorlevel 1 ( echo [WARN] Renderer patch failed, app may crash )
)

REM ============================================================================
REM Step 6: Launch with Electron
REM ============================================================================
echo [6/6] Launching app with Electron...
call :launch_electron "%APP_DIR%"
set "EXIT_CODE=%ERRORLEVEL%"
echo.
echo Electron exited with code: %EXIT_CODE%
goto :done

REM ============================================================================
REM SUBROUTINES
REM ============================================================================

:acquire_archive
set "SRC=%~1"
set "DEST=%~2"
set "IS_URL="
if /I "%SRC:~0,7%"=="http://" set "IS_URL=1"
if /I "%SRC:~0,8%"=="https://" set "IS_URL=1"
if defined IS_URL (
  echo       Downloading: %SRC%
  powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -Uri '%SRC%' -OutFile '%DEST%'"
  if errorlevel 1 ( echo [ERROR] Download failed & exit /b 1 )
  exit /b 0
)
if not exist "%SRC%" ( echo [ERROR] Source not found: %SRC% & exit /b 1 )
echo       Copying local archive...
copy /y "%SRC%" "%DEST%" >nul
if errorlevel 1 ( echo [ERROR] Copy failed & exit /b 1 )
exit /b 0

:extract_and_find_asar
set "IN_ARCHIVE=%~1"
set "OUT_DIR=%~2"
echo       Extracting archive...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -LiteralPath '%IN_ARCHIVE%' -DestinationPath '%OUT_DIR%' -Force"
if errorlevel 1 ( echo [ERROR] Extraction failed & exit /b 1 )
call :find_app_asar "%OUT_DIR%"
if not defined APP_ASAR ( echo [ERROR] app.asar not found & exit /b 1 )
exit /b 0

:find_app_asar
set "SEARCH_DIR=%~1"
set "APP_ASAR="
for /f "delims=" %%I in ('dir /s /b "%SEARCH_DIR%\app.asar" 2^>nul ^| findstr /I /C:"\\Contents\\Resources\\app.asar"') do (
  if not defined APP_ASAR set "APP_ASAR=%%~fI"
)
if not defined APP_ASAR (
  for /f "delims=" %%I in ('dir /s /b "%SEARCH_DIR%\app.asar" 2^>nul') do (
    if not defined APP_ASAR set "APP_ASAR=%%~fI"
  )
)
if defined APP_ASAR echo       app.asar: %APP_ASAR%
exit /b 0

:extract_asar
set "ASAR_FILE=%~1"
set "ASAR_OUT=%~2"
if exist "%ASAR_OUT%" rd /s /q "%ASAR_OUT%" >nul 2>&1
echo       Unpacking with @electron/asar...
call npx -y @electron/asar extract "%ASAR_FILE%" "%ASAR_OUT%"
if errorlevel 1 ( echo [ERROR] asar extract failed & exit /b 1 )
echo       Unpacked successfully
exit /b 0

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

REM ============================================================================
REM NATIVE MODULE INSTALLATION
REM Prefer downloading precompiled binaries. Build from source only as fallback.
REM ============================================================================

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
    echo       better-sqlite3: OK (precompiled)
  ) else (
    echo [ERROR] better_sqlite3.node not found after extraction
    exit /b 1
  )

  REM Update package.json version to match the prebuild we downloaded
  powershell -NoProfile -ExecutionPolicy Bypass -Command "$f='%BSQ_DIR%\package.json';$j=Get-Content -Raw $f|ConvertFrom-Json;$j.version='!BSQ_PREBUILD_VER!';$j|ConvertTo-Json -Depth 10|Set-Content $f -Encoding UTF8"
)

REM ---- node-pty: download prebuilt or build from source ----
echo.
echo       === node-pty ===
set "NPTY_DIR=%RB_DIR%\node_modules\node-pty"
if exist "%NPTY_DIR%" (
  REM Clean old Mac artifacts
  if exist "%NPTY_DIR%\build" rd /s /q "%NPTY_DIR%\build" >nul 2>&1
  if exist "%NPTY_DIR%\prebuilds" rd /s /q "%NPTY_DIR%\prebuilds" >nul 2>&1

  REM node-pty has no prebuilts on GitHub. Try @electron/rebuild with VS Build Tools.
  echo       node-pty requires compilation. Checking build tools...

  REM Check for VS Build Tools
  set "HAS_VCTOOLS="
  if exist "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC" set "HAS_VCTOOLS=1"
  if exist "C:\Program Files\Microsoft Visual Studio\2022\BuildTools\VC" set "HAS_VCTOOLS=1"
  if exist "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC" set "HAS_VCTOOLS=1"
  if exist "C:\Program Files\Microsoft Visual Studio\2022\Community\VC" set "HAS_VCTOOLS=1"

  if not defined HAS_VCTOOLS (
    echo [WARN] Visual Studio Build Tools not found.
    echo       node-pty cannot be compiled. PTY/terminal features may not work.
    echo       Install VS Build Tools: https://aka.ms/vs/17/release/vs_BuildTools.exe
    echo       Select "Desktop development with C++" workload.
    goto :npty_skip
  )

  echo       Building node-pty with @electron/rebuild...
  pushd "%RB_DIR%"
  call npx -y @electron/rebuild --version 40.0.0 --module-dir node_modules/node-pty --force 2>&1
  set "NPTY_RC=%ERRORLEVEL%"
  popd

  if !NPTY_RC! == 0 (
    echo       node-pty: OK (compiled)
  ) else (
    echo [WARN] node-pty build failed. PTY features may not work.
  )
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

:launch_electron
set "APP_TO_RUN=%~1"
set "ELECTRON_RUN_AS_NODE="
set "ELECTRON_FORCE_IS_PACKAGED=true"
REM Uncomment for verbose renderer logging (debug only):
REM set "ELECTRON_ENABLE_LOGGING=true"

REM ---- Resolve Codex CLI binary ----
call :find_codex_cli
if not defined CODEX_CLI_PATH (
  echo [ERROR] Codex CLI binary not found. Install with: npm install -g @openai/codex
  exit /b 1
)
echo       Codex CLI: %CODEX_CLI_PATH%

echo       Running: npx %ELECTRON_PACKAGE% "%APP_TO_RUN%"
call npx -y %ELECTRON_PACKAGE% "%APP_TO_RUN%"
exit /b %ERRORLEVEL%

:find_codex_cli
set "CODEX_CLI_PATH="
REM Already set by user?
if defined CODEX_CLI_PATH if exist "%CODEX_CLI_PATH%" exit /b 0

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
echo Usage:
echo   %~nx0 ^<mac_archive_or_url^>
echo.
echo   Extracts a Mac Codex .app archive and runs it on Windows via Electron.
echo   Downloads precompiled native binaries where available.
echo   Skips already-completed steps on re-run.
echo.
echo Examples:
echo   %~nx0 "C:\Downloads\Codex-mac-full.zip"
echo   %~nx0 "https://example.com/Codex-mac.zip"
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
