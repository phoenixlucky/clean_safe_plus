<#
.SYNOPSIS
    C盘清理工具 - 图形界面版
.DESCRIPTION
    基于 Windows Forms 的 C 盘安全清理工具。
    支持勾选清理项、实时日志、进度条、后台执行。
.NOTES
    需要管理员权限运行。
#>

# 管理员权限由运行时检查，不在编译期限制

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ============================================================
# 全局状态
# ============================================================
$script:CancelRequested = $false
$script:Job = $null
$script:LastLogLine = 0

# ============================================================
# 工具函数
# ============================================================

function Get-DiskInfo {
    try {
        $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
        return @{
            DeviceID  = 'C:'
            SizeGB    = [math]::Round($disk.Size / 1GB, 2)
            FreeGB    = [math]::Round($disk.FreeSpace / 1GB, 2)
            UsedGB    = [math]::Round(($disk.Size - $disk.FreeSpace) / 1GB, 2)
            FreePct   = [math]::Round($disk.FreeSpace / $disk.Size * 100, 1)
        }
    } catch {
        return @{ DeviceID = 'C:'; SizeGB = 0; FreeGB = 0; UsedGB = 0; FreePct = 0 }
    }
}

function Update-DiskDisplay {
    $info = Get-DiskInfo
    $pct = $info.FreePct
    $script:diskFreePct = $pct  # 存起来供布局动态缩放用
    $lblDiskInfo.Text = "C:  总容量 $($info.SizeGB) GB  |  已用 $($info.UsedGB) GB  |  剩余 $($info.FreeGB) GB ($($info.FreePct)%)"

    $barWidth = $pnlDiskBarBg.Width
    $newWidth = [int]($barWidth * $info.FreePct / 100)
    $pnlDiskBar.Width = $newWidth

    if ($pct -lt 10) {
        $pnlDiskBar.BackColor = [System.Drawing.Color]::FromArgb(255, 68, 68)
    } elseif ($pct -lt 20) {
        $pnlDiskBar.BackColor = [System.Drawing.Color]::FromArgb(255, 136, 0)
    } else {
        $pnlDiskBar.BackColor = [System.Drawing.Color]::FromArgb(68, 187, 68)
    }
}

function Write-Log {
    param([string]$Text, [string]$Color = 'Black', [bool]$Bold = $false)
    if ($txtLog.IsHandleCreated -and !$txtLog.Disposing -and !$txtLog.IsDisposed) {
        $txtLog.Invoke([Action]{
            $txtLog.SelectionStart = $txtLog.TextLength
            $txtLog.SelectionLength = 0
            $txtLog.SelectionColor = [System.Drawing.Color]::FromName($Color)
            if ($Bold) {
                $txtLog.SelectionFont = [System.Drawing.Font]::new($txtLog.Font, [System.Drawing.FontStyle]::Bold)
            } else {
                $txtLog.SelectionFont = $txtLog.Font
            }
            $timestamp = Get-Date -Format 'HH:mm:ss'
            $txtLog.AppendText("[$timestamp] $Text`r`n")
            $txtLog.ScrollToCaret()
        })
    }
}

function Set-Progress {
    param([int]$Percent, [string]$Status)
    if ($lblStatus.IsHandleCreated -and !$lblStatus.Disposing -and !$lblStatus.IsDisposed) {
        $lblStatus.Invoke([Action]{ $lblStatus.Text = $Status })
        $progressBar.Invoke([Action]{ $progressBar.Value = $Percent })
    }
}

# ============================================================
# 后台作业通信函数（写文件）
# ============================================================

function Write-LogBg {
    param($Text, $Color='Black', $Bold=$false)
    $logFile = Join-Path $env:TEMP "cleanup_gui_log.txt"
    "$Text|$Color|$Bold" | Out-File -FilePath $logFile -Encoding UTF8 -Append
}

function Set-ProgressBg {
    param($Percent, $Status)
    $progressFile = Join-Path $env:TEMP "cleanup_gui_progress.txt"
    "$Percent|$Status" | Out-File -FilePath $progressFile -Encoding UTF8
}

# ============================================================
# 轮询读取后台作业输出
# ============================================================

function Read-JobOutput {
    $logFile = Join-Path $env:TEMP "cleanup_gui_log.txt"
    $progressFile = Join-Path $env:TEMP "cleanup_gui_progress.txt"

    # 读取新日志行
    if (Test-Path $logFile) {
        $content = Get-Content $logFile -Encoding UTF8 -ErrorAction SilentlyContinue
        $totalLines = $content.Count
        if ($totalLines -gt $script:LastLogLine) {
            for ($i = $script:LastLogLine; $i -lt $totalLines; $i++) {
                $parts = $content[$i] -split '\|'
                if ($parts.Count -ge 3) {
                    $text = $parts[0]
                    $color = $parts[1]
                    $bold = $parts[2] -eq 'True'
                    if ($text -eq 'DONE') {
                        $timerPoll.Enabled = $false
                        $btnStart.Invoke([Action]{ $btnStart.Enabled = $true; $btnStart.Text = '开始清理' })
                        $btnCancel.Invoke([Action]{ $btnCancel.Enabled = $false })
                        Update-DiskDisplay
                        $form.Invoke([Action]{
                            [System.Windows.Forms.MessageBox]::Show(
                                'C盘清理已完成！' + [Environment]::NewLine + '请查看日志了解详细清理情况和释放空间。',
                                '清理完成',
                                [System.Windows.Forms.MessageBoxButtons]::OK,
                                [System.Windows.Forms.MessageBoxIcon]::Information
                            )
                        })
                    } else {
                        Write-Log -Text $text -Color $color -Bold $bold
                    }
                }
            }
            $script:LastLogLine = $totalLines
        }
    }

    # 读取进度
    if (Test-Path $progressFile) {
        $pContent = Get-Content $progressFile -Encoding UTF8 -ErrorAction SilentlyContinue
        if ($pContent.Count -gt 0) {
            $lastLine = $pContent[-1]
            $parts = $lastLine -split '\|'
            if ($parts.Count -ge 2) {
                $pct = [int]$parts[0]
                $status = $parts[1]
                $progressBar.Invoke([Action]{ $progressBar.Value = $pct })
                $lblStatus.Invoke([Action]{ $lblStatus.Text = $status })
            }
        }
    }
}

function Stop-Cleanup {
    $script:CancelRequested = $true
    if ($script:Job -and $script:Job.State -eq 'Running') {
        Stop-Job $script:Job -ErrorAction SilentlyContinue
        Remove-Job $script:Job -Force -ErrorAction SilentlyContinue
    }
    $script:timerPoll.Enabled = $false
    Write-Log -Text '⛔ 用户已取消操作' -Color 'Orange' -Bold $true
    Set-Progress 0 '已取消'
    $script:btnStart.Enabled = $true
    $script:btnStart.Text = '开始清理'
    $script:btnCancel.Enabled = $false
}

# ============================================================
# 后台作业脚本（用 ScriptBlock 定义，可复用）
# ============================================================

$script:JobScriptBlock = {
    param($ScriptPath)

    $logFile = Join-Path $env:TEMP "cleanup_gui_log.txt"
    $progressFile = Join-Path $env:TEMP "cleanup_gui_progress.txt"
    $uiStateFile = Join-Path $env:TEMP "cleanup_gui_state.txt"

    function Write-LogBg {
        param($Text, $Color='Black', $Bold=$false)
        "$Text|$Color|$Bold" | Out-File -FilePath $logFile -Encoding UTF8 -Append
    }
    function Set-ProgressBg {
        param($Percent, $Status)
        "$Percent|$Status" | Out-File -FilePath $progressFile -Encoding UTF8
    }

    # 读取勾选状态
    $state = Get-Content $uiStateFile -Raw -ErrorAction SilentlyContinue
    if (-not $state) {
        "ERROR|No state file found|False" | Out-File $logFile -Encoding UTF8 -Append
        return
    }
    $state = $state | ConvertFrom-Json

    # ---- 辅助函数：格式化大小 ----
    function Format-GB {
        param($val)
        return [math]::Round($val, 2).ToString('0.00').PadLeft(7)
    }

    try {
        # ========== 1. 分析目录 ==========
        if ($state.Analyze) {
            Set-ProgressBg 2 '正在分析 C 盘目录...'
            $items = Get-ChildItem 'C:\' -Force -ErrorAction SilentlyContinue
            $total = @($items).Count; $idx = 0; $results = @()
            foreach ($item in $items) {
                $idx++
                $pctDir = [math]::Min([math]::Round($idx / $total * 100, 0), 95)
                Set-ProgressBg $pctDir "分析目录 ($idx/$total): $($item.Name)"
                $sum = 0
                try { $sum = (Get-ChildItem -LiteralPath $item.FullName -Recurse -File -Force -ErrorAction SilentlyContinue 2>$null | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum } catch { $sum = 0 }
                if (-not $sum) { $sum = 0 }
                $results += [PSCustomObject]@{ Path = $item.FullName; SizeGB = [math]::Round($sum / 1GB, 2) }
            }
            $results = $results | Sort-Object SizeGB -Descending | Select-Object -First 12
            Write-LogBg "`n  C:\ 最大的 12 个目录:" 'Cyan' $true
            Write-LogBg ("  " + "目录".PadRight(50) + "大小(GB)") 'Cyan' $false
            foreach ($r in $results) { Write-LogBg ("  " + $r.Path.PadRight(50) + (Format-GB $r.SizeGB)) 'DarkCyan' $false }
            Set-ProgressBg 5 '目录分析完成'
        }

        # ========== 2. 临时文件 ==========
        if ($state.CleanTemp) {
            Set-ProgressBg 7 '正在清理临时文件...'
            $targets = @(
                @{ Name = '用户 Temp';  Path = $env:TEMP }
                @{ Name = 'AppData Temp'; Path = "$env:LOCALAPPDATA\Temp" }
                @{ Name = 'Windows Temp'; Path = "$env:SystemRoot\Temp" }
            )
            foreach ($t in $targets) {
                Write-LogBg "  清理 $($t.Name): $($t.Path)" 'Gray' $false
                if (Test-Path $t.Path) {
                    try {
                        Remove-Item -LiteralPath "$($t.Path)\*" -Recurse -Force -ErrorAction SilentlyContinue
                        Get-ChildItem -LiteralPath $t.Path -Directory -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                        Write-LogBg "  OK $($t.Name) 清理完成" 'Green' $false
                    } catch { Write-LogBg "  FAIL $($t.Name) 出错: $_" 'Red' $false }
                }
            }
            Set-ProgressBg 11 '临时文件 OK'
        }

        # ========== 3. Prefetch ==========
        if ($state.CleanPrefetch) {
            $pPath = "$env:SystemRoot\Prefetch"
            if (Test-Path $pPath) {
                Remove-Item "$pPath\*" -Recurse -Force -ErrorAction SilentlyContinue
                Write-LogBg '  OK Prefetch 已清理（自动重建，安全）' 'Green' $false
            }
            Set-ProgressBg 14 'Prefetch OK'
        }

        # ========== 4. 日志文件 ==========
        if ($state.CleanLogs) {
            $logsTargets = @(
                @{ Name = 'Windows Logs';  Path = "$env:SystemRoot\Logs" }
                @{ Name = 'WER 错误报告';   Path = "$env:ProgramData\Microsoft\Windows\WER" }
            )
            foreach ($t in $logsTargets) {
                if (Test-Path $t.Path) {
                    Remove-Item "$($t.Path)\*" -Recurse -Force -ErrorAction SilentlyContinue
                    Write-LogBg "  OK $($t.Name) 已清理" 'Green' $false
                }
            }
            Set-ProgressBg 17 '日志文件 OK'
        }

        # ========== 5. 缩略图缓存 ==========
        if ($state.CleanThumbnail) {
            $thumbDir = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
            if (Test-Path $thumbDir) {
                Remove-Item "$thumbDir\thumbcache_*.db" -Force -ErrorAction SilentlyContinue
                Write-LogBg '  OK 缩略图缓存已清理' 'Green' $false
            }
            Set-ProgressBg 20 '缩略图缓存 OK'
        }

        # ========== 6. Windows 更新缓存 ==========
        if ($state.CleanUpdate) {
            Write-LogBg '停止 Windows Update 服务...' 'Cyan' $true
            Get-Service -Name wuauserv, bits -ErrorAction SilentlyContinue |
                Where-Object { $_.Status -eq 'Running' } | Stop-Service -Force -ErrorAction SilentlyContinue
            $dlPath = "$env:SystemRoot\SoftwareDistribution\Download"
            if (Test-Path $dlPath) {
                Remove-Item "$dlPath\*" -Recurse -Force -ErrorAction SilentlyContinue
                Write-LogBg '  OK Windows 更新缓存已清理' 'Green' $false
            }
            Get-Service -Name wuauserv, bits -ErrorAction SilentlyContinue |
                Where-Object { $_.Status -eq 'Stopped' } | Start-Service -ErrorAction SilentlyContinue
            Set-ProgressBg 24 '更新缓存 OK'
        }

        # ========== 7. 回收站 ==========
        if ($state.CleanRecycle) {
            cmd.exe /c "rd /s /q C:\$Recycle.Bin 2>nul"
            Write-LogBg '  OK 回收站已清空' 'Green' $false
            Set-ProgressBg 27 '回收站 OK'
        }

        # ========== 8. Chrome 缓存 ==========
        if ($state.CleanChrome) {
            $chromeCache = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache"
            if (Test-Path $chromeCache) {
                Remove-Item "$chromeCache\*" -Recurse -Force -ErrorAction SilentlyContinue
                Write-LogBg '  OK Chrome 缓存已清理' 'Green' $false
            } else { Write-LogBg '  - 未找到 Chrome 缓存' 'Gray' $false }
            Set-ProgressBg 29 'Chrome OK'
        }

        # ========== 9. Edge 缓存 ==========
        if ($state.CleanEdge) {
            $edgeCache = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache"
            if (Test-Path $edgeCache) {
                Remove-Item "$edgeCache\*" -Recurse -Force -ErrorAction SilentlyContinue
                Write-LogBg '  OK Edge 缓存已清理' 'Green' $false
            } else { Write-LogBg '  - 未找到 Edge 缓存' 'Gray' $false }
            Set-ProgressBg 31 'Edge OK'
        }

        # ========== 10. Firefox 缓存 ==========
        if ($state.CleanFirefox) {
            $ffDir = "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles"
            if (Test-Path $ffDir) {
                Get-ChildItem "$ffDir\*\cache2" -ErrorAction SilentlyContinue | ForEach-Object {
                    Remove-Item "$($_.FullName)\*" -Recurse -Force -ErrorAction SilentlyContinue
                    Write-LogBg "  OK Firefox 缓存: $($_.FullName)" 'Green' $false
                }
            } else { Write-LogBg '  - 未找到 Firefox Profiles' 'Gray' $false }
            Set-ProgressBg 33 'Firefox OK'
        }

        # ========== 11. 微信缓存 ==========
        if ($state.CleanWeChat) {
            $wxPath = "$env:USERPROFILE\Documents\WeChat Files"
            if (Test-Path $wxPath) {
                Get-ChildItem $wxPath -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                    $fs = Join-Path $_.FullName "FileStorage"
                    if (Test-Path $fs) {
                        Remove-Item "$fs\*" -Recurse -Force -ErrorAction SilentlyContinue
                        Write-LogBg "  OK 微信缓存: $($_.Name)" 'Green' $false
                    }
                }
            } else { Write-LogBg '  - 未找到微信缓存' 'Gray' $false }
            Set-ProgressBg 37 '微信缓存 OK'
        }

        # ========== 12. VSCode 缓存 ==========
        if ($state.CleanVSCode) {
            $vscCache = "$env:APPDATA\Code\Cache"
            $vscCachedData = "$env:APPDATA\Code\CachedData"
            if (Test-Path $vscCache) { Remove-Item "$vscCache\*" -Recurse -Force -ErrorAction SilentlyContinue; Write-LogBg '  OK VSCode Cache' 'Green' $false }
            if (Test-Path $vscCachedData) { Remove-Item "$vscCachedData\*" -Recurse -Force -ErrorAction SilentlyContinue; Write-LogBg '  OK VSCode CachedData' 'Green' $false }
            Set-ProgressBg 39 'VSCode OK'
        }

        # ========== 13. NVIDIA 缓存 ==========
        if ($state.CleanNVIDIA) {
            $nvTargets = @("$env:ProgramData\NVIDIA Corporation\Downloader", "${env:ProgramFiles}\NVIDIA Corporation\Installer2")
            foreach ($t in $nvTargets) {
                if (Test-Path $t) {
                    Remove-Item "$t\*" -Recurse -Force -ErrorAction SilentlyContinue
                    Write-LogBg "  OK NVIDIA 缓存: $t" 'Green' $false
                }
            }
            Set-ProgressBg 42 'NVIDIA OK'
        }

        # ========== 14. pip 缓存 ==========
        if ($state.CleanPip) {
            $pipCmds = @('python -m pip', 'py -m pip', 'pip')
            $found = $false
            foreach ($cmd in $pipCmds) {
                cmd.exe /c "$cmd --version 2>nul"
                if ($LASTEXITCODE -eq 0) {
                    Write-LogBg "  使用: $cmd" 'Gray' $false
                    cmd.exe /c "$cmd cache purge 2>&1" | ForEach-Object { Write-LogBg "    $_" 'DarkCyan' $false }
                    $found = $true; break
                }
            }
            if (-not $found) { Write-LogBg '  - 未检测到可用 pip' 'Gray' $false }
            Set-ProgressBg 46 'pip 缓存 OK'
        }

        # ========== 15. npm 缓存 ==========
        if ($state.CleanNpm) {
            $npmCache = "$env:APPDATA\npm-cache"
            if (Test-Path $npmCache) {
                $sizeBefore = (Get-ChildItem $npmCache -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
                Remove-Item "$npmCache\*" -Recurse -Force -ErrorAction SilentlyContinue
                Write-LogBg "  OK npm 缓存已清理" 'Green' $false
            } else { Write-LogBg '  - 未找到 npm 缓存' 'Gray' $false }
            Set-ProgressBg 48 'npm OK'
        }

        # ========== 16. conda 缓存 ==========
        if ($state.CleanConda) {
            $condaPath = (Get-Command conda -ErrorAction SilentlyContinue).Source
            if ($condaPath) {
                cmd.exe /c "call `"$condaPath`" clean --all -y 2>nul"
                Write-LogBg '  OK conda 缓存清理完成' 'Green' $false
            } else { Write-LogBg '  - 未检测到 conda' 'Gray' $false }
            Set-ProgressBg 53 'conda OK'
        }

        # ========== 17. __pycache__ ==========
        if ($state.CleanPyCache) {
            $drives = @("C:\")
            $dirsFound = 0
            foreach ($drv in $drives) {
                Get-ChildItem $drv -Directory -Name '__pycache__' -Recurse -ErrorAction SilentlyContinue -Depth 4 | ForEach-Object {
                    $fullPath = Join-Path $drv $_
                    Remove-Item "$fullPath\*" -Recurse -Force -ErrorAction SilentlyContinue
                    $dirsFound++
                }
            }
            Write-LogBg "  OK __pycache__ 已清理 ($dirsFound 个目录)" 'Green' $false
            Set-ProgressBg 55 '__pycache__ OK'
        }

        # ========== 18. Docker 清理 ==========
        if ($state.CleanDocker) {
            $dockerPath = (Get-Command docker -ErrorAction SilentlyContinue).Source
            if ($dockerPath) {
                docker system prune -a -f 2>&1 | ForEach-Object {
                    $line = $_ -replace '[\r\n]', ''
                    if ($line.Trim()) { Write-LogBg "    $line" 'DarkCyan' $false }
                }
                Write-LogBg '  OK Docker 清理完成' 'Green' $false
            } else { Write-LogBg '  - 未检测到 Docker' 'Gray' $false }
            Set-ProgressBg 60 'Docker OK'
        }

        # ========== 19. 关闭休眠 ==========
        if ($state.DisableHibernate) {
            $status = cmd.exe /c "powercfg /h status"
            if ($status -match '(enabled|已启用)') {
                cmd.exe /c "powercfg /h off"
                Write-LogBg '  OK 已关闭休眠，hiberfil.sys 已删除' 'Green' $false
            } else {
                Write-LogBg '  - 休眠已关闭，无需操作' 'Gray' $false
            }
            Set-ProgressBg 65 '休眠 OK'
        }

        # ========== 结果显示 ==========
        Set-ProgressBg 70 '正在查询清理后空间...'
        $diskAfter = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
        $freeAfter = [math]::Round($diskAfter.FreeSpace / 1GB, 2)
        $freeBefore = $state.BeforeFreeGB
        $freedGB = [math]::Round($freeAfter - $freeBefore, 2)
        if ($freedGB -ge 0) {
            Write-LogBg "`n━━━━━ 清理前后对比 ━━━━━" 'Cyan' $true
            Write-LogBg "  清理前剩余: $freeBefore GB" 'Gray' $false
            Write-LogBg "  清理后剩余: $freeAfter GB" 'Gray' $false
            Write-LogBg "  释放空间:   $freedGB GB" 'Lime' $true
            Write-LogBg "━━━━━━━━━━━━━━━━━━━━" 'Cyan' $true
        } else {
            Write-LogBg "`n清理完成！当前 C 盘剩余空间: $freeAfter GB" 'Green' $true
        }
        Set-ProgressBg 95 '清理完成'

    } catch {
        Write-LogBg "发生未预期的错误: $_" 'Red' $true
    } finally {
        Set-ProgressBg 100 '清理完成'
    }

    "DONE|$(Get-Date -Format 'HH:mm:ss')|False" | Out-File $logFile -Encoding UTF8 -Append
}

# ============================================================
# 启动清理（后台作业）
# ============================================================

function Start-Cleanup {
    $script:CancelRequested = $false
    $script:diskBefore = Get-DiskInfo

    $btnStart.Invoke([Action]{ $btnStart.Enabled = $false; $btnStart.Text = '运行中...' })
    $btnCancel.Invoke([Action]{ $btnCancel.Enabled = $true })

    # 重置日志文件
    $logFile = Join-Path $env:TEMP "cleanup_gui_log.txt"
    $progressFile = Join-Path $env:TEMP "cleanup_gui_progress.txt"
    Remove-Item $logFile -Force -ErrorAction SilentlyContinue
    Remove-Item $progressFile -Force -ErrorAction SilentlyContinue

    $script:LastLogLine = 0
    $script:Job = Start-Job -Name 'CleanupJob' -ScriptBlock $script:JobScriptBlock -ArgumentList $PSCommandPath

    # 启动轮询 timer
    $timerPoll.Interval = 300
    $timerPoll.Enabled = $true
}

# ============================================================
# 构建 GUI
# ============================================================

function Build-Form {
    $form = New-Object System.Windows.Forms.Form
    $script:form = $form  # 脚本作用域别名，供 $script:updateLayout 使用
    $form.Text = 'C盘清理工具 - 安全版'
    $form.Size = [System.Drawing.Size]::new(820, 780)
    $form.StartPosition = 'CenterScreen'
    $form.MinimumSize = [System.Drawing.Size]::new(780, 700)
    $form.Font = [System.Drawing.Font]::new('微软雅黑', 9)
    $form.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 245)
    try {
        $form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon('powershell.exe')
    } catch { }

    # 标题栏（固定顶部）
    $pnlTitle = New-Object System.Windows.Forms.Panel
    $pnlTitle.Size = [System.Drawing.Size]::new(820, 50)
    $pnlTitle.BackColor = [System.Drawing.Color]::FromArgb(30, 55, 110)
    $pnlTitle.Dock = 'Top'
    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = 'C盘清理工具 - 安全版'
    $lblTitle.Font = [System.Drawing.Font]::new('微软雅黑', 14, [System.Drawing.FontStyle]::Bold)
    $lblTitle.ForeColor = [System.Drawing.Color]::White
    $lblTitle.Size = [System.Drawing.Size]::new(500, 50)
    $lblTitle.Location = [System.Drawing.Point]::new(15, 8)
    $pnlTitle.Controls.Add($lblTitle)
    $form.Controls.Add($pnlTitle)

    # 所有控件直接放在窗体上，用 $topPad 控制垂直位置
    # 按剩余空间均匀分配上下边距
    $script:topPad = 65

    # 用脚本块而非函数（事件脚本块可访问闭包变量，函数不行）
    # 注意：所有引用的控件变量必须用 $script: 前缀，否则 Resize 事件中找不到
    $script:updateLayout = {
        $formW = $script:form.ClientSize.Width - 40   # 左右各 20 margin
        $cardW = [math]::Max(600, $formW)
        $barW  = $cardW - 40

        # 顶部固定间距，不随窗口高度变化（避免最大化时顶部空白过大）
        $script:topPad = 55

        # 磁盘卡片 + 进度条
        $script:pnlDiskCard.Size = [System.Drawing.Size]::new($cardW, 108)
        $script:pnlDiskCard.Location = [System.Drawing.Point]::new(20, $topPad)
        $script:lblDiskInfo.Size = [System.Drawing.Size]::new($barW + 20, 30)
        $script:pnlDiskBarBg.Size = [System.Drawing.Size]::new($barW, 8)
        $fp = if ($script:diskFreePct) { $script:diskFreePct } else { 50 }
        $diskBarPx = [math]::Max(5, [int]($barW * $fp / 100))
        $script:pnlDiskBar.Size = [System.Drawing.Size]::new($diskBarPx, 8)

        # 选项面板
        $script:grpOptions.Size = [System.Drawing.Size]::new($cardW, 370)
        $script:grpOptions.Location = [System.Drawing.Point]::new(20, $topPad + 115)
        # 内嵌滚动面板大小
        $script:innerPanel.Size = [System.Drawing.Size]::new($cardW - 2, 354)

        # 按钮（动态右对齐）
        $btnW = 140; $btnH = 38
        $script:btnStart.Size = [System.Drawing.Size]::new($btnW, $btnH)
        $script:btnCancel.Size = [System.Drawing.Size]::new(100, $btnH)
        $script:btnSelectAll.Size = [System.Drawing.Size]::new(80, 28)
        $script:btnClearAll.Size = [System.Drawing.Size]::new(90, 28)

        $btnRowY = $topPad + 490
        $script:btnStart.Location = [System.Drawing.Point]::new(20, $btnRowY)
        $script:btnCancel.Location = [System.Drawing.Point]::new(170, $btnRowY)
        $rightEdge = $cardW + 20
        $script:btnSelectAll.Location = [System.Drawing.Point]::new($rightEdge - 180, $topPad + 495)
        $script:btnClearAll.Location = [System.Drawing.Point]::new($rightEdge - 100, $topPad + 495)

        # 状态条 + 进度条
        $script:lblStatus.Size = [System.Drawing.Size]::new($cardW, 22)
        $script:lblStatus.Location = [System.Drawing.Point]::new(20, $topPad + 535)
        $script:progressBar.Size = [System.Drawing.Size]::new($cardW, 20)
        $script:progressBar.Location = [System.Drawing.Point]::new(20, $topPad + 558)

        # 日志框（动态填满剩余高度）
        $logY = $topPad + 582
        $logBottom = $script:form.ClientSize.Height - 10
        $logH = [math]::Max(50, $logBottom - $logY)
        $script:txtLog.Size = [System.Drawing.Size]::new($cardW, $logH)
        $script:txtLog.Location = [System.Drawing.Point]::new(20, $logY)
    }

    # ---- 磁盘信息卡片 ----
    $pnlDiskCard = New-Object System.Windows.Forms.Panel
    $script:pnlDiskCard = $pnlDiskCard
    $pnlDiskCard.Size = [System.Drawing.Size]::new(780, 110)
    $pnlDiskCard.BackColor = [System.Drawing.Color]::White
    $pnlDiskCard.BorderStyle = 'FixedSingle'

    $lblDiskLabel = New-Object System.Windows.Forms.Label
    $lblDiskLabel.Text = 'C 盘空间'
    $lblDiskLabel.Font = [System.Drawing.Font]::new('微软雅黑', 10, [System.Drawing.FontStyle]::Bold)
    $lblDiskLabel.Location = [System.Drawing.Point]::new(12, 8)
    $lblDiskLabel.Size = [System.Drawing.Size]::new(200, 25)
    $pnlDiskCard.Controls.Add($lblDiskLabel)

    $script:lblDiskInfo = New-Object System.Windows.Forms.Label
    $lblDiskInfo.Font = [System.Drawing.Font]::new('微软雅黑', 9, [System.Drawing.FontStyle]::Bold)
    $lblDiskInfo.Location = [System.Drawing.Point]::new(12, 50)
    $lblDiskInfo.Size = [System.Drawing.Size]::new(740, 30)
    $lblDiskInfo.UseCompatibleTextRendering = $true
    $pnlDiskCard.Controls.Add($lblDiskInfo)

    $script:pnlDiskBarBg = New-Object System.Windows.Forms.Panel
    $pnlDiskBarBg.Location = [System.Drawing.Point]::new(12, 88)
    $pnlDiskBarBg.Size = [System.Drawing.Size]::new(740, 8)
    $pnlDiskBarBg.BackColor = [System.Drawing.Color]::FromArgb(220, 220, 220)
    $script:pnlDiskBar = New-Object System.Windows.Forms.Panel
    $pnlDiskBar.Size = [System.Drawing.Size]::new(350, 8)
    $pnlDiskBar.BackColor = [System.Drawing.Color]::FromArgb(68, 187, 68)
    $pnlDiskBarBg.Controls.Add($pnlDiskBar)
    $pnlDiskCard.Controls.Add($pnlDiskBarBg)

    $form.Controls.Add($pnlDiskCard)

    # ---- 勾选区域（带滚动） ----
    $grpOptions = New-Object System.Windows.Forms.Panel
    $script:grpOptions = $grpOptions
    $grpOptions.Size = [System.Drawing.Size]::new(780, 370)
    $grpOptions.BackColor = [System.Drawing.Color]::White
    $grpOptions.BorderStyle = 'FixedSingle'

    # 模拟 GroupBox 标题
    $lblGroupTitle = New-Object System.Windows.Forms.Label
    $lblGroupTitle.Text = ' 清理选项 '
    $lblGroupTitle.Font = [System.Drawing.Font]::new('微软雅黑', 9, [System.Drawing.FontStyle]::Bold)
    $lblGroupTitle.Location = [System.Drawing.Point]::new(10, -2)
    $lblGroupTitle.Size = [System.Drawing.Size]::new(100, 18)
    $lblGroupTitle.BackColor = [System.Drawing.Color]::White
    $grpOptions.Controls.Add($lblGroupTitle)

    # 内嵌滚动面板
    $innerPanel = New-Object System.Windows.Forms.Panel
    $script:innerPanel = $innerPanel
    $innerPanel.Location = [System.Drawing.Point]::new(0, 14)
    $innerPanel.Size = [System.Drawing.Size]::new(778, 354)
    $innerPanel.AutoScroll = $true
    $innerPanel.BackColor = [System.Drawing.Color]::White
    $grpOptions.Controls.Add($innerPanel)
    # 后续复选框都添加到 $innerPanel

    # ---- 辅助：创建标签头 ----
    function Add-SectionHeader($parent, $text, $y) {
        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = $text
        $lbl.Font = [System.Drawing.Font]::new('微软雅黑', 9, [System.Drawing.FontStyle]::Bold)
        $lbl.ForeColor = [System.Drawing.Color]::FromArgb(30, 55, 110)
        $lbl.Location = [System.Drawing.Point]::new(12, $y)
        $lbl.Size = [System.Drawing.Size]::new(740, 22)
        $parent.Controls.Add($lbl)
    }

    # 列参数
    $col1x = 15; $col2x = 395; $cbW = 365; $cbH = 26

    # ═══════ 一、系统清理（安全）═══════
    Add-SectionHeader $innerPanel '▸ 系统清理（安全）' 10

    $script:chkTemp = New-Object System.Windows.Forms.CheckBox
    $chkTemp.Text = '临时文件 (Temp / Windows Temp)'
    $chkTemp.Location = [System.Drawing.Point]::new($col1x, 32); $chkTemp.Size = [System.Drawing.Size]::new($cbW, $cbH)
    $chkTemp.Checked = $true
    $innerPanel.Controls.Add($chkTemp)

    $script:chkPrefetch = New-Object System.Windows.Forms.CheckBox
    $chkPrefetch.Text = 'Prefetch（自动重建，安全）'
    $chkPrefetch.Location = [System.Drawing.Point]::new($col2x, 32); $chkPrefetch.Size = [System.Drawing.Size]::new($cbW, $cbH)
    $chkPrefetch.Checked = $true
    $innerPanel.Controls.Add($chkPrefetch)

    $script:chkUpdate = New-Object System.Windows.Forms.CheckBox
    $chkUpdate.Text = 'Windows 更新缓存（需重启服务）'
    $chkUpdate.Location = [System.Drawing.Point]::new($col1x, 60); $chkUpdate.Size = [System.Drawing.Size]::new($cbW, $cbH)
    $chkUpdate.Checked = $true
    $innerPanel.Controls.Add($chkUpdate)

    $script:chkLogs = New-Object System.Windows.Forms.CheckBox
    $chkLogs.Text = '日志文件 (C:\Windows\Logs + WER)'
    $chkLogs.Location = [System.Drawing.Point]::new($col2x, 60); $chkLogs.Size = [System.Drawing.Size]::new($cbW, $cbH)
    $chkLogs.Checked = $true
    $innerPanel.Controls.Add($chkLogs)

    $script:chkThumbnail = New-Object System.Windows.Forms.CheckBox
    $chkThumbnail.Text = '缩略图缓存 (thumbcache_*.db)'
    $chkThumbnail.Location = [System.Drawing.Point]::new($col1x, 88); $chkThumbnail.Size = [System.Drawing.Size]::new($cbW, $cbH)
    $chkThumbnail.Checked = $true
    $innerPanel.Controls.Add($chkThumbnail)

    $script:chkRecycle = New-Object System.Windows.Forms.CheckBox
    $chkRecycle.Text = '回收站 (C:\$Recycle.Bin)'
    $chkRecycle.Location = [System.Drawing.Point]::new($col2x, 88); $chkRecycle.Size = [System.Drawing.Size]::new($cbW, $cbH)
    $chkRecycle.Checked = $true
    $innerPanel.Controls.Add($chkRecycle)

    # ═══════ 二、浏览器缓存 ═══════
    Add-SectionHeader $innerPanel '▸ 浏览器缓存' 122

    $script:chkChrome = New-Object System.Windows.Forms.CheckBox
    $chkChrome.Text = 'Chrome 浏览器缓存'
    $chkChrome.Location = [System.Drawing.Point]::new($col1x, 146); $chkChrome.Size = [System.Drawing.Size]::new($cbW, $cbH)
    $chkChrome.Checked = $false
    $innerPanel.Controls.Add($chkChrome)

    $script:chkEdge = New-Object System.Windows.Forms.CheckBox
    $chkEdge.Text = 'Edge 浏览器缓存'
    $chkEdge.Location = [System.Drawing.Point]::new($col2x, 146); $chkEdge.Size = [System.Drawing.Size]::new($cbW, $cbH)
    $chkEdge.Checked = $false
    $innerPanel.Controls.Add($chkEdge)

    $script:chkFirefox = New-Object System.Windows.Forms.CheckBox
    $chkFirefox.Text = 'Firefox 浏览器缓存'
    $chkFirefox.Location = [System.Drawing.Point]::new($col1x, 174); $chkFirefox.Size = [System.Drawing.Size]::new($cbW, $cbH)
    $chkFirefox.Checked = $false
    $innerPanel.Controls.Add($chkFirefox)

    # ═══════ 三、应用缓存 ═══════
    Add-SectionHeader $innerPanel '▸ 应用缓存' 208

    $script:chkWeChat = New-Object System.Windows.Forms.CheckBox
    $chkWeChat.Text = '微信缓存（聊天图片/视频，可能超 10GB）'
    $chkWeChat.Location = [System.Drawing.Point]::new($col1x, 232); $chkWeChat.Size = [System.Drawing.Size]::new($cbW, $cbH)
    $chkWeChat.Checked = $false
    $innerPanel.Controls.Add($chkWeChat)

    $script:chkVSCode = New-Object System.Windows.Forms.CheckBox
    $chkVSCode.Text = 'VSCode 缓存'
    $chkVSCode.Location = [System.Drawing.Point]::new($col2x, 232); $chkVSCode.Size = [System.Drawing.Size]::new($cbW, $cbH)
    $chkVSCode.Checked = $false
    $innerPanel.Controls.Add($chkVSCode)

    $script:chkNVIDIA = New-Object System.Windows.Forms.CheckBox
    $chkNVIDIA.Text = 'NVIDIA 缓存 (Downloader + Installer2)'
    $chkNVIDIA.Location = [System.Drawing.Point]::new($col1x, 260); $chkNVIDIA.Size = [System.Drawing.Size]::new($cbW, $cbH)
    $chkNVIDIA.Checked = $false
    $innerPanel.Controls.Add($chkNVIDIA)

    # ═══════ 四、开发缓存 ═══════
    Add-SectionHeader $innerPanel '▸ 开发缓存' 294

    $script:chkPip = New-Object System.Windows.Forms.CheckBox
    $chkPip.Text = 'pip 缓存 (pip cache purge)'
    $chkPip.Location = [System.Drawing.Point]::new($col1x, 318); $chkPip.Size = [System.Drawing.Size]::new($cbW, $cbH)
    $chkPip.Checked = $false
    $innerPanel.Controls.Add($chkPip)

    $script:chkNpm = New-Object System.Windows.Forms.CheckBox
    $chkNpm.Text = 'npm 缓存 (npm cache clean)'
    $chkNpm.Location = [System.Drawing.Point]::new($col2x, 318); $chkNpm.Size = [System.Drawing.Size]::new($cbW, $cbH)
    $chkNpm.Checked = $false
    $innerPanel.Controls.Add($chkNpm)

    $script:chkConda = New-Object System.Windows.Forms.CheckBox
    $chkConda.Text = 'conda 缓存 (conda clean --all)'
    $chkConda.Location = [System.Drawing.Point]::new($col1x, 346); $chkConda.Size = [System.Drawing.Size]::new($cbW, $cbH)
    $chkConda.Checked = $false
    $innerPanel.Controls.Add($chkConda)

    $script:chkPyCache = New-Object System.Windows.Forms.CheckBox
    $chkPyCache.Text = '__pycache__（Python 字节码缓存）'
    $chkPyCache.Location = [System.Drawing.Point]::new($col2x, 346); $chkPyCache.Size = [System.Drawing.Size]::new($cbW, $cbH)
    $chkPyCache.Checked = $false
    $innerPanel.Controls.Add($chkPyCache)

    $script:chkDocker = New-Object System.Windows.Forms.CheckBox
    $chkDocker.Text = 'Docker (docker system prune -a)'
    $chkDocker.Location = [System.Drawing.Point]::new($col1x, 374); $chkDocker.Size = [System.Drawing.Size]::new($cbW, $cbH)
    $chkDocker.Checked = $false
    $innerPanel.Controls.Add($chkDocker)

    # ═══════ 五、其他 ═══════
    Add-SectionHeader $innerPanel '▸ 其他' 408

    $script:chkHibernate = New-Object System.Windows.Forms.CheckBox
    $chkHibernate.Text = '关闭休眠 (删除 hiberfil.sys，释放数 GB)'
    $chkHibernate.Location = [System.Drawing.Point]::new($col1x, 432); $chkHibernate.Size = [System.Drawing.Size]::new($cbW, $cbH)
    $chkHibernate.Checked = $false
    $innerPanel.Controls.Add($chkHibernate)

    $script:chkAnalyze = New-Object System.Windows.Forms.CheckBox
    $chkAnalyze.Text = '分析 C:\ 大目录（速度较慢，显示最大 12 个目录）'
    $chkAnalyze.Location = [System.Drawing.Point]::new($col2x, 432); $chkAnalyze.Size = [System.Drawing.Size]::new($cbW, $cbH)
    $chkAnalyze.Checked = $false
    $innerPanel.Controls.Add($chkAnalyze)

    $form.Controls.Add($grpOptions)

    # ---- 按钮区域 ----
    $script:btnStart = New-Object System.Windows.Forms.Button
    $btnStart.Text = '开始清理'
    $btnStart.Font = [System.Drawing.Font]::new('微软雅黑', 10, [System.Drawing.FontStyle]::Bold)
    $btnStart.Size = [System.Drawing.Size]::new(140, 38)
    $btnStart.BackColor = [System.Drawing.Color]::FromArgb(68, 160, 68)
    $btnStart.ForeColor = [System.Drawing.Color]::White
    $btnStart.FlatStyle = 'Flat'
    $btnStart.FlatAppearance.BorderSize = 0
    $btnStart.Cursor = 'Hand'
    $btnStart.Add_Click({
        $beforeInfo = Get-DiskInfo
        $state = @{
            Analyze       = $chkAnalyze.Checked
            CleanTemp     = $chkTemp.Checked
            CleanPrefetch = $chkPrefetch.Checked
            CleanUpdate   = $chkUpdate.Checked
            CleanLogs     = $chkLogs.Checked
            CleanThumbnail = $chkThumbnail.Checked
            CleanRecycle  = $chkRecycle.Checked
            CleanChrome   = $chkChrome.Checked
            CleanEdge     = $chkEdge.Checked
            CleanFirefox  = $chkFirefox.Checked
            CleanWeChat   = $chkWeChat.Checked
            CleanVSCode   = $chkVSCode.Checked
            CleanNVIDIA   = $chkNVIDIA.Checked
            CleanPip      = $chkPip.Checked
            CleanNpm      = $chkNpm.Checked
            CleanConda    = $chkConda.Checked
            CleanPyCache  = $chkPyCache.Checked
            CleanDocker   = $chkDocker.Checked
            DisableHibernate = $chkHibernate.Checked
            BeforeFreeGB  = $beforeInfo.FreeGB
            BeforeUsedGB  = $beforeInfo.UsedGB
        }
        $state | ConvertTo-Json | Out-File (Join-Path $env:TEMP "cleanup_gui_state.txt") -Encoding UTF8 -Force
        $script:LastLogLine = 0
        $txtLog.Clear()
        Write-Log -Text '开始执行清理...' -Color 'Cyan' -Bold $true
        Start-Cleanup
    })

    $script:btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = '取消'
    $btnCancel.Font = [System.Drawing.Font]::new('微软雅黑', 10)
    $btnCancel.Size = [System.Drawing.Size]::new(100, 38)
    $btnCancel.BackColor = [System.Drawing.Color]::FromArgb(200, 60, 60)
    $btnCancel.ForeColor = [System.Drawing.Color]::White
    $btnCancel.FlatStyle = 'Flat'
    $btnCancel.FlatAppearance.BorderSize = 0
    $btnCancel.Enabled = $false
    $btnCancel.Cursor = 'Hand'
    $btnCancel.Add_Click({ Stop-Cleanup })

    $script:btnSelectAll = New-Object System.Windows.Forms.Button
    $btnSelectAll.Text = '全选'
    $btnSelectAll.Size = [System.Drawing.Size]::new(80, 28)
    $btnSelectAll.Font = [System.Drawing.Font]::new('微软雅黑', 8)
    $btnSelectAll.Cursor = 'Hand'
    $btnSelectAll.Add_Click({
        $chkTemp.Checked = $true; $chkPrefetch.Checked = $true
        $chkUpdate.Checked = $true; $chkLogs.Checked = $true
        $chkThumbnail.Checked = $true; $chkRecycle.Checked = $true
        $chkChrome.Checked = $true; $chkEdge.Checked = $true; $chkFirefox.Checked = $true
        $chkWeChat.Checked = $true; $chkVSCode.Checked = $true; $chkNVIDIA.Checked = $true
        $chkPip.Checked = $true; $chkNpm.Checked = $true; $chkConda.Checked = $true
        $chkPyCache.Checked = $true; $chkDocker.Checked = $true
        $chkHibernate.Checked = $true; $chkAnalyze.Checked = $true
    })

    $script:btnClearAll = New-Object System.Windows.Forms.Button
    $btnClearAll.Text = '取消全选'
    $btnClearAll.Size = [System.Drawing.Size]::new(90, 28)
    $btnClearAll.Font = [System.Drawing.Font]::new('微软雅黑', 8)
    $btnClearAll.Cursor = 'Hand'
    $btnClearAll.Add_Click({
        $chkTemp.Checked = $false; $chkPrefetch.Checked = $false
        $chkUpdate.Checked = $false; $chkLogs.Checked = $false
        $chkThumbnail.Checked = $false; $chkRecycle.Checked = $false
        $chkChrome.Checked = $false; $chkEdge.Checked = $false; $chkFirefox.Checked = $false
        $chkWeChat.Checked = $false; $chkVSCode.Checked = $false; $chkNVIDIA.Checked = $false
        $chkPip.Checked = $false; $chkNpm.Checked = $false; $chkConda.Checked = $false
        $chkPyCache.Checked = $false; $chkDocker.Checked = $false
        $chkHibernate.Checked = $false; $chkAnalyze.Checked = $false
    })

    $form.Controls.Add($btnStart)
    $form.Controls.Add($btnCancel)
    $form.Controls.Add($btnSelectAll)
    $form.Controls.Add($btnClearAll)

    # ---- 状态标签 + 进度条 ----
    $script:lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.Text = '就绪'
    $lblStatus.Size = [System.Drawing.Size]::new(760, 22)
    $lblStatus.Font = [System.Drawing.Font]::new('微软雅黑', 9)
    $form.Controls.Add($lblStatus)

    $script:progressBar = New-Object System.Windows.Forms.ProgressBar
    $progressBar.Size = [System.Drawing.Size]::new(760, 20)
    $progressBar.Style = 'Continuous'
    $progressBar.Value = 0
    $form.Controls.Add($progressBar)

    # ---- 日志框 ----
    $script:txtLog = New-Object System.Windows.Forms.RichTextBox
    $txtLog.Size = [System.Drawing.Size]::new(760, 130)
    $txtLog.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 35)
    $txtLog.ForeColor = [System.Drawing.Color]::FromArgb(200, 200, 200)
    $txtLog.Font = [System.Drawing.Font]::new('Consolas', 9)
    $txtLog.ReadOnly = $true
    $txtLog.BorderStyle = 'FixedSingle'
    $txtLog.WordWrap = $false
    $txtLog.Text = '就绪，请勾选清理项后点击"开始清理"...' + "`r`n"
    $form.Controls.Add($txtLog)

    # ---- 初始化布局 + 绑定 Resize ----
    & $script:updateLayout
    $form.Add_Resize({ & $script:updateLayout })

    # ---- 轮询 Timer ----
    $script:timerPoll = New-Object System.Windows.Forms.Timer
    $script:timerPoll.Add_Tick({ Read-JobOutput })

    # ---- 初始化磁盘信息 ----
    Update-DiskDisplay

    # ---- 关闭时清理 ----
    $form.Add_FormClosed({
        $script:timerPoll.Enabled = $false
        Stop-Cleanup
        $tmpDir = [System.IO.Path]::GetTempPath()
        $tmpFiles = @(
            [System.IO.Path]::Combine($tmpDir, "cleanup_gui_log.txt"),
            [System.IO.Path]::Combine($tmpDir, "cleanup_gui_progress.txt"),
            [System.IO.Path]::Combine($tmpDir, "cleanup_gui_state.txt")
        )
        foreach ($f in $tmpFiles) {
            if (Test-Path $f) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
        }
    })

    return $form
}

# ============================================================
# 入口
# ============================================================

$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Warning '需要管理员权限！'
    $result = [System.Windows.Forms.MessageBox]::Show(
        'C盘清理工具需要管理员权限才能执行。`n是否以管理员身份重新启动？',
        '需要管理员权限',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    if ($result -eq 'Yes') {
        Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    }
    exit
}

[System.Windows.Forms.Application]::EnableVisualStyles()
$form = Build-Form
[System.Windows.Forms.Application]::Run($form)
