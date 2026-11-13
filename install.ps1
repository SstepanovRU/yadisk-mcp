<#
.SYNOPSIS
    Installs yadisk-mcp from this checkout and registers it in Claude Code and Codex (Windows).

.DESCRIPTION
    1. Creates .venv and installs the package (pip install -e .).
    2. Ensures the YANDEX_DISK_TOKEN user environment variable is set (prompts if missing).
    3. Verifies the token against the Yandex Disk API.
    4. Registers the server as "yadisk" in Claude Code (user scope) and Codex (~/.codex/config.toml).

    Safe to re-run. The token is never written to the repository or to client configs:
    clients inherit it from the user environment.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\install.ps1
.EXAMPLE
    .\install.ps1 -ServerArgs '--safe-delete','--read-only'
.EXAMPLE
    .\install.ps1 -NoRegister
#>
param(
    # Arguments passed to yadisk-mcp by every client.
    [string[]]$ServerArgs = @('--safe-delete'),
    # Only install and verify; do not touch Claude Code / Codex configs.
    [switch]$NoRegister
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

function Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Ok($msg)   { Write-Host "    $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "    $msg" -ForegroundColor Yellow }

# --- 1. Python ---------------------------------------------------------------
Step 'Looking for Python >= 3.11'
$pyCmd = $null
foreach ($candidate in @(@('py', '-3'), @('python'))) {
    if (Get-Command $candidate[0] -ErrorAction SilentlyContinue) {
        $exeArgs = @($candidate | Select-Object -Skip 1)
        $out = & $candidate[0] @exeArgs -c 'import sys; print(int(sys.version_info >= (3, 11)))' 2>$null
        if ($LASTEXITCODE -eq 0 -and "$out".Trim() -eq '1') { $pyCmd = $candidate; break }
    }
}
if (-not $pyCmd) {
    throw 'Python 3.11+ not found. Install it: winget install Python.Python.3.13  (then reopen the terminal)'
}
Ok ("Using: " + ($pyCmd -join ' '))

# --- 2. venv + package -------------------------------------------------------
$venvPy = Join-Path $root '.venv\Scripts\python.exe'
$serverExe = Join-Path $root '.venv\Scripts\yadisk-mcp.exe'

Step 'Creating virtual environment (.venv)'
if (-not (Test-Path $venvPy)) {
    $exeArgs = @($pyCmd | Select-Object -Skip 1)
    & $pyCmd[0] @exeArgs -m venv (Join-Path $root '.venv')
    if ($LASTEXITCODE -ne 0) { throw 'venv creation failed' }
    Ok 'Created'
} else {
    Ok 'Already exists'
}

Step 'Installing yadisk-mcp into .venv'
$exeLocked = $false
if (Test-Path $serverExe) {
    # A running MCP client keeps yadisk-mcp.exe open, and pip cannot replace it.
    try { [IO.File]::Open($serverExe, 'Open', 'ReadWrite', 'None').Close() } catch { $exeLocked = $true }
}
if ($exeLocked) {
    Warn 'yadisk-mcp.exe is in use (Claude Code / Codex running) - reinstall skipped.'
    Warn 'Code changes still apply (editable install). To update dependencies, close the clients and re-run.'
} else {
    & $venvPy -m pip install --quiet --upgrade pip
    & $venvPy -m pip install --quiet -e $root
    if ($LASTEXITCODE -ne 0) { throw 'pip install failed' }
}
if (-not (Test-Path $serverExe)) { throw "Expected $serverExe after install" }
Ok $serverExe

# --- 3. Token ----------------------------------------------------------------
Step 'Checking YANDEX_DISK_TOKEN (user environment variable)'
$token = [Environment]::GetEnvironmentVariable('YANDEX_DISK_TOKEN', 'User')
if (-not $token) {
    Warn 'Not set. Get a token first (see INSTALL.md, section "Token"), then paste it here.'
    $secure = Read-Host 'YANDEX_DISK_TOKEN' -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { $token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    if (-not $token) { throw 'Empty token' }
    [Environment]::SetEnvironmentVariable('YANDEX_DISK_TOKEN', $token, 'User')
    Ok 'Saved to user environment'
} else {
    Ok 'Already set'
}
$env:YANDEX_DISK_TOKEN = $token

Step 'Verifying token against Yandex Disk API'
# Single quotes only inside: Windows PowerShell 5.1 strips double quotes from native args.
$check = @'
import asyncio, os, sys, yadisk
async def main():
    async with yadisk.AsyncClient(token=os.environ['YANDEX_DISK_TOKEN'], session='aiohttp') as c:
        return await c.check_token()
try:
    ok = asyncio.run(main())
except Exception as e:
    print('    check failed:', type(e).__name__, e)
    sys.exit(2)
sys.exit(0 if ok else 1)
'@
& $venvPy -c $check
if ($LASTEXITCODE -eq 1) {
    throw 'Token is invalid or expired. Get a new one and run: [Environment]::SetEnvironmentVariable(''YANDEX_DISK_TOKEN'', ''<token>'', ''User'')'
} elseif ($LASTEXITCODE -ne 0) {
    throw 'Could not verify the token (network problem?). See the error above.'
}
Ok 'Token is valid'

if ($NoRegister) {
    Step 'Skipping client registration (-NoRegister)'
    return
}

# --- 4. Claude Code ----------------------------------------------------------
Step 'Registering in Claude Code (user scope)'
if (Get-Command claude -ErrorAction SilentlyContinue) {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    & claude mcp remove yadisk -s user *> $null
    & claude mcp add yadisk -s user -- $serverExe @ServerArgs
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    if ($code -ne 0) { Warn 'claude mcp add failed - register manually (see INSTALL.md)' } else { Ok 'Done' }
} else {
    Warn 'claude CLI not found - skipped (see INSTALL.md for manual setup)'
}

# --- 5. Codex ----------------------------------------------------------------
Step 'Registering in Codex (~/.codex/config.toml)'
$codexDir = Join-Path $HOME '.codex'
$codexCfg = Join-Path $codexDir 'config.toml'
if ((Test-Path $codexDir) -or (Get-Command codex -ErrorAction SilentlyContinue)) {
    $existing = ''
    if (Test-Path $codexCfg) { $existing = [IO.File]::ReadAllText($codexCfg) }
    if ($existing -match '(?m)^\[mcp_servers\.yadisk\]') {
        Warn '[mcp_servers.yadisk] already present - left unchanged'
    } else {
        if (-not (Test-Path $codexDir)) { New-Item -ItemType Directory -Path $codexDir | Out-Null }
        $tomlArgs = ($ServerArgs | ForEach-Object { '"' + $_ + '"' }) -join ', '
        $block = "`r`n[mcp_servers.yadisk]`r`ncommand = '$serverExe'`r`nargs = [$tomlArgs]`r`nenv_vars = [""YANDEX_DISK_TOKEN""]`r`n"
        [IO.File]::AppendAllText($codexCfg, $block, (New-Object Text.UTF8Encoding $false))
        Ok "Appended to $codexCfg"
    }
} else {
    Warn 'Codex not found - skipped'
}

Write-Host ''
Write-Host 'Installed. Restart Claude Code / Codex (and any open terminals) so they pick up YANDEX_DISK_TOKEN.' -ForegroundColor Green
Write-Host 'Check in Claude Code: claude mcp list   (yadisk should be "Connected")'
