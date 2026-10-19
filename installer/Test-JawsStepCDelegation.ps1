# Step C final acceptance: authenticated Responses invocation and evidence-based A2A verification.
[CmdletBinding()]
param(
 [switch]$AcknowledgeInferenceCharges,
 [string]$ExpectedImage='jawsregistrydev001.azurecr.io/jaws/supervisor@sha256:86c556fff7f54eb8ad81c84bc768093fd7bc083e941e9e16bbf1ea8bc0cfa289'
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$endpoint='https://jaws-foundry-dev.services.ai.azure.com/api/projects/jaws-dev'
$agent='jaws-supervisor-dev'
if($ExpectedImage -cnotmatch '^jawsregistrydev001\.azurecr\.io/jaws/supervisor@sha256:[a-f0-9]{64}$'){
 throw 'JAWS-C-ACCEPT-009: Expected Supervisor image must be an immutable jaws/supervisor digest.'
}
if(-not $AcknowledgeInferenceCharges){throw 'JAWS-C-ACCEPT-001: Explicit inference charge acknowledgment required.'}
& (Join-Path $root 'Install-JawsStepC.ps1') -Mode DelegationVerify
if(-not $?){throw 'JAWS-C-ACCEPT-002: Delegation prerequisites not verified.'}
# Reject before billable inference when the released Supervisor identity cannot
# authenticate to the project toolbox and Investigation A2A endpoint.
& (Join-Path $root 'Configure-JawsDelegationConsumerRbac.ps1') -Mode Verify
if(-not $?){throw 'JAWS-C-ACCEPT-008: Supervisor delegation RBAC not verified.'}
function Get-Jaws([string]$url){
 $out=& az rest --method get --url $url --resource https://ai.azure.com --output json --only-show-errors 2>&1
 if($LASTEXITCODE -ne 0){throw "JAWS-C-ACCEPT-003: Cannot verify agent: $($out|Out-String)"}
 return ($out|Out-String|ConvertFrom-Json -ErrorAction Stop)
}
$v1=Get-Jaws "$endpoint/agents/$agent/versions/1?api-version=v1"
$summary=Get-Jaws "$endpoint/agents/$($agent)?api-version=v1"
$latestValue=$summary.versions.latest
$latest=if($latestValue -is [string] -or $latestValue -is [ValueType]){[string]$latestValue}
 elseif($latestValue.PSObject.Properties['version']){[string]$latestValue.version}
 else{''}
if($latest -notmatch '^[0-9]+$' -or $latest -eq '1'){
 throw 'JAWS-C-ACCEPT-005: Latest routing is not a released Supervisor version after v1; no invocation attempted.'
}
$routed=Get-Jaws "$endpoint/agents/$agent/versions/${latest}?api-version=v1"
if($v1.status -ne 'active' -or $routed.status -ne 'active' -or $routed.draft -ne $false -or
 $routed.definition.container_configuration.image -cne $ExpectedImage -or
 $routed.definition.environment_variables.JAWS_INVESTIGATION_TOOLBOX_NAME -cne 'jaws-investigation-a2a-tools'){
 throw 'JAWS-C-ACCEPT-004: Live Supervisor release state does not match the expected image.'
}
$body=@{model='gpt-5-mini';input='Call the Investigation A2A toolbox tool now for a read-only investigation planning request. Identify three diagnostic checks for an unhealthy Azure VM. Do not perform any remediation. Do not answer from your own knowledge. Report what the Investigation agent actually returned.';stream=$false;store=$false}|ConvertTo-Json -Depth 8 -Compress
Import-Module (Join-Path $root 'modules/DelegationEvidence.psm1') -Force
Import-Module (Join-Path $root 'modules/MilestoneResult.psm1') -Force
$response=Invoke-JawsSupervisorAcceptanceResponse -Url "$endpoint/agents/$agent/endpoint/protocols/openai/responses?api-version=v1" -Body $body -DevProject
$evidence=Get-JawsDelegationEvidence -Response $response
$outputTypes=@($response.output | ForEach-Object { if($_ -and $_.PSObject.Properties['type']){[string]$_.type}else{'<missing-type>'} })
$excerpt=((@($evidence.Calls | ForEach-Object { [string]$_.OutputExcerpt })) -join "`n")
$taskState=if($excerpt -match 'TASK_STATE_[A-Z_]+'){$Matches[0]}else{''}
$status=Get-JawsStepCAcceptanceStatus -Evidence $evidence -Response $response -TaskState $taskState
$rateLimited=Test-JawsSupervisorRateLimit $response
$acceptedUnderRateLimit=($status -eq 'PASS' -and $rateLimited -and -not $evidence.ResponseCompleted)
$plannerResponseId=if($excerpt -match 'resp_[A-Za-z0-9]+'){$Matches[0]}else{''}
$report=[pscustomobject]@{
 Status=$status
 Classification=$evidence.Classification
 SupervisorAgent=$agent
 SupervisorVersion=$latest
 InvestigationAgent='jaws-investigation-planner-dev'
 HostedInvestigationAgent='jaws-investigation-dev'
 A2ATargetLimitation='Foundry returns HOSTED_AGENT_NOT_SUPPORTED for A2A operations against a hosted agent. The RemoteA2A connection targets the prompt planner.'
 ResponseId=[string]$response.id
 ResponseStatus=[string]$response.status
 ResponseErrorCode=[string](Get-JawsField (Get-JawsField $response 'error') 'code')
 ResponseErrorMessage=[string](Get-JawsField (Get-JawsField $response 'error') 'message')
 RateLimitAttempts=[int]$response.JawsRateLimitAttempts
 AcceptanceBasis=$(if($acceptedUnderRateLimit){'DelegationCompletedUnderRateLimit'}elseif($evidence.ResponseCompleted){'ResponseCompleted'}else{''})
 OperatorAction=$(if($acceptedUnderRateLimit){'The Supervisor response was rate-limited after the Investigation task completed. Acceptance used TOOL_INVOKED_SUCCEEDED and TASK_STATE_COMPLETED.'}elseif($rateLimited){Get-JawsRateLimitOperatorAction -DevProject}else{''})
 QuotaRequest=''
 TaskState=$taskState
 PlannerResponseId=$plannerResponseId
 OutputItemTypes=$outputTypes
 ToolCalls=$evidence.Calls
 ToolCallCount=$evidence.AttemptCount
 SuccessfulInvestigationCalls=$evidence.InvestigationSuccessCount
 EvidenceLimitations='store=false leaves this response unreadable on a later GET. TaskState and PlannerResponseId are captured from the tool output for that reason. Tool output still has to be correlated with Foundry traces before treating a new run as closure evidence.'
 RemediationRequested=$false
 AzureInfrastructureWrites=0
 InferencePerformed=$true
 TimestampUtc=[DateTime]::UtcNow.ToString('o')
}
$path=Join-Path $root '.local/jaws-step-c-final-acceptance.dev.generated.json'
$report|ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $path -Encoding utf8
Write-Host "Supervisor status: $($response.status); output types: $($outputTypes -join ', ')"
$responseError=Get-JawsField $response 'error'
if(-not [string]::IsNullOrWhiteSpace([string](Get-JawsField $responseError 'message'))){
 Write-Host "Supervisor error: $([string](Get-JawsField $responseError 'code')); $([string](Get-JawsField $responseError 'message'))"
}
Write-Host "Delegation classification: $($evidence.Classification)"
if($acceptedUnderRateLimit){
 Write-Host 'Supervisor response was rate-limited after the Investigation task completed. Acceptance used the completed tool result.'
}
foreach($call in $evidence.Calls){
 Write-Host "Tool: $($call.ToolName); output present: $($call.OutputPresent); failed: $($call.Failed)"
 if($call.OutputExcerpt){Write-Host "Tool output excerpt: $($call.OutputExcerpt)"}
}
Write-Host "Step C acceptance: $status; report: $path"
Import-Module (Join-Path $root 'modules/MilestoneResult.psm1') -Force
$stepCPassed = ($status -eq 'PASS' -and $taskState -eq 'TASK_STATE_COMPLETED')
Write-JawsMilestoneResult -Result $(if($stepCPassed){'PASS'}else{'FAIL'}) -ReadyForNextStep $stepCPassed -NextStep $(if($stepCPassed){'Step D Validate'}else{'Step C inference acceptance'}) -EvidencePath $path
if($status -ne 'PASS' -and (Test-JawsSupervisorRateLimit $response)){
 throw (Get-JawsRateLimitAcceptanceFailure $response -DevProject)
}
if($status -ne 'PASS'){throw "JAWS-C-ACCEPT-007: $($evidence.Classification). See tool output in acceptance report; Step C not closed."}
