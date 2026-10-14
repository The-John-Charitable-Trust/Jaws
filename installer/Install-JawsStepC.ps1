# Consolidated JAWS Step C installer. Preserves existing resources and approvals.
[CmdletBinding()]
param(
 [ValidateSet('Plan','Install','Verify','DelegationPlan','DelegationInstall','DelegationVerify','SupervisorV2Build','SupervisorV2Plan','SupervisorV2Publish','SupervisorV2Deploy','SupervisorReleasePlan','SupervisorRelease')][string]$Mode='Plan',
 [string]$ApprovedA2APlanSha256,
 [switch]$AcknowledgeAgentEndpointChange,
 [string]$ApprovedDelegationConnectionSha256,
 [switch]$AcknowledgeA2AConnection,
 [string]$ApprovedDelegationToolboxSha256,
 [switch]$AcknowledgeToolboxChargesAndAccess
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
if($Mode -in @('SupervisorReleasePlan','SupervisorRelease')) {
 $release=Join-Path $root 'Release-JawsSupervisorDraft.ps1'
 & $release -Mode Plan
 if($Mode -eq 'SupervisorReleasePlan'){return}
 $planPath=Join-Path $root '.local/jaws-step-c-supervisor-release-plan.dev.generated.json'
 $plan=Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
 Write-Host 'WARNING: This non-draft release may change latest-agent routing. Version 1 remains available.'
 $answer=Read-Host 'Approve release and potential hosting/inference charges? [y/N]'
 if($answer.Trim() -ine 'y'){throw 'JAWS-STEP-C-RELEASE-001: Release declined.'}
 & $release -Mode Release -ApprovedPlanSha256 $plan.PlanSha256 -AcknowledgeTrafficAndInferenceCharges
 return
}
if($Mode -in @('SupervisorV2Publish','SupervisorV2Deploy')) {
 $action=if($Mode -eq 'SupervisorV2Publish'){'Publish'}else{'Deploy'}
 & (Join-Path $root 'Invoke-JawsSupervisorV2Approved.ps1') -Mode $action
 if(-not $?){throw 'JAWS-STEP-C-V2-002: Approved candidate operation failed.'}
 return
}
if($Mode -in @('SupervisorV2Build','SupervisorV2Plan')) {
 $modeArg=if($Mode -eq 'SupervisorV2Build'){'Build'}else{'Plan'}
 & (Join-Path $root 'Prepare-JawsSupervisorV2.ps1') -Mode $modeArg
 if(-not $?){throw 'JAWS-STEP-C-V2-001: Supervisor candidate preparation failed.'}
 return
}
if($Mode -like 'Delegation*'){
 # A2A agent-card must be verified before any delegated connection actions.
 $receiptPath=Join-Path $root '.local/jaws-step-c-a2a-receipt.dev.generated.json'
 if(-not(Test-Path -LiteralPath $receiptPath -PathType Leaf)){
  throw 'JAWS-STEP-C-DELEGATION-001: Verified Investigation incoming A2A receipt is missing.'
 }
 $receipt=Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
 if($receipt.Status -cne 'A2A_AGENT_CARD_VERIFIED' -or $receipt.AgentName -cne 'jaws-investigation-dev'){
  throw 'JAWS-STEP-C-DELEGATION-002: Investigation A2A receipt does not match.'
 }
 $connection=Join-Path $root 'Configure-JawsDelegationConnection.ps1'
 $toolbox=Join-Path $root 'Configure-JawsDelegationToolbox.ps1'
 switch($Mode){
  'DelegationPlan' {
   & $connection -Mode Plan
   $connectionReceipt=Join-Path $root '.local/jaws-step-c-delegation-connection-receipt.dev.generated.json'
   if(Test-Path $connectionReceipt){ & $toolbox -Mode Plan }
   else { Write-Host 'Toolbox planning waits for a verified RemoteA2A connection.' }
  }
  'DelegationInstall' {
   if([string]::IsNullOrWhiteSpace($ApprovedDelegationConnectionSha256)){
    throw 'JAWS-STEP-C-DELEGATION-003: Exact connection plan approval required.'
   }
   & $connection -Mode Install -ApprovedPlanSha256 $ApprovedDelegationConnectionSha256 -AcknowledgeA2AConnection:$AcknowledgeA2AConnection
   if(-not $?){throw 'JAWS-STEP-C-DELEGATION-004: Connection installation failed.'}
   # Toolbox install separately approved; never create it implicitly.
   if($ApprovedDelegationToolboxSha256){
    & $toolbox -Mode Install -ApprovedPlanSha256 $ApprovedDelegationToolboxSha256 -AcknowledgeToolboxChargesAndAccess:$AcknowledgeToolboxChargesAndAccess
   } else { & $toolbox -Mode Plan }
  }
  'DelegationVerify' {
   & $connection -Mode Verify
   if(-not $?){throw 'JAWS-STEP-C-DELEGATION-005: Connection verification failed.'}
   & $toolbox -Mode Verify
  }
 }
 Write-Host 'Supervisor v1 unchanged. Runtime integration and invocation still require acceptance.'
 return
}
$local=Join-Path $root '.local'
$publish=Join-Path $local 'jaws-investigation-publish-receipt.dev.generated.json'
$deploy=Join-Path $local 'jaws-foundry-investigation-deploy-receipt.dev.generated.json'
if(-not (Test-Path -LiteralPath $publish -PathType Leaf) -or -not (Test-Path -LiteralPath $deploy -PathType Leaf)){
 throw 'JAWS-STEP-C-001: Existing Investigation publish/deploy receipts required. Run existing approved modules for any missing resources.'
}
$pr=Get-Content -LiteralPath $publish -Raw | ConvertFrom-Json
$dr=Get-Content -LiteralPath $deploy -Raw | ConvertFrom-Json
if($pr.Status -ne 'PUBLISHED_AND_DIGEST_VERIFIED' -or
   $pr.RegistryPushPerformed -ne $true -or
   $dr.AgentName -cne 'jaws-investigation-dev' -or
   [string]$dr.Image -cne [string]$pr.Image -or
   [string]$dr.Version -cne '1'){
 throw 'JAWS-STEP-C-002: Publishing/deployment receipts do not reconcile. No writes permitted.'
}
Write-Host 'JAWS Step C: existing published Investigation v1 receipts reconciled.'
$prereq=Join-Path $root 'Test-JawsPrerequisites.ps1'
# Preflight reports local state; no implicit installation.
if($Mode -eq 'Plan'){
 Write-Host 'Preflight: use Test-JawsPrerequisites.ps1 if workstation state changed.'
}
$a2a=Join-Path $root 'Configure-JawsInvestigationA2A.ps1'
if($Mode -eq 'Install'){
 if([string]::IsNullOrWhiteSpace($ApprovedA2APlanSha256) -or -not $AcknowledgeAgentEndpointChange){
  throw 'JAWS-STEP-C-003: A2A approval hash and explicit endpoint acknowledgment required.'
 }
 & $a2a -Mode Install -ApprovedPlanSha256 $ApprovedA2APlanSha256 -AcknowledgeAgentEndpointChange
}elseif($Mode -eq 'Verify'){
 & $a2a -Mode Verify
}else{
 & $a2a -Mode Plan
}
if(-not $?){throw 'JAWS-STEP-C-004: A2A step failed.'}
Write-Host 'Step C state: Investigation hosted v1 retained; Supervisor v1 unchanged.'
Write-Host 'Supervisor-to-Investigation A2A connection/tool registration and end-to-end delegation remain separate acceptance gates.'
