# JAWS Stage B2 dedicated Azure Container Registry installer.
# PowerShell 7 / Windows PowerShell 5.1, UTF-8 ASCII-safe.
# No writes in Plan. Create requires an exact plan digest and cost acknowledgment.
[CmdletBinding()]
param(
    [ValidateSet('Plan','Create')][string]$Mode='Plan',
    [Parameter(Mandatory)][ValidatePattern('^[a-z0-9]{5,50}$')][string]$RegistryName,
    [string]$StateFile=(Join-Path $PSScriptRoot 'config/jaws-installation-state.dev.json'),
    [string]$ApprovedPlanSha256,
    [switch]$AcknowledgeBillableBasicSku
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'modules/InstallationState.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'modules/DedicatedRegistry.psm1') -Force
$state=Read-JawsInstallationState -Path $StateFile
if (-not $state) { throw 'JAWS-ACR-PLAN-001: Valid authoritative installation state is required.' }
$plan=New-JawsDedicatedRegistryPlan -State $state -RegistryName $RegistryName
$outDir=Join-Path $PSScriptRoot '.local'
if (-not (Test-Path -LiteralPath $outDir)) { $null=New-Item -ItemType Directory -Path $outDir -Force }
$report=Join-Path $outDir "jaws-registry-plan.$($state.EnvironmentName).generated.json"
$plan | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $report -Encoding utf8
Write-Host "JAWS dedicated ACR: $RegistryName | $($plan.Sku) | $($plan.Location)"
Write-Host "Subscription: $($plan.SubscriptionId) | Resource group: $($plan.ResourceGroupName)"
Write-Host "Plan SHA-256: $($plan.PlanSha256)"
Write-Host "Plan report: $report"
Write-Host 'Azure Container Registry Basic has ongoing charges. Budget alerts are not spending caps.'
if ($Mode -eq 'Plan') {
    Write-Host 'PLAN ONLY: Azure writes = 0. Installation not authorized.'
    return
}
if (-not $AcknowledgeBillableBasicSku -or
    [string]::IsNullOrWhiteSpace($ApprovedPlanSha256) -or
    $ApprovedPlanSha256 -cne $plan.PlanSha256) {
    throw 'JAWS-ACR-APPROVAL-001: Exact plan digest and -AcknowledgeBillableBasicSku are mandatory.'
}
$result=Invoke-JawsDedicatedRegistryCreate -Plan $plan
$receipt=Join-Path $outDir "jaws-registry-receipt.$($state.EnvironmentName).generated.json"
$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $receipt -Encoding utf8
Write-Host "Registry result: $($result.Status) | $($result.RegistryResourceId)"
Write-Host "Receipt: $receipt"
