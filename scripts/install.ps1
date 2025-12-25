param(
  [switch]$CopyInsteadOfSymlink,
  [switch]$SkipWingetRestore
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot

function Ensure-Dir($path) {
  if (-not (Test-Path $path)) { New-Item -ItemType Directory -Path $path | Out-Null }
}

function Backup-IfExists($path) {
  if (Test-Path $path) {
    $backup = "$path.bak.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item $path $backup -Recurse -Force
  }
}

function Link-Or-Copy($src, $dst) {
  Ensure-Dir (Split-Path -Parent $dst)
  Backup-IfExists $dst
  if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }

  if ($CopyInsteadOfSymlink) {
    Copy-Item $src $dst -Recurse -Force
    return
  }

  try {
    New-Item -ItemType SymbolicLink -Path $dst -Target $src | Out-Null
  }
  catch {
    Copy-Item $src $dst -Recurse -Force
  }
}

function Ensure-WingetPackage([string]$Id) {
  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { return }
  # quick check: list installed by id (not perfect but good enough)
  $found = winget list --id $Id 2>$null
  if (-not $found) {
    Write-Host "Installing: $Id" -ForegroundColor DarkGray
    winget install --id $Id -e --accept-package-agreements --accept-source-agreements | Out-Null
  }
}

function Ensure-PSModule([string]$Name) {
  try {
    if (-not (Get-Module -ListAvailable -Name $Name)) {
      Write-Host "Installing PS module: $Name" -ForegroundColor DarkGray
      Install-Module $Name -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
    }
  }
  catch {
    Write-Host "⚠ Could not install module $Name: $($_.Exception.Message)" -ForegroundColor Yellow
  }
}

# -----------------------------
# Bootstrap tools (optional)
# -----------------------------
if (Get-Command winget -ErrorAction SilentlyContinue) {
  # Ensure essentials you rely on
  Ensure-WingetPackage "Git.Git"
  Ensure-WingetPackage "Starship.Starship"
  Ensure-WingetPackage "Notepad++.Notepad++"
}

# PowerShell modules that improve UX (optional)
Ensure-PSModule "Terminal-Icons"
# PSReadLine is built-in, but latest versions can be installed; optional:
# Ensure-PSModule "PSReadLine"

# -----------------------------
# Restore winget set (optional)
# -----------------------------
if (-not $SkipWingetRestore -and (Get-Command winget -ErrorAction SilentlyContinue)) {
  $export = Join-Path $repo "exports\winget.json"
  if (Test-Path $export) {
    Write-Host "Restoring winget packages from exports\winget.json..." -ForegroundColor DarkGray
    winget import -i $export --accept-package-agreements --accept-source-agreements | Out-Host
  }
}

# -----------------------------
# Install dotfiles (links)
# -----------------------------
$profilePath = $PROFILE
$profileSrc = Join-Path $repo "powershell\Microsoft.PowerShell_profile.ps1"
Link-Or-Copy $profileSrc $profilePath

$starshipDst = Join-Path $HOME ".config\starship.toml"
$starshipSrc = Join-Path $repo "starship\starship.toml"
Link-Or-Copy $starshipSrc $starshipDst

$wtDst = Join-Path $env:LOCALAPPDATA "Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
$wtSrc = Join-Path $repo "windows-terminal\settings.json"
if (Test-Path $wtSrc) {
  Link-Or-Copy $wtSrc $wtDst
}

"✅ Installed dotfiles."
"Profile:  $profilePath"
"Starship: $starshipDst"
if (Test-Path $wtSrc) { "WT:       $wtDst" }
