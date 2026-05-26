@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 936 >nul
color 0A
title C盘清理工具 - 完全版

net session >nul 2>&1
if not "%errorlevel%"=="0" (
    echo 正在请求管理员权限...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    if errorlevel 1 (
        echo 无法自动请求管理员权限。
        echo 请右键此文件，选择"以管理员身份运行"。
        pause
    )
    exit /b
)

echo ==================================================
echo C盘清理工具：安全清理 + 可选空间分析
echo ==================================================
echo.

echo [当前C盘空间]
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_LogicalDisk -Filter 'DeviceID=''C:''' | Select-Object DeviceID,@{Name='SizeGB';Expression={[math]::Round($_.Size/1GB,2)}},@{Name='FreeGB';Expression={[math]::Round($_.FreeSpace/1GB,2)}} | Format-Table -AutoSize"
echo.

echo ==================================================
echo 一、分析 C:\ 下的大目录
echo ==================================================
echo 单位：GB。这个步骤可能很慢，可按 N 跳过。
echo.

set /p analyzechoice=是否现在分析 C 盘大目录？^(Y/N^): 
if /i "%analyzechoice%"=="Y" (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='SilentlyContinue'; Get-ChildItem C:\ -Force -ErrorAction SilentlyContinue | ForEach-Object { $sum=0; try { $sum=(Get-ChildItem -LiteralPath $_.FullName -Recurse -Force -File -ErrorAction SilentlyContinue 2>$null | Measure-Object -Property Length -Sum).Sum } catch { $sum=0 }; if ($null -eq $sum) { $sum=0 }; [PSCustomObject]@{Name=$_.FullName; GB=[math]::Round($sum/1GB,2)} } | Sort-Object GB -Descending | Select-Object -First 12 | Format-Table -AutoSize"

    echo.
    echo [判断建议]
    echo - Users 很大：重点检查 AppData、下载、桌面、微信/QQ/浏览器缓存。
    echo - Windows 很大：优先做磁盘清理和更新缓存清理。
    echo - ProgramData 很大：多半是软件缓存、Docker、安装包缓存。
    echo - System Volume Information 很大：可以考虑清理系统还原点。
    echo - Program Files 很大：说明软件较多，建议迁移或卸载不用的软件。
) else (
    echo 已跳过大目录分析。
)
echo.

set /p gochoice=是否继续执行安全清理？^(Y/N^): 
if /i not "%gochoice%"=="Y" (
    echo 已取消清理。
    pause
    exit /b
)

echo.
echo ==================================================
echo 二、执行安全清理（自动执行）
echo ==================================================

echo [1/8] 清理用户临时文件...
del /s /f /q "%temp%\*" >nul 2>&1
for /d %%i in ("%temp%\*") do rd /s /q "%%i" >nul 2>&1

echo [2/8] 清理 AppData Local Temp...
del /s /f /q "C:\Users\%username%\AppData\Local\Temp\*" >nul 2>&1
for /d %%i in ("C:\Users\%username%\AppData\Local\Temp\*") do rd /s /q "%%i" >nul 2>&1

echo [3/8] 清理 Prefetch（自动重建，安全）...
del /s /f /q "C:\Windows\Prefetch\*" >nul 2>&1
for /d %%i in ("C:\Windows\Prefetch\*") do rd /s /q "%%i" >nul 2>&1

echo [4/8] 清理日志文件（C:\Windows\Logs + WER）...
del /s /f /q "C:\Windows\Logs\*" >nul 2>&1
for /d %%i in ("C:\Windows\Logs\*") do rd /s /q "%%i" >nul 2>&1
del /s /f /q "C:\ProgramData\Microsoft\Windows\WER\*" >nul 2>&1
for /d %%i in ("C:\ProgramData\Microsoft\Windows\WER\*") do rd /s /q "%%i" >nul 2>&1

echo [5/8] 清理缩略图缓存...
del /s /f /q "C:\Users\%username%\AppData\Local\Microsoft\Windows\Explorer\thumbcache_*.db" >nul 2>&1

echo [6/8] 清理 Windows 更新下载缓存...
net stop wuauserv >nul 2>&1
net stop bits >nul 2>&1
del /s /f /q "C:\Windows\SoftwareDistribution\Download\*" >nul 2>&1
for /d %%i in ("C:\Windows\SoftwareDistribution\Download\*") do rd /s /q "%%i" >nul 2>&1
net start wuauserv >nul 2>&1
net start bits >nul 2>&1

echo [7/8] 清理 Windows 临时目录...
del /s /f /q "C:\Windows\Temp\*" >nul 2>&1
for /d %%i in ("C:\Windows\Temp\*") do rd /s /q "%%i" >nul 2>&1

echo [8/8] 清理回收站...
rd /s /q C:\$Recycle.Bin >nul 2>&1

echo 安全清理完成。
echo.

echo ==================================================
echo 三、可选清理：关闭休眠
echo ==================================================
echo 说明：关闭休眠会删除 hiberfil.sys，通常释放数 GB 到几十 GB。
echo。
echo 影响：不能使用"休眠"功能，普通关机和睡眠通常不受影响。
echo.
set /p hchoice=是否关闭休眠？^(Y/N^): 
if /i "%hchoice%"=="Y" (
    powercfg -h off
    echo 已关闭休眠。
) else (
    echo 已跳过休眠清理。
)

echo.
echo ==================================================
echo 四、可选清理：浏览器缓存
echo ==================================================
set /p brchoice=是否清理浏览器缓存（Chrome/Edge/Firefox）？^(Y/N^): 
if /i "!brchoice!"=="Y" (
    echo 清理 Chrome 缓存...
    if exist "%LOCALAPPDATA%\Google\Chrome\User Data\Default\Cache" (
        del /s /f /q "%LOCALAPPDATA%\Google\Chrome\User Data\Default\Cache\*" >nul 2>&1
        for /d %%i in ("%LOCALAPPDATA%\Google\Chrome\User Data\Default\Cache\*") do rd /s /q "%%i" >nul 2>&1
        echo Chrome 缓存已清理
    ) else ( echo 未找到 Chrome 缓存 )
    echo 清理 Edge 缓存...
    if exist "%LOCALAPPDATA%\Microsoft\Edge\User Data\Default\Cache" (
        del /s /f /q "%LOCALAPPDATA%\Microsoft\Edge\User Data\Default\Cache\*" >nul 2>&1
        for /d %%i in ("%LOCALAPPDATA%\Microsoft\Edge\User Data\Default\Cache\*") do rd /s /q "%%i" >nul 2>&1
        echo Edge 缓存已清理
    ) else ( echo 未找到 Edge 缓存 )
    echo 清理 Firefox 缓存...
    if exist "%LOCALAPPDATA%\Mozilla\Firefox\Profiles" (
        for /d %%i in ("%LOCALAPPDATA%\Mozilla\Firefox\Profiles\*\cache2") do (
            if exist "%%i" (
                del /s /f /q "%%i\*" >nul 2>&1
                for /d %%j in ("%%i\*") do rd /s /q "%%j" >nul 2>&1
            )
        )
        echo Firefox 缓存已清理
    ) else ( echo 未找到 Firefox 缓存 )
    echo 浏览器缓存清理完成
) else (
    echo 已跳过浏览器缓存清理。
)

echo.
echo ==================================================
echo 五、可选清理：微信缓存
echo ==================================================
set /p wxchoice=是否清理微信缓存（聊天图片/视频，可能超 10GB）？^(Y/N^): 
if /i "!wxchoice!"=="Y" (
    if exist "%USERPROFILE%\Documents\WeChat Files" (
        for /d %%i in ("%USERPROFILE%\Documents\WeChat Files\*") do (
            if exist "%%i\FileStorage" (
                del /s /f /q "%%i\FileStorage\*" >nul 2>&1
                for /d %%j in ("%%i\FileStorage\*") do rd /s /q "%%j" >nul 2>&1
                echo 微信缓存已清理：%%~nxi
            )
        )
    ) else (
        echo 未找到微信缓存目录
    )
) else (
    echo 已跳过微信缓存清理。
)

echo.
echo ==================================================
echo 六、可选清理：VSCode 缓存
echo ==================================================
set /p vscchoice=是否清理 VSCode 缓存？^(Y/N^): 
if /i "!vscchoice!"=="Y" (
    if exist "%APPDATA%\Code\Cache" (
        del /s /f /q "%APPDATA%\Code\Cache\*" >nul 2>&1
        for /d %%i in ("%APPDATA%\Code\Cache\*") do rd /s /q "%%i" >nul 2>&1
        echo VSCode Cache 已清理
    )
    if exist "%APPDATA%\Code\CachedData" (
        del /s /f /q "%APPDATA%\Code\CachedData\*" >nul 2>&1
        for /d %%i in ("%APPDATA%\Code\CachedData\*") do rd /s /q "%%i" >nul 2>&1
        echo VSCode CachedData 已清理
    )
) else (
    echo 已跳过 VSCode 缓存清理。
)

echo.
echo ==================================================
echo 七、可选清理：NVIDIA 缓存
echo ==================================================
set /p nvchoice=是否清理 NVIDIA 缓存（Downloader + Installer2）？^(Y/N^): 
if /i "!nvchoice!"=="Y" (
    if exist "C:\ProgramData\NVIDIA Corporation\Downloader" (
        del /s /f /q "C:\ProgramData\NVIDIA Corporation\Downloader\*" >nul 2>&1
        for /d %%i in ("C:\ProgramData\NVIDIA Corporation\Downloader\*") do rd /s /q "%%i" >nul 2>&1
    )
    if exist "C:\Program Files\NVIDIA Corporation\Installer2" (
        del /s /f /q "C:\Program Files\NVIDIA Corporation\Installer2\*" >nul 2>&1
        for /d %%i in ("C:\Program Files\NVIDIA Corporation\Installer2\*") do rd /s /q "%%i" >nul 2>&1
    )
    echo NVIDIA 缓存已清理
) else (
    echo 已跳过 NVIDIA 缓存清理。
)

echo.
echo ==================================================
echo 八、可选清理：pip 缓存
echo ==================================================
set "PIP_CMD="
python -m pip --version >nul 2>&1
if not errorlevel 1 set "PIP_CMD=python -m pip"
if not defined PIP_CMD (
    py -m pip --version >nul 2>&1
    if not errorlevel 1 set "PIP_CMD=py -m pip"
)
if not defined PIP_CMD (
    pip --version >nul 2>&1
    if not errorlevel 1 set "PIP_CMD=pip"
)
if defined PIP_CMD (
    echo [pip 缓存目录]
    !PIP_CMD! cache dir
    echo.
    set /p pchoice=是否清理 pip 缓存？^(Y/N^): 
    if /i "!pchoice!"=="Y" (
        !PIP_CMD! cache purge
        echo pip 缓存已清理
    ) else (
        echo 已跳过 pip 缓存清理。
    )
) else (
    echo 未检测到可用的 pip，已跳过。
)

echo.
echo ==================================================
echo 九、可选清理：npm 缓存
echo ==================================================
set /p npmchoice=是否清理 npm 缓存？^(Y/N^): 
if /i "!npmchoice!"=="Y" (
    if exist "%APPDATA%\npm-cache" (
        del /s /f /q "%APPDATA%\npm-cache\*" >nul 2>&1
        for /d %%i in ("%APPDATA%\npm-cache\*") do rd /s /q "%%i" >nul 2>&1
        echo npm 缓存已清理
    ) else (
        echo 未找到 npm 缓存目录
    )
) else (
    echo 已跳过 npm 缓存清理。
)

echo.
echo ==================================================
echo 十、可选清理：conda 缓存
echo ==================================================
where conda >nul 2>&1
if "%errorlevel%"=="0" (
    echo 已检测到 conda。
    echo 即将执行：conda clean --all -y
    set /p cchoice=是否继续清理 conda 缓存？^(Y/N^): 
    if /i "!cchoice!"=="Y" (
        call conda clean --all -y 2>nul
        if errorlevel 1 (
            echo conda 清理失败，请手动检查 conda 环境。
        ) else (
            echo conda 清理完成。
        )
    ) else (
        echo 已跳过 conda 清理。
    )
) else (
    echo 未检测到 conda，已跳过。
)

echo.
echo ==================================================
echo 十一、可选清理：__pycache__（Python 字节码缓存）
echo ==================================================
set /p pycchoice=是否清理所有 __pycache__ 目录？^(Y/N^): 
if /i "!pycchoice!"=="Y" (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$count=0; Get-ChildItem C:\ -Directory -Name __pycache__ -Recurse -ErrorAction SilentlyContinue -Depth 4 | ForEach-Object { Remove-Item (Join-Path 'C:\' $_) -Recurse -Force -ErrorAction SilentlyContinue; $count++ }; Write-Host ('  清理了 ' + $count + ' 个 __pycache__ 目录')"
    echo __pycache__ 已清理
) else (
    echo 已跳过 __pycache__ 清理。
)

echo.
echo ==================================================
echo 十二、可选清理：Docker
echo ==================================================
where docker >nul 2>&1
if "%errorlevel%"=="0" (
    echo [Docker 当前占用]
    docker system df
    echo.
    echo 危险提示：
    echo docker system prune -a -f 会删除未使用的容器、网络、镜像和构建缓存。
    echo 正在运行的容器不会被删除。
    echo.
    set /p dchoice=是否执行 docker system prune -a -f？^(Y/N^): 
    if /i "!dchoice!"=="Y" (
        docker system prune -a -f
    ) else (
        echo 已跳过 Docker 清理。
    )
) else (
    echo 未检测到 Docker，已跳过。
)

echo.
echo ==================================================
echo 清理后 C 盘空间
echo ==================================================
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_LogicalDisk -Filter 'DeviceID=''C:''' | Select-Object DeviceID,@{Name='SizeGB';Expression={[math]::Round($_.Size/1GB,2)}},@{Name='FreeGB';Expression={[math]::Round($_.FreeSpace/1GB,2)}} | Format-Table -AutoSize"

echo.
echo ==================================================
echo ✅ C盘清理完成！
echo ==================================================
echo.
echo 如果 C 盘仍然很满，请重点检查：
echo   C:\Users\%username%\AppData
echo   C:\ProgramData
echo   C:\Windows
echo   System Volume Information
echo.
pause
