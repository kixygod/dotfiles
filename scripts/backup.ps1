$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot

function Ensure-Dir($path) {
  if (-not (Test-Path $path)) { New-Item -ItemType Directory -Path $path | Out-Null }
}

function Full($p) {
  try { return [System.IO.Path]::GetFullPath($p) } catch { return $p }
}

function Is-LinkTo($path, $target) {
  try {
    $item = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
    if (-not $item) { return $false }
    if (-not $item.LinkType) { return $false }
    $t = $item.Target
    if (-not $t) { return $false }
    return (Full $t) -ieq (Full $target)
  }
  catch { return $false }
}

function Copy-IfNotSame {
  param(
    [Parameter(Mandatory)][string]$Src,
    [Parameter(Mandatory)][string]$Dst
  )

  Ensure-Dir (Split-Path -Parent $Dst)

  $srcFull = Full $Src
  $dstFull = Full $Dst

  if ($srcFull -ieq $dstFull) {
    "ℹ Skip (same path): $Dst"
    return
  }

  if (Is-LinkTo $Src $Dst) {
    "ℹ Skip (src is link to dst): $Src -> $Dst"
    return
  }
  if (Is-LinkTo $Dst $Src) {
    "ℹ Skip (dst is link to src): $Dst -> $Src"
    return
  }

  $content = Get-Content -LiteralPath $Src -Raw
  Set-Content -LiteralPath $Dst -Value $content -Encoding UTF8
  "✅ Synced: $Src -> $Dst"
}

function Write-IfChanged {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Content
  )

  Ensure-Dir (Split-Path -Parent $Path)

  if (Test-Path $Path) {
    $existing = Get-Content -LiteralPath $Path -Raw
    if ($existing -eq $Content) {
      "ℹ No change: $Path"
      return $false
    }
  }

  Set-Content -LiteralPath $Path -Value $Content -Encoding UTF8
  "✅ Updated: $Path"
  return $true
}

function Normalize-WingetExportJson([string]$Path) {
  $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
  $obj = $raw | ConvertFrom-Json -ErrorAction Stop

  # Reduce noise: CreationDate changes every export
  if ($null -ne $obj.CreationDate) {
    $obj.PSObject.Properties.Remove("CreationDate")
  }

  return ($obj | ConvertTo-Json -Depth 64)
}

function Export-WingetIfChanged {
  param([Parameter(Mandatory)][string]$OutPath)

  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    "ℹ winget not found, skipping export."
    return
  }

  $tmp = [System.IO.Path]::GetTempFileName()
  try {
    winget export -o $tmp --accept-source-agreements | Out-Null

    $normalized = Normalize-WingetExportJson -Path $tmp
    if (-not $normalized.EndsWith("`n")) { $normalized += "`n" }

    Write-IfChanged -Path $OutPath -Content $normalized | Out-Null
  }
  finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
  }
}

# -----------------------------
# PowerShell profile
# -----------------------------
$dstProfile = Join-Path $repo "powershell\Microsoft.PowerShell_profile.ps1"
$srcProfile = $PROFILE
Copy-IfNotSame -Src $srcProfile -Dst $dstProfile

# -----------------------------
# Starship
# -----------------------------
$dstStarship = Join-Path $repo "starship\starship.toml"
$srcStarship = Join-Path $HOME ".config\starship.toml"
if (Test-Path $srcStarship) {
  Copy-IfNotSame -Src $srcStarship -Dst $dstStarship
}

# -----------------------------
# Windows Terminal
# -----------------------------
$srcWT = Join-Path $env:LOCALAPPDATA "Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
$dstWT = Join-Path $repo "windows-terminal\settings.json"
if (Test-Path $srcWT) {
  Copy-IfNotSame -Src $srcWT -Dst $dstWT
}

# -----------------------------
# Exports
# -----------------------------
Ensure-Dir (Join-Path $repo "exports")

Export-WingetIfChanged -OutPath (Join-Path $repo "exports\winget.json")

# Modules list (only update file if content changed)
$modulesPath = Join-Path $repo "exports\modules.txt"
$modules = Get-Module -ListAvailable |
Select-Object -ExpandProperty Name -Unique |
Sort-Object

$modulesContent = ($modules -join "`n") + "`n"
Write-IfChanged -Path $modulesPath -Content $modulesContent | Out-Null

"✅ Backup complete."
