# Step E: publish the Supervisor to Teams so the operator can test communication.
# Validate is read-only. Install requires -AcknowledgeStepEInstall.
# Accept re-reads the bot. A pass does not record a Teams reply.
[CmdletBinding()]
param(
    [ValidateSet('Validate','Install','Accept')][string]$Mode = 'Validate',
    [string]$EnvironmentName = 'dev',
    [switch]$AcknowledgeStepEInstall
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$started = Get-Date
Import-Module (Join-Path $root 'modules/StepETeams.psm1') -Force
Import-Module (Join-Path $root 'modules/MilestoneResult.psm1') -Force
$local = Join-Path $root '.local'
if (-not (Test-Path -LiteralPath $local)) { New-Item -ItemType Directory -Path $local | Out-Null }
$evidenceName = switch ($Mode) {
    'Validate' { "jaws-step-e-validate.$EnvironmentName.generated.json" }
    'Install' { "jaws-step-e-install.$EnvironmentName.generated.json" }
    'Accept' { "jaws-step-e-acceptance.$EnvironmentName.generated.json" }
}
$evidencePath = Join-Path $local $evidenceName
$label = if ($Mode -eq 'Accept') { 'ACCEPTANCE' } else { $Mode.ToUpperInvariant() }
$next = switch ($Mode) {
    'Validate' { 'Step E Install' }
    'Install' { 'Step E Accept' }
    'Accept' { 'Step F Validate' }
}
try {
    $result = switch ($Mode) {
        'Validate' { Invoke-JawsStepEValidate -EnvironmentName $EnvironmentName -InstallerRoot $root }
        'Install' { Invoke-JawsStepEInstall -EnvironmentName $EnvironmentName -InstallerRoot $root -AcknowledgeStepEInstall:$AcknowledgeStepEInstall }
        'Accept' { Invoke-JawsStepEAccept -EnvironmentName $EnvironmentName -InstallerRoot $root }
    }
    $evidencePath = $result.EvidencePath
    Write-Host "STEP-E $label PASS"
    Write-Host 'Customer installation accepted: false'
    Write-Host "Azure writes: $($result.AzureWrites)"
    Write-Host 'Publish scope: Shared'
    Write-Host 'Specialists published: false'
    Write-Host 'Teams reply recorded: false'
    Write-Host 'FedRAMP Moderate: false'
    Write-JawsMilestoneResult -Result PASS -ReadyForNextStep $result.ReadyForNextStep -NextStep $result.NextStep -EvidencePath $evidencePath
} catch {
    Save-JawsMilestoneFailure -Path $evidencePath -Message $_.Exception.Message -Started $started
    Write-Host "STEP-E $label FAIL"
    Write-Host 'Customer installation accepted: false'
    Write-JawsMilestoneResult -Result FAIL -ReadyForNextStep $false -NextStep $next -EvidencePath $evidencePath
    throw
}
