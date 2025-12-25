$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot

function Ensure-Dir($path) {
  if (-not (Test-Path $path)) { New-Item -ItemType Directory -Path $path | Out-Null }
}

# PowerShell profile
Ensure-Dir (Join-Path $repo "powershell")
Copy-Item $PROFILE (Join-Path $repo "powershell\Microsoft.PowerShell_profile.ps1") -Force

# Starship
Ensure-Dir (Join-Path $repo "starship")
$starshipPath = Join-Path $HOME ".config\starship.toml"
if (Test-Path $starshipPath) {
  Copy-Item $starshipPath (Join-Path $repo "starship\starship.toml") -Force
}

# Windows Terminal
$wtPath = Join-Path $env:LOCALAPPDATA "Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
Ensure-Dir (Join-Path $repo "windows-terminal")
if (Test-Path $wtPath) {
  Copy-Item $wtPath (Join-Path $repo "windows-terminal\settings.json") -Force
}

# Exports
Ensure-Dir (Join-Path $repo "exports")
if (Get-Command winget -ErrorAction SilentlyContinue) {
  winget export -o (Join-Path $repo "exports\winget.json") --accept-source-agreements
}

# Modules list (optional)
Ensure-Dir (Join-Path $repo "exports")
Get-Module -ListAvailable | Select-Object -ExpandProperty Name -Unique |
  Sort-Object |
  Set-Content (Join-Path $repo "exports\modules.txt")

"✅ Backup complete."
