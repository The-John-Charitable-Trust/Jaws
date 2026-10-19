# One Foundry tool call that opens and closes a browser session. It does not navigate.
# A failure stops the capability path. A CLI stand-in is not a live private-path receipt.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$EnvironmentName,
    [switch]$AcknowledgeBrowserPrivatePath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$started = Get-Date
Import-Module (Join-Path $root 'modules/StepDBrowser.psm1') -Force
Import-Module (Join-Path $root 'modules/MilestoneResult.psm1') -Force
$local = Join-Path $root '.local'
if (-not (Test-Path -LiteralPath $local)) { New-Item -ItemType Directory -Path $local | Out-Null }
$evidencePath = Join-Path $local "jaws-step-d-browser-private-path.$EnvironmentName.generated.json"
try {
    $result = Invoke-JawsBrowserPrivatePath -EnvironmentName $EnvironmentName -InstallerRoot $root -AcknowledgeBrowserPrivatePath:$AcknowledgeBrowserPrivatePath
    $evidencePath = $result.EvidencePath
    if (-not $result.Passed) {
        Write-Host 'STEP-D PRIVATE PATH FAIL'
        Write-Host 'Customer installation accepted: false'
        Write-Host 'Azure writes: 0'
        Write-JawsMilestoneResult -Result FAIL -ReadyForNextStep $false -NextStep $result.NextStep -EvidencePath $evidencePath
        throw $result.Error
    }
    Write-Host 'STEP-D PRIVATE PATH PASS'
    Write-Host 'Customer installation accepted: false'
    Write-Host 'Azure writes: 0'
    Write-Host 'Navigation attempted: false'
    Write-JawsMilestoneResult -Result PASS -ReadyForNextStep $result.ReadyForNextStep -NextStep $result.NextStep -EvidencePath $evidencePath
} catch {
    $structured = $false
    if (Test-Path -LiteralPath $evidencePath -PathType Leaf) {
        try {
            $existing = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json
            if ($existing.PSObject.Properties['PrivatePathProven'] -and $existing.PSObject.Properties['CompletedAtUtc']) {
                $written = [DateTime]::Parse([string]$existing.CompletedAtUtc).ToUniversalTime()
                if ($written -ge $started.ToUniversalTime().AddSeconds(-2)) { $structured = $true }
            }
        } catch { }
    }
    if (-not $structured) {
        Save-JawsMilestoneFailure -Path $evidencePath -Message $_.Exception.Message -Started $started
    }
    if ($_.Exception.Message -notmatch 'JAWS-STEP-D-040:') {
        Write-Host 'STEP-D PRIVATE PATH FAIL'
        Write-Host 'Customer installation accepted: false'
        Write-JawsMilestoneResult -Result FAIL -ReadyForNextStep $false -NextStep 'Test-JawsBrowserPrivatePath.ps1' -EvidencePath $evidencePath
    }
    throw
}
