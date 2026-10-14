# Step C: Foundry A2A v1.0 toolbox. No Supervisor modification.
[CmdletBinding()]
param(
 [ValidateSet('Plan','Install','Verify')][string]$Mode='Plan',
 [string]$ApprovedPlanSha256,
 [switch]$AcknowledgeToolboxChargesAndAccess
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$project='https://jaws-foundry-dev.services.ai.azure.com/api/projects/jaws-dev'
$name='jaws-investigation-a2a-tools'
$connName='jaws-investigation-a2a-dev'
$connectionUrl="$project/connections/$($connName)?api-version=v1"
function Get-Api([string]$Url,[switch]$AllowNotFound) {
 $result=& az rest --method get --url $Url --resource https://ai.azure.com --output json --only-show-errors 2>&1
 if($LASTEXITCODE -eq 0){return ($result | Out-String | ConvertFrom-Json)}
 $err=$result | Out-String
 if($AllowNotFound -and $err -match '(?i)(404|not found)'){return $null}
 throw "JAWS-TOOLBOX-001: Unable to read Foundry state: $err"
}
$conn=Get-Api -Url $connectionUrl
if($null -eq $conn -or -not $conn.id -or $conn.name -cne $connName) {
 throw 'JAWS-TOOLBOX-002: Authenticated Investigation RemoteA2A project connection not verified.'
}
$target="https://jaws-foundry-dev.services.ai.azure.com/api/projects/jaws-dev/agents/jaws-investigation-dev/endpoint/protocols/a2a"
if([string]$conn.target -cne $target -and [string]$conn.properties.target -cne $target) {
 throw 'JAWS-TOOLBOX-003: Connection target drift; refusing toolbox installation.'
}
$desired=[ordered]@{
 description='JAWS Investigation A2A v1.0 toolbox, read-only planning.'
 tools=@([ordered]@{
  type='a2a'
  a2a_version='1.0'
  base_url=$target
  project_connection_id=[string]$conn.id
 })
}
$payload=ConvertTo-Json -InputObject $desired -Depth 15 -Compress
$hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($payload))).ToLowerInvariant()
$local=Join-Path $PSScriptRoot '.local'
if(-not(Test-Path $local)){$null=New-Item -ItemType Directory -Force -Path $local}
$planPath=Join-Path $local 'jaws-step-c-toolbox-plan.dev.generated.json'
[pscustomobject]@{ToolboxName=$name;ConnectionId=$conn.id;PlanSha256=$hash;Target=$target;AzureWrites=0} |
 ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $planPath -Encoding utf8
$versionsUrl="$project/toolboxes/$name/versions?api-version=v1"
$existing=Get-Api -Url $versionsUrl -AllowNotFound
$items=if($null -ne $existing -and $null -ne $existing.value){@($existing.value)}else{@()}
if($Mode -eq 'Plan') {
 Write-Host "Toolbox versions discovered: $($items.Count); Plan SHA-256: $hash"
 Write-Host "Plan: $planPath"
 Write-Host 'PLAN ONLY: no writes; existing versions must be reconciled before new version creation.'
 return
}
if($Mode -eq 'Install' -and $items.Count -eq 0){
 if($ApprovedPlanSha256 -cne $hash -or -not $AcknowledgeToolboxChargesAndAccess) {
  throw 'JAWS-TOOLBOX-004: Exact toolbox plan approval and cost/security acknowledgment required.'
 }
 $file=[IO.Path]::GetTempFileName()
 try {
  [IO.File]::WriteAllText($file,$payload,[Text.UTF8Encoding]::new($false))
  $created=& az rest --method post --url $versionsUrl --resource https://ai.azure.com --headers 'Content-Type=application/json' --body "@$file" --output json --only-show-errors 2>&1
  if($LASTEXITCODE -ne 0){throw "JAWS-TOOLBOX-005: Toolbox create outcome uncertain. Inspect Foundry before retrying: $($created | Out-String)"}
 } finally {Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue}
} elseif($Mode -eq 'Install' -and $items.Count -gt 0) {
 throw 'JAWS-TOOLBOX-006: Existing toolbox versions detected. Refuse to replace or add a version without verified configuration comparison.'
}
$actual=Get-Api -Url $versionsUrl
if($null -eq $actual -or $null -eq $actual.value -or @($actual.value).Count -eq 0) {
 throw 'JAWS-TOOLBOX-007: Toolbox version not verifiable.'
}
Write-Host "Toolbox versions available: $(@($actual.value).Count)"
Write-Host 'Supervisor v1 unchanged. Hosted runtime toolbox registration and live delegation are not yet verified.'
