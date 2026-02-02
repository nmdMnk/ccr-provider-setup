#Requires -Version 5.1
<#
.SYNOPSIS
    Automates CLIProxyAPI installation/updates and configures claude-code-router for Claude Max and Qwen.

.DESCRIPTION
    This script runs as normal user. Only the installation step (writing to Program Files) requires admin elevation.
    1. Downloads/updates CLIProxyAPI from GitHub (admin elevation for install only)
    2. Creates config.yaml for CLIProxyAPI
    3. Handles Claude authentication via browser
    4. Handles Qwen authentication via browser (optional)
    5. Starts the proxy and waits for port 8317
    6. Configures claude-code-router with CLIProxyAPI provider (Claude + Qwen models)
    7. Restarts CCR to apply changes

.PARAMETER SkipQwen
    Skip Qwen authentication and provider setup

.NOTES
    Author: CCRSetup
    Requires: PowerShell 5.1+, claude-code-router installed
#>

param(
    [string]$InstallPath = "C:\Program Files\CLIProxyAPI",
    [int]$ProxyPort = 8317,
    [switch]$SkipQwen,
    [switch]$SkipCodex,  # Skip Codex authentication
    [switch]$SkipAntigravity  # Skip Antigravity authentication
)

$ErrorActionPreference = "Stop"

# Import shared functions
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir "CCRSetup-Functions.ps1")

Write-Host "=== CLIProxyAPI Setup for Claude Max & Qwen ===" -ForegroundColor Cyan
Write-Host ""

# ============================================================================
# 1. Clean up orphan CCR processes
# ============================================================================
Write-Host "Checking for orphan CCR processes..." -ForegroundColor Cyan

& ccr stop 2>$null | Out-Null
Start-Sleep -Milliseconds 500
Stop-OrphanProcesses -Port 3456

Write-Host "CCR cleanup done" -ForegroundColor Green
Write-Host ""

# ============================================================================
# 2. Check Installation
# ============================================================================
Write-Host "Checking CLIProxyAPI..." -ForegroundColor Cyan

$installStatus = Get-CLIProxyInstallStatus -InstallPath $InstallPath

if ($installStatus.Installed) {
    Write-Host "CLIProxyAPI already installed" -ForegroundColor Green
} else {
    Write-Host "CLIProxyAPI not installed" -ForegroundColor Yellow

    # Install
    Write-Host ""
    $result = Install-CLIProxyAPI -InstallPath $InstallPath
    if (-not $result) {
        exit 1
    }
}

# Verify installation
$installStatus = Get-CLIProxyInstallStatus -InstallPath $InstallPath
if (-not $installStatus.Installed) {
    Write-Host "Error: cli-proxy-api.exe not found" -ForegroundColor Red
    exit 1
}

# ============================================================================
# 3. Create/update config.yaml
# ============================================================================
Write-Host ""
Write-Host "Checking config.yaml..." -ForegroundColor Cyan

Set-ProxyConfig -Port $ProxyPort

# ============================================================================
# 4. Claude Authentication
# ============================================================================
Write-Host ""
Write-Host "Checking authentication..." -ForegroundColor Cyan

$authStatus = Get-AuthStatus

if (-not $authStatus.ClaudeConfigured) {
    Start-ClaudeLogin -InstallPath $InstallPath
} else {
    Write-Host "Claude authentication found" -ForegroundColor Green
}

# ============================================================================
# 5. Qwen Authentication (optional)
# ============================================================================
if (-not $SkipQwen) {
    Write-Host ""
    Write-Host "Checking Qwen authentication..." -ForegroundColor Cyan

    $authStatus = Get-AuthStatus

    if (-not $authStatus.QwenConfigured) {
        $result = Start-QwenLogin -InstallPath $InstallPath
        if (-not $result) {
            Write-Host "Skipping Qwen setup." -ForegroundColor Yellow
            $SkipQwen = $true
        }
    } else {
        Write-Host "Qwen authentication found" -ForegroundColor Green
    }
}

# ============================================================================
# 6. Codex Authentication (optional)
# ============================================================================
if (-not $SkipCodex) {
    Write-Host ""
    Write-Host "Checking Codex authentication..." -ForegroundColor Cyan

    $authStatus = Get-AuthStatus

    if (-not $authStatus.CodexConfigured) {
        $result = Start-CodexLogin -InstallPath $InstallPath
        if (-not $result) {
            Write-Host "Skipping Codex setup." -ForegroundColor Yellow
            $SkipCodex = $true
        }
    } else {
        Write-Host "Codex authentication found" -ForegroundColor Green
    }
}

# ============================================================================
# 7. Antigravity Authentication (optional)
# ============================================================================
if (-not $SkipAntigravity) {
    Write-Host ""
    Write-Host "Checking Antigravity authentication..." -ForegroundColor Cyan

    $authStatus = Get-AuthStatus

    if (-not $authStatus.AntigravityConfigured) {
        $result = Start-AntigravityLogin -InstallPath $InstallPath
        if (-not $result) {
            Write-Host "Skipping Antigravity setup." -ForegroundColor Yellow
            $SkipAntigravity = $true
        }
    } else {
        Write-Host "Antigravity authentication found" -ForegroundColor Green
    }
}

# ============================================================================
# 8. Start Proxy
# ============================================================================
Write-Host ""
Write-Host "Starting proxy..." -ForegroundColor Cyan

$result = Start-ProxyService -InstallPath $InstallPath -Port $ProxyPort
if (-not $result) {
    Write-Host "Error: Proxy failed to start" -ForegroundColor Red
    exit 1
}

# ============================================================================
# 9. Configure claude-code-router
# ============================================================================
Write-Host ""
Write-Host "Configuring claude-code-router..." -ForegroundColor Cyan

$providerParams = @{ Port = $ProxyPort }
if (-not $SkipQwen) {
    $authCheck = Get-AuthStatus
    if ($authCheck.QwenConfigured) { $providerParams.IncludeQwen = $true }
}
if (-not $SkipCodex) {
    $authCheck = Get-AuthStatus
    if ($authCheck.CodexConfigured) { $providerParams.IncludeCodex = $true }
}
if (-not $SkipAntigravity) {
    $authCheck = Get-AuthStatus
    if ($authCheck.AntigravityConfigured) { $providerParams.IncludeAntigravity = $true }
}
Add-CCRProvider @providerParams

# ============================================================================
# 10. Restart CCR
# ============================================================================
Write-Host ""
Restart-CCR

# ============================================================================
# Done
# ============================================================================
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Setup Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "To use: ccr code" -ForegroundColor Cyan
Write-Host ""
Write-Host "Note: CLIProxyAPI must remain running." -ForegroundColor Yellow
