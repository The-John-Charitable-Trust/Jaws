# Step C A2A endpoint configuration for existing active Investigation v1.
# Plan/Verify are read-only. Install uses exact SHA approval and verifies read-back.
[CmdletBinding()]
param(
 [ValidateSet('Plan','Install','Verify')][string]$Mode='Plan',
 [string]$ApprovedPlanSha256,
 [switch]$AcknowledgeAgentEndpointChange,
 [string]$ProjectEndpoint='https://jaws-foundry-dev.services.ai.azure.com/api/projects/jaws-dev',
 [string]$AgentName='jaws-investigation-dev'
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($ProjectEndpoint -cne 'https://jaws-foundry-dev.services.ai.azure.com/api/projects/jaws-dev' -or
   $AgentName -cne 'jaws-investigation-dev') {throw 'JAWS-STEP-C-A2A-001: Unexpected Foundry agent scope.'}
function Read-Foundry([string]$Url) {
 $result=& az rest --method get --url $Url --resource https://ai.azure.com --output json --only-show-errors 2>&1
 if($LASTEXITCODE -ne 0) {throw "JAWS-STEP-C-A2A-002: Foundry read failed: $($result | Out-String)"}
 return ($result | Out-String | ConvertFrom-Json -ErrorAction Stop)
}
function Get-Property($obj,[string]$name) {
 if($null -eq $obj) {return $null}
 $p=$obj.PSObject.Properties[$name]
 if($null -eq $p){return $null}
 return $p.Value
}
function Test-A2A($Agent) {
 $ep=Get-Property $Agent 'agent_endpoint'
 $pc=Get-Property $ep 'protocol_configuration'
 $card=Get-Property $Agent 'agent_card'
 return ($null -ne (Get-Property $pc 'a2a') -and $null -ne (Get-Property $pc 'responses') -and
   $null -ne $card -and [string](Get-Property $card 'description') -match 'investigation')
}
$version=Read-Foundry "$ProjectEndpoint/agents/$AgentName/versions/1?api-version=v1"
if((Get-Property $version 'name') -cne $AgentName -or (Get-Property $version 'status') -ne 'active' -or
 (Get-Property (Get-Property $version 'definition') 'kind') -ne 'hosted') {
 throw 'JAWS-STEP-C-A2A-003: Existing Investigation v1 is not the expected active hosted agent.'
}
$agent=Read-Foundry "$ProjectEndpoint/agents/$($AgentName)?api-version=v1"
if((Get-Property $agent 'name') -cne $AgentName) {throw 'JAWS-STEP-C-A2A-004: Agent identity mismatch.'}
$desired=[ordered]@{
 agent_card=[ordered]@{
  description='JAWS read-only investigation planning agent. No external evidence retrieval or remediation.'
  version='1.0.0'
  skills=@([ordered]@{id='investigation-planning';name='Azure Operational Investigation';description='Plans defensible read-only investigations; does not query tools or remediate.'})
 }
 agent_endpoint=[ordered]@{protocol_configuration=[ordered]@{responses=[ordered]@{};a2a=[ordered]@{}}}
}
$payload=ConvertTo-Json -InputObject $desired -Depth 12 -Compress
$hash=[System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($payload))
$planHash=[Convert]::ToHexString($hash).ToLowerInvariant()
$dir=Join-Path $PSScriptRoot '.local'
if(-not (Test-Path $dir)){ $null=New-Item -ItemType Directory -Force -Path $dir }
$planPath=Join-Path $dir 'jaws-step-c-a2a-plan.dev.generated.json'
[pscustomobject]@{Operation='ConfigureInvestigationIncomingA2A';Agent=$AgentName;AgentVersion='1';Payload=$desired;PlanSha256=$planHash;AzureWrites=0} |
 ConvertTo-Json -Depth 18 | Set-Content -LiteralPath $planPath -Encoding utf8
$already=Test-A2A $agent
if($Mode -eq 'Plan'){
 Write-Host "Investigation A2A configured: $already"
 Write-Host "Plan SHA-256: $planHash"
 Write-Host "Plan: $planPath"
 Write-Host 'PLAN ONLY: no Azure writes. New Supervisor delegation is a separate operation.'
 return
}
if($Mode -eq 'Install' -and -not $already) {
 if(-not $AcknowledgeAgentEndpointChange -or $ApprovedPlanSha256 -cne $planHash){
  throw 'JAWS-STEP-C-A2A-005: Exact approved plan fingerprint and acknowledgment required.'
 }
 $temp=[IO.Path]::GetTempFileName()
 try {
  [IO.File]::WriteAllText($temp,$payload,[Text.UTF8Encoding]::new($false))
  $response=& az rest --method patch --url "$ProjectEndpoint/agents/$($AgentName)?api-version=v1" --resource https://ai.azure.com --headers 'Content-Type=application/merge-patch+json' --body "@$temp" --output json --only-show-errors 2>&1
  if($LASTEXITCODE -ne 0){throw "JAWS-STEP-C-A2A-006: PATCH outcome uncertain, inspect live state before retry: $($response | Out-String)"}
 } finally {Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue}
}
$actual=Read-Foundry "$ProjectEndpoint/agents/$($AgentName)?api-version=v1"
if(-not (Test-A2A $actual)) {throw 'JAWS-STEP-C-A2A-007: A2A endpoint read-back did not verify.'}
$card=Read-Foundry "$ProjectEndpoint/agents/$AgentName/endpoint/protocols/a2a/agentCard/v1.0"
if(-not (Get-Property $card 'protocolVersion') -or [string](Get-Property $card 'protocolVersion') -ne '1.0'){
 throw 'JAWS-STEP-C-A2A-008: Authenticated v1.0 agent card unavailable or version mismatch.'
}
$receipt=[pscustomobject]@{Status='A2A_AGENT_CARD_VERIFIED';AgentName=$AgentName;Version='1';Protocol='a2a';ProtocolVersion='1.0';PlanSha256=$planHash;VerifiedAtUtc=[DateTime]::UtcNow.ToString('o');SupervisorDelegationVerified=$false}
$receiptPath=Join-Path $dir 'jaws-step-c-a2a-receipt.dev.generated.json'
$receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receiptPath -Encoding utf8
Write-Host "Verified incoming A2A: $AgentName; Receipt: $receiptPath"
