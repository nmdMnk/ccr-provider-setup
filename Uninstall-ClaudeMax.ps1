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
.PARAMETER KeepAuth
    Keep authentication files (for reinstall)

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

# Import shared functions
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir "CCRSetup-Functions.ps1")

Write-Host "=== Uninstall CLIProxyAPI / Claude Max & Qwen ===" -ForegroundColor Cyan
Write-Host ""

# ============================================================================
# 1. Stop processes
# ============================================================================
Write-Host "Stopping processes..." -ForegroundColor Cyan

& ccr stop 2>$null | Out-Null
Stop-ProxyService
Stop-OrphanProcesses -Port 3456

Write-Host "Processes stopped" -ForegroundColor Green
Write-Host ""

# ============================================================================
# 2. Remove CLIProxyAPI from CCR config
# ============================================================================
Write-Host "Removing CLIProxyAPI provider from CCR config..." -ForegroundColor Cyan

Remove-CCRProvider
Write-Host ""

# ============================================================================
# 3. Remove CLIProxyAPI installation (requires admin)
# ============================================================================
Write-Host "Removing CLIProxyAPI..." -ForegroundColor Cyan

Uninstall-CLIProxyAPI -InstallPath $InstallPath
Write-Host ""

# ============================================================================
# 4. Remove config.yaml
# ============================================================================
Write-Host "Removing config.yaml..." -ForegroundColor Cyan

Remove-ProxyConfig
Write-Host ""

# ============================================================================
# 5. Remove auth files (unless -KeepAuth)
# ============================================================================
if (-not $KeepAuth) {
    Write-Host "Removing auth files..." -ForegroundColor Cyan
    Remove-AuthFiles
} else {
    Write-Host "Keeping auth files (-KeepAuth specified)" -ForegroundColor Yellow
}
Write-Host ""

# ============================================================================
# 6. Restart CCR
# ============================================================================
Restart-CCR

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
    Write-Host "  - Auth files (claude-*.json, qwen-*.json, codex-*.json, antigravity-*.json)" -ForegroundColor Gray
}
Write-Host ""
Write-Host "To reinstall: .\Setup-ClaudeMax.ps1" -ForegroundColor Cyan
