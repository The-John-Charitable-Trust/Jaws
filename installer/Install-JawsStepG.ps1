# Step G. Validate is read-only. A pass is not a fresh-subscription receipt.
[CmdletBinding()]
param(
    [ValidateSet('Validate','Install','Accept')][string]$Mode = 'Validate',
    [string]$EnvironmentName = 'dev',
    [switch]$AcknowledgeStepGInstall
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
    'Validate' { "jaws-step-g-validate.$EnvironmentName.generated.json" }
    'Install' { "jaws-step-g-install.$EnvironmentName.generated.json" }
    'Accept' { "jaws-step-g-acceptance.$EnvironmentName.generated.json" }
}
$evidencePath = Join-Path $local $evidenceName
$label = if ($Mode -eq 'Accept') { 'ACCEPTANCE' } else { $Mode.ToUpperInvariant() }
$next = switch ($Mode) {
    'Validate' { 'Step G Install' }
    'Install' { 'Step G Accept' }
    'Accept' { 'Step H Validate' }
}
try {
    $result = switch ($Mode) {
        'Validate' { Invoke-JawsStepGValidate -EnvironmentName $EnvironmentName -InstallerRoot $root }
        'Install' { Invoke-JawsStepGInstall -EnvironmentName $EnvironmentName -InstallerRoot $root -AcknowledgeStepGInstall:$AcknowledgeStepGInstall }
        'Accept' { Invoke-JawsStepGAccept -EnvironmentName $EnvironmentName -InstallerRoot $root }
    }
    $evidencePath = $result.EvidencePath
    Write-Host "STEP-G $label PASS"
    Write-Host 'Customer installation accepted: false'
    Write-Host "Azure writes: $($result.AzureWrites)"
    Write-Host 'MCP server deployed: false'
    Write-Host 'Live tool call: false'
    Write-Host 'FedRAMP Moderate: false'
    Write-JawsMilestoneResult -Result PASS -ReadyForNextStep $result.ReadyForNextStep -NextStep $result.NextStep -EvidencePath $evidencePath
} catch {
    Save-JawsMilestoneFailure -Path $evidencePath -Message $_.Exception.Message -Started $started
    Write-Host "STEP-G $label FAIL"
    Write-Host 'Customer installation accepted: false'
    Write-JawsMilestoneResult -Result FAIL -ReadyForNextStep $false -NextStep $next -EvidencePath $evidencePath
    throw
}
