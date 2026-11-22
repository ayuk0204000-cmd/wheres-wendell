<#
.SYNOPSIS
  Compiles the mod's scripts with the game's own redscript compiler, without the game.

.DESCRIPTION
  Makes a copy of the game's script cache and of src\r6\scripts in a temporary folder and
  runs <game>\engine\tools\scc.exe on the copy. Nothing in the game folder is written.
  The scripts of the necessary mods (Codeware, ArchiveXL, TweakXL, Mod Settings) are read
  from the game folder.

  The exit code is 0 only if the compile has no error.
#>
param(
    [string]$GamePath = 'C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077'
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot

$scc = Join-Path $GamePath 'engine\tools\scc.exe'
$cache = Join-Path $GamePath 'r6\cache\final.redscripts'
foreach ($f in $scc, $cache) {
    if (-not (Test-Path $f)) { throw "Not found: $f" }
}

$plugins = Join-Path $GamePath 'red4ext\plugins'
$pluginScripts = @(
    (Join-Path $plugins 'ArchiveXL\Scripts'),
    (Join-Path $plugins 'Codeware\Scripts'),
    (Join-Path $plugins 'TweakXL\Scripts'),
    (Join-Path $plugins 'mod_settings\packed.reds'),
    (Join-Path $plugins 'mod_settings\module.reds')
)
foreach ($p in $pluginScripts) {
    if (-not (Test-Path $p)) { throw "Necessary mod not found: $p" }
}

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("WendellStripes-compile-" + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Force (Join-Path $work 'r6\cache'), (Join-Path $work 'r6\out') | Out-Null
    Copy-Item $cache (Join-Path $work 'r6\cache')
    Copy-Item -Recurse (Join-Path $repo 'src\r6\scripts') (Join-Path $work 'r6\scripts')
    $pathsFile = Join-Path $work 'paths.txt'
    $pluginScripts | Set-Content $pathsFile -Encoding utf8

    $output = & $scc -compile (Join-Path $work 'r6\scripts') -customCacheDir (Join-Path $work 'r6\out') -compilePathsFile $pathsFile 2>&1
    $code = $LASTEXITCODE
    $output | Where-Object { "$_" -notmatch '\.reds$' } | ForEach-Object { "$_" }

    $ok = $code -eq 0 -and (Test-Path (Join-Path $work 'r6\out\final.redscripts')) -and
        -not ($output | Where-Object { "$_" -match '^\[ERROR' })
    if (-not $ok) {
        Write-Host 'Compile check: FAILED' -ForegroundColor Red
        exit 1
    }
    Write-Host 'Compile check: no error' -ForegroundColor Green
}
finally {
    if (Test-Path $work) { Remove-Item -Recurse -Force $work -Confirm:$false }
}
