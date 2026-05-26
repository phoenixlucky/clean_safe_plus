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
            $total = @($items).Count
            $idx = 0
            $results = @()

            foreach ($item in $items) {
                $idx++
                $pctDir = [math]::Min([math]::Round($idx / $total * 100, 0), 95)
                Set-ProgressBg $pctDir "分析目录 ($idx/$total): $($item.Name)"

                $sum = 0
                try {
                    $sum = (Get-ChildItem -LiteralPath $item.FullName -Recurse -File -Force -ErrorAction SilentlyContinue `
                        2>$null | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                } catch {
                    $sum = 0
                }
                if (-not $sum) { $sum = 0 }

                $results += [PSCustomObject]@{
                    Path   = $item.FullName
                    SizeGB = [math]::Round($sum / 1GB, 2)
                }
            }

            $results = $results | Sort-Object SizeGB -Descending | Select-Object -First 12

            Write-LogBg "`n  C:\ 最大的 12 个目录:" 'Cyan' $true
            Write-LogBg ("  " + "目录".PadRight(50) + "大小(GB)") 'Cyan' $false
            foreach ($r in $results) {
                $sizeStr = Format-GB $r.SizeGB
                Write-LogBg ("  " + $r.Path.PadRight(50) + $sizeStr) 'DarkCyan' $false
            }
            Set-ProgressBg 5 '目录分析完成'
        }

        # ========== 2. 安全清理-临时文件 ==========
        if ($state.CleanTemp) {
            Set-ProgressBg 8 '正在清理临时文件...'
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
                        Get-ChildItem -LiteralPath $t.Path -Directory -ErrorAction SilentlyContinue |
                            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                        Write-LogBg "  OK $($t.Name) 清理完成" 'Green' $false
                    } catch {
                        Write-LogBg "  FAIL $($t.Name) 出错: $_" 'Red' $false
                    }
                }
            }
            Set-ProgressBg 20 '临时文件清理 OK'
        }

        # ========== 3. Windows 更新缓存 ==========
        if ($state.CleanUpdate) {
            Write-LogBg '停止 Windows Update 服务...' 'Cyan' $true
            Get-Service -Name wuauserv, bits -ErrorAction SilentlyContinue |
                Where-Object { $_.Status -eq 'Running' } |
                Stop-Service -Force -ErrorAction SilentlyContinue

            $dlPath = "$env:SystemRoot\SoftwareDistribution\Download"
            if (Test-Path $dlPath) {
                Remove-Item "$dlPath\*" -Recurse -Force -ErrorAction SilentlyContinue
                Write-LogBg '  OK Windows 更新缓存已清理' 'Green' $false
            }

            Get-Service -Name wuauserv, bits -ErrorAction SilentlyContinue |
                Where-Object { $_.Status -eq 'Stopped' } |
                Start-Service -ErrorAction SilentlyContinue
            Set-ProgressBg 30 '更新缓存 OK'
        }

        # ========== 4. 回收站 ==========
        if ($state.CleanRecycle) {
            cmd.exe /c "rd /s /q C:\$Recycle.Bin 2>nul"
            Write-LogBg '  OK 回收站已清空' 'Green' $false
            Set-ProgressBg 35 '回收站 OK'
        }

        # ========== 5. 关闭休眠 ==========
        if ($state.DisableHibernate) {
            $status = cmd.exe /c "powercfg /h status"
            if ($status -match 'enabled') {
                cmd.exe /c "powercfg /h off"
                Write-LogBg '  OK 已关闭休眠，hiberfil.sys 已删除' 'Green' $false
            } else {
                Write-LogBg '  - 休眠已关闭，无需操作' 'Gray' $false
            }
            Set-ProgressBg 40 '休眠检查 OK'
        }

        # ========== 6. pip 缓存 ==========
        if ($state.CleanPip) {
            $pipCmds = @('python -m pip', 'py -m pip', 'pip')
            $found = $false
            foreach ($cmd in $pipCmds) {
                $result = cmd.exe /c "$cmd --version 2>nul"
                if ($LASTEXITCODE -eq 0) {
                    Write-LogBg "  使用: $cmd" 'Gray' $false
                    cmd.exe /c "$cmd cache purge 2>&1" | ForEach-Object {
                        Write-LogBg "    $_" 'DarkCyan' $false
                    }
                    $found = $true
                    break
                }
            }
            if (-not $found) {
                Write-LogBg '  - 未检测到可用 pip' 'Gray' $false
            }
            Set-ProgressBg 50 'pip 缓存 OK'
        }

        # ========== 7. conda 缓存 ==========
        if ($state.CleanConda) {
            $condaPath = (Get-Command conda -ErrorAction SilentlyContinue).Source
            if ($condaPath) {
                cmd.exe /c "call `"$condaPath`" clean --all -y 2>nul"
                Write-LogBg '  OK conda 缓存清理完成' 'Green' $false
            } else {
                Write-LogBg '  - 未检测到 conda' 'Gray' $false
            }
            Set-ProgressBg 60 'conda 缓存 OK'
        }

        # ========== 8. Docker 清理 ==========
        if ($state.CleanDocker) {
            $dockerPath = (Get-Command docker -ErrorAction SilentlyContinue).Source
            if ($dockerPath) {
                docker system prune -a -f 2>&1 | ForEach-Object {
                    $line = $_ -replace '[\r\n]', ''
                    if ($line.Trim()) { Write-LogBg "    $line" 'DarkCyan' $false }
                }
                Write-LogBg '  OK Docker 清理完成' 'Green' $false
            } else {
                Write-LogBg '  - 未检测到 Docker' 'Gray' $false
            }
            Set-ProgressBg 75 'Docker 清理 OK'
        }

        # ========== 结果显示 ==========
        Set-ProgressBg 80 '正在查询清理后空间...'
        $diskAfter = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
        $freeAfter = [math]::Round($diskAfter.FreeSpace / 1GB, 2)
        $freeBefore = $state.BeforeFreeGB
        $freedGB = [math]::Round($freeAfter - $freeBefore, 2)
        if ($freedGB -ge 0) {
            Write-LogBg "`n━━━━ 清理前后对比 ━━━━" 'Cyan' $true
            Write-LogBg "  清理前剩余: $freeBefore GB" 'Gray' $false
            Write-LogBg "  清理后剩余: $freeAfter GB" 'Gray' $false
            Write-LogBg "  释放空间:   $freedGB GB" 'Lime' $true
            Write-LogBg "━━━━━━━━━━━━━━━━━━" 'Cyan' $true
        } else {
            Write-LogBg "`n清理完成！当前 C 盘剩余空间: $freeAfter GB" 'Green' $true
        }

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
    $form.Text = 'C盘清理工具 - 安全版'
    $form.Size = [System.Drawing.Size]::new(820, 700)
    $form.StartPosition = 'CenterScreen'
    $form.MinimumSize = [System.Drawing.Size]::new(700, 600)
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
    $script:updateLayout = {
        $availH = $form.ClientSize.Height - 50
        $contentH = 645
        $gap = [math]::Max(5, [int](($availH - $contentH) / 2))
        $script:topPad = 50 + $gap
        $pnlDiskCard.Location = [System.Drawing.Point]::new(20, $topPad)
        $grpOptions.Location = [System.Drawing.Point]::new(20, $topPad + 125)
        $btnStart.Location = [System.Drawing.Point]::new(20, $topPad + 380)
        $btnCancel.Location = [System.Drawing.Point]::new(170, $topPad + 380)
        $btnSelectAll.Location = [System.Drawing.Point]::new(290, $topPad + 385)
        $btnClearAll.Location = [System.Drawing.Point]::new(380, $topPad + 385)
        $lblStatus.Location = [System.Drawing.Point]::new(20, $topPad + 430)
        $progressBar.Location = [System.Drawing.Point]::new(20, $topPad + 455)
        $txtLog.Location = [System.Drawing.Point]::new(20, $topPad + 485)
    }

    # ---- 磁盘信息卡片 ----
    $pnlDiskCard = New-Object System.Windows.Forms.Panel
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

    # ---- 勾选区域 ----
    $grpOptions = New-Object System.Windows.Forms.GroupBox
    $grpOptions.Text = ' 清理选项 '
    $grpOptions.Size = [System.Drawing.Size]::new(780, 260)
    $grpOptions.BackColor = [System.Drawing.Color]::White
    $grpOptions.Font = [System.Drawing.Font]::new('微软雅黑', 9, [System.Drawing.FontStyle]::Bold)

    $script:chkAnalyze = New-Object System.Windows.Forms.CheckBox
    $chkAnalyze.Text = '分析 C:\ 大目录 (速度较慢，显示最大12个目录)'
    $chkAnalyze.Location = [System.Drawing.Point]::new(15, 28)
    $chkAnalyze.Size = [System.Drawing.Size]::new(450, 25)
    $chkAnalyze.Checked = $false

    $script:chkCleanTemp = New-Object System.Windows.Forms.CheckBox
    $chkCleanTemp.Text = '安全清理 - 临时文件 + 更新缓存 + 回收站'
    $chkCleanTemp.Location = [System.Drawing.Point]::new(15, 58)
    $chkCleanTemp.Size = [System.Drawing.Size]::new(450, 25)
    $chkCleanTemp.Checked = $true

    $script:chkHibernate = New-Object System.Windows.Forms.CheckBox
    $chkHibernate.Text = '关闭休眠 (删除 hiberfil.sys，释放数 GB)'
    $chkHibernate.Location = [System.Drawing.Point]::new(15, 88)
    $chkHibernate.Size = [System.Drawing.Size]::new(450, 25)
    $chkHibernate.Checked = $false

    $script:chkPip = New-Object System.Windows.Forms.CheckBox
    $chkPip.Text = '清理 pip 缓存'
    $chkPip.Location = [System.Drawing.Point]::new(15, 118)
    $chkPip.Size = [System.Drawing.Size]::new(450, 25)
    $chkPip.Checked = $false

    $script:chkConda = New-Object System.Windows.Forms.CheckBox
    $chkConda.Text = '清理 conda 缓存 (包缓存/索引/临时文件)'
    $chkConda.Location = [System.Drawing.Point]::new(15, 148)
    $chkConda.Size = [System.Drawing.Size]::new(450, 25)
    $chkConda.Checked = $false

    $script:chkDocker = New-Object System.Windows.Forms.CheckBox
    $chkDocker.Text = '清理 Docker (docker system prune -a -f)'
    $chkDocker.Location = [System.Drawing.Point]::new(15, 178)
    $chkDocker.Size = [System.Drawing.Size]::new(450, 25)
    $chkDocker.Checked = $false

    $lblNote = New-Object System.Windows.Forms.Label
    $lblNote.Text = '说明：勾选"安全清理"会清理临时文件、Windows 更新缓存和回收站，不会删除个人文档。'
    $lblNote.Font = [System.Drawing.Font]::new('微软雅黑', 8)
    $lblNote.ForeColor = [System.Drawing.Color]::Gray
    $lblNote.Location = [System.Drawing.Point]::new(15, 210)
    $lblNote.Size = [System.Drawing.Size]::new(700, 20)

    $lblNote2 = New-Object System.Windows.Forms.Label
    $lblNote2.Text = '其他选项按需勾选。'
    $lblNote2.Font = [System.Drawing.Font]::new('微软雅黑', 8)
    $lblNote2.ForeColor = [System.Drawing.Color]::Gray
    $lblNote2.Location = [System.Drawing.Point]::new(15, 230)
    $lblNote2.Size = [System.Drawing.Size]::new(700, 20)

    $grpOptions.Controls.Add($chkAnalyze)
    $grpOptions.Controls.Add($chkCleanTemp)
    $grpOptions.Controls.Add($chkHibernate)
    $grpOptions.Controls.Add($chkPip)
    $grpOptions.Controls.Add($chkConda)
    $grpOptions.Controls.Add($chkDocker)
    $grpOptions.Controls.Add($lblNote)
    $grpOptions.Controls.Add($lblNote2)
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
            CleanTemp     = $chkCleanTemp.Checked
            CleanUpdate   = $chkCleanTemp.Checked
            CleanRecycle  = $chkCleanTemp.Checked
            DisableHibernate = $chkHibernate.Checked
            CleanPip      = $chkPip.Checked
            CleanConda    = $chkConda.Checked
            CleanDocker   = $chkDocker.Checked
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

    $btnSelectAll = New-Object System.Windows.Forms.Button
    $btnSelectAll.Text = '全选'
    $btnSelectAll.Size = [System.Drawing.Size]::new(80, 28)
    $btnSelectAll.Font = [System.Drawing.Font]::new('微软雅黑', 8)
    $btnSelectAll.Cursor = 'Hand'
    $btnSelectAll.Add_Click({
        $chkAnalyze.Checked = $true; $chkCleanTemp.Checked = $true
        $chkHibernate.Checked = $true; $chkPip.Checked = $true
        $chkConda.Checked = $true; $chkDocker.Checked = $true
    })

    $btnClearAll = New-Object System.Windows.Forms.Button
    $btnClearAll.Text = '取消全选'
    $btnClearAll.Size = [System.Drawing.Size]::new(90, 28)
    $btnClearAll.Font = [System.Drawing.Font]::new('微软雅黑', 8)
    $btnClearAll.Cursor = 'Hand'
    $btnClearAll.Add_Click({
        $chkAnalyze.Checked = $false; $chkCleanTemp.Checked = $false
        $chkHibernate.Checked = $false; $chkPip.Checked = $false
        $chkConda.Checked = $false; $chkDocker.Checked = $false
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
