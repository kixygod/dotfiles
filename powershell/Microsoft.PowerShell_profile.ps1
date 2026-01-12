# =====================================================
# PowerShell profile — work-focused dotfiles (Kixy)
# PowerShell 7+ recommended
# =====================================================

# -----------------------------
# Fast & safe profile bootstrap
# -----------------------------
$ErrorActionPreference = "Continue"

function Import-IfAvailable {
    param([Parameter(Mandatory)][string]$Name)
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
# Terminal capability detection
# -----------------------------
function Test-InteractiveTerminal {
    # 1) Должен быть интерактивный хост (не PowerShell -NonInteractive и т.п.)
    if (-not $Host.UI -or -not $Host.UI.RawUI) { return $false }

    # 2) Явно отключаем для известных "dumb" сред (IDE терминалы)
    if ($env:TERM_PROGRAM -match 'vscode|cursor' -or $env:CURSOR_EDITOR) { return $false }

    # 3) На Windows: проверяем, что это обычный интерактивный терминал
    if ($IsWindows) {
        # Проверяем, что это консольный хост (не скрипт/автоматизация)
        if ($Host.Name -eq 'ConsoleHost' -or $Host.Name -eq 'WindowsTerminal') {
            # Проверяем, что вывод не редиректнут (в обычном терминале это False)
            try {
                if ([Console]::IsOutputRedirected -or [Console]::IsErrorRedirected) { return $false }
            } catch { return $false }
            
            # Пытаемся включить VT для лучшей поддержки
            try {
                Add-Type -Namespace Win32 -Name Native -MemberDefinition @"
using System;
using System.Runtime.InteropServices;

public static class Native {
  [DllImport("kernel32.dll", SetLastError=true)] public static extern IntPtr GetStdHandle(int nStdHandle);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out int lpMode);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool SetConsoleMode(IntPtr hConsoleHandle, int dwMode);
}
"@ -ErrorAction SilentlyContinue | Out-Null

                $STD_OUTPUT_HANDLE = -11
                $ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004

                $h = [Win32.Native]::GetStdHandle($STD_OUTPUT_HANDLE)
                if ($h -ne [IntPtr]::Zero) {
                    $mode = 0
                    if ([Win32.Native]::GetConsoleMode($h, [ref]$mode)) {
                        # Пробуем включить VT (не критично, если не получится)
                        if (-not ($mode -band $ENABLE_VIRTUAL_TERMINAL_PROCESSING)) {
                            [Win32.Native]::SetConsoleMode($h, $mode -bor $ENABLE_VIRTUAL_TERMINAL_PROCESSING) | Out-Null
                        }
                    }
                }
            } catch {}
            
            return $true
        }
        return $false
    }

    # 4) Для *nix: проверяем на явно "dumb" терминалы
    if ($env:TERM -eq "dumb") { return $false }

    # 5) Проверка на редирект вывода
    try {
        if ([Console]::IsOutputRedirected -or [Console]::IsErrorRedirected) { return $false }
    } catch { return $false }

    # По умолчанию считаем терминал рабочим
    return $true
}

$script:IsRichTerminal = Test-InteractiveTerminal

# -----------------------------
# Prompt (Starship)
# -----------------------------
if ($script:IsRichTerminal -and (Get-Command starship -ErrorAction SilentlyContinue)) {
    Invoke-Expression (& starship init powershell)
}

# -----------------------------
# Aliases
# -----------------------------
Set-Alias c cls
if (Get-Command "notepad++" -ErrorAction SilentlyContinue) { Set-Alias npp notepad++ }

# -----------------------------
# PSReadLine (history, prediction, UX)
# -----------------------------
if ($script:IsRichTerminal) { Import-Module PSReadLine -Force }

Set-PSReadLineOption -EditMode Windows
Set-PSReadLineOption -BellStyle None
Set-PSReadLineOption -HistorySaveStyle SaveIncrementally
Set-PSReadLineOption -MaximumHistoryCount 10000

if ($script:IsRichTerminal) {
    # Включаем predictions только там, где есть VT
    try {
        Set-PSReadLineOption -PredictionSource HistoryAndPlugin -ErrorAction Stop
        Set-PSReadLineOption -PredictionViewStyle ListView -ErrorAction Stop
    } catch {}
} else {
    # В non-VT средах (Cursor, dumb, output capture) predictions должны быть выключены
    try {
        Set-PSReadLineOption -PredictionSource None -ErrorAction Stop
    } catch {}
}

Set-PSReadLineKeyHandler -Key Ctrl+r -Function ReverseSearchHistory
Set-PSReadLineKeyHandler -Key Ctrl+Shift+r -Function ForwardSearchHistory
Set-PSReadLineKeyHandler -Key UpArrow -Function PreviousHistory
Set-PSReadLineKeyHandler -Key DownArrow -Function NextHistory
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
# QoL functions
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

# =====================================================
# dots — dotfiles & work environment (NO FLAGS)
# =====================================================

function Get-DotfilesRoot {
    $p = Get-Item -LiteralPath $PROFILE -ErrorAction Stop
    $real = if ($p.LinkType -and $p.Target) { $p.Target } else { $PROFILE }
    return (Resolve-Path (Join-Path (Split-Path $real -Parent) "..")).Path
}

function dots-root {
    Write-Host (Get-DotfilesRoot)
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
            Write-Host "❌ $($c.Name): missing ($($c.Src))" -ForegroundColor Red
            continue
        }

        if (-not $item.LinkType) {
            Write-Host "⚠ $($c.Name): not a symlink ($($c.Src))" -ForegroundColor Yellow
            continue
        }

        if ($item.Target -ne $c.Dst) {
            Write-Host "⚠ $($c.Name): wrong target -> $($item.Target) (expected $($c.Dst))" -ForegroundColor Yellow
            continue
        }

        Write-Host "✅ $($c.Name)" -ForegroundColor Green
    }

    Write-Host "Repo: $repo" -ForegroundColor DarkGray
}

function dots-doctor {
    $ok = $true

    Write-Host "dots doctor — system checks" -ForegroundColor Cyan
    Write-Host ""

    # PowerShell
    Write-Host ("PowerShell: " + $PSVersionTable.PSVersion.ToString()) -ForegroundColor DarkGray

    # git
    if (Get-Command git -ErrorAction SilentlyContinue) {
        Write-Host ("Git:       " + (& git --version 2>$null)) -ForegroundColor DarkGray
    }
    else {
        Write-Host "❌ Git: not found" -ForegroundColor Red
        $ok = $false
    }

    # winget
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host ("winget:    " + (& winget --version 2>$null)) -ForegroundColor DarkGray
    }
    else {
        Write-Host "❌ winget: not found" -ForegroundColor Red
        $ok = $false
    }

    # starship
    if (Get-Command starship -ErrorAction SilentlyContinue) {
        Write-Host ("Starship:  " + (& starship --version 2>$null)) -ForegroundColor DarkGray
    }
    else {
        Write-Host "⚠ Starship: not found (prompt falls back to default)" -ForegroundColor Yellow
    }

    Write-Host ""
    if ($ok) { Write-Host "✅ doctor: OK" -ForegroundColor Green }
    else { Write-Host "❌ doctor: problems found" -ForegroundColor Red }
}

# -----------------------------
# Apps management (ALLOWLIST based)
# -----------------------------
function dots-apps-paths {
    $repo = Get-DotfilesRoot
    return @{
        Repo      = $repo
        Allowlist = (Join-Path $repo "exports\winget.allowlist.txt")
        WorkJson  = (Join-Path $repo "exports\winget.work.json")
    }
}

function dots-apps-read-allowlist {
    $p = dots-apps-paths
    $allow = $p.Allowlist

    if (-not (Test-Path $allow)) {
        throw ("allowlist not found: " + $allow + "`nCreate it: dotfiles/exports/winget.allowlist.txt")
    }

    $items =
    Get-Content -LiteralPath $allow -ErrorAction Stop |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and -not $_.StartsWith("#") } |
    Sort-Object -Unique

    return $items
}

function dots-apps-export {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw "winget not found" }

    $p = dots-apps-paths
    $ids = dots-apps-read-allowlist

    # IMPORTANT:
    # winget import validates CreationDate as date-time; must be ISO 8601 with timezone (Z).
    $creation = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

    $doc = [ordered]@{
        '$schema'    = 'https://aka.ms/winget-packages.schema.2.0.json'
        CreationDate = $creation
        Sources      = @(
            @{
                Packages      = @()
                SourceDetails = @{
                    Argument   = "https://cdn.winget.microsoft.com/cache"
                    Identifier = "Microsoft.Winget.Source_8wekyb3d8bbwe"
                    Name       = "winget"
                    Type       = "Microsoft.PreIndexed.Package"
                }
            }
        )
    }

    foreach ($id in $ids) {
        $doc.Sources[0].Packages += @{ PackageIdentifier = $id }
    }

    $json = ($doc | ConvertTo-Json -Depth 32)
    Set-Content -LiteralPath $p.WorkJson -Value ($json + "`n") -Encoding UTF8

    Write-Host "✅ exported work apps -> $($p.WorkJson)" -ForegroundColor Green
    Write-Host "   source: allowlist -> $($p.Allowlist)" -ForegroundColor DarkGray
}

function dots-apps-sync {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw "winget not found" }

    $p = dots-apps-paths
    if (-not (Test-Path $p.WorkJson)) {
        Write-Host "ℹ $($p.WorkJson) not found. Running: dots apps export" -ForegroundColor DarkGray
        dots-apps-export
    }

    Write-Host "→ winget import (work allowlist)" -ForegroundColor DarkGray
    winget import -i $p.WorkJson --accept-package-agreements --accept-source-agreements | Out-Host
}

function dots-apps-upgrade {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw "winget not found" }

    Write-Host "→ winget upgrade --all --include-unknown" -ForegroundColor DarkGray
    winget upgrade --all --include-unknown --accept-package-agreements --accept-source-agreements | Out-Host
}

function dots-apps-diff {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw "winget not found" }

    $allow = dots-apps-read-allowlist

    # Get installed identifiers via winget export (reliable, no ARP garbage)
    $tmp = [System.IO.Path]::GetTempFileName()
    try {
        winget export -o $tmp --accept-source-agreements | Out-Null
        $raw = Get-Content -LiteralPath $tmp -Raw -ErrorAction Stop
        $obj = $raw | ConvertFrom-Json -ErrorAction Stop

        $installed = @()
        foreach ($s in $obj.Sources) {
            foreach ($pkg in $s.Packages) {
                if ($pkg.PackageIdentifier) { $installed += $pkg.PackageIdentifier }
            }
        }
        $installed = $installed | Sort-Object -Unique

        $missing = $allow | Where-Object { $_ -notin $installed }
        $extra = $installed | Where-Object { $_ -notin $allow }

        Write-Host ""
        Write-Host "Missing (in allowlist but not installed):" -ForegroundColor Yellow
        if ($missing.Count -eq 0) { Write-Host "  (none)" -ForegroundColor DarkGray }
        else { $missing | ForEach-Object { Write-Host $_ } }

        Write-Host ""
        Write-Host "Extra (installed but not in allowlist):" -ForegroundColor Yellow
        if ($extra.Count -eq 0) { Write-Host "  (none)" -ForegroundColor DarkGray }
        else { $extra | ForEach-Object { Write-Host $_ } }

        Write-Host ""
        Write-Host ("Allowlist:  " + (dots-apps-paths).Allowlist) -ForegroundColor DarkGray
    }
    finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}

# -----------------------------
# Dotfiles scripts
# -----------------------------
function dots-install {
    $repo = Get-DotfilesRoot
    Push-Location $repo
    try { & "$repo\scripts\install.ps1" }
    finally { Pop-Location }
}

function dots-backup {
    $repo = Get-DotfilesRoot
    Push-Location $repo
    try { & "$repo\scripts\backup.ps1" }
    finally { Pop-Location }
}

# -----------------------------
# Git helpers in repo
# -----------------------------
function dots-status {
    $repo = Get-DotfilesRoot
    Push-Location $repo
    try { git status }
    finally { Pop-Location }
}

function dots-diff {
    $repo = Get-DotfilesRoot
    Push-Location $repo
    try { git diff }
    finally { Pop-Location }
}

function dots-save {
    $repo = Get-DotfilesRoot
    Push-Location $repo
    try {
        & "$repo\scripts\backup.ps1"
        git add -A
        git status
        git diff --cached --stat
        Write-Host 'ℹ Saved locally (staged). Next: dots commit "msg"' -ForegroundColor DarkGray
    }
    finally { Pop-Location }
}

function dots-commit {
    param([Parameter(Mandatory)][string]$Message)

    $repo = Get-DotfilesRoot
    Push-Location $repo
    try {
        git diff --cached --quiet
        if ($LASTEXITCODE -eq 0) {
            Write-Host "ℹ Nothing staged. Run: dots save" -ForegroundColor DarkGray
            git status
            return
        }
        git commit -m $Message
        git status
    }
    finally { Pop-Location }
}

function dots-push {
    $repo = Get-DotfilesRoot
    Push-Location $repo
    try {
        git push -u origin HEAD
        git status
    }
    finally { Pop-Location }
}

# -----------------------------
# Main dispatcher (no flags, only commands)
# -----------------------------
function dots {
    param(
        [Parameter(Position = 0)][string]$Command = "help",
        [Parameter(Position = 1)][string]$Arg1,
        [Parameter(Position = 2)][string]$Arg2
    )

    try {
        switch ($Command) {
            "help" {
                @"
dots — dotfiles & work environment

Core:
  dots doctor
  dots check
  dots root

Dotfiles:
  dots install
  dots backup

Git:
  dots status
  dots diff
  dots save
  dots commit "msg"
  dots push

Apps (allowlist-based):
  dots apps export   (allowlist -> exports/winget.work.json)
  dots apps sync     (install missing from exports/winget.work.json)
  dots apps upgrade  (upgrade everything)
  dots apps diff     (installed vs allowlist)

Files:
  exports/winget.allowlist.txt   (YOU maintain)
  exports/winget.work.json       (auto-generated)

Suggested routine:
  dots doctor
  dots apps diff
  dots apps export
  dots apps sync
"@ | Write-Host
            }

            "root" { dots-root }
            "check" { dots-check }
            "doctor" { dots-doctor }

            "install" { dots-install }
            "backup" { dots-backup }

            "status" { dots-status }
            "diff" { dots-diff }
            "save" { dots-save }
            "commit" {
                if (-not $Arg1) { throw 'Commit message required: dots commit "msg"' }
                dots-commit -Message $Arg1
            }
            "push" { dots-push }

            "apps" {
                switch ($Arg1) {
                    "export" { dots-apps-export }
                    "sync" { dots-apps-sync }
                    "upgrade" { dots-apps-upgrade }
                    "diff" { dots-apps-diff }
                    default {
                        Write-Host "Unknown apps command: $Arg1" -ForegroundColor Red
                        Write-Host "Use: dots apps export | sync | upgrade | diff" -ForegroundColor DarkGray
                    }
                }
            }

            default {
                Write-Host "Unknown command: $Command" -ForegroundColor Red
                Write-Host "Run: dots help" -ForegroundColor DarkGray
            }
        }
    }
    catch {
        Write-Host "Exception: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# -----------------------------
# Docker helpers
# -----------------------------
function dps { docker ps }
function dcu { docker compose up -d }
function dcd { docker compose down }
function dcl { docker compose logs -f --tail 200 }

# -----------------------------
# Git shortcuts
# -----------------------------
function gs { git status }
function gl { git log --oneline --decorate -n 20 }
function gd { git diff }
