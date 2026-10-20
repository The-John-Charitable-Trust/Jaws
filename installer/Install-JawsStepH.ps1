# Step H. Validate is read-only. A pass is not a fresh-subscription receipt.
[CmdletBinding()]
param(
    [ValidateSet('Validate','Install','Accept')][string]$Mode = 'Validate',
    [string]$EnvironmentName = 'dev',
    [switch]$AcknowledgeStepHInstall
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$started = Get-Date
Import-Module (Join-Path $root 'modules/LaterSteps.psm1') -Force
Import-Module (Join-Path $root 'modules/MilestoneResult.psm1') -Force
$local = Join-Path $root '.local'
if (-not (Test-Path -LiteralPath $local)) { New-Item -ItemType Directory -Path $local | Out-Null }
$evidenceName = switch ($Mode) {
    'Validate' { "jaws-step-h-validate.$EnvironmentName.generated.json" }
    'Install' { "jaws-step-h-install.$EnvironmentName.generated.json" }
    'Accept' { "jaws-step-h-acceptance.$EnvironmentName.generated.json" }
}
$evidencePath = Join-Path $local $evidenceName
$label = if ($Mode -eq 'Accept') { 'ACCEPTANCE' } else { $Mode.ToUpperInvariant() }
$next = switch ($Mode) {
    'Validate' { 'Step H Install' }
    'Install' { 'Step H Accept' }
    'Accept' { 'Step I Validate' }
}
try {
    $result = switch ($Mode) {
        'Validate' { Invoke-JawsStepHValidate -EnvironmentName $EnvironmentName -InstallerRoot $root }
        'Install' { Invoke-JawsStepHInstall -EnvironmentName $EnvironmentName -InstallerRoot $root -AcknowledgeStepHInstall:$AcknowledgeStepHInstall }
        'Accept' { Invoke-JawsStepHAccept -EnvironmentName $EnvironmentName -InstallerRoot $root }
    }
    $evidencePath = $result.EvidencePath
    Write-Host "STEP-H $label PASS"
    Write-Host 'Customer installation accepted: false'
    Write-Host "Azure writes: $($result.AzureWrites)"
    Write-Host 'Change executed: false'
    Write-Host 'FedRAMP Moderate: false'
    Write-JawsMilestoneResult -Result PASS -ReadyForNextStep $result.ReadyForNextStep -NextStep $result.NextStep -EvidencePath $evidencePath
} catch {
    Save-JawsMilestoneFailure -Path $evidencePath -Message $_.Exception.Message -Started $started
    Write-Host "STEP-H $label FAIL"
    Write-Host 'Customer installation accepted: false'
    Write-JawsMilestoneResult -Result FAIL -ReadyForNextStep $false -NextStep $next -EvidencePath $evidencePath
    throw
}
