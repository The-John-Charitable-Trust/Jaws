# Read-only check that the A2A target is the prompt planner, not the hosted Investigation agent.
[CmdletBinding()]
param(
 [string]$ProjectEndpoint='https://jaws-foundry-dev.services.ai.azure.com/api/projects/jaws-dev',
 [string]$AgentName='jaws-investigation-planner-dev'
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($ProjectEndpoint -cne 'https://jaws-foundry-dev.services.ai.azure.com/api/projects/jaws-dev' -or
   $AgentName -cne 'jaws-investigation-planner-dev') {
 throw 'JAWS-PLANNER-001: Unexpected planner scope.'
}
function Read-Foundry([string]$Url) {
 $result=& az rest --method get --url $Url --resource https://ai.azure.com --output json --only-show-errors 2>&1
 if($LASTEXITCODE -ne 0) {throw "JAWS-PLANNER-002: Foundry read failed: $($result | Out-String)"}
 return ($result | Out-String | ConvertFrom-Json -ErrorAction Stop)
}
$agent=Read-Foundry "$ProjectEndpoint/agents/${AgentName}?api-version=v1"
$version=Read-Foundry "$ProjectEndpoint/agents/$AgentName/versions/1?api-version=v1"
$kind=[string]$version.definition.kind
$model=[string]$version.definition.model
$instructions=[string]$version.definition.instructions
$protocols=@($agent.agent_endpoint.protocols)
if($agent.name -cne $AgentName -or $version.status -cne 'active' -or $kind -cne 'prompt' -or
   $model -cne 'gpt-5-mini' -or $instructions -notmatch 'INVESTIGATION PLANNING ONLY' -or
   $protocols -notcontains 'a2a' -or $protocols -notcontains 'responses') {
 throw 'JAWS-PLANNER-003: Prompt planner is not the expected active A2A target.'
}
Write-Host "Investigation prompt planner verified: $AgentName version 1 kind=$kind model=$model"
