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
  } catch {
    return $false
  }
}

function Copy-IfNotSame {
  param(
    [Parameter(Mandatory)][string]$Src,
    [Parameter(Mandatory)][string]$Dst
  )

  Ensure-Dir (Split-Path -Parent $Dst)

  $srcFull = Full $Src
  $dstFull = Full $Dst

  # same path -> skip
  if ($srcFull -ieq $dstFull) {
    "ℹ Skip (same path): $Dst"
    return
  }

  # If src is a link to dst OR dst is a link to src -> skip
  if (Is-LinkTo $Src $Dst) {
    "ℹ Skip (src is link to dst): $Src -> $Dst"
    return
  }
  if (Is-LinkTo $Dst $Src) {
    "ℹ Skip (dst is link to src): $Dst -> $Src"
    return
  }

  # Copy by content (safe even if weird link semantics)
  $content = Get-Content -LiteralPath $Src -Raw
  Set-Content -LiteralPath $Dst -Value $content -Encoding UTF8
  "✅ Synced: $Src -> $Dst"
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

if (Get-Command winget -ErrorAction SilentlyContinue) {
  winget export -o (Join-Path $repo "exports\winget.json") --accept-source-agreements | Out-Null
}

if (Get-Command choco -ErrorAction SilentlyContinue) {
  # optional: only if you use choco
  # choco export --output-file-path (Join-Path $repo "exports\choco-packages.config") | Out-Null
}

Get-Module -ListAvailable |
  Select-Object -ExpandProperty Name -Unique |
  Sort-Object |
  Set-Content (Join-Path $repo "exports\modules.txt") -Encoding UTF8

"✅ Backup complete."
