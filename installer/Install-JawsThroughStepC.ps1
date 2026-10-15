# One Step C installation for the dev project.
# Validate reads Azure and writes nothing. Install applies one known correction per failed gate,
# re-checks that gate, and stops on any other drift. Supervisor v1 is never modified and no
# Supervisor version is posted.
[CmdletBinding()]
param(
 [ValidateSet('Validate','Install')][string]$Mode='Validate',
 [switch]$AcknowledgeStepCInstall,
 [switch]$AcknowledgeInferenceCharges,
 [string]$ExpectedImage='jawsregistrydev001.azurecr.io/jaws/supervisor@sha256:86c556fff7f54eb8ad81c84bc768093fd7bc083e941e9e16bbf1ea8bc0cfa289'
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
Import-Module (Join-Path $root 'modules/StepCInstall.psm1') -Force
Import-Module (Join-Path $root 'modules/FoundrySupervisorReconciliation.psm1') -Force
if($ExpectedImage -cnotmatch '^jawsregistrydev001\.azurecr\.io/jaws/supervisor@sha256:[a-f0-9]{64}$'){
 throw 'JAWS-INSTALL-C-013: Expected Supervisor image must be an immutable jaws/supervisor digest.'
}
if($Mode -eq 'Install' -and -not $AcknowledgeStepCInstall){
 throw 'JAWS-INSTALL-C-001: Install corrections require -AcknowledgeStepCInstall. -Mode Validate performs no Azure writes.'
}

$script:gateOrder=@('Prerequisites','State','InvestigationA2A','Planner','Connection','Toolbox','Rbac','Supervisor','Identity','Acceptance')
$script:gates=New-Object System.Collections.Generic.List[object]
$script:corrections=New-Object System.Collections.Generic.List[string]
$local=Join-Path $root '.local'
if(-not (Test-Path -LiteralPath $local)){ $null=New-Item -ItemType Directory -Force -Path $local | Out-Null }
$receiptPath=Join-Path $local 'jaws-step-c-install.dev.generated.json'
$a2a=Join-Path $root 'Configure-JawsInvestigationA2A.ps1'
$planner=Join-Path $root 'Configure-JawsInvestigationPlanner.ps1'
$connection=Join-Path $root 'Configure-JawsDelegationConnection.ps1'
$toolbox=Join-Path $root 'Configure-JawsDelegationToolbox.ps1'
$repair=Join-Path $root 'Repair-JawsDelegationToolbox.ps1'
$rbac=Join-Path $root 'Configure-JawsDelegationConsumerRbac.ps1'
$identity=Join-Path $root 'Test-JawsA2AIdentityContext.ps1'
$accept=Join-Path $root 'Test-JawsStepCDelegation.ps1'
$endpoint='https://jaws-foundry-dev.services.ai.azure.com/api/projects/jaws-dev'

function Add-Gate([string]$Name,[string]$Result,[string]$ErrorCode,[string]$Detail){
 $script:gates.Add([pscustomobject]@{Name=$Name;Result=$Result;ErrorCode=$ErrorCode;Detail=$Detail}) | Out-Null
}
function Read-PlanSha([string]$FileName){
 $path=Join-Path $local $FileName
 if(-not (Test-Path -LiteralPath $path -PathType Leaf)){ throw "JAWS-INSTALL-C-009: Plan file missing after the read-only check: $FileName" }
 $plan=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
 $sha=[string]$plan.PlanSha256
 if($sha -notmatch '^[a-f0-9]{64}$'){ throw "JAWS-INSTALL-C-010: Plan fingerprint is not a SHA-256 digest: $FileName" }
 return $sha
}
function Repair-KnownToolbox {
 & $repair -Mode Plan
 $sha=Read-PlanSha 'jaws-step-c-toolbox-repair-plan.dev.generated.json'
 $needsCreate=$false
 try { & $repair -Mode Verify } catch {
  if($_.Exception.Message -notmatch 'JAWS-TOOLBOX-REPAIR-008'){ throw }
  $needsCreate=$true
 }
 if($needsCreate){
  & $repair -Mode Create -ApprovedPlanSha256 $sha -AcknowledgeToolboxRepair
  & $repair -Mode Verify
 }
 & $repair -Mode Promote -ApprovedPlanSha256 $sha -AcknowledgeToolboxRepair
}
function Invoke-StepCCorrection([string]$Action){
 switch($Action){
  'PatchInvestigationA2A' {
   $sha=Read-PlanSha 'jaws-step-c-a2a-plan.dev.generated.json'
   & $a2a -Mode Install -ApprovedPlanSha256 $sha -AcknowledgeAgentEndpointChange
  }
  'CreatePlanner' {
   $sha=Read-PlanSha 'jaws-step-c-planner-plan.dev.generated.json'
   & $planner -Mode Install -ApprovedPlanSha256 $sha -AcknowledgePlannerCreate
  }
  'CreateConnection' {
   $sha=Read-PlanSha 'jaws-step-c-delegation-connection-plan.dev.generated.json'
   & $connection -Mode Install -ApprovedPlanSha256 $sha -AcknowledgeA2AConnection
  }
  'RetargetConnection' {
   $sha=Read-PlanSha 'jaws-step-c-delegation-connection-plan.dev.generated.json'
   & $connection -Mode Retarget -ApprovedPlanSha256 $sha -AcknowledgeA2AConnection
  }
  'CreateToolbox' {
   $sha=Read-PlanSha 'jaws-step-c-toolbox-plan.dev.generated.json'
   & $toolbox -Mode Install -ApprovedPlanSha256 $sha -AcknowledgeToolboxChargesAndAccess
  }
  'RepairToolbox' { Repair-KnownToolbox }
  'AssignConsumerRole' {
   $sha=Read-PlanSha 'jaws-step-c-delegation-consumer-rbac-plan.dev.generated.json'
   & $rbac -Mode Assign -ApprovedPlanSha256 $sha -AcknowledgeSecurityRoleAssignment
  }
  default { throw "JAWS-INSTALL-C-011: No correction is defined for $Action." }
 }
}
function Invoke-CorrectableGate([string]$Name,[scriptblock]$Verify){
 try {
  & $Verify
  Add-Gate $Name 'Passed' '' ''
 } catch {
  $message=$_.Exception.Message
  $action=Get-JawsStepCCorrection -Gate $Name -ErrorMessage $message -Mode $Mode
  if(-not $action){
   Add-Gate $Name 'Blocked' (Get-JawsErrorCode $message) $message
   throw
  }
  try {
   Invoke-StepCCorrection -Action $action
   & $Verify
   $script:corrections.Add($action) | Out-Null
   Add-Gate $Name 'Repaired' '' $action
  } catch {
   $repairMessage=$_.Exception.Message
   Add-Gate $Name 'Blocked' (Get-JawsErrorCode $repairMessage) $repairMessage
   throw
  }
 }
}
function Invoke-RequiredGate([string]$Name,[scriptblock]$Action){
 try {
  $result=& $Action
  if([string]$result -eq 'Skipped'){ Add-Gate $Name 'Skipped' '' 'Acceptance inference was not requested.' }
  else { Add-Gate $Name 'Passed' '' '' }
 } catch {
  $message=$_.Exception.Message
  Add-Gate $Name 'Blocked' (Get-JawsErrorCode $message) $message
  throw
 }
}
function Read-Foundry([string]$Url){
 $out=Invoke-JawsAzRestGet -Url $Url -Resource 'https://ai.azure.com' 2>&1
 if($LASTEXITCODE -ne 0){ throw "JAWS-INSTALL-C-003: Foundry read failed: $($out | Out-String)" }
 return ($out | Out-String | ConvertFrom-Json -ErrorAction Stop)
}
function Assert-SupervisorRoute {
 $summary=Read-Foundry "$endpoint/agents/jaws-supervisor-dev?api-version=v1"
 $v1=Read-Foundry "$endpoint/agents/jaws-supervisor-dev/versions/1?api-version=v1"
 if($v1.status -ne 'active' -or $v1.draft -ne $false){
  throw 'JAWS-INSTALL-C-004: Supervisor v1 is not an active release. It is not modified.'
 }
 $latestValue=if($null -ne $summary.PSObject.Properties['versions']){$summary.versions.latest}else{$null}
 $latest=if($null -eq $latestValue){''}
  elseif($latestValue -is [string] -or $latestValue -is [ValueType]){[string]$latestValue}
  elseif($latestValue.PSObject.Properties['version']){[string]$latestValue.version}
  else{''}
 if($latest -notmatch '^[0-9]+$' -or $latest -eq '1'){
  throw 'JAWS-INSTALL-C-005: Latest routing is not a released Supervisor version after v1. No version is posted.'
 }
 $versions=@(Get-JawsSupervisorVersionInventory -ReadPage { param($url) Read-Foundry $url } -ProjectEndpoint $endpoint)
 $routed=@($versions | Where-Object { [string]$_.version -ceq $latest })
 if($routed.Count -ne 1){ throw 'JAWS-INSTALL-C-006: Routed Supervisor version is missing from the detail inventory.' }
 $row=$routed[0]
 $image=[string](Get-JawsFoundryField $row @('definition','container_configuration','image'))
 $toolboxName=[string](Get-JawsFoundryField $row @('definition','environment_variables','JAWS_INVESTIGATION_TOOLBOX_NAME'))
 if([string]$row.status -cne 'active' -or $row.draft -ne $false -or $toolboxName -cne 'jaws-investigation-a2a-tools' -or $image -cne $ExpectedImage){
  throw "JAWS-INSTALL-C-007: Routed Supervisor is not the active non-draft release $ExpectedImage with the Investigation toolbox. No version is posted."
 }
 $v1Image=[string](Get-JawsFoundryField $v1 @('definition','container_configuration','image'))
 if($v1Image -ceq $image){ throw 'JAWS-INSTALL-C-008: Routed image matches Supervisor v1. Refusing to treat that as the Step C release.' }
}

$failed=$null
$status='BLOCKED'
try {
 Invoke-RequiredGate 'Prerequisites' {
  if($PSVersionTable.PSVersion.Major -lt 7){ throw 'JAWS-INSTALL-C-002: PowerShell 7 or newer is required.' }
  if(-not (Get-Command az -ErrorAction SilentlyContinue)){ throw 'JAWS-INSTALL-C-002: Azure CLI is required before Step C installation.' }
 }
 Invoke-RequiredGate 'State' {
  Import-Module (Join-Path $root 'modules/InstallationState.psm1') -Force
  $state=Read-JawsInstallationState -Path (Join-Path $root 'config/jaws-installation-state.dev.json')
  if($null -eq $state -or $state.Platform -cne 'JAWS' -or $state.EnvironmentName -cne 'dev' -or $state.ResourceGroupName -cne 'rg-aiops-lab'){
   throw 'JAWS-INSTALL-C-014: Step C installation is locked to the authoritative dev state.'
  }
 }
 Invoke-CorrectableGate 'InvestigationA2A' { & $a2a -Mode Verify }
 Invoke-CorrectableGate 'Planner' { & $planner -Mode Verify }
 Invoke-CorrectableGate 'Connection' { & $connection -Mode Verify }
 Invoke-CorrectableGate 'Toolbox' { & $toolbox -Mode Verify }
 Invoke-CorrectableGate 'Rbac' { & $rbac -Mode Verify }
 Invoke-RequiredGate 'Supervisor' { Assert-SupervisorRoute }
 Invoke-RequiredGate 'Identity' { & $identity }
 Invoke-RequiredGate 'Acceptance' {
  if(-not $AcknowledgeInferenceCharges){ return 'Skipped' }
  & $accept -AcknowledgeInferenceCharges -ExpectedImage $ExpectedImage
 }
 $acceptanceRow=@($script:gates.ToArray() | Where-Object { $_.Name -eq 'Acceptance' }) | Select-Object -Last 1
 $acceptance=if($null -eq $acceptanceRow){'Failed'}elseif($acceptanceRow.Result -eq 'Passed'){'Passed'}elseif($acceptanceRow.Result -eq 'Skipped'){'Skipped'}else{'Failed'}
 $status=Get-JawsStepCInstallStatus -GateResults @($script:gates.ToArray()) -Acceptance $acceptance
} catch {
 $failed=$_
 $status='BLOCKED'
} finally {
 $errorCode=if($failed){ Get-JawsErrorCode $failed.Exception.Message }else{''}
 $errorMessage=if($failed){ $failed.Exception.Message }else{''}
 [pscustomobject]@{
  SchemaVersion='1.0'
  Mode=$Mode
  Status=$status
  GateOrder=@($script:gateOrder)
  Gates=@($script:gates.ToArray())
  Corrections=@($script:corrections.ToArray())
  ExpectedImage=$ExpectedImage
  ErrorCode=$errorCode
  ErrorMessage=$errorMessage
  SupervisorV1Modified=$false
  SupervisorVersionPosted=$false
  AzureInfrastructureWrites=0
  CompletedAtUtc=[DateTime]::UtcNow.ToString('o')
 } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receiptPath -Encoding utf8
}
Write-Host "Step C install: $status"
foreach($gate in $script:gates.ToArray()){ Write-Host ("  {0,-20} {1}" -f $gate.Name,$gate.Result) }
if($script:corrections.Count -gt 0){ Write-Host ("Corrections: {0}" -f ($script:corrections.ToArray() -join ', ')) }
Write-Host "Receipt: $receiptPath"
if($status -eq 'VALIDATED'){
 Write-Host 'Non-billable Step C gates passed. Re-run .\installer\Install-JawsThroughStepC.ps1 -Mode Validate -AcknowledgeInferenceCharges to run the Supervisor acceptance call.'
}
if($failed){ throw $failed.Exception.Message }
