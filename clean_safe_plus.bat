@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 936 >nul
color 0A
title C盘清理工具 - 安全版

net session >nul 2>&1
if "%errorlevel%"=="0" goto :main

echo 正在请求管理员权限...
set "SELF=%~f0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath $env:SELF -Verb RunAs"
if errorlevel 1 goto :adminfail
exit /b

:adminfail
echo 无法自动请求管理员权限。
echo 请右键此文件，选择“以管理员身份运行”。
pause
exit /b



:diskinfo
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_LogicalDisk -Filter 'DeviceID=''C:''' | Select-Object DeviceID,@{Name='SizeGB';Expression={[math]::Round($_.Size/1GB,2)}},@{Name='FreeGB';Expression={[math]::Round($_.FreeSpace/1GB,2)}} | Format-Table -AutoSize"
goto :eof

:getfreegb
for /f "usebackq delims=" %%A in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "[math]::Round((Get-CimInstance Win32_LogicalDisk -Filter 'DeviceID=''C:''' ).FreeSpace/1GB,2)"`) do set "%~1=%%A"
goto :eof

:cleandir
set "CLEAN_PATH=%~1"
set "CLEAN_NAME=%~2"
if not defined CLEAN_NAME set "CLEAN_NAME=%~1"
if not defined CLEAN_PATH (
    echo   跳过空路径
    goto :eof
)
if /i "%CLEAN_PATH%"=="C:\" (
    echo   跳过危险路径：%CLEAN_PATH%
    goto :eof
)
if /i "%CLEAN_PATH%"=="C:" (
    echo   跳过危险路径：%CLEAN_PATH%
    goto :eof
)
if /i "%CLEAN_PATH%"=="\" (
    echo   跳过危险路径：%CLEAN_PATH%
    goto :eof
)
if not exist "%CLEAN_PATH%" (
    echo   未找到：%CLEAN_NAME%
    goto :eof
)
echo   正在清理：%CLEAN_NAME%
rem Use PowerShell so hidden/system items are included and failures can be counted.
set "CLEAN_RESULT="
for /f "tokens=1-3" %%A in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=$env:CLEAN_PATH; if(-not (Test-Path -LiteralPath $p -PathType Container)){Write-Output '0 0 0'; exit}; $items=@(Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue); $before=(Get-ChildItem -LiteralPath $p -Force -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum; if($null -eq $before){$before=0}; $failed=0; foreach($item in $items){try{Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop}catch{$failed++}}; $after=(Get-ChildItem -LiteralPath $p -Force -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum; if($null -eq $after){$after=0}; $freed=[math]::Max(0,[double]$before-[double]$after); Write-Output ('{0} {1} {2}' -f $freed,$failed,$items.Count)" 2^>nul') do set "CLEAN_RESULT=%%A %%B %%C"
if not defined CLEAN_RESULT set "CLEAN_RESULT=0 1 0"
echo   已处理：%CLEAN_NAME%
call :showcleanresult
goto :eof

:showcleanresult
set "CLEAN_FREED_BYTES=0"
set "CLEAN_FAILED=0"
set "CLEAN_ITEMS=0"
for /f "tokens=1-3" %%A in ("!CLEAN_RESULT!") do (
    set "CLEAN_FREED_BYTES=%%A"
    set "CLEAN_FAILED=%%B"
    set "CLEAN_ITEMS=%%C"
)
set "CLEAN_FREED_MB=0"
for /f "usebackq delims=" %%A in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "[math]::Round([double]'!CLEAN_FREED_BYTES!'/1MB,2)"`) do set "CLEAN_FREED_MB=%%A"
echo   Result: !CLEAN_ITEMS! items, !CLEAN_FREED_MB! MB freed, !CLEAN_FAILED! failed
if not "!CLEAN_FAILED!"=="0" echo   Warning: locked or protected items were skipped.
set "CLEAN_RESULT="
goto :eof

:cleanfiles
set "FILE_PATTERN=%~1"
set "FILE_NAME=%~2"
set "CLEAN_RESULT="
for /f "tokens=1-3" %%A in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "$pattern=$env:FILE_PATTERN; $root=[IO.Path]::GetDirectoryName($pattern); $leaf=[IO.Path]::GetFileName($pattern); if(-not (Test-Path -LiteralPath $root -PathType Container)){Write-Output '0 0 0'; exit}; $items=@(Get-ChildItem -LiteralPath $root -Filter $leaf -File -Force -Recurse -ErrorAction SilentlyContinue); $before=($items | Measure-Object -Property Length -Sum).Sum; if($null -eq $before){$before=0}; $failed=0; foreach($item in $items){try{Remove-Item -LiteralPath $item.FullName -Force -ErrorAction Stop}catch{$failed++}}; $after=(Get-ChildItem -LiteralPath $root -Filter $leaf -File -Force -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum; if($null -eq $after){$after=0}; $freed=[math]::Max(0,[double]$before-[double]$after); Write-Output ('{0} {1} {2}' -f $freed,$failed,$items.Count)" 2^>nul') do set "CLEAN_RESULT=%%A %%B %%C"
if not defined CLEAN_RESULT set "CLEAN_RESULT=0 1 0"
echo   已处理：%FILE_NAME%
call :showcleanresult
goto :eof

:service_stop
sc query "%~1" >nul 2>&1
if errorlevel 1 goto :eof
sc stop "%~1" >nul 2>&1
for /l %%N in (1,1,20) do (
    for /f "tokens=3" %%S in ('sc query "%~1" ^| findstr /i "STATE"') do if "%%S"=="1" goto :eof
    timeout /t 1 /nobreak >nul
)
goto :eof

:closeprocess
set "PROC_NAME=%~1"
tasklist /fi "IMAGENAME eq %PROC_NAME%" /fo csv /nh | find /i "%PROC_NAME%" >nul 2>&1
if errorlevel 1 goto :eof
echo   %PROC_NAME% is running and may lock cache files.
set "PROC_CHOICE="
set /p "PROC_CHOICE=Close %PROC_NAME% now? (Y/N): "
if /i "!PROC_CHOICE!"=="Y" taskkill /f /im "%PROC_NAME%" >nul 2>&1
goto :eof

:service_start
sc query "%~1" >nul 2>&1
if errorlevel 1 goto :eof
sc start "%~1" >nul 2>&1
for /l %%N in (1,1,20) do (
    for /f "tokens=3" %%S in ('sc query "%~1" ^| findstr /i "STATE"') do if "%%S"=="4" goto :eof
    timeout /t 1 /nobreak >nul
)
goto :eof

:fixvpntun
ipconfig /flushdns >nul 2>&1
netsh winsock reset >nul 2>&1
netsh int ip reset >nul 2>&1
netsh winhttp reset proxy >nul 2>&1
sc config Dnscache start= auto >nul 2>&1
call :service_start Dnscache
sc config iphlpsvc start= auto >nul 2>&1
call :service_start iphlpsvc
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' } | ForEach-Object { Get-NetIPInterface -InterfaceIndex $_.InterfaceIndex -ErrorAction SilentlyContinue | Set-NetIPInterface -AutomaticMetric Enabled -ErrorAction SilentlyContinue }" >nul 2>&1
goto :eof

:main
call :getfreegb FREE_BEFORE

echo ==================================================
echo C盘清理工具：安全清理 + 系统优化 + 缓存清理
echo ==================================================
echo.

echo [当前C盘空间]
call :diskinfo
echo.

set /p gochoice=是否继续执行安全清理？^(Y/N^):
if /i not "!gochoice!"=="Y" (
    echo 已取消清理。
    pause
    exit /b
)

echo.
echo ==================================================
echo 板块一、执行安全清理（自动执行）
echo ==================================================

echo [1/8] 清理用户临时文件...
call :cleandir "%TEMP%" "用户 Temp"

echo [2/8] 清理 AppData Local Temp...
call :cleandir "%LOCALAPPDATA%\Temp" "AppData Local Temp"

echo [3/8] 清理 Prefetch（自动重建，安全）...
call :cleandir "%SystemRoot%\Prefetch" "Prefetch"

echo [4/8] 清理日志文件（Windows Logs + WER）...
    call :cleandir "%SystemRoot%\Logs" "Windows Logs"
    call :cleandir "%ProgramData%\Microsoft\Windows\WER" "WER 错误报告"
    call :cleandir "%LOCALAPPDATA%\Microsoft\Windows\WER" "用户 WER 错误报告"

echo [5/8] 清理缩略图缓存...
call :cleanfiles "%LOCALAPPDATA%\Microsoft\Windows\Explorer\thumbcache_*.db" "缩略图缓存"

echo [6/8] 清理 Windows 更新下载缓存...
call :service_stop wuauserv
call :service_stop bits
call :service_stop DoSvc
call :cleandir "%SystemRoot%\SoftwareDistribution\Download" "Windows 更新下载缓存"
call :cleandir "%SystemRoot%\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache" "Delivery Optimization 缓存"
call :cleandir "%LOCALAPPDATA%\D3DSCache" "DirectX Shader 缓存"
call :cleandir "%LOCALAPPDATA%\NVIDIA\DXCache" "NVIDIA DX 缓存"
call :cleandir "%LOCALAPPDATA%\NVIDIA\GLCache" "NVIDIA GL 缓存"
call :cleandir "%LOCALAPPDATA%\AMD\DxCache" "AMD DX 缓存"
call :cleandir "%LOCALAPPDATA%\AMD\GLCache" "AMD GL 缓存"
call :service_start wuauserv
call :service_start bits
call :service_start DoSvc

echo [7/8] 清理 Windows 临时目录...
call :cleandir "%SystemRoot%\Temp" "Windows Temp"

echo [8/8] 清理回收站...
call :cleandir "C:\$Recycle.Bin" "回收站"
echo   已清理回收站

echo 安全清理完成。
echo.

echo ==================================================
echo 板块二、系统优化
echo ==================================================
echo.

echo --- 2.1 关闭休眠 ---
echo 说明：关闭休眠会删除 hiberfil.sys，通常释放数 GB 到几十 GB。
echo 影响：不能使用“休眠”功能，普通关机和睡眠通常不受影响。
echo.
set /p hchoice=是否关闭休眠？^(Y/N^):
if /i "!hchoice!"=="Y" (
    powercfg -h off
    echo 已关闭休眠。
) else (
    echo 跳过休眠。
)

echo.
echo --- 2.2 系统服务与性能优化 ---
echo 说明：停止 Xbox 等非必要后台服务、关闭窗口透明效果、禁用 OneDrive 自启动。
echo.
set /p sysoptchoice=是否执行系统服务与性能优化？^(Y/N^):
if /i "!sysoptchoice!"=="Y" (
    echo 停止非必要服务...
    call :service_stop SysMain
    sc config SysMain start= disabled >nul 2>&1
    call :service_stop WSearch
    sc config WSearch start= manual >nul 2>&1
    call :service_stop XblAuthManager
    sc config XblAuthManager start= disabled >nul 2>&1
    call :service_stop XblGameSave
    sc config XblGameSave start= disabled >nul 2>&1
    call :service_stop XboxNetApiSvc
    sc config XboxNetApiSvc start= disabled >nul 2>&1

    echo 优化视觉效果...
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v EnableTransparency /t REG_DWORD /d 0 /f >nul 2>&1
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" /v VisualFXSetting /t REG_DWORD /d 2 /f >nul 2>&1

    echo 禁用 OneDrive 自启动...
    reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v OneDrive /f >nul 2>&1

    echo 系统服务与性能优化完成。
    echo 建议重启电脑以应用所有设置。
) else (
    echo 跳过系统服务与性能优化。
)

echo.
echo --- 2.3 网络优化 ---
echo 说明：关闭后台网络服务、DNS 刷新、协议重置、TCP 参数调优、网卡省电关闭、MTU 优化。
echo 注意：执行中网络会短暂断开，刷新后会恢复。
echo.
set /p netchoice=是否执行网络优化？^(Y/N^):
if /i "!netchoice!"=="Y" (
    echo [1/6] 关闭后台网络服务...
    call :service_stop DoSvc
    sc config DoSvc start= disabled >nul 2>&1
    call :service_stop DiagTrack
    sc config DiagTrack start= disabled >nul 2>&1
    call :service_stop dmwappushservice
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

    echo 网络优化完成。
    echo 建议重启电脑以应用所有设置。
) else (
    echo 跳过网络优化。
)

echo.
echo --- 2.4 修复 VPN/TUN 关闭后无法联网 ---
echo 说明：刷新 DNS、重置 Winsock/IP、重置 WinHTTP 代理、恢复活动网卡自动 metric。
echo 适合 Clash/mihomo/sing-box/WireGuard 的 TUN 模式或全局代理异常后的系统网络问题。
echo 注意：执行后请测试网络，再重新开启 VPN/TUN。
echo.
set /p tunchoice=是否执行 VPN/TUN 网络修复？^(Y/N^):
if /i "!tunchoice!"=="Y" (
    call :fixvpntun
    echo VPN/TUN 网络修复已执行，请测试网络后再开启 TUN。
) else (
    echo 跳过 VPN/TUN 网络修复。
)

echo.
echo ==================================================
echo 板块三、应用缓存清理
echo ==================================================
echo.

echo --- 3.1 浏览器缓存 ---
set /p brchoice=是否清理浏览器缓存（Chrome/Edge/Firefox）？^(Y/N^):
if /i "!brchoice!"=="Y" (
    call :closeprocess chrome.exe
    call :closeprocess msedge.exe
    call :closeprocess firefox.exe
    if exist "%LOCALAPPDATA%\Google\Chrome\User Data" (
        for /d %%p in ("%LOCALAPPDATA%\Google\Chrome\User Data\*") do (
            call :cleandir "%%p\Cache" "Chrome %%~nxp Cache"
            call :cleandir "%%p\Code Cache" "Chrome %%~nxp Code Cache"
            call :cleandir "%%p\GPUCache" "Chrome %%~nxp GPUCache"
            call :cleandir "%%p\ShaderCache" "Chrome %%~nxp ShaderCache"
            call :cleandir "%%p\GrShaderCache" "Chrome %%~nxp GrShaderCache"
            call :cleandir "%%p\Service Worker\CacheStorage" "Chrome %%~nxp Service Worker CacheStorage"
        )
    ) else (
        echo   未找到 Chrome 用户数据目录。
    )
    if exist "%LOCALAPPDATA%\Microsoft\Edge\User Data" (
        for /d %%p in ("%LOCALAPPDATA%\Microsoft\Edge\User Data\*") do (
            call :cleandir "%%p\Cache" "Edge %%~nxp Cache"
            call :cleandir "%%p\Code Cache" "Edge %%~nxp Code Cache"
            call :cleandir "%%p\GPUCache" "Edge %%~nxp GPUCache"
            call :cleandir "%%p\ShaderCache" "Edge %%~nxp ShaderCache"
            call :cleandir "%%p\GrShaderCache" "Edge %%~nxp GrShaderCache"
            call :cleandir "%%p\Service Worker\CacheStorage" "Edge %%~nxp Service Worker CacheStorage"
        )
    ) else (
        echo   未找到 Edge 用户数据目录。
    )
    if exist "%LOCALAPPDATA%\Mozilla\Firefox\Profiles" (
        for /d %%p in ("%LOCALAPPDATA%\Mozilla\Firefox\Profiles\*") do (
            call :cleandir "%%p\cache2" "Firefox %%~nxp cache2"
            call :cleandir "%%p\startupCache" "Firefox %%~nxp startupCache"
        )
    ) else (
        echo   未找到 Firefox Profiles。
    )
    echo 浏览器缓存清理完成。
) else (
    echo 跳过浏览器缓存清理。
)

echo.
echo --- 3.2 微信缓存 ---
set /p wxchoice=是否清理微信缓存（聊天图片/视频，可能超 10GB）？^(Y/N^):
if /i "!wxchoice!"=="Y" (
    set "WX_FOUND=0"
    call :closeprocess WeChat.exe
    call :closeprocess Weixin.exe
    rem ---- 微信 3.x：默认位置 + 注册表自定义保存路径（FileSavePath 存上级目录）----
    for %%R in ("%USERPROFILE%\Documents\WeChat Files" "%USERPROFILE%\Documents\Weixin Files" "%USERPROFILE%\Documents\xwechat_files" "%USERPROFILE%\WeChat Files" "%APPDATA%\Tencent\WeChat Files" "%APPDATA%\Tencent\Weixin Files" "%LOCALAPPDATA%\Tencent\WeChat Files" "%LOCALAPPDATA%\Tencent\Weixin Files") do (
        if exist "%%~R" (
            if exist "%%~R\FileStorage" (
                set "WX_FOUND=1"
                call :cleandir "%%~R\FileStorage" "微信缓存：%%~nxR"
            )
            for /d %%i in ("%%~R\*") do (
                if exist "%%i\FileStorage" (
                    set "WX_FOUND=1"
                    call :cleandir "%%i\FileStorage" "微信缓存：%%~nxi"
                )
            )
        )
    )
    for /f "usebackq delims=" %%S in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$v=$null; try{$v=(Get-ItemProperty -Path 'HKCU:\Software\Tencent\WeChat' -ErrorAction Stop).FileSavePath}catch{}; if($v -and $v -notmatch '^MyDocument:$'){ Write-Output $v }"`) do (
        for %%T in ("%%S" "%%S\WeChat Files" "%%S\Weixin Files" "%%S\xwechat_files") do (
            if exist "%%~T" (
                if exist "%%~T\FileStorage" (
                    set "WX_FOUND=1"
                    call :cleandir "%%~T\FileStorage" "微信缓存（注册表自定义路径）"
                )
                for /d %%i in ("%%~T\*") do (
                    if exist "%%i\FileStorage" (
                        set "WX_FOUND=1"
                        call :cleandir "%%i\FileStorage" "微信缓存：%%~nxi"
                    )
                )
            )
        )
    )
    rem ---- 微信 4.x：xwechat_files 新结构（msg\attach|file|image|video，无 FileStorage）----
    for /f "usebackq delims=" %%i in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$dirs=@(); $roots=@($env:USERPROFILE+'\Documents',$env:USERPROFILE+'\Documents\WeChat Files',$env:USERPROFILE+'\Documents\Weixin Files',$env:USERPROFILE+'\Documents\xwechat_files',$env:APPDATA+'\Tencent',$env:LOCALAPPDATA+'\Tencent'); try{$v=(Get-ItemProperty -Path 'HKCU:\Software\Tencent\WeChat' -ErrorAction Stop).FileSavePath; if($v -and $v -notmatch '^MyDocument:$'){$roots += @($v,(Join-Path $v 'WeChat Files'),(Join-Path $v 'Weixin Files'),(Join-Path $v 'xwechat_files'))}}catch{}; foreach($root in ($roots | Select-Object -Unique)){ if(-not (Test-Path -LiteralPath $root)){ continue }; Get-ChildItem -LiteralPath $root -Directory -Recurse -Depth 6 -ErrorAction SilentlyContinue | Where-Object { $_.Name -ieq 'msg' -and $_.FullName -match '(?i)(WeChat Files|Weixin Files|xwechat_files)' } | ForEach-Object { foreach($s in @('attach','file','image','video')){ $d=Join-Path $_.FullName $s; if(Test-Path -LiteralPath $d){ $dirs += $d } } } }; $dirs | Select-Object -Unique"`) do (
        if exist "%%i" (
            set "WX_FOUND=1"
            call :cleandir "%%i" "微信缓存：%%i"
        )
    )
    rem ---- 兜底：递归搜索 FileStorage（覆盖非常规位置）----
    for /f "usebackq delims=" %%i in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$r1=$env:USERPROFILE+'\Documents'; $r2=$env:APPDATA+'\Tencent'; $r3=$env:LOCALAPPDATA+'\Tencent'; $roots=@($r1,$r2,$r3); foreach($root in $roots){ if(Test-Path -LiteralPath $root){ foreach($d in Get-ChildItem -LiteralPath $root -Directory -Filter FileStorage -Recurse -Depth 5 -ErrorAction SilentlyContinue){ if($d.FullName -match '(?i)(WeChat Files|xwechat_files|Weixin)'){ Write-Output $d.FullName } } } }"`) do (
        if exist "%%i" (
            set "WX_FOUND=1"
            call :cleandir "%%i" "微信缓存：%%i"
        )
    )
    if "!WX_FOUND!"=="0" (
        echo 未找到微信缓存目录。
        echo 可在微信 设置 ^> 文件管理 中查看保存位置后手动清理。
        set /p wxmanual=或直接输入微信缓存目录路径（回车跳过）:
        if not "!wxmanual!"=="" (
            if exist "!wxmanual!" (
                if exist "!wxmanual!\FileStorage" (
                    set "WX_FOUND=1"
                    call :cleandir "!wxmanual!\FileStorage" "微信缓存（手动输入）"
                )
                for /d %%m in ("!wxmanual!\msg") do (
                    for %%s in (attach file image video) do (
                        if exist "%%m\%%s" (
                            set "WX_FOUND=1"
                            call :cleandir "%%m\%%s" "微信缓存（手动输入）%%s"
                        )
                    )
                )
                for /d %%a in ("!wxmanual!\*") do (
                    if exist "%%a\FileStorage" (
                        set "WX_FOUND=1"
                        call :cleandir "%%a\FileStorage" "微信缓存（手动输入）%%~nxa"
                    )
                    if exist "%%a\msg" (
                        for %%s in (attach file image video) do (
                            if exist "%%a\msg\%%s" (
                                set "WX_FOUND=1"
                                call :cleandir "%%a\msg\%%s" "微信缓存（手动输入）%%s"
                            )
                        )
                    )
                )
                if "!WX_FOUND!"=="0" (
                    echo   未能识别该目录，已跳过。
                )
            ) else (
                echo   路径不存在，已跳过。
            )
        )
    )
) else (
    echo 跳过微信缓存清理。
)

echo.
echo --- 3.3 VSCode 缓存 ---
set /p vscchoice=是否清理 VSCode 缓存？^(Y/N^):
if /i "!vscchoice!"=="Y" (
    call :cleandir "%APPDATA%\Code\Cache" "VSCode Cache"
    call :cleandir "%APPDATA%\Code\CachedData" "VSCode CachedData"
    call :cleandir "%APPDATA%\Code\Code Cache" "VSCode Code Cache"
    call :cleandir "%APPDATA%\Code\GPUCache" "VSCode GPUCache"
    call :cleandir "%APPDATA%\Code\logs" "VSCode logs"
    call :cleandir "%APPDATA%\Code\CachedExtensionVSIXs" "VSCode CachedExtensionVSIXs"
) else (
    echo 跳过 VSCode 缓存清理。
)

echo.
echo --- 3.4 NVIDIA 缓存 ---
set /p nvchoice=是否清理 NVIDIA 缓存（Downloader + Installer2）？^(Y/N^):
if /i "!nvchoice!"=="Y" (
    call :cleandir "%ProgramData%\NVIDIA Corporation\Downloader" "NVIDIA Downloader"
    call :cleandir "%ProgramFiles%\NVIDIA Corporation\Installer2" "NVIDIA Installer2"
) else (
    echo 跳过 NVIDIA 缓存清理。
)

echo.
echo ==================================================
echo 板块四、开发工具缓存
echo ==================================================
echo.

echo --- 4.1 pip 缓存 ---
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
        echo pip 缓存已清理。
    ) else (
        echo 跳过 pip 缓存清理。
    )
) else (
    echo 未检测到可用的 pip，跳过。
)

echo.
echo --- 4.2 npm 缓存 ---
set /p npmchoice=是否清理 npm 缓存？^(Y/N^):
if /i "!npmchoice!"=="Y" (
    where npm >nul 2>&1
    if not errorlevel 1 (
        echo   即将执行：npm cache clean --force
        call npm cache clean --force
    ) else (
        echo   未检测到 npm 命令，仅清理常见缓存目录。
    )
    call :cleandir "%APPDATA%\npm-cache" "npm Roaming 缓存"
    call :cleandir "%LOCALAPPDATA%\npm-cache" "npm LocalAppData 缓存"
) else (
    echo 跳过 npm 缓存清理。
)

echo.
echo --- 4.3 conda 缓存 ---
where conda >nul 2>&1
if not errorlevel 1 (
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
        echo 跳过 conda 清理。
    )
) else (
    echo 未检测到 conda，跳过。
)

echo.
echo --- 4.4 __pycache__（Python 字节码缓存） ---
set /p pycchoice=是否清理所有 __pycache__ 目录？^(Y/N^):
if /i "!pycchoice!"=="Y" (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$count=0; Get-ChildItem C:\ -Directory -Name __pycache__ -Recurse -ErrorAction SilentlyContinue -Depth 4 | ForEach-Object { Remove-Item (Join-Path 'C:\' $_) -Recurse -Force -ErrorAction SilentlyContinue; $count++ }; Write-Host ('  清理了 ' + $count + ' 个 __pycache__ 目录')"
    echo __pycache__ 已清理。
) else (
    echo 跳过 __pycache__ 清理。
)

echo.
echo --- 4.5 Docker ---
where docker >nul 2>&1
if not errorlevel 1 (
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
        echo 跳过 Docker 清理。
    )
) else (
    echo 未检测到 Docker，跳过。
)

echo.
echo ==================================================
echo 最后、分析 C:\ 下的大目录
echo ==================================================
echo 单位：GB。这个步骤可能很慢，可按 N 跳过。
echo.

set /p analyzechoice=是否现在分析 C 盘大目录？^(Y/N^):
if /i "!analyzechoice!"=="Y" (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='SilentlyContinue'; $targets=@('C:\Users\Administrator\AppData','C:\ProgramData','C:\Windows','C:\System Volume Information'); Write-Host '[重点目录]'; foreach($p in $targets){ $sum=0; try { $sum=(Get-ChildItem -LiteralPath $p -Recurse -Force -File -ErrorAction SilentlyContinue 2>$null | Measure-Object Length -Sum).Sum } catch { $sum=0 }; if($null -eq $sum){$sum=0}; [PSCustomObject]@{Name=$p; GB=[math]::Round($sum/1GB,2)} } | Format-Table -AutoSize; Write-Host ''; Write-Host '[C:\ 根目录 Top 12]'; Get-ChildItem C:\ -Force -ErrorAction SilentlyContinue | ForEach-Object { $sum=0; try { $sum=(Get-ChildItem -LiteralPath $_.FullName -Recurse -Force -File -ErrorAction SilentlyContinue 2>$null | Measure-Object Length -Sum).Sum } catch { $sum=0 }; if ($null -eq $sum) { $sum=0 }; [PSCustomObject]@{Name=$_.FullName; GB=[math]::Round($sum/1GB,2)} } | Sort-Object GB -Descending | Select-Object -First 12 | Format-Table -AutoSize"

    echo.
    echo [如果 C 盘仍然很满，请重点检查]
    echo - C:\Users\Administrator\AppData：浏览器、微信/QQ、开发工具缓存；不要删除整个 AppData。
    echo - C:\ProgramData：NVIDIA、Docker、安装包、公共缓存；只清理确认是缓存的子目录。
    echo - C:\Windows：优先用系统组件清理，不要手动删除 WinSxS、Installer、System32。
    echo - System Volume Information：通常是系统还原点/卷影副本占用。
    echo.
    set /p dismchoice=是否执行 Windows 组件清理 DISM？^(Y/N^):
    if /i "!dismchoice!"=="Y" (
        Dism.exe /Online /Cleanup-Image /StartComponentCleanup
    ) else (
        echo 跳过 Windows 组件清理。
    )
    echo.
    set /p vsschoice=是否将 C 盘系统还原/卷影副本上限设为 5GB？^(Y/N^):
    if /i "!vsschoice!"=="Y" (
        vssadmin Resize ShadowStorage /For=C: /On=C: /MaxSize=5GB
    ) else (
        echo 跳过 System Volume Information 处理。
    )
) else (
    echo 已跳过大目录分析。
)

call :getfreegb FREE_AFTER
for /f "usebackq delims=" %%A in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "[math]::Round([double]'!FREE_AFTER!' - [double]'!FREE_BEFORE!', 2)"`) do set "FREE_DELTA=%%A"

echo.
echo ==================================================
echo 清理后 C 盘空间
echo ==================================================
call :diskinfo

echo.
echo ==================================================
echo C盘清理完成！
echo ==================================================
echo 清理前剩余：!FREE_BEFORE! GB
echo 清理后剩余：!FREE_AFTER! GB
echo 本次释放：  !FREE_DELTA! GB
echo.
echo 如果 C 盘仍然很满，请重点检查：
echo   C:\Users\Administrator\AppData
echo   C:\ProgramData
echo   C:\Windows
echo   System Volume Information
echo.
pause
