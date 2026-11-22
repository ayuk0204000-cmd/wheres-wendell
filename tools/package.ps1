<#
.SYNOPSIS
  Makes the release package: dist\WendellStripes-<version>.zip.
.DESCRIPTION
  The zip has the layout of the game folder (archive\, r6\), so it installs through Vortex and
  by extraction into the game folder. It holds only these files:
    r6\scripts\WendellStripes\*.reds
    r6\tweaks\WendellStripes\*.yaml
    archive\pc\mod\WendellStripes.archive
    archive\pc\mod\WendellStripes.archive.xl
  The archive file is not in git. Use -Build to make it new (needs the game and WolvenKit CLI),
  or run tools\character\build.ps1 before this script.
.EXAMPLE
  .\tools\package.ps1 -Version 1.0.0 -Build
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version,
    [switch]$Build
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$src = Join-Path $repo 'src'
$dist = Join-Path $repo 'dist'
$stage = Join-Path $dist 'stage'
$zip = Join-Path $dist "WendellStripes-$Version.zip"

if ($Build) {
    & (Join-Path $PSScriptRoot 'character\build.ps1')
}

$archive = Join-Path $src 'archive\pc\mod\WendellStripes.archive'
if (-not (Test-Path $archive)) { throw 'WendellStripes.archive is missing. Use -Build.' }
# The archive must be newer than the tools that make it.
$newest = Get-ChildItem (Join-Path $PSScriptRoot 'character') -File | Sort-Object LastWriteTime | Select-Object -Last 1
if ($newest.LastWriteTime -gt (Get-Item $archive).LastWriteTime) {
    throw "WendellStripes.archive is older than tools\character\$($newest.Name). Use -Build."
}

# The debug settings must be off in a release.
$settings = Get-Content (Join-Path $src 'r6\scripts\WendellStripes\Settings.reds') -Raw
foreach ($name in 'debugMode', 'forgetMeetings') {
    if ($settings -notmatch "public let ${name}: Bool = false;") { throw "Settings.reds: the default of $name is not false." }
}

if (Test-Path $stage) { Remove-Item $stage -Recurse -Force -Confirm:$false }
if (Test-Path $zip) { Remove-Item $zip -Force -Confirm:$false }
New-Item -ItemType Directory -Force $stage | Out-Null

$files = @(Get-ChildItem (Join-Path $src 'r6\scripts\WendellStripes') -Filter *.reds -File) +
         @(Get-ChildItem (Join-Path $src 'r6\tweaks\WendellStripes') -Filter *.yaml -File) +
         @(Get-Item $archive, "$archive.xl")
foreach ($file in $files) {
    $rel = $file.FullName.Substring($src.Length + 1)
    $to = Join-Path $stage $rel
    New-Item -ItemType Directory -Force (Split-Path $to -Parent) | Out-Null
    Copy-Item $file.FullName $to
}

Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -CompressionLevel Optimal

# Check the zip: its entries must be the staged files, with paths from the game folder.
Add-Type -AssemblyName System.IO.Compression.FileSystem
$reader = [IO.Compression.ZipFile]::OpenRead($zip)
try {
    $entries = @($reader.Entries | Where-Object { $_.Length -gt 0 -or -not $_.FullName.EndsWith('/') } | ForEach-Object { $_.FullName.Replace('\', '/') })
} finally {
    $reader.Dispose()
}
$expected = @($files | ForEach-Object { $_.FullName.Substring($src.Length + 1).Replace('\', '/') })
$difference = Compare-Object ($entries | Sort-Object) ($expected | Sort-Object)
if ($difference) { throw "The zip does not hold the expected files: $($difference | Out-String)" }
if ($entries | Where-Object { $_ -notmatch '^(archive/pc/mod|r6/scripts/WendellStripes|r6/tweaks/WendellStripes)/' }) { throw 'The zip has a file outside the mod paths.' }

Remove-Item $stage -Recurse -Force -Confirm:$false
$entries | Sort-Object | ForEach-Object { Write-Host "  $_" }
Write-Host "package: $zip ($([math]::Round((Get-Item $zip).Length / 1KB)) KB, $($entries.Count) files)"
