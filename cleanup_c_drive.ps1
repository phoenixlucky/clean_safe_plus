[CmdletBinding()]
param(
    # Preview only by default. Pass -Apply to delete.
    [switch]$Apply,

    # Remove the current user's AppData\Local\hermes directory.
    [switch]$RemoveHermes,

    # Run Windows Disk Cleanup default safe items.
    [switch]$RunWindowsCleanup,

    # Remove rebuildable artifacts from this project's one-click packaging.
    [switch]$CleanBuildArtifacts
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

$targets = @()

function Add-ContentsTarget {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Label
    )

    if (Test-Path -LiteralPath $Path -PathType Container) {
        $script:targets += [pscustomobject]@{
            Path  = $Path
            Label = $Label
            Mode  = 'Contents'
        }
    }
}

function Add-DirectoryTarget {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Label
    )

    if (Test-Path -LiteralPath $Path -PathType Container) {
        $script:targets += [pscustomobject]@{
            Path  = $Path
            Label = $Label
            Mode  = 'Directory'
        }
    }
}

function Add-AIAppCacheTargets {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Label
    )

    foreach ($relative in @(
        'Cache',
        'Code Cache',
        'GPUCache',
        'DawnCache',
        'CachedData',
        'CachedExtensionVSIXs',
        'Service Worker\CacheStorage',
        'logs'
    )) {
        Add-ContentsTarget -Path (Join-Path $Path $relative) -Label "$Label $relative"
    }
}

function Get-DirectoryBytes {
    param([Parameter(Mandatory)] [string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return [int64]0
    }

    $files = @(Get-ChildItem -LiteralPath $Path -Force -File -Recurse -ErrorAction SilentlyContinue)
    $sum = ($files | Measure-Object -Property Length -Sum).Sum
    if ($null -eq $sum) { return [int64]0 }
    return [int64]$sum
}

function Format-Bytes {
    param([int64]$Bytes)
    return ('{0:N2} GB' -f ($Bytes / 1GB))
}

# Only explicit temp, cache, and log directories are included.
$localTemp = Join-Path $env:LOCALAPPDATA 'Temp'
Add-ContentsTarget -Path $localTemp -Label 'LocalAppData Temp'
Add-ContentsTarget -Path (Join-Path $env:LOCALAPPDATA 'uv\cache') -Label 'uv cache'
Add-ContentsTarget -Path (Join-Path $env:LOCALAPPDATA 'electron\Cache') -Label 'Electron cache'
Add-ContentsTarget -Path (Join-Path $env:LOCALAPPDATA 'electron-builder\Cache') -Label 'Electron Builder cache'
Add-ContentsTarget -Path (Join-Path $env:LOCALAPPDATA 'EvaluationSpiders\Chrome9222\Default\Cache') -Label 'EvaluationSpiders browser cache'
Add-ContentsTarget -Path (Join-Path $env:LOCALAPPDATA 'EvaluationSpiders\Chrome9222\Default\Code Cache') -Label 'EvaluationSpiders code cache'
Add-ContentsTarget -Path (Join-Path $env:LOCALAPPDATA 'Huorong\AppStore\storecache\Cache') -Label 'Huorong AppStore cache'
Add-ContentsTarget -Path (Join-Path $env:LOCALAPPDATA 'mcp-chrome-bridge\logs') -Label 'Chrome MCP logs'
Add-ContentsTarget -Path (Join-Path $env:LOCALAPPDATA 'node-gyp\Cache') -Label 'node-gyp cache'
Add-ContentsTarget -Path (Join-Path $env:APPDATA '@deepseek-ai\dsh-desktop\Cache') -Label 'DeepSeek desktop cache'

foreach ($app in @(
    @{ Path = (Join-Path $env:LOCALAPPDATA 'Claude'); Label = 'Claude' },
    @{ Path = (Join-Path $env:LOCALAPPDATA 'Cursor'); Label = 'Cursor' },
    @{ Path = (Join-Path $env:LOCALAPPDATA 'Windsurf'); Label = 'Windsurf' },
    @{ Path = (Join-Path $env:LOCALAPPDATA 'Trae'); Label = 'Trae' },
    @{ Path = (Join-Path $env:LOCALAPPDATA 'Kiro'); Label = 'Kiro' },
    @{ Path = (Join-Path $env:LOCALAPPDATA 'ChatGPT'); Label = 'ChatGPT' },
    @{ Path = (Join-Path $env:LOCALAPPDATA 'OpenAI\ChatGPT'); Label = 'ChatGPT' },
    @{ Path = (Join-Path $env:LOCALAPPDATA 'LM Studio'); Label = 'LM Studio' },
    @{ Path = (Join-Path $env:APPDATA 'Claude'); Label = 'Claude' },
    @{ Path = (Join-Path $env:APPDATA 'Cursor'); Label = 'Cursor' },
    @{ Path = (Join-Path $env:APPDATA 'Windsurf'); Label = 'Windsurf' },
    @{ Path = (Join-Path $env:APPDATA 'Trae'); Label = 'Trae' },
    @{ Path = (Join-Path $env:APPDATA 'Kiro'); Label = 'Kiro' },
    @{ Path = (Join-Path $env:APPDATA 'ChatGPT'); Label = 'ChatGPT' },
    @{ Path = (Join-Path $env:APPDATA 'OpenAI\ChatGPT'); Label = 'ChatGPT' },
    @{ Path = (Join-Path $env:APPDATA 'LM Studio'); Label = 'LM Studio' }
)) {
    Add-AIAppCacheTargets -Path $app.Path -Label $app.Label
}

$chatgptPackages = Join-Path $env:LOCALAPPDATA 'Packages'
if (Test-Path -LiteralPath $chatgptPackages -PathType Container) {
    foreach ($package in @(Get-ChildItem -LiteralPath $chatgptPackages -Force -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'OpenAI.ChatGPT*' })) {
        Add-ContentsTarget -Path (Join-Path $package.FullName 'LocalCache') -Label 'ChatGPT app local cache'
    }
}

if ($CleanBuildArtifacts) {
    Add-ContentsTarget -Path (Join-Path $PSScriptRoot 'dist') -Label 'Frontend build output (dist)'
    Add-ContentsTarget -Path (Join-Path $PSScriptRoot 'node_modules\.vite') -Label 'Vite build cache'
    Add-ContentsTarget -Path (Join-Path $PSScriptRoot 'src-tauri\gen') -Label 'Tauri generated files'
    Add-ContentsTarget -Path (Join-Path $PSScriptRoot 'src-tauri\target\debug') -Label 'Tauri Debug build output'
    foreach ($relative in @(
        'src-tauri\target\release\build',
        'src-tauri\target\release\deps',
        'src-tauri\target\release\.fingerprint',
        'src-tauri\target\release\incremental',
        'src-tauri\target\release\examples',
        'src-tauri\target\release\bundle'
    )) {
        Add-ContentsTarget -Path (Join-Path $PSScriptRoot $relative) -Label "Tauri packaging intermediate ($relative)"
    }
}

# The state directory name may change; only target playwright-mcp\cache below it.
$reasonixStateRoot = Join-Path $env:APPDATA 'reasonix\mcp-state'
if (Test-Path -LiteralPath $reasonixStateRoot -PathType Container) {
    foreach ($state in @(Get-ChildItem -LiteralPath $reasonixStateRoot -Force -Directory)) {
        Add-ContentsTarget -Path (Join-Path $state.FullName 'playwright-mcp\cache') -Label "Reasonix Playwright cache ($($state.Name))"
    }
}

if ($RemoveHermes) {
    Add-DirectoryTarget -Path (Join-Path $env:LOCALAPPDATA 'hermes') -Label 'Hermes local data (whole directory)'
}

$mode = if ($Apply) { 'APPLY' } else { 'PREVIEW' }
Write-Host "C drive cleanup: $mode" -ForegroundColor Cyan
Write-Host 'Only rebuildable temp files, caches, and logs are included by default.'
if ($RemoveHermes -and -not $Apply) {
    Write-Warning '-RemoveHermes was supplied without -Apply; Hermes will only be shown, not removed.'
}
if ($CleanBuildArtifacts -and -not $Apply) {
    Write-Warning '-CleanBuildArtifacts was supplied without -Apply; build artifacts will only be shown, not removed.'
}
Write-Host ''

$beforeFree = (New-Object System.IO.DriveInfo('C')).AvailableFreeSpace
$estimatedBefore = [int64]0
$failed = 0

foreach ($target in $targets) {
    $before = Get-DirectoryBytes -Path $target.Path
    $estimatedBefore += $before

    if (-not $Apply) {
        Write-Host ('[PREVIEW] {0}: {1}  ({2})' -f $target.Label, (Format-Bytes $before), $target.Path)
        continue
    }

    if ($target.Mode -eq 'Directory') {
        try {
            Remove-Item -LiteralPath $target.Path -Recurse -Force -ErrorAction Stop
        } catch {
            $failed++
        }
    } else {
        foreach ($item in @(Get-ChildItem -LiteralPath $target.Path -Force -ErrorAction SilentlyContinue)) {
            try {
                Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
            } catch {
                $failed++
            }
        }
    }

    $after = Get-DirectoryBytes -Path $target.Path
    $freed = [math]::Max([int64]0, ($before - $after))
    Write-Host ('[DONE] {0}: freed about {1}; remaining {2}' -f $target.Label, (Format-Bytes $freed), (Format-Bytes $after))
}

if ($Apply -and $RunWindowsCleanup) {
    $cleanmgr = Join-Path $env:SystemRoot 'System32\cleanmgr.exe'
    if (Test-Path -LiteralPath $cleanmgr) {
        Write-Host '[RUN] Windows Disk Cleanup default items' -ForegroundColor Yellow
        Start-Process -FilePath $cleanmgr -ArgumentList '/verylowdisk', '/d', 'C:' -Wait -WindowStyle Hidden
    } else {
        Write-Warning 'cleanmgr.exe was not found; Windows cleanup was skipped.'
    }
}

$afterFree = (New-Object System.IO.DriveInfo('C')).AvailableFreeSpace
Write-Host ''
Write-Host ('C free space: {0} -> {1}; actual increase about {2}' -f (Format-Bytes $beforeFree), (Format-Bytes $afterFree), (Format-Bytes ([math]::Max([int64]0, ($afterFree - $beforeFree))))) -ForegroundColor Green
if (-not $Apply) {
    Write-Host ('Estimated cleanup: {0}. To apply:' -f (Format-Bytes $estimatedBefore))
    Write-Host '  powershell -NoProfile -ExecutionPolicy Bypass -File .\cleanup_c_drive.ps1 -Apply'
    Write-Host 'To remove the whole Hermes local data directory, also add: -RemoveHermes'
    Write-Host 'To remove this project''s rebuildable packaging artifacts, also add: -CleanBuildArtifacts'
}
if ($failed -gt 0) {
    Write-Warning ("Skipped {0} items because they were locked or protected. Close related apps and retry." -f $failed)
}
