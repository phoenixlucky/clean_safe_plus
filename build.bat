@echo off
setlocal EnableExtensions

chcp 65001 >nul
title Clean Safe Plus - Portable EXE Build
cd /d "%~dp0"
set "RELEASE_DIR=%~dp0releases"

echo ================================================
echo        Clean Safe Plus - Portable EXE
echo ================================================
echo.

where node >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Node.js was not found in PATH.
    echo Install Node.js and run this file again.
    goto :fail
)

where npm >nul 2>&1
if errorlevel 1 (
    echo [ERROR] npm was not found in PATH.
    echo Install Node.js and run this file again.
    goto :fail
)

if not exist "package.json" (
    echo [ERROR] package.json was not found.
    goto :fail
)

echo [1/2] Checking dependencies...
if exist "node_modules\.bin\tauri.cmd" (
    echo Dependencies are already installed.
) else (
    echo Installing dependencies...
    call npm install --no-audit --no-fund
    if errorlevel 1 (
        echo [ERROR] Dependency installation failed.
        goto :fail
    )
)

if not exist "node_modules\.bin\tauri.cmd" (
    echo [ERROR] Tauri CLI is unavailable after dependency setup.
    echo Delete node_modules and run this file again if a file is locked.
    goto :fail
)

echo.
echo [2/2] Building the portable executable...
call node_modules\.bin\tauri.cmd build --no-bundle
if errorlevel 1 (
    echo [ERROR] EXE build failed.
    goto :fail
)

echo.
echo Copying the portable EXE into releases...
if not exist "%RELEASE_DIR%" mkdir "%RELEASE_DIR%"
set "APP_EXE=%~dp0src-tauri\target\release\clean-safe-plus.exe"
if not exist "%APP_EXE%" (
    echo [ERROR] Portable EXE was not found: %APP_EXE%
    goto :fail
)
del /q "%RELEASE_DIR%\CleanSafePlus.exe" >nul 2>&1
copy /y "%APP_EXE%" "%RELEASE_DIR%\CleanSafePlus.exe" >nul

echo [OK] Portable EXE build completed.
echo Output: %RELEASE_DIR%
start "" "%RELEASE_DIR%"
pause
exit /b 0

:fail
echo.
echo Portable EXE build was not completed. Check the error above.
pause
exit /b 1
