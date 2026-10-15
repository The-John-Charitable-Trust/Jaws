# Release one approved Supervisor draft that carries a newly published image.
# Supervisor v1 is read and left unchanged. Existing released versions are not patched.
[CmdletBinding()]
param(
 [ValidateSet('Plan','Release')][string]$Mode='Plan',
 [string]$ApprovedPlanSha256,
 [switch]$AcknowledgeTrafficAndInferenceCharges,
 [string]$StateFile=(Join-Path $PSScriptRoot 'config/jaws-installation-state.dev.json'),
 [string]$PublishReceiptFile=(Join-Path $PSScriptRoot '.local/jaws-supervisor-publish-receipt.dev.generated.json')
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'modules/InstallationState.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'modules/FoundrySupervisorDeployment.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'modules/FoundrySupervisorReconciliation.psm1') -Force
$state=Read-JawsInstallationState -Path $StateFile
if($null -eq $state -or $state.Platform -cne 'JAWS' -or $state.EnvironmentName -cne 'dev'){
 throw 'JAWS-SUP-CANDIDATE-001: Authoritative JAWS dev state required.'
}
if(-not (Test-Path -LiteralPath $PublishReceiptFile -PathType Leaf)){
 throw 'JAWS-SUP-CANDIDATE-002: Supervisor publish receipt missing.'
}
$receipt=Resolve-JawsSupervisorPublishReceipt -ReceiptContent (Get-Content -LiteralPath $PublishReceiptFile -Raw | ConvertFrom-Json)
$image=[string]$receipt.Image
$endpoint='https://jaws-foundry-dev.services.ai.azure.com/api/projects/jaws-dev'
$agent='jaws-supervisor-dev'
function Read-Foundry([string]$url){
 $out=& az rest --method get --url $url --resource https://ai.azure.com --output json --only-show-errors 2>&1
 if($LASTEXITCODE -ne 0){throw "JAWS-SUP-CANDIDATE-003: Azure state read failed: $($out|Out-String)"}
 return ($out|Out-String|ConvertFrom-Json -ErrorAction Stop)
}
$v1=Read-Foundry "$endpoint/agents/$agent/versions/1?api-version=v1"
if($v1.status -ne 'active' -or $v1.draft -ne $false){throw 'JAWS-SUP-CANDIDATE-004: Supervisor v1 is not an active release.'}
if([string]$v1.definition.container_configuration.image -ceq $image){
 throw 'JAWS-SUP-CANDIDATE-005: Refusing to release an image that is already Supervisor v1.'
}
$versions=Read-Foundry "$endpoint/agents/$agent/versions?api-version=v1"
$matches=@($versions.data | Where-Object {
  $null -ne $_ -and
  [string]$_.definition.container_configuration.image -ceq $image -and
  [string]$_.definition.environment_variables.JAWS_INVESTIGATION_TOOLBOX_NAME -ceq 'jaws-investigation-a2a-tools'
})
$released=@($matches | Where-Object { $_.draft -eq $false -and $_.status -eq 'active' })
$dir=Join-Path $PSScriptRoot '.local'
if(-not (Test-Path $dir)){$null=New-Item -ItemType Directory -Force -Path $dir}
$path=Join-Path $dir 'jaws-step-c-supervisor-candidate-release-plan.dev.generated.json'
if($released.Count -gt 0){
 [pscustomobject]@{
  Agent=$agent;SourceDraft='';Image=$image;Operation='AlreadyPresent';PlanSha256=''
  LeavesSupervisorV1Unchanged=$true;MayChangeLatestRouting=$false;Version=[string]$released[0].version
 } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding utf8
 Write-Host "Active release $($released[0].version) already uses $image. No write."
 return
}
$drafts=@($matches | Where-Object { $_.draft -eq $true -and $_.status -eq 'active' })
if($drafts.Count -ne 1){throw "JAWS-SUP-CANDIDATE-006: Expected one active draft for the published image, found $($drafts.Count)."}
$draft=$drafts[0]
# Independent, read-only gate: a direct Release invocation cannot bypass reconciliation.
$verifiedPath=Join-Path $PSScriptRoot '.local/jaws-step-c-supervisor-deployment-verified.dev.generated.json'
if(-not(Test-Path -LiteralPath $verifiedPath -PathType Leaf)){
 throw 'JAWS-SUP-CANDIDATE-011: Reconciliation receipt missing; run SupervisorCandidateWait.'
}
$verified=Get-Content -LiteralPath $verifiedPath -Raw | ConvertFrom-Json
if($verified.Status -cne 'ACTIVE_VERIFIED' -or $verified.ActiveVerified -ne $true -or
 [string]$verified.ResolvedVersion -cne [string]$draft.version -or
 [string]$verified.Image -cne $image){
 throw 'JAWS-SUP-CANDIDATE-012: Candidate receipt does not match active draft/image. Release blocked.'
}

$definition=[ordered]@{
 kind='hosted'
 container_configuration=[ordered]@{image=$image}
 cpu=[string]$draft.definition.cpu
 memory=[string]$draft.definition.memory
 protocol_versions=@([ordered]@{protocol='responses';version='2.0.0'})
 environment_variables=[ordered]@{
  AZURE_AI_MODEL_DEPLOYMENT_NAME=[string]$draft.definition.environment_variables.AZURE_AI_MODEL_DEPLOYMENT_NAME
  JAWS_INVESTIGATION_TOOLBOX_NAME='jaws-investigation-a2a-tools'
 }
}
$payload=[ordered]@{draft=$false;definition=$definition}
$json=ConvertTo-Json -InputObject $payload -Depth 15 -Compress
$sha=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($json))).ToLowerInvariant()
[pscustomobject]@{
 Agent=$agent;SourceDraft=[string]$draft.version;Image=$image;Operation='CreateNonDraftRelease'
 PlanSha256=$sha;LeavesSupervisorV1Unchanged=$true;MayChangeLatestRouting=$true;Payload=$payload
} | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding utf8
if($Mode -eq 'Plan'){
 Write-Host "Source draft: $($draft.version)"
 Write-Host "Image: $image"
 Write-Host 'WARNING: A non-draft release can change latest-version routing. Supervisor v1 remains available.'
 Write-Host "Plan SHA-256: $sha"
 Write-Host "Plan: $path"
 Write-Host 'PLAN ONLY: no Azure writes.'
 return
}
if(-not $AcknowledgeTrafficAndInferenceCharges -or $ApprovedPlanSha256 -cne $sha){
 throw 'JAWS-SUP-CANDIDATE-007: Exact plan approval and traffic acknowledgment required.'
}
$tmp=[IO.Path]::GetTempFileName()
try{
 [IO.File]::WriteAllText($tmp,$json,[Text.UTF8Encoding]::new($false))
 $out=& az rest --method post --url "$endpoint/agents/$agent/versions?api-version=v1" --resource https://ai.azure.com --headers 'Content-Type=application/json' --body "@$tmp" --output json --only-show-errors 2>&1
 if($LASTEXITCODE -ne 0){throw "JAWS-SUP-CANDIDATE-008: Release result uncertain. Inspect the agent before retrying: $($out|Out-String)"}
 $created=$out|Out-String|ConvertFrom-Json
}finally{Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue}
if($created.draft -ne $false -or [string]$created.definition.container_configuration.image -cne $image){
 throw 'JAWS-SUP-CANDIDATE-009: Release response did not match the approved image. Inspect Azure state; do not retry.'
}
$v1After=Read-Foundry "$endpoint/agents/$agent/versions/1?api-version=v1"
if([string]$v1After.definition.container_configuration.image -cne [string]$v1.definition.container_configuration.image -or $v1After.status -ne 'active'){
 throw 'JAWS-SUP-CANDIDATE-010: Supervisor v1 changed during release. Stop and inspect Azure state.'
}
Write-Host "Supervisor release created: $($created.version). Image: $image. Supervisor v1 unchanged."
Write-Host "Re-run SupervisorV2Verify -ExpectedImage $image after the version is active."
