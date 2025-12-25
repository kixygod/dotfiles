[CmdletBinding()]
param(
  [switch]$CopyInsteadOfSymlink,
  [switch]$Winget,
  [switch]$WingetUpgrade,
  [switch]$SkipBootstrap
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

function Ensure-PSModule([string]$Name) {
  try {
    if (-not (Get-Module -ListAvailable -Name $Name)) {
      Write-Host "Installing PS module: $Name" -ForegroundColor DarkGray
      Install-Module $Name -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
    }
  }
  catch {
    Write-Host "⚠ Could not install module $Name : $($_.Exception.Message)" -ForegroundColor Yellow
  }
}

# -----------------------------
# Make --winget-upgrade work alone
# -----------------------------
if ($WingetUpgrade) {
  $Winget = $true
}

# -----------------------------
# Optional bootstrap (fast UX stuff)
# -----------------------------
if (-not $SkipBootstrap) {
  Ensure-PSModule "Terminal-Icons"
}

# -----------------------------
# Optional winget restore
# -----------------------------
if ($Winget) {
  if (Get-Command winget -ErrorAction SilentlyContinue) {
    $export = Join-Path $repo "exports\winget.json"
    if (Test-Path $export) {
      Write-Host "Restoring winget packages from exports\winget.json..." -ForegroundColor DarkGray

      $importArgs = @(
        "import", "-i", $export,
        "--accept-package-agreements",
        "--accept-source-agreements"
      )

      if ($WingetUpgrade) {
        $importArgs += "--include-unknown"
      }

      & winget @importArgs | Out-Host
    }
    else {
      Write-Host "ℹ exports\winget.json not found, skipping winget import." -ForegroundColor DarkGray
    }
  }
  else {
    Write-Host "ℹ winget not found, skipping winget import." -ForegroundColor DarkGray
  }
}
else {
  Write-Host "ℹ Winget restore skipped (default). Use: dots install --winget (or --winget-upgrade)" -ForegroundColor DarkGray
}

# -----------------------------
# Install dotfiles (links/copy)
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
