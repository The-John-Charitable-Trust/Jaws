# Consolidated JAWS Step C installer. Preserves existing resources and approvals.
[CmdletBinding()]
param(
 [ValidateSet('Plan','Install','Verify')][string]$Mode='Plan',
 [string]$ApprovedA2APlanSha256,
 [switch]$AcknowledgeAgentEndpointChange
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
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
