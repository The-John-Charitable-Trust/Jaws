#Requires -Version 7.0
<#
.SYNOPSIS
  Safely synchronize a local JAWS branch with its matching branch on origin.
.EXAMPLE
  .\Sync-Jaws.ps1
.EXAMPLE
  .\Sync-Jaws.ps1 -Branch feature/my-work
.EXAMPLE
  .\Sync-Jaws.ps1 -BackupUntracked
.EXAMPLE
  .\Sync-Jaws.ps1 -RepositoryPath 'C:\Users\Me\Documents\JawsOSS' -Branch main
.NOTES
  Never resets, cleans, stashes, commits, pushes, or force-merges work.
  Refuses tracked changes. Optional -BackupUntracked moves only untracked files to a timestamped sibling directory.
  Fetch deliberately omits --prune, avoiding Windows failures deleting stale remote-ref folders.
#>
[CmdletBinding()]
param(
    [string]$RepositoryPath = (Get-Location).Path,
    [ValidateNotNullOrEmpty()][string]$Branch = 'main',
    [ValidateNotNullOrEmpty()][string]$Remote = 'origin',
    [switch]$BackupUntracked
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
    # Never automatically move or alter tracked modifications, deletions or staging.
    $tracked = @(& git -C $top diff --name-only HEAD)
    if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect tracked changes.' }
    $untracked = @(& git -C $top ls-files --others --exclude-standard)
    if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect untracked files.' }
    if ($tracked.Count -gt 0) {
        $tracked | ForEach-Object { Write-Host "Tracked change: $_" -ForegroundColor Yellow }
        throw 'Tracked changes exist. Commit or preserve them manually before syncing.'
    }
    if ($untracked.Count -gt 0) {
        if (-not $BackupUntracked) {
            $untracked | ForEach-Object { Write-Host "Untracked: $_" -ForegroundColor Yellow }
            throw 'Untracked files detected. Re-run with -BackupUntracked to preserve them outside the repository.'
        }
        $parent = Split-Path -Parent $top
        $leaf = Split-Path -Leaf $top
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $backupDir = Join-Path $parent ("$leaf-untracked-backup-$stamp-" + [guid]::NewGuid().ToString('N').Substring(0,8))
        New-Item -ItemType Directory -Path $backupDir -ErrorAction Stop | Out-Null
        Write-Host "Preserving $($untracked.Count) untracked file(s) in: $backupDir" -ForegroundColor Cyan
        foreach ($relative in $untracked) {
            # Git paths are relative to repository root; do not allow traversal.
            if ([IO.Path]::IsPathRooted($relative) -or @($relative -split '[\\/]' | Where-Object { $_ -eq '..' }).Count -gt 0) {
                throw "Unsafe untracked file path: $relative"
            }
            $source = Join-Path $top $relative
            $destination = Join-Path $backupDir $relative
            $destinationParent = Split-Path -Parent $destination
            New-Item -ItemType Directory -Path $destinationParent -Force -ErrorAction Stop | Out-Null
            Move-Item -LiteralPath $source -Destination $destination -ErrorAction Stop
        }
        Write-Host 'Untracked-file backup complete. Tracked files were not changed.' -ForegroundColor Green
        $remaining = @(& git -C $top status --porcelain=v1 --untracked-files=all)
        if ($LASTEXITCODE -ne 0 -or $remaining.Count -gt 0) {
            throw 'Working tree still has changes after backup. Review git status; synchronization stopped.'
        }
    }
    $remoteUrl = & git -C $top remote get-url $Remote 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $remoteUrl) { throw "Remote '$Remote' does not exist." }
    Write-Host "Fetching $Remote..." -ForegroundColor Cyan
    Invoke-Git @('-C',$top,'fetch',$Remote)
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
