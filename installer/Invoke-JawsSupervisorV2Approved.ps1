# Interactive, plan-bound JAWS Step C Supervisor v2 publishing/deployment.
# Authorization occurs before each potential Azure write. No duplicate agent.
[CmdletBinding()]
param([ValidateSet('Publish','Deploy')][string]$Mode)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Confirm-ApprovedPlan([string]$Label,[string]$PlanPath) {
 if(-not (Test-Path -LiteralPath $PlanPath -PathType Leaf)){throw "JAWS-STEP-C-APPROVAL-001: Plan not found: $PlanPath"}
 $plan=Get-Content -LiteralPath $PlanPath -Raw | ConvertFrom-Json
 $sha=[string]$plan.PlanSha256
 if($sha -cnotmatch '^[a-f0-9]{64}$'){throw 'JAWS-STEP-C-APPROVAL-002: Invalid plan fingerprint.'}
 Write-Host "Operation: $Label"
 Write-Host "Plan fingerprint: $sha"
 if($plan.PSObject.Properties['Plan'] -and $plan.Plan.PSObject.Properties['Image']){
  Write-Host "Immutable image: $($plan.Plan.Image)"
 }
 if($plan.PSObject.Properties['Plan'] -and $plan.Plan.PSObject.Properties['TargetTag']){
  Write-Host "Target image: $($plan.Plan.TargetTag)"
 }
 Write-Host 'Azure storage, hosted compute, or model inference charges may apply.'
 $response=Read-Host 'Approve this exact plan and its potential charges? [y/N]'
 if($null -eq $response -or $response.Trim() -ine 'y') {throw 'JAWS-STEP-C-APPROVAL-003: Operator declined. No changes made.'}
 return $sha
}
if($Mode -eq 'Publish'){
 $entry=Join-Path $PSScriptRoot 'Publish-JawsSupervisor.ps1'
 & $entry -Mode Plan
 $planPath=Join-Path $PSScriptRoot '.local/jaws-supervisor-publish-plan.dev.generated.json'
 $hash=Confirm-ApprovedPlan 'Publish new Supervisor container to ACR' $planPath
 & $entry -Mode Publish -ApprovedPlanSha256 $hash -AcknowledgeImageStorageAndTransferCharges
 if(-not $?){throw 'JAWS-STEP-C-APPROVAL-004: Publish failed.'}
 return
}
$entry=Join-Path $PSScriptRoot 'Deploy-JawsSupervisor.ps1'
$receipt=Join-Path $PSScriptRoot '.local/jaws-supervisor-publish-receipt.dev.generated.json'
if(-not(Test-Path $receipt -PathType Leaf)){throw 'JAWS-STEP-C-APPROVAL-005: Supervisor publish receipt missing.'}
& $entry -Mode Plan -AgentName 'jaws-supervisor-dev' -ToolboxName 'jaws-investigation-a2a-tools' -PublishReceiptFile $receipt
$planPath=Join-Path $PSScriptRoot '.local/jaws-foundry-supervisor-plan.dev.generated.json'
$hash=Confirm-ApprovedPlan 'Create a DRAFT version on existing Supervisor agent' $planPath
& $entry -Mode Deploy -AgentName 'jaws-supervisor-dev' -ToolboxName 'jaws-investigation-a2a-tools' -PublishReceiptFile $receipt -ApprovedPlanSha256 $hash -AcknowledgeHostingAndInferenceCharges
if(-not $?){throw 'JAWS-STEP-C-APPROVAL-006: Deployment failed.'}
