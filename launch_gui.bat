@echo off
title Clean C Drive - GUI
cd /d "%~dp0"

echo Launching GUI version - C Drive Cleanup Tool...
echo (first launch may be slow, loading .NET components...)
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0clean_safe_gui.ps1"

if errorlevel 1 (
    echo.
    echo Launch failed. Try:
    echo 1. Right-click launch_gui.bat and select "Run as administrator"
    echo 2. Ensure PowerShell execution policy allows script:
    echo    powershell Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
    echo.
    pause
)
