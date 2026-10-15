# Stage B2 Microsoft Foundry hosted Supervisor installer.
# Read-only Plan; explicit approved Deploy can create one agent.
[CmdletBinding()]
param(
    [ValidateSet('Plan','Deploy')][string]$Mode='Plan',
    [string]$StateFile=(Join-Path $PSScriptRoot 'config/jaws-installation-state.dev.json'),
    [string]$PublishReceiptFile=(Join-Path $PSScriptRoot '.local/jaws-supervisor-publish-receipt.dev.generated.json'),
    [string]$AgentName='jaws-supervisor-dev',
    [string]$ToolboxName,
    [string]$ApprovedPlanSha256,
    [switch]$AcknowledgeHostingAndInferenceCharges
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'modules/InstallationState.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'modules/FoundrySupervisorDeployment.psm1') -Force
$state=Read-JawsInstallationState -Path $StateFile
if ($null -eq $state) {throw 'JAWS-FOUNDRY-019: Authoritative JAWS state required.'}
if (-not (Test-Path -LiteralPath $PublishReceiptFile -PathType Leaf)) {
    throw 'JAWS-FOUNDRY-020: Verified ACR publish receipt not found.'
}
$receipt=Get-Content -LiteralPath $PublishReceiptFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
$plan=New-JawsFoundrySupervisorPlan -State $state -PublishReceipt $receipt -AgentName $AgentName -ToolboxName $ToolboxName
$outDir=Join-Path $PSScriptRoot '.local'
if (-not (Test-Path -LiteralPath $outDir)) {$null=New-Item -ItemType Directory -Path $outDir -Force}
$report=Join-Path $outDir "jaws-foundry-supervisor-plan.$($state.EnvironmentName).generated.json"
$plan | ConvertTo-Json -Depth 25 | Set-Content -LiteralPath $report -Encoding utf8
Write-Host "Target: $($plan.Plan.ProjectEndpoint) | Agent: $AgentName"
Write-Host "Immutable image: $($plan.Plan.Image)"
Write-Host "Plan SHA-256: $($plan.PlanSha256)"
Write-Host "Plan report: $report"
Write-Host 'Hosted compute and model inference may create charges; exact prices/quotas not independently verified.'
if ($Mode -eq 'Plan') {
    Write-Host 'PLAN ONLY: zero Azure calls/writes. Deployment not approved.'
    return
}
if (-not $AcknowledgeHostingAndInferenceCharges -or
    [string]::IsNullOrWhiteSpace($ApprovedPlanSha256) -or
    $ApprovedPlanSha256 -cne $plan.PlanSha256) {
    throw 'JAWS-FOUNDRY-APPROVAL-001: Exact plan digest and explicit hosting/inference cost acknowledgment required.'
}
# If an earlier POST submitted this exact image, reconcile its recorded state.
# A missing/inconsistent version list does not authorize a duplicate create.
$receiptPath=Join-Path $outDir "jaws-foundry-supervisor-deploy-receipt.$($state.EnvironmentName).generated.json"
if($ToolboxName -eq 'jaws-investigation-a2a-tools' -and (Test-Path -LiteralPath $receiptPath -PathType Leaf)){
 $prior=Get-Content -LiteralPath $receiptPath -Raw|ConvertFrom-Json
 if([string]$prior.Image -ceq [string]$plan.Plan.Image){
  Write-Host 'Matching previous deployment receipt found. Reconciling without new POST.'
  & (Join-Path $PSScriptRoot 'Reconcile-JawsSupervisorCandidate.ps1') -Mode Wait
  $verified=Get-Content (Join-Path $outDir 'jaws-step-c-supervisor-deployment-verified.dev.generated.json') -Raw|ConvertFrom-Json
  $prior.Status=[string]$verified.Status
  $prior.Version=[string]$verified.ResolvedVersion
  $prior.ActiveVerified=[bool]$verified.ActiveVerified
  $prior|ConvertTo-Json -Depth 15|Set-Content -LiteralPath $receiptPath -Encoding utf8
  Write-Host "Recovered deployment: $($prior.Status); version $($prior.Version)"
  return
 }
}
$result=Invoke-JawsFoundrySupervisorDeployment -DeploymentPlan $plan
$receiptPath=Join-Path $outDir "jaws-foundry-supervisor-deploy-receipt.$($state.EnvironmentName).generated.json"
$result | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $receiptPath -Encoding utf8
Write-Host "Deployment: $($result.Status) | Agent: $($result.AgentName) | Version: $($result.Version)"
Write-Host "Receipt: $receiptPath"
# Automatically reconcile the submitted image by immutable digest.
# Read-only reconciliation never retries the deployment POST.
if($ToolboxName -eq 'jaws-investigation-a2a-tools'){
 try{
  & (Join-Path $PSScriptRoot 'Reconcile-JawsSupervisorCandidate.ps1') -Mode Wait
 }catch{
  $result.Status='RECONCILIATION_INDETERMINATE'
  $result.ActiveVerified=$false
  $result | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $receiptPath -Encoding utf8
  throw "JAWS-FOUNDRY-025: Candidate reconciliation incomplete. No second deployment permitted. $($_.Exception.Message)"
 }
 $verified=Get-Content (Join-Path $outDir 'jaws-step-c-supervisor-deployment-verified.dev.generated.json') -Raw|ConvertFrom-Json
 $result.Status=[string]$verified.Status
 $result.Version=[string]$verified.ResolvedVersion
 $result.ActiveVerified=[bool]$verified.ActiveVerified
 $result | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $receiptPath -Encoding utf8
 Write-Host "Deployment reconciled: $($result.Status); version $($result.Version)"
}else{
 Write-Host 'Deployment initiated only. Version must become active and pass authenticated invocation before acceptance.'
}
