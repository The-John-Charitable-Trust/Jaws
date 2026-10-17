# JAWS Stage B2 Supervisor publication installer. No Foundry deployment.
[CmdletBinding()]
param(
    [ValidateSet('Plan','Publish')][string]$Mode='Plan',
    [string]$StateFile=(Join-Path $PSScriptRoot 'config/jaws-installation-state.dev.json'),
    [string]$RegistryReceiptFile=(Join-Path $PSScriptRoot '.local/jaws-registry-receipt.dev.generated.json'),
    [string]$ApprovedPlanSha256,
    [switch]$AcknowledgeImageStorageAndTransferCharges
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'modules/InstallationState.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'modules/SupervisorPublish.psm1') -Force
$state=Read-JawsInstallationState -Path $StateFile
if ($null -eq $state) {throw 'JAWS-PUSH-017: Authoritative state missing.'}
if (-not (Test-Path -LiteralPath $RegistryReceiptFile -PathType Leaf)) {
    throw 'JAWS-PUSH-018: Installer-created registry receipt missing.'
}
$receipt=Get-Content -LiteralPath $RegistryReceiptFile -Raw | ConvertFrom-Json -ErrorAction Stop
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw 'JAWS-PUSH-009: Docker Desktop or Docker CLI not installed.'
}
$imageId=(& docker image inspect 'jaws-supervisor:local' --format '{{.Id}}' 2>$null | Out-String).Trim()
if ($LASTEXITCODE -ne 0) {
    throw 'JAWS-PUSH-019: Build local Linux image first through Install-Jaws.ps1 -Mode Package -BuildContainer.'
}
$plan=Get-JawsSupervisorPublishPlan -State $state -RegistryReceipt $receipt -LocalImageId $imageId
$local=Join-Path $PSScriptRoot '.local'
if (-not (Test-Path -LiteralPath $local)) {$null=New-Item -ItemType Directory -Path $local -Force}
$planFile=Join-Path $local "jaws-supervisor-publish-plan.$($state.EnvironmentName).generated.json"
$plan | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $planFile -Encoding utf8
Write-Host "Supervisor image: $($plan.Plan.SourceImageId)"
Write-Host "Target registry: $($plan.Plan.TargetTag)"
Write-Host "Plan SHA-256: $($plan.PlanSha256)"
Write-Host "Plan file: $planFile"
Write-Host "Storage and network charges are possible. Foundry deployment is a separate milestone."
if ($Mode -eq 'Plan') {
    Write-Host 'PLAN ONLY: no Azure calls or writes.'
    return
}
if (-not $AcknowledgeImageStorageAndTransferCharges -or
    [string]::IsNullOrWhiteSpace($ApprovedPlanSha256) -or
    $ApprovedPlanSha256 -cne $plan.PlanSha256) {
    throw 'JAWS-PUSH-APPROVAL-001: Exact plan hash and explicit storage/transfer cost acknowledgment required.'
}
$result=Invoke-JawsSupervisorPublish -Plan $plan
$report=Join-Path $local "jaws-supervisor-publish-receipt.$($state.EnvironmentName).generated.json"
$result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $report -Encoding utf8
Write-Host "Image publication: $($result.Status)"
Write-Host "Immutable image URI: $($result.Image)"
Write-Host "Receipt: $report"
