#Requires -Version 5.1
<#
.SYNOPSIS
    Uninstalls CLIProxyAPI and removes claude-max/qwen configuration from claude-code-router.

.DESCRIPTION
    This script:
    1. Stops CLIProxyAPI and CCR processes
    2. Removes CLIProxyAPI provider from CCR config
    3. Removes CLIProxyAPI from Program Files (requires admin)
    4. Removes config.yaml and auth files (Claude and Qwen)

.NOTES
    Author: CCRSetup
    Requires: PowerShell 5.1+
#>

param(
    [string]$InstallPath = "C:\Program Files\CLIProxyAPI",
    [switch]$KeepAuth
)

if ($InstallPath -notmatch '^[A-Za-z]:\\') {
    Write-Host "Error: Invalid argument '$InstallPath'" -ForegroundColor Red
    Write-Host "Usage: .\Uninstall-ClaudeMax.ps1 [-KeepAuth]" -ForegroundColor Yellow
    exit 1
}

$ErrorActionPreference = "Stop"

# Helper: Kill orphan processes on a port (requires admin if elevated)
function Stop-OrphanProcesses([int]$Port) {
    $listeners = netstat -ano | Select-String ":$Port.*LISTENING"
    if (-not $listeners) { return }

    $pids = ($listeners | ForEach-Object {
        if ($_ -match "LISTENING\s+(\d+)") { $matches[1] }
    } | Select-Object -Unique) -join ","

    if ($pids) {
        Write-Host "Killing orphan processes on port $Port (PIDs: $pids)..." -ForegroundColor Yellow
        $killScript = "Stop-Process -Id $pids -Force -ErrorAction SilentlyContinue"
        Start-Process -FilePath "powershell.exe" -ArgumentList "-Command", $killScript -Verb RunAs -Wait
        Start-Sleep -Seconds 1
    }
}

Write-Host "=== Uninstall CLIProxyAPI / Claude Max & Qwen ===" -ForegroundColor Cyan
Write-Host ""

# ============================================================================
# 1. Stop processes
# ============================================================================
Write-Host "Stopping processes..." -ForegroundColor Cyan

& ccr stop 2>$null | Out-Null
Get-Process -Name "cli-proxy-api" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Stop-OrphanProcesses -Port 3456

Write-Host "Processes stopped" -ForegroundColor Green
Write-Host ""

# ============================================================================
# 2. Remove CLIProxyAPI from CCR config
# ============================================================================
Write-Host "Removing CLIProxyAPI provider from CCR config..." -ForegroundColor Cyan

$configPath = Join-Path $env:USERPROFILE ".claude-code-router\config.json"

if (Test-Path $configPath) {
    $configText = Get-Content $configPath -Raw -Encoding UTF8

    # Remove CLIProxyAPI provider block
    if ($configText -match '"name":\s*"CLIProxyAPI"') {
        $configText = $configText -replace ',\s*\{\s*"name":\s*"CLIProxyAPI"[^}]*"models":\s*\[[^\]]*\]\s*\}', ''
        Write-Host "Removed CLIProxyAPI provider" -ForegroundColor Green
    } else {
        Write-Host "CLIProxyAPI not found in config" -ForegroundColor Gray
    }

    # Reset Router.think to empty
    $configText = $configText -replace '"think":\s*"CLIProxyAPI,[^"]*"', '"think": ""'

    [System.IO.File]::WriteAllText($configPath, $configText, [System.Text.UTF8Encoding]::new($false))
    Write-Host "Config updated" -ForegroundColor Green
} else {
    Write-Host "CCR config not found" -ForegroundColor Gray
}
Write-Host ""

# ============================================================================
# 3. Remove CLIProxyAPI installation (requires admin)
# ============================================================================
Write-Host "Removing CLIProxyAPI..." -ForegroundColor Cyan

if (Test-Path $InstallPath) {
    Write-Host "Removing $InstallPath (requires admin)..." -ForegroundColor Yellow

    $removeScript = @"
Remove-Item -Path '$InstallPath' -Recurse -Force -ErrorAction SilentlyContinue
Write-Host 'CLIProxyAPI removed' -ForegroundColor Green
"@
    Start-Process -FilePath "powershell.exe" -ArgumentList "-Command", $removeScript -Verb RunAs -Wait
} else {
    Write-Host "CLIProxyAPI not installed" -ForegroundColor Gray
}
Write-Host ""

# ============================================================================
# 4. Remove config.yaml
# ============================================================================
Write-Host "Removing config.yaml..." -ForegroundColor Cyan

$configYamlPath = Join-Path $env:USERPROFILE "config.yaml"
if (Test-Path $configYamlPath) {
    Remove-Item $configYamlPath -Force
    Write-Host "Removed: $configYamlPath" -ForegroundColor Green
} else {
    Write-Host "config.yaml not found" -ForegroundColor Gray
}
Write-Host ""

# ============================================================================
# 5. Remove auth files (unless -KeepAuth)
# ============================================================================
if (-not $KeepAuth) {
    Write-Host "Removing auth files..." -ForegroundColor Cyan

    # Remove Claude auth files
    $claudeAuthFiles = Get-ChildItem -Path $env:USERPROFILE -Filter "claude-*.json" -ErrorAction SilentlyContinue
    if ($claudeAuthFiles) {
        foreach ($file in $claudeAuthFiles) {
            Remove-Item $file.FullName -Force
            Write-Host "Removed: $($file.Name)" -ForegroundColor Green
        }
    } else {
        Write-Host "No Claude auth files found" -ForegroundColor Gray
    }

    # Remove Qwen auth files
    $qwenAuthFiles = Get-ChildItem -Path $env:USERPROFILE -Filter "qwen-*.json" -ErrorAction SilentlyContinue
    if ($qwenAuthFiles) {
        foreach ($file in $qwenAuthFiles) {
            Remove-Item $file.FullName -Force
            Write-Host "Removed: $($file.Name)" -ForegroundColor Green
        }
    } else {
        Write-Host "No Qwen auth files found" -ForegroundColor Gray
    }
} else {
    Write-Host "Keeping auth files (-KeepAuth specified)" -ForegroundColor Yellow
}
Write-Host ""

# ============================================================================
# 6. Restart CCR
# ============================================================================
Write-Host "Restarting CCR..." -ForegroundColor Cyan

& ccr stop 2>&1 | Out-Null
Start-Sleep -Seconds 1
& ccr restart 2>&1 | Out-Null
Start-Sleep -Seconds 1
& ccr start 2>&1 | Out-Null
Start-Sleep -Seconds 2

if ((& ccr status 2>&1) -match "Running") {
    Write-Host "CCR running" -ForegroundColor Green
} else {
    Write-Host "CCR not running (run 'ccr start' manually)" -ForegroundColor Yellow
}

# ============================================================================
# Done
# ============================================================================
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Uninstall Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Removed:" -ForegroundColor Gray
Write-Host "  - CLIProxyAPI from $InstallPath" -ForegroundColor Gray
Write-Host "  - CLIProxyAPI provider from CCR" -ForegroundColor Gray
Write-Host "  - config.yaml" -ForegroundColor Gray
if (-not $KeepAuth) {
    Write-Host "  - Auth files (claude-*.json, qwen-*.json)" -ForegroundColor Gray
}
Write-Host ""
Write-Host "To reinstall: .\Setup-ClaudeMax.ps1" -ForegroundColor Cyan
