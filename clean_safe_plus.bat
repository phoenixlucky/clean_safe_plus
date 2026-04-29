@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 936 >nul
color 0A
title C盘清理工具 - 安全版

net session >nul 2>&1
if not "%errorlevel%"=="0" (
    echo 正在请求管理员权限...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    if errorlevel 1 (
        echo 无法自动请求管理员权限。
        echo 请右键此文件，选择“以管理员身份运行”。
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
echo 二、执行安全清理
echo ==================================================

echo [1/5] 清理用户临时文件...
del /s /f /q "%temp%\*" >nul 2>&1
for /d %%i in ("%temp%\*") do rd /s /q "%%i" >nul 2>&1

echo [2/5] 清理 AppData Local Temp...
del /s /f /q "C:\Users\%username%\AppData\Local\Temp\*" >nul 2>&1
for /d %%i in ("C:\Users\%username%\AppData\Local\Temp\*") do rd /s /q "%%i" >nul 2>&1

echo [3/5] 清理 Windows 更新下载缓存...
net stop wuauserv >nul 2>&1
net stop bits >nul 2>&1
del /s /f /q "C:\Windows\SoftwareDistribution\Download\*" >nul 2>&1
for /d %%i in ("C:\Windows\SoftwareDistribution\Download\*") do rd /s /q "%%i" >nul 2>&1
net start wuauserv >nul 2>&1
net start bits >nul 2>&1

echo [4/5] 清理回收站...
rd /s /q C:\$Recycle.Bin >nul 2>&1

echo [5/5] 清理 Windows 临时目录...
del /s /f /q "C:\Windows\Temp\*" >nul 2>&1
for /d %%i in ("C:\Windows\Temp\*") do rd /s /q "%%i" >nul 2>&1

echo 安全清理完成。
echo.

echo ==================================================
echo 三、可选清理：关闭休眠
echo ==================================================
echo 说明：关闭休眠会删除 hiberfil.sys，通常释放数 GB 到几十 GB。
echo 影响：不能使用“休眠”功能，普通关机和睡眠通常不受影响。
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
echo 四、可选清理：pip 缓存
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
    ) else (
        echo 已跳过 pip 缓存清理。
    )
) else (
    echo 未检测到可用的 pip，已跳过。
    echo 如果看到 pip launcher 错误，请修复 Python 安装或使用 python -m pip。
)

echo.
echo ==================================================
echo 五、可选清理：conda 缓存
echo ==================================================
where conda >nul 2>&1
if "%errorlevel%"=="0" (
    echo 已检测到 conda。
    echo 即将执行：conda clean --all -y
    echo 说明：清理包缓存、索引缓存、临时文件，不删除已有环境。
    echo 如果本机 conda 插件有告警，脚本会隐藏这些告警输出。
    set /p cchoice=是否继续清理 conda 缓存？^(Y/N^): 
    if /i "!cchoice!"=="Y" (
        conda clean --all -y 2>nul
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
echo 六、可选清理：Docker
echo ==================================================
where docker >nul 2>&1
if "%errorlevel%"=="0" (
    echo [Docker 当前占用]
    docker system df
    echo.
    echo [Docker 容器列表]
    docker ps -a
    echo.
    echo [Docker 镜像列表]
    docker images
    echo.
    echo 危险提示：
    echo docker system prune -a -f 会删除未使用的容器、网络、镜像和构建缓存。
    echo 正在运行的容器不会被删除。
    echo 未使用镜像删除后，下次可能需要重新下载。
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
echo 七、清理后 C 盘空间
echo ==================================================
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_LogicalDisk -Filter 'DeviceID=''C:''' | Select-Object DeviceID,@{Name='SizeGB';Expression={[math]::Round($_.Size/1GB,2)}},@{Name='FreeGB';Expression={[math]::Round($_.FreeSpace/1GB,2)}} | Format-Table -AutoSize"

echo.
echo ==================================================
echo 清理完成
echo ==================================================
echo 如果 C 盘仍然很满，请重点检查：
echo C:\Users\Administrator\AppData
echo C:\ProgramData
echo C:\Windows
echo System Volume Information
echo ==================================================
pause
