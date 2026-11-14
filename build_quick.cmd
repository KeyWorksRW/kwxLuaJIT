@echo off
setlocal

rem Check the kwxLuaJIT quick test app. LuaJIT is an interpreted language, so the
rem build-only path compiles each source file to bytecode (-bl) without running
rem it. Nothing is launched here -- the GUI drive belongs to the verification
rem phase.
rem
rem   build_quick.cmd        compile tests\quick (the verification gate)
rem   build_quick.cmd help   this text

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

if not exist "tests\quick\quick_main.lua" goto :no_main

for %%F in (tests\quick\quick_main.lua tests\quick\quick_mainframe.lua tests\quick\quick_dlg.lua) do (
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
echo Usage: build_quick.cmd
echo.
echo   build_quick.cmd        compile tests\quick and exit with the compile result
echo   build_quick.cmd help   this text
exit /b 0

:no_main
echo ERROR: tests\quick\quick_main.lua does not exist.
exit /b 1
