#Requires -Version 5.1
param(
    [string]$InstallPath = "C:\Program Files\CLIProxyAPI",
    [int]$ProxyPort = 8317
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir "CCRSetup-Functions.ps1")

function Show-Menu {
    Clear-Host

    $proxy = Get-CLIProxyInstallStatus -InstallPath $InstallPath
    $running = Get-ProxyRunningStatus -Port $ProxyPort
    $auth = Get-AuthStatus
    $ccr = Get-CCRStatus
    # Title
    Write-Host ""
    Write-Host "   CCRSetup" -ForegroundColor Cyan -NoNewline
    Write-Host " - CLIProxyAPI & CCR Manager" -ForegroundColor DarkGray
    Write-Host ""

    # Status bar
    Write-Host "   " -NoNewline
    if ($proxy.Installed) { Write-Host " CLIProxy:OK " -BackgroundColor DarkGreen -ForegroundColor White -NoNewline }
    else { Write-Host " CLIProxy:NO " -BackgroundColor DarkRed -ForegroundColor White -NoNewline }
    Write-Host " " -NoNewline
    if ($running.Running -and $running.Process) { Write-Host " Proxy:ON " -BackgroundColor DarkGreen -ForegroundColor White -NoNewline }
    else { Write-Host " Proxy:OFF " -BackgroundColor DarkRed -ForegroundColor White -NoNewline }
    Write-Host " " -NoNewline
    if ($auth.ClaudeConfigured) { Write-Host " Claude:OK " -BackgroundColor DarkGreen -ForegroundColor White -NoNewline }
    else { Write-Host " Claude:NO " -BackgroundColor DarkRed -ForegroundColor White -NoNewline }
    Write-Host " " -NoNewline
    if ($auth.QwenConfigured) { Write-Host " Qwen:OK " -BackgroundColor DarkGreen -ForegroundColor White -NoNewline }
    else { Write-Host " Qwen:-- " -BackgroundColor DarkGray -ForegroundColor White -NoNewline }
    Write-Host " " -NoNewline
    if ($auth.CodexConfigured) { Write-Host " Codex:OK " -BackgroundColor DarkGreen -ForegroundColor White -NoNewline }
    else { Write-Host " Codex:-- " -BackgroundColor DarkGray -ForegroundColor White -NoNewline }
    Write-Host " " -NoNewline
    if ($auth.AntigravityConfigured) { Write-Host " Antigravity:OK" -BackgroundColor DarkGreen -ForegroundColor White -NoNewline }
    else { Write-Host " Antigravity:--" -BackgroundColor DarkGray -ForegroundColor White -NoNewline }
    Write-Host " " -NoNewline
    if ($ccr.ProviderConfigured -and $ccr.Running) { Write-Host " CCR:OK " -BackgroundColor DarkGreen -ForegroundColor White -NoNewline }
    else { Write-Host " CCR:NO " -BackgroundColor DarkRed -ForegroundColor White -NoNewline }
    Write-Host ""

    # Auth files
    $hasAuth = $auth.ClaudeConfigured -or $auth.QwenConfigured -or $auth.CodexConfigured -or $auth.AntigravityConfigured
    if ($hasAuth) {
        if ($auth.ClaudeFiles) { $auth.ClaudeFiles | ForEach-Object { Write-Host "   Claude: $($_.Name)" -ForegroundColor DarkGreen } }
        if ($auth.QwenFiles)   { $auth.QwenFiles   | ForEach-Object { Write-Host "   Qwen:   $($_.Name)" -ForegroundColor DarkGreen } }
        if ($auth.CodexFiles)  { $auth.CodexFiles  | ForEach-Object { Write-Host "   Codex:  $($_.Name)" -ForegroundColor DarkGreen } }
        if ($auth.AntigravityFiles) { $auth.AntigravityFiles | ForEach-Object { Write-Host "   Antigravity: $($_.Name)" -ForegroundColor DarkGreen } }
    }
    Write-Host ""

    # Menu
    Write-Host "   SETUP" -ForegroundColor Yellow
    Write-Host "   [1] Install CLIProxyAPI    [2] Config yaml"
    Write-Host ""
    Write-Host "   AUTH" -ForegroundColor Yellow
    Write-Host "   [3] Login Claude    [4] Login Qwen    [15] Login Codex    [16] Login Antigravity"
    Write-Host "   [5] Remove auth"
    Write-Host ""
    Write-Host "   SERVICES" -ForegroundColor Yellow
    Write-Host "   [6] Start Proxy    [7] Stop Proxy    [8] Restart CCR    [9] Clean orphans"
    Write-Host ""
    Write-Host "   CCR CONFIG" -ForegroundColor Yellow
    Write-Host "   [10] Add provider    [11] Remove provider    [12] Show models"
    Write-Host ""
    Write-Host "   UNINSTALL" -ForegroundColor Yellow
    Write-Host "   [13] Uninstall proxy    [14] Uninstall all"
    Write-Host ""
    Write-Host "   ----------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "   [" -NoNewline -ForegroundColor DarkGray
    Write-Host "S" -NoNewline -ForegroundColor Green
    Write-Host "] Full Setup   [" -NoNewline -ForegroundColor DarkGray
    Write-Host "R" -NoNewline -ForegroundColor Cyan
    Write-Host "] Refresh   [" -NoNewline -ForegroundColor DarkGray
    Write-Host "Q" -NoNewline -ForegroundColor Red
    Write-Host "] Quit" -ForegroundColor DarkGray
    Write-Host ""
}

function Wait-Key {
    Write-Host "`n   Press any key..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# Actions
function Do-Install {
    Write-Host "`n   >>> Install CLIProxyAPI <<<" -ForegroundColor Cyan
    $i = Get-CLIProxyInstallStatus -InstallPath $InstallPath
    if ($i.Installed) {
        $c = Read-Host "   Already installed. Reinstall? (y/N)"
        if ($c -notmatch '^[yY]') { return }
    }
    Install-CLIProxyAPI -InstallPath $InstallPath
    Wait-Key
}

function Do-Config {
    Write-Host "`n   >>> Config yaml <<<" -ForegroundColor Cyan
    Set-ProxyConfig -Port $ProxyPort
    Wait-Key
}

function Do-Claude {
    Write-Host "`n   >>> Login Claude <<<" -ForegroundColor Cyan
    $i = Get-CLIProxyInstallStatus -InstallPath $InstallPath
    if (-not $i.Installed) { Write-Host "   Error: not installed" -ForegroundColor Red; Wait-Key; return }
    $a = Get-AuthStatus
    if ($a.ClaudeConfigured) {
        $c = Read-Host "   Already authenticated. Re-auth? (y/N)"
        if ($c -notmatch '^[yY]') { return }
        Remove-AuthFiles -Only Claude
    }
    Start-ClaudeLogin -InstallPath $InstallPath
    Wait-Key
}

function Do-Qwen {
    Write-Host "`n   >>> Login Qwen <<<" -ForegroundColor Cyan
    $i = Get-CLIProxyInstallStatus -InstallPath $InstallPath
    if (-not $i.Installed) { Write-Host "   Error: not installed" -ForegroundColor Red; Wait-Key; return }
    $a = Get-AuthStatus
    if ($a.QwenConfigured) {
        $c = Read-Host "   Already authenticated. Re-auth? (y/N)"
        if ($c -notmatch '^[yY]') { return }
        Remove-AuthFiles -Only Qwen
    }
    Start-QwenLogin -InstallPath $InstallPath
    Wait-Key
}

function Do-CodexLogin {
    Write-Host "`n   >>> Login Codex <<<" -ForegroundColor Cyan
    $i = Get-CLIProxyInstallStatus -InstallPath $InstallPath
    if (-not $i.Installed) { Write-Host "   Error: not installed" -ForegroundColor Red; Wait-Key; return }
    $a = Get-AuthStatus
    if ($a.CodexConfigured) {
        $c = Read-Host "   Already authenticated. Re-auth? (y/N)"
        if ($c -notmatch '^[yY]') { return }
        Remove-AuthFiles -Only Codex
    }
    Start-CodexLogin -InstallPath $InstallPath
    Wait-Key
}

function Do-AntigravityLogin {
    Write-Host "`n   >>> Login Antigravity <<<" -ForegroundColor Cyan
    $i = Get-CLIProxyInstallStatus -InstallPath $InstallPath
    if (-not $i.Installed) { Write-Host "   Error: not installed" -ForegroundColor Red; Wait-Key; return }
    $a = Get-AuthStatus
    if ($a.AntigravityConfigured) {
        $c = Read-Host "   Already authenticated. Re-auth? (y/N)"
        if ($c -notmatch '^[yY]') { return }
        Remove-AuthFiles -Only Antigravity
    }
    Start-AntigravityLogin -InstallPath $InstallPath
    Wait-Key
}

function Do-RemoveAuth {
    Write-Host "`n   >>> Remove Auth <<<" -ForegroundColor Cyan
    Write-Host "   1=Claude  2=Qwen  3=Codex  4=Antigravity  5=All  0=Cancel"
    switch (Read-Host "   Choice") {
        "1" { Remove-AuthFiles -Only Claude }
        "2" { Remove-AuthFiles -Only Qwen }
        "3" { Remove-AuthFiles -Only Codex }
        "4" { Remove-AuthFiles -Only Antigravity }
        "5" { Remove-AuthFiles }
    }
    Wait-Key
}

function Do-StartProxy {
    Write-Host "`n   >>> Start Proxy <<<" -ForegroundColor Cyan
    $i = Get-CLIProxyInstallStatus -InstallPath $InstallPath
    if (-not $i.Installed) { Write-Host "   Error: not installed" -ForegroundColor Red; Wait-Key; return }
    $cfg = Get-ConfigYamlStatus
    if (-not $cfg.Exists) { Set-ProxyConfig -Port $ProxyPort }
    Start-ProxyService -InstallPath $InstallPath -Port $ProxyPort
    Wait-Key
}

function Do-StopProxy {
    Write-Host "`n   >>> Stop Proxy <<<" -ForegroundColor Cyan
    Stop-ProxyService
    Wait-Key
}

function Do-RestartCCR {
    Write-Host "`n   >>> Restart CCR <<<" -ForegroundColor Cyan
    Restart-CCR
    Wait-Key
}

function Do-Clean {
    Write-Host "`n   >>> Clean Orphans <<<" -ForegroundColor Cyan
    $c1 = Stop-OrphanProcesses -Port $ProxyPort
    $c2 = Stop-OrphanProcesses -Port 3456
    if (-not $c1 -and -not $c2) { Write-Host "   No orphan processes" -ForegroundColor Green }
    Wait-Key
}

function Do-AddProvider {
    Write-Host "`n   >>> Add Provider <<<" -ForegroundColor Cyan
    $ccr = Get-CCRStatus
    if (-not $ccr.ConfigExists) { Write-Host "   Error: CCR config not found" -ForegroundColor Red; Wait-Key; return }
    $a = Get-AuthStatus
    $params = @{ Port = $ProxyPort }
    if ($a.QwenConfigured) { $params.IncludeQwen = $true }
    if ($a.CodexConfigured) { $params.IncludeCodex = $true }
    if ($a.AntigravityConfigured) { $params.IncludeAntigravity = $true }
    Add-CCRProvider @params
    Wait-Key
}

function Do-RemoveProvider {
    Write-Host "`n   >>> Remove Provider <<<" -ForegroundColor Cyan
    if ((Read-Host "   Confirm? (y/N)") -match '^[yY]') { Remove-CCRProvider }
    Wait-Key
}

function Do-Models {
    Write-Host "`n   >>> Models <<<" -ForegroundColor Cyan
    $p = Get-ProxyRunningStatus -Port $ProxyPort
    if (-not $p.Running) { Write-Host "   Proxy not running" -ForegroundColor Yellow; Wait-Key; return }
    $m = Get-AvailableModels -Port $ProxyPort
    if ($m) { $m | ForEach-Object { Write-Host "   - $_" } }
    Wait-Key
}

function Do-Uninstall {
    Write-Host "`n   >>> Uninstall CLIProxyAPI <<<" -ForegroundColor Cyan
    if ((Read-Host "   Confirm? (y/N)") -match '^[yY]') {
        Stop-ProxyService
        Uninstall-CLIProxyAPI -InstallPath $InstallPath
    }
    Wait-Key
}

function Do-UninstallAll {
    Write-Host "`n   >>> Uninstall All <<<" -ForegroundColor Cyan
    Write-Host "   Removes: CLIProxyAPI, config, auth, provider" -ForegroundColor Yellow
    if ((Read-Host "   Confirm? (y/N)") -notmatch '^[yY]') { Wait-Key; return }
    $keepAuth = (Read-Host "   Keep auth files? (y/N)") -match '^[yY]'
    Stop-ProxyService; Stop-CCR; Remove-CCRProvider
    Uninstall-CLIProxyAPI -InstallPath $InstallPath; Remove-ProxyConfig
    if (-not $keepAuth) { Remove-AuthFiles }
    Restart-CCR
    Write-Host "`n   Done!" -ForegroundColor Green
    Wait-Key
}

function Do-FullSetup {
    Write-Host "`n   >>> Full Setup <<<" -ForegroundColor Cyan
    if ((Read-Host "   Run? (Y/n)") -match '^[nN]') { return }

    & ccr stop 2>$null | Out-Null; Stop-OrphanProcesses -Port 3456

    $i = Get-CLIProxyInstallStatus -InstallPath $InstallPath
    if (-not $i.Installed) { Install-CLIProxyAPI -InstallPath $InstallPath }
    else { Write-Host "   CLIProxyAPI OK" -ForegroundColor Green }

    Set-ProxyConfig -Port $ProxyPort

    $a = Get-AuthStatus
    if (-not $a.ClaudeConfigured) { Start-ClaudeLogin -InstallPath $InstallPath }
    else { Write-Host "   Claude OK" -ForegroundColor Green }

    $a = Get-AuthStatus
    if (-not $a.QwenConfigured) {
        if ((Read-Host "   Setup Qwen? (Y/n)") -notmatch '^[nN]') { Start-QwenLogin -InstallPath $InstallPath }
    } else { Write-Host "   Qwen OK" -ForegroundColor Green }

    $a = Get-AuthStatus
    if (-not $a.CodexConfigured) {
        if ((Read-Host "   Setup Codex? (Y/n)") -notmatch '^[nN]') { Start-CodexLogin -InstallPath $InstallPath }
    } else { Write-Host "   Codex OK" -ForegroundColor Green }

    $a = Get-AuthStatus
    if (-not $a.AntigravityConfigured) {
        if ((Read-Host "   Setup Antigravity? (Y/n)") -notmatch '^[nN]') { Start-AntigravityLogin -InstallPath $InstallPath }
    } else { Write-Host "   Antigravity OK" -ForegroundColor Green }

    Start-ProxyService -InstallPath $InstallPath -Port $ProxyPort
    $a = Get-AuthStatus
    $params = @{ Port = $ProxyPort }
    if ($a.QwenConfigured) { $params.IncludeQwen = $true }
    if ($a.CodexConfigured) { $params.IncludeCodex = $true }
    if ($a.AntigravityConfigured) { $params.IncludeAntigravity = $true }
    Add-CCRProvider @params
    Restart-CCR

    Write-Host "`n   *** SETUP COMPLETE! Run: ccr code ***" -ForegroundColor Green
    Wait-Key
}

# Main
while ($true) {
    Show-Menu
    switch ((Read-Host "   ").ToUpper()) {
        "1"  { Do-Install }
        "2"  { Do-Config }
        "3"  { Do-Claude }
        "4"  { Do-Qwen }
        "5"  { Do-RemoveAuth }
        "6"  { Do-StartProxy }
        "7"  { Do-StopProxy }
        "8"  { Do-RestartCCR }
        "9"  { Do-Clean }
        "10" { Do-AddProvider }
        "11" { Do-RemoveProvider }
        "12" { Do-Models }
        "13" { Do-Uninstall }
        "14" { Do-UninstallAll }
        "15" { Do-CodexLogin }
        "16" { Do-AntigravityLogin }
        "S"  { Do-FullSetup }
        "R"  { }
        "Q"  { Write-Host "`n   Ciao!" -ForegroundColor Cyan; exit 0 }
    }
}
