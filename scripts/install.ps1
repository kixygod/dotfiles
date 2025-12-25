param(
  [switch]$CopyInsteadOfSymlink
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
    # fallback to copy if symlink is not allowed
    Copy-Item $src $dst -Recurse -Force
  }
}

# --- PowerShell profile ---
$profilePath = $PROFILE
$profileSrc = Join-Path $repo "powershell\Microsoft.PowerShell_profile.ps1"
Link-Or-Copy $profileSrc $profilePath

# --- Starship config ---
$starshipDst = Join-Path $HOME ".config\starship.toml"
$starshipSrc = Join-Path $repo "starship\starship.toml"
Link-Or-Copy $starshipSrc $starshipDst

# --- Windows Terminal settings (optional) ---
$wtDst = Join-Path $env:LOCALAPPDATA "Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
$wtSrc = Join-Path $repo "windows-terminal\settings.json"
if (Test-Path $wtSrc) {
  Link-Or-Copy $wtSrc $wtDst
}

"✅ Installed dotfiles."
"Profile:  $profilePath"
"Starship: $starshipDst"
if (Test-Path $wtSrc) { "WT:       $wtDst" }
