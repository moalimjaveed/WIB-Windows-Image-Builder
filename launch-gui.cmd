@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\launch-gui.ps1" %*
if %ERRORLEVEL% neq 0 (
    echo.
    echo [WIB] Studio exited with error code: %ERRORLEVEL%
    pause
)
