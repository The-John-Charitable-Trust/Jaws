# Step C: read-only A2A delegation readiness. No Azure writes or agent updates.
[CmdletBinding()]
param(
 [string]$ProjectEndpoint='https://jaws-foundry-dev.services.ai.azure.com/api/projects/jaws-dev',
 [string]$Supervisor='jaws-supervisor-dev',
 [string]$Investigation='jaws-investigation-dev'
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($ProjectEndpoint -cne 'https://jaws-foundry-dev.services.ai.azure.com/api/projects/jaws-dev' -or
   $Supervisor -cne 'jaws-supervisor-dev' -or $Investigation -cne 'jaws-investigation-dev') {
 throw 'JAWS-A2A-001: Unexpected project or agent identity.'
}
function Read-Agent([string]$Name) {
 $url="$ProjectEndpoint/agents/$Name/versions/1?api-version=v1"
 $output=& az rest --method get --url $url --resource https://ai.azure.com --output json --only-show-errors 2>&1
 if($LASTEXITCODE -ne 0) {throw "JAWS-A2A-002: Cannot read $Name version 1: $($output | Out-String)"}
 return ($output | Out-String | ConvertFrom-Json)
}
$supervisor=Read-Agent $Supervisor
$investigation=Read-Agent $Investigation
foreach($agent in @($supervisor,$investigation)) {
 if($agent.status -ne 'active' -or $agent.definition.kind -ne 'hosted') {
  throw "JAWS-A2A-003: Agent $($agent.name) is not an active hosted agent."
 }
}
$target="$ProjectEndpoint/agents/$Investigation/endpoint/protocols/a2a"
Write-Host "Supervisor: $($supervisor.name):$($supervisor.version) ($($supervisor.status))"
Write-Host "Investigation: $($investigation.name):$($investigation.version) ($($investigation.status))"
Write-Host "Investigation A2A target: $target"
Write-Host "Investigation protocols: $((@($investigation.definition.protocol_versions) | ForEach-Object { $_.protocol }) -join ', ')"
if(@($investigation.definition.protocol_versions | Where-Object { $_.protocol -eq 'a2a' }).Count -eq 0) {
 Write-Warning 'A2A is not listed as enabled. Do not create the A2A connection until incoming A2A is enabled and authenticated.'
}
Write-Host 'READ-ONLY: no Azure changes, no Supervisor modification.'
