@echo off
REM DinoX Windows Launcher (Legacy/Fallback)
REM dinox.exe now sets all environment variables internally.
REM You can simply double-click dinox.exe directly!
REM This batch file is kept for backward compatibility.

REM Get the directory where this script is located
set "DINOX_DIR=%~dp0"
set "DINOX_DIR=%DINOX_DIR:~0,-1%"

REM Add bin directory to PATH for gpg, tor, etc.
set "PATH=%DINOX_DIR%\bin;%DINOX_DIR%;%PATH%"

REM Launch DinoX (no terminal window will appear)
start "" "%DINOX_DIR%\dinox.exe" %*
