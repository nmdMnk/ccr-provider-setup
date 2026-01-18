#Requires -Version 5.1
<#
.SYNOPSIS
    Automates CLIProxyAPI installation/updates and configures claude-code-router for Anthropic Max subscription.

.DESCRIPTION
    This script runs as normal user. Only the installation step (writing to Program Files) requires admin elevation.
    1. Downloads/updates CLIProxyAPI from GitHub (admin elevation for install only)
    2. Creates config.yaml for CLIProxyAPI
    3. Handles Claude authentication via browser (works normally as user)
    4. Starts the proxy and waits for port 8317
    5. Configures claude-code-router with claude-max provider
    6. Restarts CCR to apply changes

.NOTES
    Author: CCRSetup
    Requires: PowerShell 5.1+, claude-code-router installed
#>

param(
    [string]$InstallPath = "C:\Program Files\CLIProxyAPI",
    [int]$ProxyPort = 8317,
    [string]$ThinkModel = "claude-opus-4-20250514"
)

$ErrorActionPreference = "Stop"
$exePath = Join-Path $InstallPath "cli-proxy-api.exe"

# Helper: Test if a port is listening (faster than Test-NetConnection)
function Test-Port([int]$Port) {
    $tcp = New-Object System.Net.Sockets.TcpClient
    try {
        $tcp.Connect("localhost", $Port)
        return $true
    } catch {
        return $false
    } finally {
        $tcp.Dispose()
    }
}

# Helper: Kill orphan processes on a port (requires admin if elevated)
function Stop-OrphanProcesses([int]$Port) {
    $listeners = netstat -ano | Select-String ":$Port.*LISTENING"
    if (-not $listeners) { return }

    $pids = ($listeners | ForEach-Object {
        if ($_ -match "LISTENING\s+(\d+)") { $matches[1] }
    } | Select-Object -Unique) -join ","

    if ($pids) {
        Write-Host "Found orphan processes on port $Port (PIDs: $pids), killing..." -ForegroundColor Yellow
        $killScript = "Stop-Process -Id $pids -Force -ErrorAction SilentlyContinue"
        Start-Process -FilePath "powershell.exe" -ArgumentList "-Command", $killScript -Verb RunAs -Wait
        Start-Sleep -Seconds 1
    }
}

Write-Host "=== CLIProxyAPI Setup for Claude Max ===" -ForegroundColor Cyan
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
# 2. Check Installation and Version
# ============================================================================
Write-Host "Checking CLIProxyAPI..." -ForegroundColor Cyan

$needsInstall = $true
$latestRelease = $null

$headers = @{ "User-Agent" = "CLIProxyAPI-Setup" }
$repoUrls = @(
    "https://api.github.com/repos/anthropics/claude-cli-proxy-api/releases/latest",
    "https://api.github.com/repos/router-for-me/CLIProxyAPI/releases/latest"
)

foreach ($url in $repoUrls) {
    try {
        $latestRelease = Invoke-RestMethod -Uri $url -Headers $headers -ErrorAction Stop
        $latestVersion = $latestRelease.tag_name -replace '^v', ''
        Write-Host "Latest version: $latestVersion" -ForegroundColor Gray
        break
    } catch {
        $latestRelease = $null
    }
}

if (Test-Path $exePath) {
    Write-Host "Found existing installation" -ForegroundColor Gray
    $needsInstall = $false  # Default: don't reinstall if exists

    if ($latestRelease) {
        # Could add version comparison here if needed
        Write-Host "CLIProxyAPI already installed" -ForegroundColor Green
    } else {
        Write-Host "CLIProxyAPI installed (skipping update check)" -ForegroundColor Green
    }
} else {
    Write-Host "CLIProxyAPI not installed" -ForegroundColor Yellow
}

# ============================================================================
# 3. Download and Install (admin elevation only for this step)
# ============================================================================
if ($needsInstall -and $latestRelease) {
    Write-Host ""
    Write-Host "Installing CLIProxyAPI $latestVersion..." -ForegroundColor Cyan

    $asset = $latestRelease.assets | Where-Object {
        $_.name -like "*windows*amd64*.zip" -or $_.name -like "*win*x64*.zip" -or $_.name -like "*windows*.zip"
    } | Select-Object -First 1

    if (-not $asset) {
        Write-Host "Error: Could not find Windows download" -ForegroundColor Red
        exit 1
    }

    $downloadUrl = $asset.browser_download_url
    $zipPath = Join-Path $env:TEMP "CLIProxyAPI-$latestVersion.zip"
    $extractPath = Join-Path $env:TEMP "CLIProxyAPI-extract"

    Write-Host "Downloading $($asset.name)..." -ForegroundColor Gray
    Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -UseBasicParsing

    # Extract to temp first (no admin needed)
    if (Test-Path $extractPath) { Remove-Item $extractPath -Recurse -Force }
    Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

    # Install to Program Files (requires admin - only elevation point)
    Write-Host "Installing to $InstallPath (requires admin)..." -ForegroundColor Yellow

    $installScript = @"
`$ErrorActionPreference = 'Stop'
if (-not (Test-Path '$InstallPath')) { New-Item -Path '$InstallPath' -ItemType Directory -Force | Out-Null }
Get-Process -Name 'cli-proxy-api' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500
Copy-Item -Path '$extractPath\*' -Destination '$InstallPath' -Recurse -Force
Write-Host 'Installation complete' -ForegroundColor Green
"@

    Start-Process -FilePath "powershell.exe" -ArgumentList "-Command", $installScript -Verb RunAs -Wait

    # Cleanup temp files
    Remove-Item $zipPath -ErrorAction SilentlyContinue
    Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue

    if (Test-Path $exePath) {
        Write-Host "CLIProxyAPI installed successfully" -ForegroundColor Green
    } else {
        Write-Host "Error: Installation failed" -ForegroundColor Red
        exit 1
    }
}

if (-not (Test-Path $exePath)) {
    Write-Host "Error: cli-proxy-api.exe not found" -ForegroundColor Red
    exit 1
}

# ============================================================================
# 4. Create/update config.yaml
# ============================================================================
Write-Host ""
Write-Host "Checking config.yaml..." -ForegroundColor Cyan

$configYamlPath = Join-Path $env:USERPROFILE "config.yaml"
if (-not (Test-Path $configYamlPath)) {
    Write-Host "Creating config.yaml..." -ForegroundColor Yellow
    @"
# CLIProxyAPI Configuration
port: $ProxyPort
auth-dir: $env:USERPROFILE
"@ | Set-Content $configYamlPath -Encoding UTF8
    Write-Host "Created: $configYamlPath" -ForegroundColor Green
} else {
    $configContent = Get-Content $configYamlPath -Raw
    if ($configContent -notmatch 'auth-dir:') {
        Write-Host "Adding auth-dir to config.yaml..." -ForegroundColor Yellow
        $configContent = $configContent -replace '(port:\s*\d+)', "`$1`nauth-dir: $env:USERPROFILE"
        $configContent | Set-Content $configYamlPath -Encoding UTF8
    }
    Write-Host "config.yaml OK" -ForegroundColor Green
}

# ============================================================================
# 5. Start Claude Login (if needed) - runs as user, browser works normally
# ============================================================================
Write-Host ""
Write-Host "Checking authentication..." -ForegroundColor Cyan

$authFiles = Get-ChildItem -Path $env:USERPROFILE -Filter "claude-*.json" -ErrorAction SilentlyContinue

if (-not $authFiles -or $authFiles.Count -eq 0) {
    Write-Host "No authentication found. Starting Claude login..." -ForegroundColor Yellow
    Write-Host "Click the link below to authenticate:" -ForegroundColor Yellow
    Write-Host ""

    # Start login (runs as current user - browser opens normally!)
    $loginProc = Start-Process -FilePath $exePath -ArgumentList "--claude-login" -WorkingDirectory $env:USERPROFILE -PassThru

    Write-Host "Waiting for authentication (max 120s)..."
    $timeout = 120
    $elapsed = 0
    while ($elapsed -lt $timeout) {
        $authFiles = Get-ChildItem -Path $env:USERPROFILE -Filter "claude-*.json" -ErrorAction SilentlyContinue
        if ($authFiles -and $authFiles.Count -gt 0) {
            Write-Host ""
            Write-Host "Authentication successful!" -ForegroundColor Green
            Stop-Process -Id $loginProc.Id -Force -ErrorAction SilentlyContinue
            break
        }
        Start-Sleep -Seconds 2
        $elapsed += 2
        Write-Host "." -NoNewline
    }
    Write-Host ""

    if ($elapsed -ge $timeout) {
        Write-Host "Warning: Authentication timeout." -ForegroundColor Yellow
    }
} else {
    Write-Host "Authentication found" -ForegroundColor Green
}

# ============================================================================
# 6. Start Proxy
# ============================================================================
Write-Host ""
Write-Host "Starting proxy..." -ForegroundColor Cyan

if (Test-Port $ProxyPort) {
    Write-Host "Proxy already running on port $ProxyPort" -ForegroundColor Green
} else {
    Get-Process -Name "cli-proxy-api" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500

    Start-Process -FilePath $exePath -WindowStyle Hidden -WorkingDirectory $env:USERPROFILE

    Write-Host "Waiting for proxy..."
    $timeout = 60
    $elapsed = 0
    while ($elapsed -lt $timeout) {
        if (Test-Port $ProxyPort) {
            Write-Host "Proxy active on port $ProxyPort!" -ForegroundColor Green
            break
        }
        Start-Sleep -Seconds 2
        $elapsed += 2
        Write-Host "." -NoNewline
    }
    Write-Host ""

    if ($elapsed -ge $timeout) {
        Write-Host "Error: Proxy failed to start" -ForegroundColor Red
        exit 1
    }
}

# ============================================================================
# 7. Configure claude-code-router
# ============================================================================
Write-Host ""
Write-Host "Configuring claude-code-router..." -ForegroundColor Cyan

$configPath = Join-Path $env:USERPROFILE ".claude-code-router\config.json"

if (-not (Test-Path $configPath)) {
    Write-Host "Error: CCR config not found" -ForegroundColor Red
    exit 1
}

$configText = Get-Content $configPath -Raw -Encoding UTF8

if ($configText -notmatch '"name":\s*"claude-max"') {
    Write-Host "Adding claude-max provider..." -ForegroundColor Yellow

    $providerJson = @"
,
    {
      "name": "claude-max",
      "api_base_url": "http://localhost:$ProxyPort/v1/chat/completions",
      "api_key": "not-required",
      "models": [
        "claude-opus-4-20250514",
        "claude-sonnet-4-20250514"
      ]
    }
"@
    $configText = $configText -replace '(\}\s*)\n(\s*\],\s*\n\s*"StatusLine")', "`$1$providerJson`n`$2"
    Write-Host "Added claude-max provider" -ForegroundColor Green
} else {
    Write-Host "claude-max already configured" -ForegroundColor Green
}

if ($configText -notmatch '"think":\s*"claude-max') {
    $configText = $configText -replace '("think":\s*)"[^"]*"', "`$1`"claude-max,$ThinkModel`""
    Write-Host "Updated Router.think" -ForegroundColor Gray
}

[System.IO.File]::WriteAllText($configPath, $configText, [System.Text.UTF8Encoding]::new($false))
Write-Host "Config saved" -ForegroundColor Green

# ============================================================================
# 8. Restart CCR
# ============================================================================
Write-Host ""
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
    Write-Host "Warning: Run 'ccr start' manually" -ForegroundColor Yellow
}

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
