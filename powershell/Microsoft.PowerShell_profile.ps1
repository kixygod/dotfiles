# -----------------------------
# Fast & safe profile bootstrap
# -----------------------------
$ErrorActionPreference = "SilentlyContinue"

function Import-IfAvailable {
    param(
        [Parameter(Mandatory)] [string] $Name
    )
    try {
        if (Get-Module -ListAvailable -Name $Name) {
            Import-Module $Name -ErrorAction SilentlyContinue
            return $true
        }
    } catch {}
    return $false
}

# -----------------------------
# Prompt (Starship)
# -----------------------------
if (Get-Command starship -ErrorAction SilentlyContinue) {
    Invoke-Expression (& starship init powershell)
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
function dots {
	param(
		[ValidateSet("install","backup")]$cmd
	)
	$repo = "$HOME\dotfiles"
	if ($cmd -eq "install") { & "$repo\scripts\install.ps1" }
	if ($cmd -eq "backup")  { & "$repo\scripts\backup.ps1" }
}

# Docker helpers
function dps { docker ps }
function dcu { docker compose up -d }
function dcd { docker compose down }
function dcl { docker compose logs -f --tail 200 }

# Git helpers
function gs { git status }
function gl { git log --oneline --decorate -n 20 }

# -----------------------------
# Environment niceties
# -----------------------------
$env:POWERSHELL_TELEMETRY_OPTOUT = "1"
$env:STARSHIP_CONFIG = "$HOME\.config\starship.toml"
