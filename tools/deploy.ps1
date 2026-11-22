<#
.SYNOPSIS
  Copies the mod from src/ into the Cyberpunk 2077 folder, or removes it.
.DESCRIPTION
  Touches only these paths in the game folder:
    r6\scripts\WendellStripes\
    r6\tweaks\WendellStripes\
    archive\pc\mod\WendellStripes.archive
    archive\pc\mod\WendellStripes.archive.xl
#>
[CmdletBinding()]
param(
    [string]$GamePath = 'C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077',
    [switch]$Remove
)

$ErrorActionPreference = 'Stop'
$src = Join-Path (Split-Path $PSScriptRoot -Parent) 'src'

if (-not (Test-Path (Join-Path $GamePath 'bin\x64\Cyberpunk2077.exe'))) {
    throw "Cyberpunk2077.exe not found below '$GamePath'. Use -GamePath."
}

$dirs  = @('r6\scripts\WendellStripes', 'r6\tweaks\WendellStripes')
$files = @('archive\pc\mod\WendellStripes.archive', 'archive\pc\mod\WendellStripes.archive.xl')

# Start from a clean state so that files deleted from src/ do not stay in the game.
foreach ($rel in $dirs + $files) {
    $target = Join-Path $GamePath $rel
    if (Test-Path $target) {
        Remove-Item $target -Recurse -Force -Confirm:$false
        Write-Host "removed  $rel"
    }
}

if ($Remove) {
    Write-Host 'Mod removed from the game folder.'
    return
}

foreach ($rel in $dirs) {
    $from = Join-Path $src $rel
    if (-not (Test-Path $from)) { continue }
    if (-not (Get-ChildItem $from -Recurse -File -Exclude '.gitkeep')) { continue }
    $to = Join-Path $GamePath $rel
    New-Item -ItemType Directory -Force $to | Out-Null
    Copy-Item (Join-Path $from '*') $to -Recurse -Force -Exclude '.gitkeep'
    Write-Host "copied   $rel"
}

foreach ($rel in $files) {
    $from = Join-Path $src $rel
    if (-not (Test-Path $from)) { continue }
    Copy-Item $from (Join-Path $GamePath $rel) -Force
    Write-Host "copied   $rel"
}

Write-Host 'Mod deployed. Start the game to compile the scripts.'
