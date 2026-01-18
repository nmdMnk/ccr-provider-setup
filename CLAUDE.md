# CCRSetup Project

## Overview
PowerShell scripts for automating CLIProxyAPI installation and claude-code-router configuration to use Anthropic Max subscription and Qwen.

## Files
- `Setup-ClaudeMax.ps1` - Main setup script (Claude Max + Qwen)
- `Uninstall-ClaudeMax.ps1` - Uninstall script

## Usage

### Run Setup
```powershell
# Setup both Claude Max and Qwen
.\Setup-ClaudeMax.ps1

# Skip Qwen setup
.\Setup-ClaudeMax.ps1 -SkipQwen
```

The script will:
1. Check/elevate admin privileges (only for install)
2. Download/update CLIProxyAPI from GitHub
3. Open browser for Claude authentication (if needed)
4. Open browser for Qwen authentication (if needed)
5. Start proxy on port 8317
6. Add `CLIProxyAPI` provider to CCR config (with all models)
7. Restart claude-code-router

### Run Uninstall
```powershell
# Remove everything
.\Uninstall-ClaudeMax.ps1

# Keep auth files (for reinstall)
.\Uninstall-ClaudeMax.ps1 -KeepAuth
```

### Verify Installation
```powershell
# Check proxy is running
Test-NetConnection localhost -Port 8317

# Check CCR config
cat ~/.claude-code-router/config.json

# Test with CCR
ccr code
```

## Configuration

### Install Location
`C:\Program Files\CLIProxyAPI`

### Auth Tokens
- Claude: `~/claude-*.json`
- Qwen: `~/qwen-*.json`

### CCR Provider Added
```json
{
  "name": "CLIProxyAPI",
  "api_base_url": "http://localhost:8317/v1/chat/completions",
  "api_key": "not-required",
  "models": [
    "claude-opus-4-20250514",
    "claude-sonnet-4-20250514",
    "qwen3-coder-plus",
    "qwen3-coder-flash"
  ]
}
```

### Router Configuration
The script sets `Router.think` to `CLIProxyAPI,claude-opus-4-20250514`

### Available Models (CLIProxyAPI)
Query models: `curl http://localhost:8317/v1/models`

**Claude:**
- claude-opus-4-20250514
- claude-sonnet-4-20250514
- claude-opus-4-5-20251101
- claude-sonnet-4-5-20250929
- claude-3-7-sonnet-20250219
- claude-3-5-haiku-20241022

**Qwen:**
- qwen3-coder-plus
- qwen3-coder-flash
- vision-model

## Autostart
CLIProxyAPI must be running for the proxy to work. To autostart:
1. Create a scheduled task, or
2. Add shortcut to `shell:startup` folder

## Troubleshooting

### Proxy not responding
```powershell
# Check if running
Get-Process -Name "cli-proxy-api"

# Restart manually (from user profile directory!)
cd $env:USERPROFILE
& "C:\Program Files\CLIProxyAPI\cli-proxy-api.exe"
```

### Re-authenticate
```powershell
# Delete auth and re-run setup
Remove-Item ~/claude-*.json
.\Setup-ClaudeMax.ps1
```

### GitHub API rate limit
The script may fail to check versions if rate limited. Install will still work with existing files.

---

## Errors Encountered & Solutions

### 1. CLIProxyAPI: "failed to load config"
**Error:** `failed to load config: failed to read config file: open C:\Users\...\config.yaml: The system cannot find the file specified`

**Cause:** CLIProxyAPI requires a `config.yaml` file in the working directory.

**Solution:** Create `~/config.yaml` with:
```yaml
port: 8317
auth-dir: C:\Users\YOUR_USERNAME
```

### 2. CLIProxyAPI: "failed to create auth directory"
**Error:** `proxy service exited with error: cliproxy: failed to create auth directory : mkdir : The system cannot find the path specified`

**Cause:** `config.yaml` missing `auth-dir` setting.

**Solution:** Add `auth-dir: C:\Users\YOUR_USERNAME` to `config.yaml`.

### 3. Browser doesn't open for login (admin context)
**Error:** Browser window flashes but doesn't appear when running as admin.

**Cause:** Browsers don't launch properly from elevated (admin) processes.

**Solution:** Launch login in a separate non-elevated PowerShell window:
```powershell
Start-Process "powershell.exe" -WorkingDirectory $env:USERPROFILE -ArgumentList "-NoExit", "-Command", "& 'C:\Program Files\CLIProxyAPI\cli-proxy-api.exe' --claude-login"
```

### 4. CLIProxyAPI looks in system32 for config
**Error:** `failed to read config file: open C:\WINDOWS\system32\config.yaml`

**Cause:** When running as admin, working directory defaults to `system32`.

**Solution:** Always set `-WorkingDirectory $env:USERPROFILE` when starting CLIProxyAPI.

### 5. Auth file location
**Note:** CLIProxyAPI saves auth files directly in `~` (e.g., `~/claude-email@example.com.json`), NOT in `~/.cli-proxy-api/`.

### 6. CCR won't start - orphan processes
**Error:** `ccr start` says "Loaded JSON config" but status shows "Not Running", or `ccr ui` says "Service startup timeout" and resets config.

**Cause:** Multiple orphan node processes blocking port 3456. Can appear as "corrupted JSON" but the real problem is orphan processes.

**Solution:**
```powershell
# Find ALL orphan processes on port 3456
netstat -ano | Select-String ":3456.*LISTENING"

# Kill ALL of them (may need admin)
Stop-Process -Id <PID1>,<PID2> -Force

# Then start CCR
ccr start
```

**Note:** There can be MULTIPLE processes on the same port. Kill all of them.

### 7. CCR config broken by PowerShell
**Error:** CCR refuses to start after script modifies config.json.

**Cause:** PowerShell's `ConvertTo-Json` changes JSON formatting in ways CCR doesn't accept.

**Solution:** Modify config.json using text replacement, not JSON parsing:
```powershell
$configText = Get-Content $configPath -Raw
$configText = $configText -replace 'pattern', 'replacement'
[System.IO.File]::WriteAllText($configPath, $configText, [System.Text.UTF8Encoding]::new($false))
```
**Important:** Use `UTF8Encoding($false)` to avoid BOM.

### 8. Unknown model error
**Error:** `unknown provider for model claude-opus-4-20250115`

**Cause:** Model name doesn't exist in CLIProxyAPI.

**Solution:** Query available models and use correct names:
```powershell
curl http://localhost:8317/v1/models
```
Use `claude-opus-4-20250514` instead of `claude-opus-4-20250115`.
