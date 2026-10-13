# Recover a successfully-created JAWS hosted Supervisor when the original POST receipt was not recorded.
# All Azure operations are read-only. Writes only a local installer receipt.
[CmdletBinding()]
param(
    [string]$StateFile=(Join-Path $PSScriptRoot 'config/jaws-installation-state.dev.json'),
    [string]$PublishReceiptFile=(Join-Path $PSScriptRoot '.local/jaws-supervisor-publish-receipt.dev.generated.json'),
    [string]$ApprovedPlanSha256
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'modules/InstallationState.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'modules/FoundrySupervisorDeployment.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'modules/FoundrySupervisorReconciliation.psm1') -Force

$state=Read-JawsInstallationState -Path $StateFile
if ($null -eq $state) { throw 'JAWS-RECOVER-001: Valid installation state required.' }
$receipt=Get-Content -LiteralPath $PublishReceiptFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
$plan=New-JawsFoundrySupervisorPlan -State $state -PublishReceipt $receipt -AgentName 'jaws-supervisor-dev'
Test-JawsFoundryDeploymentPlan -DeploymentPlan $plan
if ([string]::IsNullOrWhiteSpace($ApprovedPlanSha256) -or $ApprovedPlanSha256 -cne $plan.PlanSha256) {
    throw 'JAWS-RECOVER-002: Exact approved deployment plan fingerprint required.'
}
$p=$plan.Plan
if ($p.ProjectEndpoint -cne 'https://jaws-foundry-dev.services.ai.azure.com/api/projects/jaws-dev' -or
    $p.AgentName -cne 'jaws-supervisor-dev') {
    throw 'JAWS-RECOVER-003: Refusing recovery outside the JAWS dev project.'
}
$url="$($p.ProjectEndpoint)/agents/$($p.AgentName)?api-version=v1"
$json=& az rest --method get --url $url --resource https://ai.azure.com --output json --only-show-errors 2>$null
if ($LASTEXITCODE -ne 0) {throw 'JAWS-RECOVER-004: Failed to read the existing hosted agent; no receipt created.'}
$agent=$json | Out-String | ConvertFrom-Json -ErrorAction Stop
# Compare the live agent to the desired installation, field by field. On drift, save
# diagnostics only; never issue a successful deployment receipt.
$comparison=Compare-JawsFoundrySupervisorState -DeploymentPlan $plan -ActualAgent $agent
$diagnosticPath=Join-Path $PSScriptRoot ".local/jaws-foundry-supervisor-reconciliation.$($state.EnvironmentName).generated.json"
$comparison | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $diagnosticPath -Encoding utf8
$comparison.Checks | Format-Table -AutoSize | Out-Host
Write-Host "Reconciliation report: $diagnosticPath"
if ($comparison.OverallStatus -ne 'MATCH') {
    throw "JAWS-RECOVER-005: Existing agent differs from approved configuration: $($comparison.FailedFields -join ', '). No deployment receipt created."
}
$path=Join-Path $PSScriptRoot ".local/jaws-foundry-supervisor-deploy-receipt.$($state.EnvironmentName).generated.json"
if (Test-Path -LiteralPath $path -PathType Leaf) {
    throw 'JAWS-RECOVER-006: Deployment receipt already exists. Refusing overwrite.'
}
$result=[pscustomobject]@{
    Status='PROVISIONING_STARTED';AgentName=[string]$p.AgentName;Version='1'
    Image=[string]$p.Image;ProjectEndpoint=[string]$p.ProjectEndpoint
    AgentVersionUri="$($p.ProjectEndpoint)/agents/$($p.AgentName)/versions/1"
    PlanSha256=[string]$plan.PlanSha256;FoundryDeploymentPerformed=$true
    AzureWrites=0;ActiveVerified=$true;InvocationVerified=$false
    RecoverySource='VerifiedExistingAgentVersion';RecoveredStatus='active'
}
$result | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $path -Encoding utf8
Write-Host "RECOVERED: $($p.AgentName) version 1 is active with approved immutable image." -ForegroundColor Green
Write-Host "Azure writes: 0 | Receipt: $path"
Write-Host 'Authenticated inference has not yet been verified.'
