@echo off
setlocal EnableExtensions
color 0A
title C Drive Cleanup Tool - Safe Plus

net session >nul 2>&1
if not "%errorlevel%"=="0" (
    echo Requesting administrator permission...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    if errorlevel 1 (
        echo Failed to request administrator permission.
        echo Please right-click this file and choose Run as administrator.
        pause
    )
    exit /b
)

echo ==================================================
echo C Drive Cleanup Tool: safe cleanup and disk analysis
echo ==================================================
echo.

echo [Current C drive space]
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_LogicalDisk -Filter 'DeviceID=''C:''' | Select-Object DeviceID,@{Name='SizeGB';Expression={[math]::Round($_.Size/1GB,2)}},@{Name='FreeGB';Expression={[math]::Round($_.FreeSpace/1GB,2)}} | Format-Table -AutoSize"
echo.

echo ==================================================
echo 1. Analyze top folders under C:\
echo ==================================================
echo Unit: GB. Larger folders should be checked first.
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem C:\ -Force -ErrorAction SilentlyContinue | ForEach-Object { $sum=(Get-ChildItem $_.FullName -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum; if ($null -eq $sum) { $sum=0 }; [PSCustomObject]@{Name=$_.FullName; GB=[math]::Round($sum/1GB,2)} } | Sort-Object GB -Descending | Select-Object -First 12 | Format-Table -AutoSize"

echo.
echo [Suggestions]
echo - Large Users folder: check AppData, Downloads, Desktop, chat/browser caches.
echo - Large Windows folder: run Windows cleanup and update cache cleanup.
echo - Large ProgramData folder: check app caches, Docker, installer caches.
echo - Large System Volume Information: clean system restore points.
echo - Large Program Files folders: uninstall or move large apps.
echo.

set /p gochoice=Continue safe cleanup? ^(Y/N^): 
if /i not "%gochoice%"=="Y" (
    echo Cleanup cancelled.
    pause
    exit /b
)

echo.
echo ==================================================
echo 2. Safe cleanup
echo ==================================================

echo [1/5] Cleaning user temp files...
del /s /f /q "%temp%\*" >nul 2>&1
for /d %%i in ("%temp%\*") do rd /s /q "%%i" >nul 2>&1

echo [2/5] Cleaning AppData Local Temp...
del /s /f /q "C:\Users\%username%\AppData\Local\Temp\*" >nul 2>&1
for /d %%i in ("C:\Users\%username%\AppData\Local\Temp\*") do rd /s /q "%%i" >nul 2>&1

echo [3/5] Cleaning Windows Update download cache...
net stop wuauserv >nul 2>&1
net stop bits >nul 2>&1
del /s /f /q "C:\Windows\SoftwareDistribution\Download\*" >nul 2>&1
for /d %%i in ("C:\Windows\SoftwareDistribution\Download\*") do rd /s /q "%%i" >nul 2>&1
net start wuauserv >nul 2>&1
net start bits >nul 2>&1

echo [4/5] Cleaning Recycle Bin...
rd /s /q C:\$Recycle.Bin >nul 2>&1

echo [5/5] Cleaning Windows temp folder...
del /s /f /q "C:\Windows\Temp\*" >nul 2>&1
for /d %%i in ("C:\Windows\Temp\*") do rd /s /q "%%i" >nul 2>&1

echo Safe cleanup completed.
echo.

echo ==================================================
echo 3. Optional cleanup: disable hibernation
echo ==================================================
echo This removes hiberfil.sys and may free several GB.
echo Hibernation will be disabled. Shutdown and sleep are usually unaffected.
echo.
set /p hchoice=Disable hibernation? ^(Y/N^): 
if /i "%hchoice%"=="Y" (
    powercfg -h off
    echo Hibernation disabled.
) else (
    echo Skipped hibernation cleanup.
)

echo.
echo ==================================================
echo 4. Optional cleanup: pip cache
echo ==================================================
where pip >nul 2>&1
if "%errorlevel%"=="0" (
    echo [pip cache directory]
    pip cache dir
    echo.
    set /p pchoice=Clean pip cache? ^(Y/N^): 
    if /i "%pchoice%"=="Y" (
        pip cache purge
    ) else (
        echo Skipped pip cache cleanup.
    )
) else (
    echo pip not found. Skipped.
)

echo.
echo ==================================================
echo 5. Optional cleanup: conda cache
echo ==================================================
where conda >nul 2>&1
if "%errorlevel%"=="0" (
    echo [conda info]
    conda info
    echo.
    echo Command: conda clean --all -y
    echo This cleans package caches, index caches and temporary files.
    set /p cchoice=Continue conda cleanup? ^(Y/N^): 
    if /i "%cchoice%"=="Y" (
        conda clean --all -y
    ) else (
        echo Skipped conda cleanup.
    )
) else (
    echo conda not found. Skipped.
)

echo.
echo ==================================================
echo 6. Optional cleanup: Docker
echo ==================================================
where docker >nul 2>&1
if "%errorlevel%"=="0" (
    echo [Docker disk usage]
    docker system df
    echo.
    echo [Docker containers]
    docker ps -a
    echo.
    echo [Docker images]
    docker images
    echo.
    echo Warning:
    echo docker system prune -a -f removes unused containers, networks, images and build cache.
    echo Running containers will not be removed.
    echo Removed images may need to be downloaded again later.
    echo.
    set /p dchoice=Run docker system prune -a -f? ^(Y/N^): 
    if /i "%dchoice%"=="Y" (
        docker system prune -a -f
    ) else (
        echo Skipped Docker cleanup.
    )
) else (
    echo Docker not found. Skipped.
)

echo.
echo ==================================================
echo 7. C drive space after cleanup
echo ==================================================
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_LogicalDisk -Filter 'DeviceID=''C:''' | Select-Object DeviceID,@{Name='SizeGB';Expression={[math]::Round($_.Size/1GB,2)}},@{Name='FreeGB';Expression={[math]::Round($_.FreeSpace/1GB,2)}} | Format-Table -AutoSize"

echo.
echo ==================================================
echo Cleanup finished
echo ==================================================
echo If C drive is still full, check these folders:
echo C:\Users\Administrator\AppData
echo C:\ProgramData
echo C:\Windows
echo System Volume Information
echo ==================================================
pause
