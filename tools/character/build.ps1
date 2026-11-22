<#
.SYNOPSIS
  Builds src\archive\pc\mod\WendellStripes.archive (the Stripes character and the cane of V) from base-game files.
.DESCRIPTION
  Needs WolvenKit CLI (`cp77tools`, dotnet global tool `wolvenkit.cli`) and Python 3.
  The CLI must be able to export a mesh without materials: its appsettings.json needs
    "MeshExportArgs": { "WithMaterials": false, "MaterialRepo": "<a folder>", "isGLBinary": true }
  All intermediate files go to .work\ in the repo (not in git). Base-game files are not copied into git.
#>
[CmdletBinding()]
param(
    [string]$GamePath = 'C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077'
)

$ErrorActionPreference = 'Stop'
$env:PATH += ";$env:USERPROFILE\.dotnet\tools"
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$work = Join-Path $repo '.work'
$base = Join-Path $work 'base'
$json = Join-Path $work 'json'
$raw  = Join-Path $work 'raw'
$mask = Join-Path $work 'mask'
$out  = Join-Path $work 'WendellStripes'
$content = Join-Path $GamePath 'archive\pc\content'

function Invoke-Cli {
    # Runs cp77tools and stops if its output has an error line.
    $lines = & cp77tools @args 2>&1 | ForEach-Object { $_.ToString() }
    $errors = $lines | Where-Object { $_ -match '\] - .*(Error|Exception)|^\[\s*\d+: Error' }
    if ($errors) { $errors | Select-Object -First 5 | Write-Host; throw "cp77tools $($args[0]) failed" }
}

foreach ($dir in $json, $raw, $mask, $out) {
    if (Test-Path $dir) { Remove-Item $dir -Recurse -Force -Confirm:$false }
    New-Item -ItemType Directory -Force $dir | Out-Null
}

# Base-game files, as paths below $base. The stripe masks are made for the meshes in $striped:
# name of the mask, mode (top or hat), texture size, band width in metres, half of the shoulder width in metres.
$garment = 'base\characters\garment'
$npcTop = "$garment\citizen_casual\torso\t1_004_tshirt__longsleeve\t1_004_ma_tshirt__longsleeve.mesh"
$npcHat = "$garment\citizen_casual\head\h1_003_hat__beanie\h1_003_ma_hat__beanie.mesh"
$striped = @(
    @{ Mesh = $npcTop; Name = 'ml_top_stripes'; Mode = 'top'; Size = 1024; Band = 0.038; Shoulder = 0.19; Target = 'characters\stripes\garment\textures' },
    @{ Mesh = $npcHat; Name = 'ml_hat_stripes'; Mode = 'hat'; Size = 512; Band = 0.022; Shoulder = 0.19; Target = 'characters\stripes\garment\textures' },
    @{ Mesh = 'base\environment\decoration\unique\npc_cane\npc_cane_a.mesh'; Name = 'ml_cane'; Mode = 'cane'; Size = 512; Band = 0.04; Shoulder = 0.19; Target = 'items\cane\textures' }
)
$sources = @($striped | ForEach-Object { $_.Mesh }) + @(
    # The cane: the material setup of the base cane weapon (source of the layers) and the weapon appearance files.
    'base\characters\main_npc\fingers\textures\ml_i1_001_ma_slot__fingers_cane.mlsetup',
    'base\weapons\melee\club_1h\cane\w_cane_appearances.app',
    'base\weapons\melee\club_1h\cane\appearances\w_cane_grip.app',
    # An icon atlas of the base game: the pattern for the atlas of the cane icon.
    'base\gameplay\gui\common\icons\items\item_icons3.inkatlas',
    "$garment\citizen_casual\legs\l1_028_pants__tight\l1_028_ma_pants__tight.mesh",
    'base\characters\entities\citizen\citizen__lowlife_ma.ent',
    'base\characters\appearances\citizen\citizen__lowlife_ma.app',
    "$garment\citizen_casual\head\h1_069_specs__round\h1_069_ma_specs__round.mesh",
    "$garment\light_crowd\torso\t1_004_tshirt__longsleeve_lc\textures\ml_t1_004_ma_tshirt__longsleeve_lc_new_stripes.mlsetup"
)

Write-Host '1/6 extract base-game files'
$pattern = '^(' + (($sources | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')$'
Invoke-Cli unbundle (Join-Path $content 'basegame_4_appearance.archive') -o $base -r $pattern
Invoke-Cli unbundle (Join-Path $content 'basegame_4_gamedata.archive') -o $base -r $pattern
foreach ($source in $sources) {
    if (-not (Test-Path (Join-Path $base $source))) { throw "not found in the game archives: $source" }
}

Write-Host '2/6 convert to JSON'
foreach ($source in $sources) { Invoke-Cli convert serialize (Join-Path $base $source) -o $json }

Write-Host '3/6 make the stripe masks'
$venv = Join-Path $work 'venv'
$python = Join-Path $venv 'Scripts\python.exe'
if (-not (Test-Path $python)) {
    python -m venv $venv
    & $python -m pip install -q numpy pillow
}
foreach ($item in $striped) {
    Invoke-Cli export (Join-Path $base $item.Mesh) -o $raw -gp $GamePath
    $glb = Join-Path $raw ([IO.Path]::GetFileNameWithoutExtension($item.Mesh) + '.glb')
    $dir = Join-Path $mask $item.Name
    & $python (Join-Path $PSScriptRoot 'make_stripe_mask.py') $glb $dir $item.Name $item.Size $item.Mode $item.Band $item.Shoulder
    if ($LASTEXITCODE -ne 0) { throw "make_stripe_mask.py failed ($($item.Name))" }
    Invoke-Cli import (Join-Path $dir "$($item.Name).masklist") -o $dir
}
# The inventory icon of the cane: draw it, make a texture of it, and give the texture to step 4 as JSON.
$icon = Join-Path $mask 'icon'
New-Item -ItemType Directory -Force $icon | Out-Null
& $python (Join-Path $PSScriptRoot 'make_cane_icon.py') (Join-Path $icon 'cane_icon.png')
if ($LASTEXITCODE -ne 0) { throw 'make_cane_icon.py failed' }
Invoke-Cli import (Join-Path $icon 'cane_icon.png') -o $icon
Invoke-Cli convert serialize (Join-Path $icon 'cane_icon.xbm') -o $json

Write-Host '4/6 build the character and item files'
& $python (Join-Path $PSScriptRoot 'build_character.py') $json $out
if ($LASTEXITCODE -ne 0) { throw 'build_character.py failed' }

Write-Host '5/6 convert to game files'
Invoke-Cli convert deserialize $out
# Delete the JSON sources: each one has the converted file next to it, with the same name less ".json".
Get-ChildItem $out -Recurse -Filter *.json | Where-Object { Test-Path ($_.FullName -replace '\.json$', '') -PathType Leaf } | Remove-Item -Force -Confirm:$false
foreach ($item in $striped) {
    $dir = Join-Path $out "wendellstripes\$($item.Target)"
    New-Item -ItemType Directory -Force $dir | Out-Null
    Copy-Item (Join-Path $mask "$($item.Name)\$($item.Name).mlmask") (Join-Path $dir "$($item.Name).mlmask")
}
if (-not (Test-Path (Join-Path $out 'wendellstripes\localization\en-us.json'))) { throw 'missing after conversion: localization' }
$expected = @(
    'characters\stripes\stripes.ent', 'characters\stripes\stripes.app',
    'characters\stripes\garment\t1_top_stripes.mesh', 'characters\stripes\garment\h1_hat_stripes.mesh',
    'characters\stripes\garment\textures\ml_stripes.mlsetup',
    'items\cane\cane.mesh', 'items\cane\cane_weapon.app', 'items\cane\cane_grip.app', 'items\cane\textures\ml_cane.mlsetup',
    'items\cane\cane_icon.inkatlas', 'items\cane\textures\cane_icon.xbm',
    'items\factory.csv'
)
foreach ($file in $expected) {
    if (-not (Test-Path (Join-Path $out "wendellstripes\$file") -PathType Leaf)) { throw "missing after conversion: $file" }
}
$left = Get-ChildItem $out -Recurse -Filter *.json | Where-Object { $_.Name -ne 'en-us.json' }
if ($left) { throw "not converted: $($left.Name -join ', ')" }

Write-Host '6/6 pack'
$target = Join-Path $repo 'src\archive\pc\mod'
Invoke-Cli pack $out -o $target
Get-Item (Join-Path $target 'WendellStripes.archive') | ForEach-Object { Write-Host "built $($_.FullName) ($([math]::Round($_.Length / 1KB)) KB)" }
