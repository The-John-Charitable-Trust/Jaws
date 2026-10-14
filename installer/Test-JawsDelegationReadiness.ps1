# Step C: read-only hosted-agent and A2A readiness. No Azure writes.
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
 try {return ($output | Out-String | ConvertFrom-Json -ErrorAction Stop)}
 catch {throw "JAWS-A2A-004: Foundry returned invalid JSON for $Name."}
}
function Get-Field($Object,[string]$Property) {
 if($null -eq $Object) { return $null }
 $p=$Object.PSObject.Properties[$Property]
 if($null -eq $p) {return $null}
 return $p.Value
}
$supervisor=Read-Agent $Supervisor
$investigation=Read-Agent $Investigation
foreach($item in @(@{Name=$Supervisor;Data=$supervisor},@{Name=$Investigation;Data=$investigation})) {
 $agent=$item.Data
 $name=Get-Field $agent 'name'
 $status=Get-Field $agent 'status'
 $definition=Get-Field $agent 'definition'
 $kind=Get-Field $definition 'kind'
 $version=Get-Field $agent 'version'
 Write-Host "Foundry $($item.Name): name=$name; version=$version; status=$(if($null -eq $status){'<not returned>'}else{$status}); kind=$(if($null -eq $kind){'<not returned>'}else{$kind})"
 if($name -cne $item.Name -or $null -eq $definition -or $kind -ne 'hosted') {
  throw "JAWS-A2A-003: Foundry did not confirm hosted agent identity for $($item.Name)."
 }
 if($null -eq $status) {
  Write-Warning "JAWS-A2A-005: No status in $($item.Name) version response. Activation is unverified; inspect raw agent GET before delegation."
 } elseif($status -ne 'active') {
  throw "JAWS-A2A-003: $($item.Name) version 1 is not active (status=$status)."
 }
}
$definition=Get-Field $investigation 'definition'
$protocols=@(Get-Field $definition 'protocol_versions')
$protocolNames=@($protocols | Where-Object { $null -ne $_ } | ForEach-Object { Get-Field $_ 'protocol' })
$target="$ProjectEndpoint/agents/$Investigation/endpoint/protocols/a2a"
Write-Host "Investigation configured protocols: $($protocolNames -join ', ')"
Write-Host "Proposed A2A endpoint (not validated): $target"
if($protocolNames -notcontains 'a2a') {
 Write-Warning 'JAWS-A2A-006: Investigation currently does not advertise A2A. Responses-only does not prove A2A readiness. No delegation changes permitted.'
}
Write-Host 'READ-ONLY: no Azure changes, no Supervisor modification.'
