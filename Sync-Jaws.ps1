#Requires -Version 7.0
<#
.SYNOPSIS
  Safely synchronize a local JAWS branch with its matching branch on origin.
.EXAMPLE
  .\Sync-Jaws.ps1
.EXAMPLE
  .\Sync-Jaws.ps1 -Branch feature/my-work
.EXAMPLE
  .\Sync-Jaws.ps1 -RepositoryPath 'C:\Users\Me\Documents\JawsOSS' -Branch main
.NOTES
  Never resets, cleans, stashes, commits, pushes, or force-merges work.
  Stops if tracked/untracked changes exist; permits explicitly ignored files.
#>
[CmdletBinding()]
param(
    [string]$RepositoryPath = (Get-Location).Path,
    [ValidateNotNullOrEmpty()][string]$Branch = 'main',
    [ValidateNotNullOrEmpty()][string]$Remote = 'origin'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Git {
    param([Parameter(Mandatory)][string[]]$Arguments)
    & git @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Git command failed (exit $LASTEXITCODE): git $($Arguments -join ' ')"
    }
}

try {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw 'Git is not installed or is missing from PATH.'
    }
    $resolvedPath = (Resolve-Path -LiteralPath $RepositoryPath -ErrorAction Stop).Path
    $top = (& git -C $resolvedPath rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0 -or -not $top) {
        throw "Not a Git repository: $resolvedPath"
    }
    $top = ([string]$top).Trim()
    Write-Host "Repository: $top" -ForegroundColor Cyan
    $before = & git -C $top status --porcelain=v1 --untracked-files=all
    if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect working tree.' }
    if (@($before).Count -gt 0) {
        Write-Warning 'Uncommitted or untracked files detected. Nothing has been changed.'
        $before | ForEach-Object { Write-Host "  $_" }
        throw 'Commit, move, or otherwise preserve these files before syncing. This script will not stash or remove them.'
    }
    $remoteUrl = & git -C $top remote get-url $Remote 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $remoteUrl) { throw "Remote '$Remote' does not exist." }
    Write-Host "Fetching $Remote..." -ForegroundColor Cyan
    Invoke-Git @('-C',$top,'fetch','--prune',$Remote)
    & git -C $top show-ref --verify --quiet "refs/remotes/$Remote/$Branch"
    if ($LASTEXITCODE -ne 0) { throw "Remote branch '$Remote/$Branch' was not found." }
    $current = (& git -C $top branch --show-current).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Unable to identify current branch.' }
    if ($current -ne $Branch) {
        Write-Host "Switching from '$current' to '$Branch'..." -ForegroundColor Cyan
        & git -C $top show-ref --verify --quiet "refs/heads/$Branch"
        if ($LASTEXITCODE -eq 0) {
            Invoke-Git @('-C',$top,'switch',$Branch)
        } else {
            Invoke-Git @('-C',$top,'switch','--track','-c',$Branch,"$Remote/$Branch")
        }
    }
    Write-Host "Fast-forwarding '$Branch' from '$Remote/$Branch'..." -ForegroundColor Cyan
    Invoke-Git @('-C',$top,'merge','--ff-only',"$Remote/$Branch")
    Write-Host ''
    Invoke-Git @('-C',$top,'status','--short','--branch')
    Invoke-Git @('-C',$top,'log','-1','--format=Latest commit: %h %s')
    Write-Host "Synchronization completed: $Branch" -ForegroundColor Green
} catch {
    Write-Error "Synchronization stopped safely: $($_.Exception.Message)"
    exit 1
}
