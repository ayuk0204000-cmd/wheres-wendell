<#
.SYNOPSIS
  Makes the next commit on the branch `public`: the files of `main` less the internal files.
.DESCRIPTION
  `main` is the internal branch. `public` has its own history, with no commit of `main` in it,
  and it is the only branch that goes to the public repository (remote `github`, branch `main`).
  This script changes no file in the work folder and it does not push.
.EXAMPLE
  .\tools\publish.ps1 -Message "Version 1.0.1"
  git push github
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Message
)

$ErrorActionPreference = 'Stop'
# Files that stay internal.
$internal = @('CLAUDE.md', 'rare-encounter-mod-plan.md')

function Invoke-Git {
    $out = & git @args
    if ($LASTEXITCODE -ne 0) { throw "git $($args -join ' ') failed" }
    return $out
}

Set-Location (Split-Path $PSScriptRoot -Parent)
if (Invoke-Git status --porcelain) { throw 'The work folder has changes that are not committed. Commit them on main first.' }
if ((Invoke-Git rev-parse --abbrev-ref HEAD) -ne 'main') { throw 'Run this script on the branch main.' }

# Make the tree in a temporary index: the index and the files of the work folder do not change.
$index = Join-Path ([IO.Path]::GetTempPath()) "wendellstripes-publish-$PID.index"
$env:GIT_INDEX_FILE = $index
try {
    Invoke-Git read-tree main | Out-Null
    Invoke-Git rm --cached --quiet --ignore-unmatch -- @internal | Out-Null
    $tree = Invoke-Git write-tree
} finally {
    Remove-Item Env:GIT_INDEX_FILE
    if (Test-Path $index) { Remove-Item $index -Force -Confirm:$false }
}

& git rev-parse --verify --quiet refs/heads/public | Out-Null
$parent = if ($LASTEXITCODE -eq 0) { Invoke-Git rev-parse refs/heads/public } else { $null }
if ($parent -and (Invoke-Git rev-parse "$parent^{tree}") -eq $tree) {
    Write-Host 'The branch public already has these files. No new commit.'
    return
}
$commit = if ($parent) { Invoke-Git commit-tree $tree -p $parent -m $Message } else { Invoke-Git commit-tree $tree -m $Message }

# Checks, before the branch moves: no internal file, and no public file that names one
# (this script is the exception: it has the list).
$files = @(Invoke-Git ls-tree -r --name-only $commit)
foreach ($path in $internal) {
    if ($files -contains $path) { throw "The public tree has the internal file $path." }
}
$pattern = ($internal | ForEach-Object { [regex]::Escape($_) }) -join '|'
$named = @(& git grep -l -E $pattern $commit -- . ':!tools/publish.ps1')
if ($named) { throw "These public files name an internal file: $($named -join ', ')" }

Invoke-Git update-ref refs/heads/public $commit | Out-Null
$files | ForEach-Object { Write-Host "  $_" }
Write-Host "public: commit $($commit.Substring(0, 7)), $($files.Count) files. To send it: git push github"
