# Billable Supervisor delegation check for a Step B environment. Writes no Azure configuration.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$EnvironmentName,
    [switch]$AcknowledgeInferenceCharges,
    [string]$ExpectedImage
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
Import-Module (Join-Path $root 'modules/StepCEnvironment.psm1') -Force
$ctx=Resolve-JawsStepCStepBContext -EnvironmentName $EnvironmentName -InstallerRoot $root
if(-not [string]::IsNullOrWhiteSpace($ExpectedImage) -and $ExpectedImage -cne $ctx.ExpectedImage){
    throw 'JAWS-C-ACCEPT-009: Expected Supervisor image does not match the Step B receipt.'
}
if(-not $AcknowledgeInferenceCharges){ throw 'JAWS-C-ACCEPT-001: Explicit inference charge acknowledgment required.' }
& (Join-Path $root 'Configure-JawsInvestigationPlanner.ps1') -Mode Verify -EnvironmentName $ctx.EnvironmentName -ProjectEndpoint $ctx.ProjectEndpoint -AgentName $ctx.PlannerAgent -ModelName $ctx.ModelName
if(-not $?){ throw 'JAWS-C-ACCEPT-002: Investigation planner is not ready.' }
& (Join-Path $root 'Configure-JawsDelegationConnection.ps1') -Mode Verify -StateFile $ctx.StateFile
if(-not $?){ throw 'JAWS-C-ACCEPT-002: RemoteA2A connection is not ready.' }
& (Join-Path $root 'Configure-JawsDelegationToolbox.ps1') -Mode Verify -EnvironmentName $ctx.EnvironmentName -ProjectEndpoint $ctx.ProjectEndpoint -ToolboxName $ctx.ToolboxName -ConnectionName $ctx.ConnectionName -PlannerAgent $ctx.PlannerAgent
if(-not $?){ throw 'JAWS-C-ACCEPT-002: Investigation toolbox is not ready.' }
& (Join-Path $root 'Configure-JawsDelegationConsumerRbac.ps1') -Mode Verify -StateFile $ctx.StateFile
if(-not $?){ throw 'JAWS-C-ACCEPT-008: Supervisor delegation RBAC not verified.' }
& (Join-Path $root 'Publish-JawsStepCSupervisorRoute.ps1') -Mode Verify -EnvironmentName $ctx.EnvironmentName -ExpectedImage $ctx.ExpectedImage
function Read-Foundry([string]$Url){
    $out=& az rest --method get --url $Url --resource https://ai.azure.com --output json --only-show-errors 2>&1
    if($LASTEXITCODE -ne 0){ throw "JAWS-C-ACCEPT-003: Cannot verify agent: $($out | Out-String)" }
    return ($out | Out-String | ConvertFrom-Json -ErrorAction Stop)
}
$endpoint=$ctx.ProjectEndpoint
$agent=$ctx.SupervisorAgent
$summary=Read-Foundry "$endpoint/agents/${agent}?api-version=v1"
$latestValue=$summary.versions.latest
$latest=if($latestValue -is [string] -or $latestValue -is [ValueType]){[string]$latestValue}elseif($latestValue.PSObject.Properties['version']){[string]$latestValue.version}else{''}
if($latest -notmatch '^[0-9]+$' -or $latest -eq '1'){
    throw 'JAWS-C-ACCEPT-005: Latest routing is not a released Supervisor version after v1; no invocation attempted.'
}
$routed=Read-Foundry "$endpoint/agents/$agent/versions/${latest}?api-version=v1"
if($routed.status -ne 'active' -or $routed.draft -ne $false -or
   [string]$routed.definition.container_configuration.image -cne $ctx.ExpectedImage -or
   [string]$routed.definition.environment_variables.JAWS_INVESTIGATION_TOOLBOX_NAME -cne $ctx.ToolboxName){
    throw 'JAWS-C-ACCEPT-004: Live Supervisor release state does not match the Step B image and toolbox.'
}
$body=@{
    model=$ctx.ModelName
    input='Use the Investigation A2A toolbox for a read-only investigation planning request. Identify three diagnostic checks for an unhealthy Azure VM. Do not perform any remediation. Report what the Investigation agent actually returned.'
    stream=$false
    store=$false
} | ConvertTo-Json -Depth 8 -Compress
$tmp=[IO.Path]::GetTempFileName()
try{
    [IO.File]::WriteAllText($tmp,$body,[Text.UTF8Encoding]::new($false))
    $raw=& az rest --method post --url "$endpoint/agents/$agent/endpoint/protocols/openai/responses?api-version=v1" --resource https://ai.azure.com --headers 'Content-Type=application/json' --body "@$tmp" --output json --only-show-errors 2>&1
    if($LASTEXITCODE -ne 0){ throw "JAWS-C-ACCEPT-006: Supervisor invocation failed: $($raw | Out-String)" }
    $response=$raw | Out-String | ConvertFrom-Json -ErrorAction Stop
} finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
Import-Module (Join-Path $root 'modules/DelegationEvidence.psm1') -Force
$evidence=Get-JawsDelegationEvidence -Response $response
$outputTypes=@($response.output | ForEach-Object { if($_ -and $_.PSObject.Properties['type']){[string]$_.type}else{'<missing-type>'} })
$status=if($evidence.ResponseCompleted -and $evidence.Classification -ceq 'TOOL_INVOKED_SUCCEEDED'){'PASS'}else{'FAIL'}
$excerpt=((@($evidence.Calls | ForEach-Object { [string]$_.OutputExcerpt })) -join "`n")
$taskState=if($excerpt -match 'TASK_STATE_[A-Z_]+'){$Matches[0]}else{''}
$plannerResponseId=if($excerpt -match 'resp_[A-Za-z0-9]+'){$Matches[0]}else{''}
$report=[pscustomobject]@{
    Status=$status
    Classification=$evidence.Classification
    EnvironmentName=$ctx.EnvironmentName
    SupervisorAgent=$agent
    SupervisorVersion=$latest
    InvestigationAgent=$ctx.PlannerAgent
    HostedInvestigationAgent=''
    A2ATargetLimitation='Foundry returns HOSTED_AGENT_NOT_SUPPORTED for A2A operations against a hosted agent. This environment does not create a hosted Investigation agent. The RemoteA2A connection targets the prompt planner.'
    ResponseId=[string]$response.id
    ResponseStatus=[string]$response.status
    TaskState=$taskState
    PlannerResponseId=$plannerResponseId
    OutputItemTypes=$outputTypes
    ToolCalls=$evidence.Calls
    ToolCallCount=$evidence.AttemptCount
    SuccessfulInvestigationCalls=$evidence.InvestigationSuccessCount
    EvidenceLimitations='store=false leaves this response unreadable on a later GET. TaskState and PlannerResponseId are captured from the tool output. A stub or local file is not a customer installation receipt.'
    CustomerInstallationAccepted=$false
    RemediationRequested=$false
    AzureInfrastructureWrites=0
    InferencePerformed=$true
    TimestampUtc=[DateTime]::UtcNow.ToString('o')
}
$path=Join-Path $root ".local/jaws-step-c-final-acceptance.$($ctx.PlanSuffix).generated.json"
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $path -Encoding utf8
Write-Host "Supervisor status: $($response.status); output types: $($outputTypes -join ', ')"
Write-Host "Delegation classification: $($evidence.Classification)"
Write-Host "Task state: $taskState"
Write-Host "Step C acceptance: $status; report: $path"
Write-Host 'Customer installation accepted: false'
Import-Module (Join-Path $root 'modules/MilestoneResult.psm1') -Force
$stepCPassed = ($status -eq 'PASS' -and $taskState -eq 'TASK_STATE_COMPLETED')
Write-JawsMilestoneResult -Result $(if($stepCPassed){'PASS'}else{'FAIL'}) -ReadyForNextStep $stepCPassed -NextStep $(if($stepCPassed){'Step D Validate'}else{'Step C inference acceptance'}) -EvidencePath $path
if($status -ne 'PASS'){ throw "JAWS-C-ACCEPT-007: $($evidence.Classification). See tool output in acceptance report; Step C not closed." }
