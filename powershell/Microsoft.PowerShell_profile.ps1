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
# Aliases
# -----------------------------
Set-Alias c cls

if (Get-Command "notepad++" -ErrorAction SilentlyContinue) {
    Set-Alias npp notepad++
}

# -----------------------------
# PSReadLine (history, prediction, UX)
# -----------------------------
Import-Module PSReadLine -Force

Set-PSReadLineOption -EditMode Windows
Set-PSReadLineOption -BellStyle None
Set-PSReadLineOption -HistorySaveStyle SaveIncrementally
Set-PSReadLineOption -MaximumHistoryCount 10000

Set-PSReadLineOption -PredictionSource HistoryAndPlugin
Set-PSReadLineOption -PredictionViewStyle ListView

Set-PSReadLineKeyHandler -Key Ctrl+r -Function ReverseSearchHistory
Set-PSReadLineKeyHandler -Key Ctrl+Shift+r -Function ForwardSearchHistory
Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete

# -----------------------------
# History hygiene (avoid leaking secrets)
# -----------------------------
Set-PSReadLineOption -AddToHistoryHandler {
    param([string]$line)

    if ([string]::IsNullOrWhiteSpace($line)) { return $false }

    $secretPattern = @(
        "password", "passwd", "pwd",
        "token", "apikey", "api_key",
        "secret", "client_secret",
        "authorization\s*:",
        "bearer\s+",
        "PRIVATE KEY", "BEGIN RSA", "BEGIN OPENSSH"
    ) -join "|"

    if ($line -match $secretPattern) { return $false }
    if ($line -match "setx\s+(TOKEN|APIKEY|SECRET|PASSWORD)\b") { return $false }

    return $true
}

# -----------------------------
# Quality-of-life functions
# -----------------------------

function prof { npp $PROFILE 2>$null; if ($LASTEXITCODE) { notepad $PROFILE } }
function rprof { . $PROFILE }

function hist {
    $path = (Get-PSReadLineOption).HistorySavePath
    if (Test-Path $path) { npp $path 2>$null; if ($LASTEXITCODE) { notepad $path } }
    else { "History file not found: $path" }
}

function hist-clean {
    param([Parameter(Mandatory)][string]$Pattern)
    $path = (Get-PSReadLineOption).HistorySavePath
    if (-not (Test-Path $path)) { throw "History file not found: $path" }

    $content = Get-Content $path
    $filtered = $content | Where-Object { $_ -notmatch $Pattern }
    $filtered | Set-Content $path -Encoding UTF8

    "Cleaned history: removed lines matching /$Pattern/ from $path"
}

# -----------------------------
# Dotfiles helpers
# -----------------------------
function Get-DotfilesRoot {
    $p = Get-Item -LiteralPath $PROFILE -ErrorAction Stop
    $profileReal = if ($p.LinkType -and $p.Target) { $p.Target } else { $PROFILE }
    return (Resolve-Path (Join-Path (Split-Path $profileReal -Parent) "..")).Path
}

function dots {
    param(
        [Parameter(Position = 0)]
        [ValidateSet("help", "install", "backup", "save", "commit", "push", "status", "diff", "check", "root")]
        [string]$cmd = "status",

        [Parameter(Position = 1)]
        [string]$msg = "update dotfiles"
    )

    $repo = Get-DotfilesRoot
    $oldLoc = Get-Location
    $oldEA = $ErrorActionPreference
    $ErrorActionPreference = "Stop"

    try {
        if ($cmd -eq "help") {
            @"
dots — dotfiles helper (PowerShell)

Usage:
  dots <command> [args]

Commands:
  help
    Show this help.

  status
    Show repo status.
    Usage: dots status

  diff
    Show working tree diff (unstaged + staged view depends on git config).
    Usage: dots diff

  root
    Print dotfiles repo path.
    Usage: dots root

  install
    Apply dotfiles to system (runs scripts/install.ps1).
    Usage: dots install

  backup
    Sync current system configs into the repo (runs scripts/backup.ps1).
    Usage: dots backup

  save
    backup + stage all changes + show status + staged summary.
    Usage: dots save

  commit
    Commit staged changes with message.
    Usage: dots commit "message"
    Notes:
      - If nothing is staged: prints "Nothing staged. Run: dots save"

  push
    Push current HEAD to origin (sets upstream).
    Usage: dots push

  check
    Health check: verify symlinks/targets (dots-check).
    Usage: dots check

Typical flow:
  dots save
  dots commit "your message"
  dots push
"@ | Write-Host
            return
        }

        if ($cmd -eq "root") { Write-Host $repo; return }

        if (-not (Test-Path $repo)) { throw "dotfiles repo not found: $repo" }
        Set-Location $repo

        Write-Host "→ dots $cmd @ $repo" -ForegroundColor DarkGray

        switch ($cmd) {
            "install" { & "$repo\scripts\install.ps1" | Out-Host }

            "backup" { & "$repo\scripts\backup.ps1" | Out-Host }

            # save = local prep: backup + stage + show status
            "save" {
                & "$repo\scripts\backup.ps1" | Out-Host
                & git add -A | Out-Host
                & git status | Out-Host
                & git diff --cached --stat | Out-Host
                Write-Host "ℹ Saved locally (staged). Next: dots commit ""msg"" then dots push" -ForegroundColor DarkGray
            }

            # commit = only commit
            "commit" {
                & git diff --cached --quiet
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "ℹ Nothing staged. Run: dots save" -ForegroundColor DarkGray
                    & git status | Out-Host
                    break
                }

                & git commit -m $msg | Out-Host
                & git status | Out-Host
            }

            # push = only push
            "push" {
                & git push -u origin HEAD | Out-Host
                & git status | Out-Host
            }

            "status" { & git status | Out-Host }
            "diff" { & git diff | Out-Host }

            "check" { dots-check }
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


function dots-check {
    $repo = Get-DotfilesRoot

    $checks = @(
        @{ Name = "Profile"; Src = $PROFILE; Dst = (Join-Path $repo "powershell\Microsoft.PowerShell_profile.ps1") },
        @{ Name = "Starship"; Src = (Join-Path $HOME ".config\starship.toml"); Dst = (Join-Path $repo "starship\starship.toml") },
        @{ Name = "Windows Terminal"; Src = (Join-Path $env:LOCALAPPDATA "Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"); Dst = (Join-Path $repo "windows-terminal\settings.json") }
    )

    foreach ($c in $checks) {
        $item = Get-Item -LiteralPath $c.Src -ErrorAction SilentlyContinue

        if (-not $item) {
            Write-Host "❌ $($c.Name): missing $($c.Src)" -ForegroundColor Red
            continue
        }

        if (-not $item.LinkType) {
            Write-Host "⚠ $($c.Name): not a symlink ($($c.Src))" -ForegroundColor Yellow
            continue
        }

        if (($item.Target) -ne $c.Dst) {
            Write-Host "⚠ $($c.Name): points to $($item.Target) (expected $($c.Dst))" -ForegroundColor Yellow
            continue
        }

        Write-Host "✅ $($c.Name)" -ForegroundColor Green
    }

    Write-Host "Repo: $repo" -ForegroundColor DarkGray
}

# -----------------------------
# Docker helpers
# -----------------------------
function dps { docker ps }
function dcu { docker compose up -d }
function dcd { docker compose down }
function dcl { docker compose logs -f --tail 200 }

# -----------------------------
# Git helpers
# -----------------------------
function gs { git status }
function gl { git log --oneline --decorate -n 20 }
