#Requires -Version 5.1
<#
.SYNOPSIS
    Shared functions for CCRSetup scripts.

.DESCRIPTION
    Contains helper functions used by Setup-ClaudeMax.ps1, Uninstall-ClaudeMax.ps1, and Menu-CCRSetup.ps1

.NOTES
    Author: CCRSetup
#>

# ============================================================================
# Configuration Constants
# ============================================================================
$script:DefaultInstallPath = "C:\Program Files\CLIProxyAPI"
$script:DefaultProxyPort = 8317
$script:CCRPort = 3456
$script:ExeName = "cli-proxy-api.exe"

# ============================================================================
# Port and Process Helpers
# ============================================================================

function Test-Port {
    <#
    .SYNOPSIS
        Test if a port is listening on localhost.
    #>
    param([int]$Port)

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

function Stop-OrphanProcesses {
    <#
    .SYNOPSIS
        Kill orphan processes listening on a specific port.
    #>
    param([int]$Port)

    $listeners = netstat -ano | Select-String ":$Port.*LISTENING"
    if (-not $listeners) { return $false }

    $pids = ($listeners | ForEach-Object {
        if ($_ -match "LISTENING\s+(\d+)") { $matches[1] }
    } | Select-Object -Unique) -join ","

    if ($pids) {
        Write-Host "Found orphan processes on port $Port (PIDs: $pids), killing..." -ForegroundColor Yellow
        $killScript = "Stop-Process -Id $pids -Force -ErrorAction SilentlyContinue"
        Start-Process -FilePath "powershell.exe" -ArgumentList "-Command", $killScript -Verb RunAs -Wait
        Start-Sleep -Seconds 1
        return $true
    }
    return $false
}

# ============================================================================
# Status Functions
# ============================================================================

function Get-CLIProxyInstallStatus {
    <#
    .SYNOPSIS
        Get CLIProxyAPI installation status.
    .OUTPUTS
        Hashtable with Installed (bool), Path (string), Version (string or $null)
    #>
    param([string]$InstallPath = $script:DefaultInstallPath)

    $exePath = Join-Path $InstallPath $script:ExeName
    $result = @{
        Installed = $false
        Path = $InstallPath
        ExePath = $exePath
        Version = $null
    }

    if (Test-Path $exePath) {
        $result.Installed = $true
        # Try to get version info
        try {
            $versionInfo = (Get-Item $exePath).VersionInfo
            if ($versionInfo.FileVersion) {
                $result.Version = $versionInfo.FileVersion
            }
        } catch {}
    }

    return $result
}

function Get-ProxyRunningStatus {
    <#
    .SYNOPSIS
        Check if CLIProxyAPI proxy is running.
    .OUTPUTS
        Hashtable with Running (bool), Port (int), Process (object or $null)
    #>
    param([int]$Port = $script:DefaultProxyPort)

    $result = @{
        Running = $false
        Port = $Port
        Process = $null
    }

    $result.Running = Test-Port -Port $Port
    $result.Process = Get-Process -Name "cli-proxy-api" -ErrorAction SilentlyContinue

    return $result
}

function Get-AuthStatus {
    <#
    .SYNOPSIS
        Check authentication file status.
    .OUTPUTS
        Hashtable with Configured (bool) and Files (array) for Claude, Qwen, Codex, Antigravity
    #>
    $claudeFiles = Get-ChildItem -Path $env:USERPROFILE -Filter "claude-*.json" -ErrorAction SilentlyContinue
    $qwenFiles = Get-ChildItem -Path $env:USERPROFILE -Filter "qwen-*.json" -ErrorAction SilentlyContinue
    $codexFiles = Get-ChildItem -Path $env:USERPROFILE -Filter "codex-*.json" -ErrorAction SilentlyContinue
    $antigravityFiles = Get-ChildItem -Path $env:USERPROFILE -Filter "antigravity-*.json" -ErrorAction SilentlyContinue

    return @{
        ClaudeConfigured = ($claudeFiles -and $claudeFiles.Count -gt 0)
        QwenConfigured = ($qwenFiles -and $qwenFiles.Count -gt 0)
        CodexConfigured = ($codexFiles -and $codexFiles.Count -gt 0)
        AntigravityConfigured = ($antigravityFiles -and $antigravityFiles.Count -gt 0)
        ClaudeFiles = $claudeFiles
        QwenFiles = $qwenFiles
        CodexFiles = $codexFiles
        AntigravityFiles = $antigravityFiles
    }
}

function Get-CCRStatus {
    <#
    .SYNOPSIS
        Check CCR (claude-code-router) status.
    .OUTPUTS
        Hashtable with Running (bool), ProviderConfigured (bool), ConfigPath (string), ConfigExists (bool)
    #>
    $configPath = Join-Path $env:USERPROFILE ".claude-code-router\config.json"

    $result = @{
        Running = $false
        ProviderConfigured = $false
        ConfigPath = $configPath
        ConfigExists = (Test-Path $configPath)
    }

    # Check if CCR is running
    try {
        $status = & ccr status 2>&1
        $result.Running = $status -match "Running"
    } catch {
        $result.Running = $false
    }

    # Check if CLIProxyAPI provider is configured
    if ($result.ConfigExists) {
        $configText = Get-Content $configPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        if ($configText) {
            $result.ProviderConfigured = $configText -match '"name":\s*"CLIProxyAPI"'
        }
    }

    return $result
}

function Get-ConfigYamlStatus {
    <#
    .SYNOPSIS
        Check if config.yaml exists for CLIProxyAPI.
    .OUTPUTS
        Hashtable with Exists (bool), Path (string)
    #>
    $configPath = Join-Path $env:USERPROFILE "config.yaml"

    return @{
        Exists = (Test-Path $configPath)
        Path = $configPath
    }
}

# ============================================================================
# GitHub Functions
# ============================================================================

function Get-LatestRelease {
    <#
    .SYNOPSIS
        Get latest release info from GitHub.
    .OUTPUTS
        Latest release object or $null
    #>
    $headers = @{ "User-Agent" = "CLIProxyAPI-Setup" }
    $repoUrls = @(
        "https://api.github.com/repos/anthropics/claude-cli-proxy-api/releases/latest",
        "https://api.github.com/repos/router-for-me/CLIProxyAPI/releases/latest"
    )

    foreach ($url in $repoUrls) {
        try {
            $release = Invoke-RestMethod -Uri $url -Headers $headers -ErrorAction Stop
            return $release
        } catch {
            continue
        }
    }

    return $null
}

# ============================================================================
# Installation Functions
# ============================================================================

function Install-CLIProxyAPI {
    <#
    .SYNOPSIS
        Download and install CLIProxyAPI from GitHub.
    .PARAMETER InstallPath
        Installation directory (default: C:\Program Files\CLIProxyAPI)
    .OUTPUTS
        $true if successful, $false otherwise
    #>
    param([string]$InstallPath = $script:DefaultInstallPath)

    Write-Host "Checking for latest release..." -ForegroundColor Cyan
    $latestRelease = Get-LatestRelease

    if (-not $latestRelease) {
        Write-Host "Error: Could not fetch release info from GitHub" -ForegroundColor Red
        return $false
    }

    $latestVersion = $latestRelease.tag_name -replace '^v', ''
    Write-Host "Latest version: $latestVersion" -ForegroundColor Gray

    $asset = $latestRelease.assets | Where-Object {
        $_.name -like "*windows*amd64*.zip" -or $_.name -like "*win*x64*.zip" -or $_.name -like "*windows*.zip"
    } | Select-Object -First 1

    if (-not $asset) {
        Write-Host "Error: Could not find Windows download" -ForegroundColor Red
        return $false
    }

    $downloadUrl = $asset.browser_download_url
    $zipPath = Join-Path $env:TEMP "CLIProxyAPI-$latestVersion.zip"
    $extractPath = Join-Path $env:TEMP "CLIProxyAPI-extract"

    Write-Host "Downloading $($asset.name)..." -ForegroundColor Gray
    try {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -UseBasicParsing
    } catch {
        Write-Host "Error: Download failed - $_" -ForegroundColor Red
        return $false
    }

    # Extract to temp first (no admin needed)
    if (Test-Path $extractPath) { Remove-Item $extractPath -Recurse -Force }
    Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

    # Install to Program Files (requires admin)
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

    $exePath = Join-Path $InstallPath $script:ExeName
    if (Test-Path $exePath) {
        Write-Host "CLIProxyAPI installed successfully" -ForegroundColor Green
        return $true
    } else {
        Write-Host "Error: Installation failed" -ForegroundColor Red
        return $false
    }
}

function Uninstall-CLIProxyAPI {
    <#
    .SYNOPSIS
        Remove CLIProxyAPI installation.
    .PARAMETER InstallPath
        Installation directory to remove
    .OUTPUTS
        $true if successful, $false otherwise
    #>
    param([string]$InstallPath = $script:DefaultInstallPath)

    if (-not (Test-Path $InstallPath)) {
        Write-Host "CLIProxyAPI not installed" -ForegroundColor Gray
        return $true
    }

    # Stop process first
    Get-Process -Name "cli-proxy-api" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500

    Write-Host "Removing $InstallPath (requires admin)..." -ForegroundColor Yellow

    $removeScript = @"
Remove-Item -Path '$InstallPath' -Recurse -Force -ErrorAction SilentlyContinue
Write-Host 'CLIProxyAPI removed' -ForegroundColor Green
"@
    Start-Process -FilePath "powershell.exe" -ArgumentList "-Command", $removeScript -Verb RunAs -Wait

    return (-not (Test-Path $InstallPath))
}

# ============================================================================
# Config Functions
# ============================================================================

function Set-ProxyConfig {
    <#
    .SYNOPSIS
        Create or update config.yaml for CLIProxyAPI.
    .PARAMETER Port
        Proxy port (default: 8317)
    #>
    param([int]$Port = $script:DefaultProxyPort)

    $configYamlPath = Join-Path $env:USERPROFILE "config.yaml"

    if (-not (Test-Path $configYamlPath)) {
        Write-Host "Creating config.yaml..." -ForegroundColor Yellow
        @"
# CLIProxyAPI Configuration
port: $Port
auth-dir: $env:USERPROFILE
"@ | Set-Content $configYamlPath -Encoding UTF8
        Write-Host "Created: $configYamlPath" -ForegroundColor Green
    } else {
        $configContent = Get-Content $configYamlPath -Raw
        $modified = $false

        if ($configContent -notmatch 'auth-dir:') {
            Write-Host "Adding auth-dir to config.yaml..." -ForegroundColor Yellow
            $configContent = $configContent -replace '(port:\s*\d+)', "`$1`nauth-dir: $env:USERPROFILE"
            $modified = $true
        }

        if ($modified) {
            $configContent | Set-Content $configYamlPath -Encoding UTF8
        }
        Write-Host "config.yaml OK" -ForegroundColor Green
    }
}

function Remove-ProxyConfig {
    <#
    .SYNOPSIS
        Remove config.yaml file.
    #>
    $configYamlPath = Join-Path $env:USERPROFILE "config.yaml"

    if (Test-Path $configYamlPath) {
        Remove-Item $configYamlPath -Force
        Write-Host "Removed: $configYamlPath" -ForegroundColor Green
        return $true
    } else {
        Write-Host "config.yaml not found" -ForegroundColor Gray
        return $false
    }
}

# ============================================================================
# Authentication Functions
# ============================================================================

function Start-ClaudeLogin {
    <#
    .SYNOPSIS
        Start Claude authentication process.
    .PARAMETER InstallPath
        CLIProxyAPI installation path
    .PARAMETER TimeoutSeconds
        Timeout for authentication (default: 120)
    .OUTPUTS
        $true if authentication successful
    #>
    param(
        [string]$InstallPath = $script:DefaultInstallPath,
        [int]$TimeoutSeconds = 120
    )

    $exePath = Join-Path $InstallPath $script:ExeName

    if (-not (Test-Path $exePath)) {
        Write-Host "Error: CLIProxyAPI not installed" -ForegroundColor Red
        return $false
    }

    Write-Host "Starting Claude login..." -ForegroundColor Yellow
    Write-Host "Click the link below to authenticate:" -ForegroundColor Yellow
    Write-Host ""

    $loginProc = Start-Process -FilePath $exePath -ArgumentList "--claude-login" -WorkingDirectory $env:USERPROFILE -PassThru

    Write-Host "Waiting for authentication (max ${TimeoutSeconds}s)..."
    $elapsed = 0
    while ($elapsed -lt $TimeoutSeconds) {
        $authFiles = Get-ChildItem -Path $env:USERPROFILE -Filter "claude-*.json" -ErrorAction SilentlyContinue
        if ($authFiles -and $authFiles.Count -gt 0) {
            Write-Host ""
            Write-Host "Authentication successful!" -ForegroundColor Green
            Stop-Process -Id $loginProc.Id -Force -ErrorAction SilentlyContinue
            return $true
        }
        Start-Sleep -Seconds 2
        $elapsed += 2
        Write-Host "." -NoNewline
    }
    Write-Host ""

    Stop-Process -Id $loginProc.Id -Force -ErrorAction SilentlyContinue
    Write-Host "Warning: Authentication timeout." -ForegroundColor Yellow
    return $false
}

function Start-QwenLogin {
    <#
    .SYNOPSIS
        Start Qwen authentication process.
    .PARAMETER InstallPath
        CLIProxyAPI installation path
    .PARAMETER TimeoutSeconds
        Timeout for authentication (default: 120)
    .OUTPUTS
        $true if authentication successful
    #>
    param(
        [string]$InstallPath = $script:DefaultInstallPath,
        [int]$TimeoutSeconds = 120
    )

    $exePath = Join-Path $InstallPath $script:ExeName

    if (-not (Test-Path $exePath)) {
        Write-Host "Error: CLIProxyAPI not installed" -ForegroundColor Red
        return $false
    }

    Write-Host "Starting Qwen login..." -ForegroundColor Yellow
    Write-Host "Click the link below to authenticate:" -ForegroundColor Yellow
    Write-Host ""

    $loginProc = Start-Process -FilePath $exePath -ArgumentList "--qwen-login" -WorkingDirectory $env:USERPROFILE -PassThru

    Write-Host "Waiting for Qwen authentication (max ${TimeoutSeconds}s)..."
    $elapsed = 0
    while ($elapsed -lt $TimeoutSeconds) {
        $qwenAuthFiles = Get-ChildItem -Path $env:USERPROFILE -Filter "qwen-*.json" -ErrorAction SilentlyContinue
        if ($qwenAuthFiles -and $qwenAuthFiles.Count -gt 0) {
            Write-Host ""
            Write-Host "Qwen authentication successful!" -ForegroundColor Green
            Stop-Process -Id $loginProc.Id -Force -ErrorAction SilentlyContinue
            return $true
        }
        Start-Sleep -Seconds 2
        $elapsed += 2
        Write-Host "." -NoNewline
    }
    Write-Host ""

    Stop-Process -Id $loginProc.Id -Force -ErrorAction SilentlyContinue
    Write-Host "Warning: Qwen authentication timeout." -ForegroundColor Yellow
    return $false
}

function Start-CodexLogin {
    <#
    .SYNOPSIS
        Start Codex authentication process.
    .PARAMETER InstallPath
        CLIProxyAPI installation path
    .OUTPUTS
        $true if authentication successful
    #>
    param(
        [string]$InstallPath = $script:DefaultInstallPath
    )

    $exePath = Join-Path $InstallPath $script:ExeName

    if (-not (Test-Path $exePath)) {
        Write-Host "Error: CLIProxyAPI not installed" -ForegroundColor Red
        return $false
    }

    Write-Host "Starting Codex login..." -ForegroundColor Yellow
    Write-Host "A browser will open. Complete login there." -ForegroundColor Yellow
    Write-Host ""

    Start-Process -FilePath $exePath -ArgumentList "--codex-login" -WorkingDirectory $env:USERPROFILE -Wait

    $codexAuthFiles = Get-ChildItem -Path $env:USERPROFILE -Filter "codex-*.json" -ErrorAction SilentlyContinue
    if ($codexAuthFiles -and $codexAuthFiles.Count -gt 0) {
        Write-Host "Codex authentication successful!" -ForegroundColor Green
        return $true
    } else {
        Write-Host "Warning: Codex authentication may have failed." -ForegroundColor Yellow
        return $false
    }
}

function Start-AntigravityLogin {
    <#
    .SYNOPSIS
        Start Antigravity authentication process.
    .PARAMETER InstallPath
        CLIProxyAPI installation path
    .OUTPUTS
        $true if authentication successful
    #>
    param(
        [string]$InstallPath = $script:DefaultInstallPath
    )

    $exePath = Join-Path $InstallPath $script:ExeName

    if (-not (Test-Path $exePath)) {
        Write-Host "Error: CLIProxyAPI not installed" -ForegroundColor Red
        return $false
    }

    Write-Host "Starting Antigravity login..." -ForegroundColor Yellow
    Write-Host "A browser will open. Complete login there." -ForegroundColor Yellow
    Write-Host ""

    Start-Process -FilePath $exePath -ArgumentList "--antigravity-login" -WorkingDirectory $env:USERPROFILE -Wait

    $antigravityAuthFiles = Get-ChildItem -Path $env:USERPROFILE -Filter "antigravity-*.json" -ErrorAction SilentlyContinue
    if ($antigravityAuthFiles -and $antigravityAuthFiles.Count -gt 0) {
        Write-Host "Antigravity authentication successful!" -ForegroundColor Green
        return $true
    } else {
        Write-Host "Warning: Antigravity authentication may have failed." -ForegroundColor Yellow
        return $false
    }
}

function Remove-AuthFiles {
    <#
    .SYNOPSIS
        Remove authentication files.
    .PARAMETER Only
        Remove only files for a specific provider (Claude, Qwen, Codex, Antigravity).
        If not specified, removes all.
    #>
    param(
        [ValidateSet("Claude", "Qwen", "Codex", "Antigravity")]
        [string]$Only
    )

    $providers = @(
        @{ Name = "Claude"; Filter = "claude-*.json" },
        @{ Name = "Qwen";   Filter = "qwen-*.json" },
        @{ Name = "Codex";  Filter = "codex-*.json" },
        @{ Name = "Antigravity"; Filter = "antigravity-*.json" }
    )

    $removedAny = $false
    foreach ($p in $providers) {
        if ($Only -and $Only -ne $p.Name) { continue }
        $files = Get-ChildItem -Path $env:USERPROFILE -Filter $p.Filter -ErrorAction SilentlyContinue
        if ($files) {
            foreach ($file in $files) {
                Remove-Item $file.FullName -Force
                Write-Host "Removed: $($file.Name)" -ForegroundColor Green
                $removedAny = $true
            }
        } else {
            Write-Host "No $($p.Name) auth files found" -ForegroundColor Gray
        }
    }

    return $removedAny
}

# ============================================================================
# Proxy Service Functions
# ============================================================================

function Start-ProxyService {
    <#
    .SYNOPSIS
        Start CLIProxyAPI proxy service.
    .PARAMETER InstallPath
        CLIProxyAPI installation path
    .PARAMETER Port
        Proxy port (default: 8317)
    .PARAMETER TimeoutSeconds
        Timeout waiting for port (default: 60)
    .OUTPUTS
        $true if proxy started successfully
    #>
    param(
        [string]$InstallPath = $script:DefaultInstallPath,
        [int]$Port = $script:DefaultProxyPort,
        [int]$TimeoutSeconds = 60
    )

    $exePath = Join-Path $InstallPath $script:ExeName

    if (-not (Test-Path $exePath)) {
        Write-Host "Error: CLIProxyAPI not installed" -ForegroundColor Red
        return $false
    }

    if (Test-Port -Port $Port) {
        Write-Host "Proxy already running on port $Port" -ForegroundColor Green
        return $true
    }

    # Stop any existing processes
    Get-Process -Name "cli-proxy-api" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500

    Write-Host "Starting proxy..." -ForegroundColor Cyan
    Start-Process -FilePath $exePath -WindowStyle Hidden -WorkingDirectory $env:USERPROFILE

    Write-Host "Waiting for proxy..."
    $elapsed = 0
    while ($elapsed -lt $TimeoutSeconds) {
        if (Test-Port -Port $Port) {
            Write-Host "Proxy active on port $Port!" -ForegroundColor Green
            return $true
        }
        Start-Sleep -Seconds 2
        $elapsed += 2
        Write-Host "." -NoNewline
    }
    Write-Host ""

    Write-Host "Error: Proxy failed to start" -ForegroundColor Red
    return $false
}

function Stop-ProxyService {
    <#
    .SYNOPSIS
        Stop CLIProxyAPI proxy service.
    #>
    $procs = Get-Process -Name "cli-proxy-api" -ErrorAction SilentlyContinue
    if ($procs) {
        $procs | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
        Write-Host "Proxy stopped" -ForegroundColor Green
        return $true
    } else {
        Write-Host "Proxy not running" -ForegroundColor Gray
        return $false
    }
}

# ============================================================================
# CCR Configuration Functions
# ============================================================================

function Add-CCRProvider {
    <#
    .SYNOPSIS
        Add or update CLIProxyAPI provider in CCR config.
    .PARAMETER Port
        Proxy port
    .PARAMETER IncludeQwen
        Include Qwen models
    .PARAMETER IncludeCodex
        Include Codex/OpenAI models
    .PARAMETER IncludeAntigravity
        Include Antigravity models
    .OUTPUTS
        $true if successful
    #>
    param(
        [int]$Port = $script:DefaultProxyPort,
        [switch]$IncludeQwen,
        [switch]$IncludeCodex,
        [switch]$IncludeAntigravity
    )

    $configPath = Join-Path $env:USERPROFILE ".claude-code-router\config.json"

    if (-not (Test-Path $configPath)) {
        Write-Host "Error: CCR config not found" -ForegroundColor Red
        return $false
    }

    $configText = Get-Content $configPath -Raw -Encoding UTF8

    # Build models list
    $models = @(
        "claude-opus-4-20250514",
        "claude-sonnet-4-20250514"
    )
    if ($IncludeQwen) {
        $models += @("qwen3-coder-plus", "qwen3-coder-flash")
    }
    if ($IncludeCodex) {
        $models += @("gpt-5-codex", "gpt-5-codex-mini", "gpt-5.1-codex", "gpt-5.1-codex-mini", "gpt-5.1-codex-max", "gpt-5.2-codex")
    }
    if ($IncludeAntigravity) {
        $models += @("gemini-3-pro-preview", "gemini-3-flash-preview")
    }
    $modelsJson = ($models | ForEach-Object { "`"$_`"" }) -join ",`n        "

    if ($configText -notmatch '"name":\s*"CLIProxyAPI"') {
        Write-Host "Adding CLIProxyAPI provider..." -ForegroundColor Yellow

        $providerBlock = @"
{
      "name": "CLIProxyAPI",
      "api_base_url": "http://localhost:$Port/v1/chat/completions",
      "api_key": "not-required",
      "models": [
        $modelsJson
      ]
    }
"@

        # Case 1: Empty Providers array - "Providers": []
        if ($configText -match '"Providers":\s*\[\s*\]') {
            $configText = $configText -replace '"Providers":\s*\[\s*\]', "`"Providers`": [$providerBlock]"
            Write-Host "Added CLIProxyAPI provider (to empty array)" -ForegroundColor Green
        }
        # Case 2: Existing providers - insert before closing ] with StatusLine after
        elseif ($configText -match '(\}\s*)\n(\s*\],\s*\n\s*"StatusLine")') {
            $configText = $configText -replace '(\}\s*)\n(\s*\],\s*\n\s*"StatusLine")', "`$1,`n    $providerBlock`n`$2"
            Write-Host "Added CLIProxyAPI provider" -ForegroundColor Green
        }
        # Case 3: Existing providers - insert before closing ] (no StatusLine)
        elseif ($configText -match '(\}\s*)\n(\s*\],\s*\n\s*"Router")') {
            $configText = $configText -replace '(\}\s*)\n(\s*\],\s*\n\s*"Router")', "`$1,`n    $providerBlock`n`$2"
            Write-Host "Added CLIProxyAPI provider" -ForegroundColor Green
        }
        else {
            Write-Host "Warning: Could not find insertion point for provider" -ForegroundColor Yellow
            return $false
        }
    } else {
        # Provider exists - update the models list
        Write-Host "Updating CLIProxyAPI models..." -ForegroundColor Yellow
        $configText = $configText -replace '("name":\s*"CLIProxyAPI"[^}]*"models":\s*\[)[^\]]*(\])', "`$1`n        $modelsJson`n      `$2"
        Write-Host "CLIProxyAPI models updated" -ForegroundColor Green
    }

    [System.IO.File]::WriteAllText($configPath, $configText, [System.Text.UTF8Encoding]::new($false))
    Write-Host "Config saved" -ForegroundColor Green
    return $true
}

function Remove-CCRProvider {
    <#
    .SYNOPSIS
        Remove CLIProxyAPI provider from CCR config.
    .OUTPUTS
        $true if successful
    #>
    $configPath = Join-Path $env:USERPROFILE ".claude-code-router\config.json"

    if (-not (Test-Path $configPath)) {
        Write-Host "CCR config not found" -ForegroundColor Gray
        return $false
    }

    $configText = Get-Content $configPath -Raw -Encoding UTF8

    if ($configText -match '"name":\s*"CLIProxyAPI"') {
        $configText = $configText -replace ',\s*\{\s*"name":\s*"CLIProxyAPI"[^}]*"models":\s*\[[^\]]*\]\s*\}', ''
        Write-Host "Removed CLIProxyAPI provider" -ForegroundColor Green
    } else {
        Write-Host "CLIProxyAPI not found in config" -ForegroundColor Gray
        return $false
    }

    # Reset Router.think if it references CLIProxyAPI
    $configText = $configText -replace '"think":\s*"CLIProxyAPI,[^"]*"', '"think": ""'

    [System.IO.File]::WriteAllText($configPath, $configText, [System.Text.UTF8Encoding]::new($false))
    Write-Host "Config updated" -ForegroundColor Green
    return $true
}

# ============================================================================
# CCR Service Functions
# ============================================================================

function Restart-CCR {
    <#
    .SYNOPSIS
        Restart claude-code-router service.
    .OUTPUTS
        $true if CCR is running after restart
    #>
    Write-Host "Restarting CCR..." -ForegroundColor Cyan

    & ccr stop 2>&1 | Out-Null
    Start-Sleep -Seconds 1
    Stop-OrphanProcesses -Port $script:CCRPort
    & ccr restart 2>&1 | Out-Null
    Start-Sleep -Seconds 1
    & ccr start 2>&1 | Out-Null
    Start-Sleep -Seconds 2

    $status = & ccr status 2>&1
    if ($status -match "Running") {
        Write-Host "CCR running" -ForegroundColor Green
        return $true
    } else {
        Write-Host "Warning: CCR may not be running. Run 'ccr start' manually." -ForegroundColor Yellow
        return $false
    }
}

function Stop-CCR {
    <#
    .SYNOPSIS
        Stop claude-code-router service and clean up orphan processes.
    #>
    & ccr stop 2>&1 | Out-Null
    Start-Sleep -Milliseconds 500
    Stop-OrphanProcesses -Port $script:CCRPort
    Write-Host "CCR stopped" -ForegroundColor Green
}

# ============================================================================
# Model Query Functions
# ============================================================================

function Get-AvailableModels {
    <#
    .SYNOPSIS
        Query available models from CLIProxyAPI.
    .PARAMETER Port
        Proxy port
    .OUTPUTS
        Array of model names or $null if failed
    #>
    param([int]$Port = $script:DefaultProxyPort)

    if (-not (Test-Port -Port $Port)) {
        Write-Host "Proxy not running" -ForegroundColor Yellow
        return $null
    }

    try {
        $response = Invoke-RestMethod -Uri "http://localhost:$Port/v1/models" -Method Get -ErrorAction Stop
        $models = $response.data | ForEach-Object { $_.id }
        return $models
    } catch {
        Write-Host "Error querying models: $_" -ForegroundColor Red
        return $null
    }
}


