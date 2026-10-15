# Step C final acceptance: authenticated Responses invocation and evidence-based A2A verification.
[CmdletBinding()]
param(
 [switch]$AcknowledgeInferenceCharges,
 [string]$ExpectedImage='jawsregistrydev001.azurecr.io/jaws/supervisor@sha256:5a9cd89cfc626df4bdd2266194db14cda8fd33f46de1bfbc9c1111cde1c8af54'
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
$body=@{model='gpt-5-mini';input='Use the Investigation A2A toolbox for a read-only investigation planning request. Identify three diagnostic checks for an unhealthy Azure VM. Do not perform any remediation. Report what the Investigation agent actually returned.';stream=$false;store=$false}|ConvertTo-Json -Depth 8 -Compress
$tmp=[IO.Path]::GetTempFileName()
try{
 [IO.File]::WriteAllText($tmp,$body,[Text.UTF8Encoding]::new($false))
 $raw=& az rest --method post --url "$endpoint/agents/$agent/endpoint/protocols/openai/responses?api-version=v1" --resource https://ai.azure.com --headers 'Content-Type=application/json' --body "@$tmp" --output json --only-show-errors 2>&1
 if($LASTEXITCODE -ne 0){throw "JAWS-C-ACCEPT-006: Supervisor invocation failed: $($raw|Out-String)"}
 $response=$raw|Out-String|ConvertFrom-Json -ErrorAction Stop
}finally{Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue}
Import-Module (Join-Path $root 'modules/DelegationEvidence.psm1') -Force
$evidence=Get-JawsDelegationEvidence -Response $response
$outputTypes=@($response.output | ForEach-Object { if($_ -and $_.PSObject.Properties['type']){[string]$_.type}else{'<missing-type>'} })
$status=if($evidence.ResponseCompleted -and $evidence.Classification -ceq 'TOOL_INVOKED_SUCCEEDED'){'PASS'}else{'FAIL'}
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
 OutputItemTypes=$outputTypes
 ToolCalls=$evidence.Calls
 ToolCallCount=$evidence.AttemptCount
 SuccessfulInvestigationCalls=$evidence.InvestigationSuccessCount
 EvidenceLimitations='Tool-call output alone does not prove target agent execution; correlate with Foundry traces before final closure.'
 RemediationRequested=$false
 AzureInfrastructureWrites=0
 InferencePerformed=$true
 TimestampUtc=[DateTime]::UtcNow.ToString('o')
}
$path=Join-Path $root '.local/jaws-step-c-final-acceptance.dev.generated.json'
$report|ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $path -Encoding utf8
Write-Host "Supervisor status: $($response.status); output types: $($outputTypes -join ', ')"
Write-Host "Delegation classification: $($evidence.Classification)"
foreach($call in $evidence.Calls){
 Write-Host "Tool: $($call.ToolName); output present: $($call.OutputPresent); failed: $($call.Failed)"
 if($call.OutputExcerpt){Write-Host "Tool output excerpt: $($call.OutputExcerpt)"}
}
Write-Host "Step C acceptance: $status; report: $path"
if($status -ne 'PASS'){throw "JAWS-C-ACCEPT-007: $($evidence.Classification). See tool output in acceptance report; Step C not closed."}
