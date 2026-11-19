@echo off
setlocal

rem Compile the kwxLuaJIT QuickPort app. LuaJIT is interpreted, so the build-only
rem path compiles the source to bytecode without running it -- nothing is launched
rem here; the GUI drive belongs to tests\drive_quick.ps1 -Target port.
rem Derived from build_quick.cmd: same interpreter, same compile-only gate.
rem
rem   build_quick_port.cmd        compile tests\quick_port (the port lane)
rem   build_quick_port.cmd help   this text

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

if not exist "tests\quick_port\quick_port_main.lua" goto :no_main

rem `loadfile` compiles without executing, so no window is created here.
rem The path travels in QFILE, so Lua never sees it as a script to run.
set "QFILE=tests\quick_port\quick_port_main.lua"
"%LUAJIT%" -e "assert(loadfile(os.getenv('QFILE')))"
if errorlevel 1 (
    echo ERROR: luajit failed to compile %QFILE%.
    exit /b 1
)
echo Compiled %QFILE%

exit /b 0

:usage
echo Usage: build_quick_port.cmd
echo.
echo   build_quick_port.cmd        compile tests\quick_port and exit with the result
echo   build_quick_port.cmd help   this text
exit /b 0

:no_main
echo ERROR: tests\quick_port\quick_port_main.lua does not exist.
exit /b 1
