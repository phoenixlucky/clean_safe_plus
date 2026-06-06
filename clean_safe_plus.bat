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
echo C盘清理工具：安全清理 + 系统优化 + 缓存清理
echo ==================================================
echo.

echo [当前C盘空间]
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_LogicalDisk -Filter 'DeviceID=''C:''' | Select-Object DeviceID,@{Name='SizeGB';Expression={[math]::Round($_.Size/1GB,2)}},@{Name='FreeGB';Expression={[math]::Round($_.FreeSpace/1GB,2)}} | Format-Table -AutoSize"
echo.

echo ==================================================
echo 板块一、分析 C:\ 下的大目录
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
echo 板块二、执行安全清理（自动执行）
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
echo 板块三、系统优化
echo ==================================================
echo.

echo --- 3.1 关闭休眠 ---
echo 说明：关闭休眠会删除 hiberfil.sys，通常释放数 GB 到几十 GB。
echo 影响：不能使用"休眠"功能，普通关机和睡眠通常不受影响。
echo.
set /p hchoice=是否关闭休眠？^(Y/N^): 
if /i "%hchoice%"=="Y" (
    powercfg -h off
    echo 已关闭休眠。
) else (
    echo 已跳过休眠。
)

echo.
echo --- 3.2 系统服务与性能优化 ---
echo 说明：停止 Xbox 等非必需后台服务、关闭窗口透明效果、禁用 OneDrive 自启动。
echo.
set /p sysoptchoice=是否执行系统服务与性能优化？^(Y/N^): 
if /i "!sysoptchoice!"=="Y" (
    echo 停止非必要服务...
    sc stop SysMain >nul 2>&1
    sc config SysMain start= disabled >nul 2>&1
    sc stop WSearch >nul 2>&1
    sc config WSearch start= manual >nul 2>&1
    sc stop XblAuthManager >nul 2>&1
    sc config XblAuthManager start= disabled >nul 2>&1
    sc stop XblGameSave >nul 2>&1
    sc config XblGameSave start= disabled >nul 2>&1
    sc stop XboxNetApiSvc >nul 2>&1
    sc config XboxNetApiSvc start= disabled >nul 2>&1

    echo 优化视觉效果...
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v EnableTransparency /t REG_DWORD /d 0 /f >nul 2>&1
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" /v VisualFXSetting /t REG_DWORD /d 2 /f >nul 2>&1

    echo 禁用 OneDrive 自启动...
    reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v OneDrive /f >nul 2>&1

    echo 系统服务与性能优化完成
    echo 建议重启电脑以应用所有设置
) else (
    echo 已跳过系统服务与性能优化。
)

echo.
echo --- 3.3 网络优化 ---
echo 说明：关闭后台网络服务、DNS 刷新、协议重置、TCP 参数调优、网卡省电关闭、MTU 优化。
echo 注意：执行中网络会短暂断开，刷新后会恢复。
echo.
set /p netchoice=是否执行网络优化？^(Y/N^): 
if /i "!netchoice!"=="Y" (
    echo [1/6] 关闭后台网络服务...
    sc stop DoSvc >nul 2>&1
    sc config DoSvc start= disabled >nul 2>&1
    sc stop DiagTrack >nul 2>&1
    sc config DiagTrack start= disabled >nul 2>&1
    sc stop dmwappushservice >nul 2>&1
    sc config dmwappushservice start= disabled >nul 2>&1

    echo [2/6] 刷新 DNS 缓存...
    ipconfig /flushdns >nul 2>&1

    echo [3/6] 重置网络协议...
    netsh winsock reset >nul 2>&1
    netsh int ip reset >nul 2>&1
    ipconfig /release >nul 2>&1
    ipconfig /renew >nul 2>&1
    netsh interface ip delete arpcache >nul 2>&1

    echo [4/6] TCP/IP 性能参数优化...
    netsh interface tcp set global autotuninglevel=normal >nul 2>&1
    netsh interface tcp set global rss=enabled >nul 2>&1
    netsh interface tcp set global ecncapability=enabled >nul 2>&1

    echo [5/6] Wi-Fi 与网卡省电优化...
    powercfg -setacvalueindex scheme_current sub_wireless 19cbb8fa-5279-450e-9fac-8a3d5fedd0c1 0 >nul 2>&1
    powercfg -setdcvalueindex scheme_current sub_wireless 19cbb8fa-5279-450e-9fac-8a3d5fedd0c1 0 >nul 2>&1
    powercfg -setacvalueindex scheme_current sub_pcie 0ce3997e-6a54-4a3f-b1e8-4f8b9b7d8b6f 0 >nul 2>&1
    powercfg -setdcvalueindex scheme_current sub_pcie 0ce3997e-6a54-4a3f-b1e8-4f8b9b7d8b6f 0 >nul 2>&1

    echo [6/6] MTU 优化...
    netsh interface ipv4 set subinterface "Wi-Fi" mtu=1500 store=persistent >nul 2>&1
    netsh interface ipv4 set subinterface "以太网" mtu=1500 store=persistent >nul 2>&1

    echo 网络优化完成
    echo 建议重启电脑以应用所有设置
) else (
    echo 已跳过网络优化。
)

echo.
echo ==================================================
echo 板块四、应用缓存清理
echo ==================================================
echo.

echo --- 4.1 浏览器缓存 ---
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
echo --- 4.2 微信缓存 ---
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
echo --- 4.3 VSCode 缓存 ---
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
echo --- 4.4 NVIDIA 缓存 ---
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
echo 板块五、开发工具缓存
echo ==================================================
echo.

echo --- 5.1 pip 缓存 ---
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
echo --- 5.2 npm 缓存 ---
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
echo --- 5.3 conda 缓存 ---
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
echo --- 5.4 __pycache__（Python 字节码缓存） ---
set /p pycchoice=是否清理所有 __pycache__ 目录？^(Y/N^): 
if /i "!pycchoice!"=="Y" (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$count=0; Get-ChildItem C:\ -Directory -Name __pycache__ -Recurse -ErrorAction SilentlyContinue -Depth 4 | ForEach-Object { Remove-Item (Join-Path 'C:\' $_) -Recurse -Force -ErrorAction SilentlyContinue; $count++ }; Write-Host ('  清理了 ' + $count + ' 个 __pycache__ 目录')"
    echo __pycache__ 已清理
) else (
    echo 已跳过 __pycache__ 清理。
)

echo.
echo --- 5.5 Docker ---
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
