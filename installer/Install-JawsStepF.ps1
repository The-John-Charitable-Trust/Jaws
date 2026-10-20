# Step F. Validate is read-only. A pass is not a fresh-subscription receipt.
[CmdletBinding()]
param(
    [ValidateSet('Validate','Install','Accept')][string]$Mode = 'Validate',
    [string]$EnvironmentName = 'dev',
    [switch]$AcknowledgeStepFInstall
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
    'Validate' { "jaws-step-f-validate.$EnvironmentName.generated.json" }
    'Install' { "jaws-step-f-install.$EnvironmentName.generated.json" }
    'Accept' { "jaws-step-f-acceptance.$EnvironmentName.generated.json" }
}
$evidencePath = Join-Path $local $evidenceName
$label = if ($Mode -eq 'Accept') { 'ACCEPTANCE' } else { $Mode.ToUpperInvariant() }
$next = switch ($Mode) {
    'Validate' { 'Step F Install' }
    'Install' { 'Step F Accept' }
    'Accept' { 'Step G Validate' }
}
try {
    $result = switch ($Mode) {
        'Validate' { Invoke-JawsStepFValidate -EnvironmentName $EnvironmentName -InstallerRoot $root }
        'Install' { Invoke-JawsStepFInstall -EnvironmentName $EnvironmentName -InstallerRoot $root -AcknowledgeStepFInstall:$AcknowledgeStepFInstall }
        'Accept' { Invoke-JawsStepFAccept -EnvironmentName $EnvironmentName -InstallerRoot $root }
    }
    $evidencePath = $result.EvidencePath
    Write-Host "STEP-F $label PASS"
    Write-Host 'Customer installation accepted: false'
    Write-Host "Azure writes: $($result.AzureWrites)"
    Write-Host 'Mcp connection written: false'
    Write-Host 'Live tool call: false'
    Write-Host 'FedRAMP Moderate: false'
    Write-JawsMilestoneResult -Result PASS -ReadyForNextStep $result.ReadyForNextStep -NextStep $result.NextStep -EvidencePath $evidencePath
} catch {
    Save-JawsMilestoneFailure -Path $evidencePath -Message $_.Exception.Message -Started $started
    Write-Host "STEP-F $label FAIL"
    Write-Host 'Customer installation accepted: false'
    Write-JawsMilestoneResult -Result FAIL -ReadyForNextStep $false -NextStep $next -EvidencePath $evidencePath
    throw
}
