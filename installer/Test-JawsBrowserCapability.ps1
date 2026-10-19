# Ask the Supervisor to extract one value and to record an allow-list rejection.
# This spends model and browser usage. It does not accept the customer installation, and Step E stays closed.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$EnvironmentName,
    [Parameter(Mandatory)][string]$Url,
    [switch]$AcknowledgeBrowserCapability
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$started = Get-Date
Import-Module (Join-Path $root 'modules/StepDBrowser.psm1') -Force
Import-Module (Join-Path $root 'modules/MilestoneResult.psm1') -Force
$local = Join-Path $root '.local'
if (-not (Test-Path -LiteralPath $local)) { New-Item -ItemType Directory -Path $local | Out-Null }
$evidencePath = Join-Path $local "jaws-step-d-browser-capability.$EnvironmentName.generated.json"
try {
    $result = Invoke-JawsBrowserCapability -EnvironmentName $EnvironmentName -InstallerRoot $root -Url $Url -AcknowledgeBrowserCapability:$AcknowledgeBrowserCapability
    $evidencePath = $result.EvidencePath
    if (-not $result.Passed) {
        Write-Host 'STEP-D BROWSER CAPABILITY FAIL'
        Write-Host 'Customer installation accepted: false'
        Write-Host 'Azure writes: 0'
        Write-JawsMilestoneResult -Result FAIL -ReadyForNextStep $false -NextStep $result.NextStep -EvidencePath $evidencePath
        throw $result.Error
    }
    Write-Host 'STEP-D BROWSER CAPABILITY PASS'
    Write-Host 'Customer installation accepted: false'
    Write-Host 'Azure writes: 0'
    Write-Host 'Ready for next step stays false because Step E has no installer.'
    Write-JawsMilestoneResult -Result PASS -ReadyForNextStep $false -NextStep 'Step E is not installable' -EvidencePath $evidencePath
} catch {
    $structured = $false
    if (Test-Path -LiteralPath $evidencePath -PathType Leaf) {
        try {
            $existing = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json
            if ($existing.PSObject.Properties['CapabilityProven'] -and $existing.PSObject.Properties['CompletedAtUtc']) {
                $written = [DateTime]::Parse([string]$existing.CompletedAtUtc).ToUniversalTime()
                if ($written -ge $started.ToUniversalTime().AddSeconds(-2)) { $structured = $true }
            }
        } catch { }
    }
    if (-not $structured) {
        Save-JawsMilestoneFailure -Path $evidencePath -Message $_.Exception.Message -Started $started
    }
    if ($_.Exception.Message -notmatch 'JAWS-STEP-D-042:') {
        Write-Host 'STEP-D BROWSER CAPABILITY FAIL'
        Write-Host 'Customer installation accepted: false'
        Write-JawsMilestoneResult -Result FAIL -ReadyForNextStep $false -NextStep 'Test-JawsBrowserCapability.ps1' -EvidencePath $evidencePath
    }
    throw
}
