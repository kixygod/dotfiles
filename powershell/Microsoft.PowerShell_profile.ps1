# -----------------------------
# Fast & safe profile bootstrap
# -----------------------------
$ErrorActionPreference = "Continue"

function Import-IfAvailable {
    param(
        [Parameter(Mandatory)] [string] $Name
    )
    try {
        if (Get-Module -ListAvailable -Name $Name) {
            Import-Module $Name -ErrorAction SilentlyContinue
            return $true
        }
    }
    catch {}
    return $false
}

# -----------------------------
# CommandNotFound integrations
# -----------------------------
Import-IfAvailable "Microsoft.WinGet.CommandNotFound" | Out-Null

if ($env:ChocolateyInstall) {
    $chocoProfile = Join-Path $env:ChocolateyInstall "helpers\chocolateyProfile.psm1"
    if (Test-Path $chocoProfile) {
        Import-Module $chocoProfile -ErrorAction SilentlyContinue
    }
}

# -----------------------------
# Environment niceties
# -----------------------------
$env:POWERSHELL_TELEMETRY_OPTOUT = "1"
$env:STARSHIP_CONFIG = "$HOME\.config\starship.toml"

# -----------------------------
# Prompt (Starship)
# -----------------------------
if (Get-Command starship -ErrorAction SilentlyContinue) {
    Invoke-Expression (& starship init powershell)
}

# -----------------------------
# Aliases (better as functions where it matters)
# -----------------------------
Set-Alias c cls

# Don't override built-in "notepad" unless you really want to.
# Better: create explicit alias for Notepad++
if (Get-Command "notepad++" -ErrorAction SilentlyContinue) {
    Set-Alias npp notepad++
}

# -----------------------------
# PSReadLine (history, prediction, UX)
# -----------------------------
Import-Module PSReadLine -Force

# Core UX
Set-PSReadLineOption -EditMode Windows
Set-PSReadLineOption -BellStyle None
Set-PSReadLineOption -HistorySaveStyle SaveIncrementally
Set-PSReadLineOption -MaximumHistoryCount 10000

# Better completion experience
Set-PSReadLineOption -PredictionSource HistoryAndPlugin
# InlineView (like fish/zsh):
# Set-PSReadLineOption -PredictionViewStyle InlineView
Set-PSReadLineOption -PredictionViewStyle ListView

# Smart history search and navigation
Set-PSReadLineKeyHandler -Key Ctrl+r -Function ReverseSearchHistory
Set-PSReadLineKeyHandler -Key Ctrl+Shift+r -Function ForwardSearchHistory
Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward

# Optional: accept suggestion faster
Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete

# -----------------------------
# History hygiene (avoid leaking secrets)
# -----------------------------
# This prevents storing lines with typical secret patterns
Set-PSReadLineOption -AddToHistoryHandler {
    param([string]$line)

    # Skip empty / whitespace
    if ([string]::IsNullOrWhiteSpace($line)) { return $false }

    # Typical secret keywords and formats
    $secretPattern = @(
        "password", "passwd", "pwd",
        "token", "apikey", "api_key",
        "secret", "client_secret",
        "authorization\s*:",
        "bearer\s+",
        "PRIVATE KEY", "BEGIN RSA", "BEGIN OPENSSH"
    ) -join "|"

    if ($line -match $secretPattern) { return $false }

    # Also skip "setx XXX ..." for sensitive env vars
    if ($line -match "setx\s+(TOKEN|APIKEY|SECRET|PASSWORD)\b") { return $false }

    return $true
}

# -----------------------------
# Quality-of-life functions
# -----------------------------

# Fast open profile
function prof { npp $PROFILE 2>$null; if ($LASTEXITCODE) { notepad $PROFILE } }

# Reload profile
function rprof { . $PROFILE }

# Quick history file open
function hist {
    $path = (Get-PSReadLineOption).HistorySavePath
    if (Test-Path $path) { npp $path 2>$null; if ($LASTEXITCODE) { notepad $path } }
    else { "History file not found: $path" }
}

# Remove sensitive lines from history by regex
function hist-clean {
    param(
        [Parameter(Mandatory)][string]$Pattern
    )
    $path = (Get-PSReadLineOption).HistorySavePath
    if (-not (Test-Path $path)) { throw "History file not found: $path" }

    $content = Get-Content $path
    $filtered = $content | Where-Object { $_ -notmatch $Pattern }
    $filtered | Set-Content $path

    "Cleaned history: removed lines matching /$Pattern/ from $path"
}

# Dotfiles aliases
function Get-DotfilesRoot {
    # $PROFILE is a symlink -> target is inside repo
    $p = Get-Item -LiteralPath $PROFILE -ErrorAction Stop
    $profileReal = if ($p.LinkType -and $p.Target) { $p.Target } else { $PROFILE }

    # ...\dotfiles\powershell\Microsoft.PowerShell_profile.ps1 -> ...\dotfiles
    return (Resolve-Path (Join-Path (Split-Path $profileReal -Parent) "..")).Path
}

function dots {
    param(
        [Parameter(Position = 0)]
        [ValidateSet("install", "backup", "status", "diff", "save", "push", "root")]
        [string]$cmd = "status",

        [Parameter(Position = 1)]
        [string]$msg = "update dotfiles"
    )

    $repo = Get-DotfilesRoot
    $oldLoc = Get-Location
    $oldEA = $ErrorActionPreference
    $ErrorActionPreference = "Stop"

    try {
        if ($cmd -eq "root") { Write-Host $repo; return }

        Set-Location $repo
        Write-Host "→ dots $cmd @ $repo" -ForegroundColor DarkGray

        switch ($cmd) {
            "install" { & "$repo\scripts\install.ps1" | Out-Host }
            "backup" { & "$repo\scripts\backup.ps1" | Out-Host }
            "status" { & git status | Out-Host }
            "diff" { & git diff | Out-Host }
            "push" {
                & git push -u origin HEAD | Out-Host
                & git status | Out-Host
            }

            "save" {
                & "$repo\scripts\backup.ps1" | Out-Host
                & git add -A | Out-Host

                & git diff --cached --quiet
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "ℹ Nothing to commit." -ForegroundColor DarkGray
                    & git status | Out-Host
                    break
                }

                & git commit -m $msg | Out-Host
                & git status | Out-Host
            }

        }
    }
    catch {
        Write-Host "❌ dots $cmd failed: $($_.Exception.Message)" -ForegroundColor Red
    }
    finally {
        Set-Location $oldLoc
        $ErrorActionPreference = $oldEA
    }
}

# Docker helpers
function dps { docker ps }
function dcu { docker compose up -d }
function dcd { docker compose down }
function dcl { docker compose logs -f --tail 200 }

# Git helpers
function gs { git status }
function gl { git log --oneline --decorate -n 20 }