@echo off
setlocal
cd /d "%~dp0"
title WIB: Windows Image Builder
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1" %*
if %ERRORLEVEL% neq 0 (
    echo.
    echo [WIB] Command exited with code: %ERRORLEVEL%
    pause
)
