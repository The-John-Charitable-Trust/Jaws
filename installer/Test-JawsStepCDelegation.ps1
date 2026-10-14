# Step C final acceptance: authenticated Responses invocation and evidence-based A2A verification.
[CmdletBinding()]
param([switch]$AcknowledgeInferenceCharges)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$endpoint='https://jaws-foundry-dev.services.ai.azure.com/api/projects/jaws-dev'
$agent='jaws-supervisor-dev'
$expectedImage='jawsregistrydev001.azurecr.io/jaws/supervisor@sha256:5a9cd89cfc626df4bdd2266194db14cda8fd33f46de1bfbc9c1111cde1c8af54'
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
$v2=Get-Jaws "$endpoint/agents/$agent/versions/2?api-version=v1"
$summary=Get-Jaws "$endpoint/agents/$($agent)?api-version=v1"
if($v1.status -ne 'active' -or $v2.status -ne 'active' -or $v2.draft -ne $false -or
 $v2.definition.container_configuration.image -cne $expectedImage -or
 $v2.definition.environment_variables.JAWS_INVESTIGATION_TOOLBOX_NAME -cne 'jaws-investigation-a2a-tools'){
 throw 'JAWS-C-ACCEPT-004: Live Supervisor v1/v2 release state mismatch.'
}
# The unversioned Responses endpoint must route to release v2. Do not test v1 inadvertently.
$latest=[string]$summary.versions.latest
if($latest -ne '2' -and [string]$summary.versions.latest.version -ne '2'){
 throw 'JAWS-C-ACCEPT-005: Latest routing not confirmed as v2; no invocation attempted.'
}
$body=@{model='gpt-5-mini';input='Use the Investigation A2A toolbox for a read-only investigation planning request. Identify three diagnostic checks for an unhealthy Azure VM. Do not perform any remediation. Report what the Investigation agent actually returned.';stream=$false;store=$false}|ConvertTo-Json -Depth 8 -Compress
$tmp=[IO.Path]::GetTempFileName()
try{
 [IO.File]::WriteAllText($tmp,$body,[Text.UTF8Encoding]::new($false))
 $raw=& az rest --method post --url "$endpoint/agents/$agent/endpoint/protocols/openai/responses?api-version=v1" --resource https://ai.azure.com --headers 'Content-Type=application/json' --body "@$tmp" --output json --only-show-errors 2>&1
 if($LASTEXITCODE -ne 0){throw "JAWS-C-ACCEPT-006: Supervisor invocation failed: $($raw|Out-String)"}
 $response=$raw|Out-String|ConvertFrom-Json -ErrorAction Stop
}finally{Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue}
$items=@($response.output)
$toolEvidence=@($items|Where-Object { $_ -and $_.PSObject.Properties['type'] -and [string]$_.type -match '(?i)(a2a|tool|mcp)' -and (($_ | ConvertTo-Json -Depth 12 -Compress) -match '(?i)(jaws-investigation|jaws-investigation-a2a-tools|investigation-planning|/protocols/a2a)') })
$outputTypes=@($items | ForEach-Object { if($_ -and $_.PSObject.Properties['type']){[string]$_.type}else{'<missing-type>'} })
$textParts=@($items | ForEach-Object { if($_ -and $_.PSObject.Properties['content']) { foreach($part in @($_.content)){if($part -and $part.PSObject.Properties['text']){[string]$part.text}} } })
$diagnosticText=(($textParts -join ' ') -replace '[\\r\\n]+',' ').Trim()
if($diagnosticText.Length -gt 1200){$diagnosticText=$diagnosticText.Substring(0,1200)}
Write-Host "Supervisor status: $($response.status); output item types: $($outputTypes -join ', ')"
if($diagnosticText){Write-Host "Supervisor response excerpt: $diagnosticText"}
$completed=([string]$response.status -ceq 'completed')
$status=if($completed -and $toolEvidence.Count -gt 0){'PASS'}else{'FAIL'}
$report=[pscustomobject]@{
 Status=$status
 SupervisorAgent=$agent
 SupervisorVersion='2'
 InvestigationAgent='jaws-investigation-dev'
 ResponseId=[string]$response.id
 ResponseStatus=[string]$response.status
 ToolEvidenceTypes=@($toolEvidence|ForEach-Object {$_.type})
 ToolEvidenceCount=$toolEvidence.Count
 OutputItemTypes=$outputTypes
 Diagnosis=if(-not $completed){'Response did not complete'}elseif($toolEvidence.Count -eq 0){'Investigation delegation not proven: inspect output types, runtime tool enumeration and identity permissions'}else{'Investigation-related tool activity observed'}
 RemediationRequested=$false
 AzureInfrastructureWrites=0
 InferencePerformed=$true
 TimestampUtc=[DateTime]::UtcNow.ToString('o')
}
$path=Join-Path $root '.local/jaws-step-c-final-acceptance.dev.generated.json'
$report|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $path -Encoding utf8
Write-Host "Step C acceptance: $status; tool evidence items: $($toolEvidence.Count); response: $($response.id)"
Write-Host "Report: $path"
if($status -ne 'PASS'){throw 'JAWS-C-ACCEPT-007: No sufficient tool-call evidence; Step C cannot be closed.'}
