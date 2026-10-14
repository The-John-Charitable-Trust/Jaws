# Read-only identity context investigation for Step C, no credentials emitted.
[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root='https://jaws-foundry-dev.services.ai.azure.com/api/projects/jaws-dev'
function Read-Json([string]$url) {
 $out=& az rest --method get --url $url --resource https://ai.azure.com --output json --only-show-errors 2>&1
 if($LASTEXITCODE -ne 0){throw "JAWS-A2A-IDENTITY-001: Read failed: $($out | Out-String)"}
 return ($out|Out-String|ConvertFrom-Json -ErrorAction Stop)
}
$supervisor=Read-Json "$root/agents/jaws-supervisor-dev/versions/2?api-version=v1"
$connection=Read-Json "$root/connections/jaws-investigation-a2a-dev?api-version=v1"
$props=if($connection.PSObject.Properties['properties']){$connection.properties}else{$connection}
function Get-OptionalProperty($Object,[string]$Name) {
 if($null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]) {return $Object.PSObject.Properties[$Name].Value}
 return $null
}
$authType=Get-OptionalProperty $props 'authType'
if(-not $authType){$authType=Get-OptionalProperty $props 'authenticationType'}
$category=Get-OptionalProperty $props 'category'
$target=Get-OptionalProperty $props 'target'
$identity=$supervisor.instance_identity
$blueprint=$supervisor.blueprint
$status=if($identity -and $identity.client_id -and $blueprint -and $blueprint.client_id -and [string]$authType -eq 'AgenticIdentityToken'){'IDENTITY_CONTEXT_AVAILABLE'}else{'IDENTITY_CONTEXT_INCOMPLETE'}
$result=[pscustomobject]@{
 Status=$status
 SupervisorVersion=[string]$supervisor.version
 InstanceClientId=if($identity){[string]$identity.client_id}else{''}
 BlueprintClientId=if($blueprint){[string]$blueprint.client_id}else{''}
 ConnectionAuthType=[string]$props.authType
 ConnectionCategory=[string]$category
 Target=[string]$target
 ConnectionPropertyNames=@($props.PSObject.Properties.Name)
 Finding='Connection authType missing from this projection does not prove the stored ARM connection is invalid. Confirm via management-plane read if needed.'
 AzureWrites=0
 VerifiedAtUtc=[DateTime]::UtcNow.ToString('o')
}
$file=Join-Path $PSScriptRoot '.local/jaws-step-c-identity-context.dev.generated.json'
$result|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $file -Encoding utf8
Write-Host "Step C A2A identity context: $status"
Write-Host "Supervisor identity context found: $([bool]$identity.client_id)"
Write-Host "Supervisor blueprint context found: $([bool]$blueprint.client_id)"
Write-Host "Connection authentication: $($result.ConnectionAuthType)"
Write-Host "Report: $file"
if($status -ne 'IDENTITY_CONTEXT_AVAILABLE'){throw 'JAWS-A2A-IDENTITY-002: Identity context unavailable; no changes made.'}
