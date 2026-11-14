@echo off
setlocal
rem Compile-check the kwxLuaJIT probe lane. probe.wxui generates probe_mainframe.lua
rem and probe_dlg.lua into tests\quick_probe\gen\; probe_main.lua is hand-written.
rem Probe output never goes to tests\quick.
rem
rem   build_probe.cmd        compile tests\quick_probe (the probe gate)
rem   build_probe.cmd help   this text
cd /D "%~dp0"

if /I "%~1"=="help" goto :usage
if /I "%~1"=="-h" goto :usage
if /I "%~1"=="/?" goto :usage

rem luajit.exe is not on PATH; the repository ships its own build.
set "LUAJIT=%~dp0build\tools\luajit.exe"
if not exist "%LUAJIT%" (
    where luajit >nul 2>&1
    if errorlevel 1 (
        echo ERROR: luajit not found ^(expected "%LUAJIT%"^).
        exit /b 1
    )
    set "LUAJIT=luajit"
)

if not exist "tests\quick_probe\probe_main.lua" goto :no_main
if not exist "tests\quick_probe\gen\probe_mainframe.lua" goto :no_gen
if not exist "tests\quick_probe\gen\probe_dlg.lua" goto :no_gen

for %%F in (tests\quick_probe\probe_main.lua tests\quick_probe\gen\probe_mainframe.lua tests\quick_probe\gen\probe_dlg.lua) do (
    rem `loadfile` compiles without executing, so no window is created here.
    rem The path travels in QFILE, so Lua never sees it as a script to run.
    set "QFILE=%%F"
    "%LUAJIT%" -e "assert(loadfile(os.getenv('QFILE')))"
    if errorlevel 1 (
        echo ERROR: luajit failed to compile %%F.
        exit /b 1
    )
    echo Compiled %%F
)

exit /b 0

:usage
echo Usage: build_probe.cmd
echo.
echo   build_probe.cmd        compile tests\quick_probe and exit with the compile result
echo   build_probe.cmd help   this text
exit /b 0

:no_main
echo ERROR: tests\quick_probe\probe_main.lua does not exist.
exit /b 1

:no_gen
echo ERROR: tests\quick_probe\gen\probe_mainframe.lua does not exist.
echo        Generate it from ..\quick\tests\quick_probe\probe.wxui first.
exit /b 1
