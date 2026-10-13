# JAWS Stage B2 Foundry project identity ACR pull-role installer.
[CmdletBinding()]
param(
    [ValidateSet('Plan','Assign')][string]$Mode='Plan',
    [string]$RegistryName='jawsregistrydev001',
    [string]$StateFile=(Join-Path $PSScriptRoot 'config/jaws-installation-state.dev.json'),
    [string]$ApprovedPlanSha256,
    [switch]$AcknowledgeSecurityRoleAssignment
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'modules/InstallationState.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'modules/FoundryAcrRbac.psm1') -Force

$state=Read-JawsInstallationState -Path $StateFile
if (-not $state) { throw 'JAWS-RBAC-STATE-001: Valid authoritative installation state is required.' }
$plan=Get-JawsFoundryAcrRbacLivePlan -State $state -RegistryName $RegistryName
$outDir=Join-Path $PSScriptRoot '.local'
if (-not (Test-Path -LiteralPath $outDir)) { $null=New-Item -ItemType Directory -Path $outDir -Force }
$report=Join-Path $outDir "jaws-foundry-acr-rbac-plan.$($state.EnvironmentName).generated.json"
$plan | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $report -Encoding utf8

Write-Host "Project identity: $($plan.Plan.ProjectPrincipalId)"
Write-Host "Registry scope: $($plan.Plan.RegistryResourceId)"
Write-Host "Role: $($plan.Plan.RoleDefinitionName) | Mode: $($plan.Plan.RegistryRoleAssignmentMode)"
Write-Host "Plan SHA-256: $($plan.PlanSha256)"
Write-Host "Plan report: $report"
if ($Mode -eq 'Plan') {
    Write-Host 'PLAN ONLY: Azure writes = 0. Role assignment is not authorized.'
    return
}
if (-not $AcknowledgeSecurityRoleAssignment -or
    [string]::IsNullOrWhiteSpace($ApprovedPlanSha256) -or
    $ApprovedPlanSha256 -cne $plan.PlanSha256) {
    throw 'JAWS-RBAC-APPROVAL-001: Exact plan digest and -AcknowledgeSecurityRoleAssignment are mandatory.'
}
$result=Invoke-JawsFoundryAcrRbacAssignment -RbacPlan $plan
$receipt=Join-Path $outDir "jaws-foundry-acr-rbac-receipt.$($state.EnvironmentName).generated.json"
$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $receipt -Encoding utf8
Write-Host "RBAC result: $($result.Status) | $($result.RoleDefinitionName) | Azure writes: $($result.AzureWrites)"
Write-Host "Receipt: $receipt"
