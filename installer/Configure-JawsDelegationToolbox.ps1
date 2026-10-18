# Step C: Foundry A2A v1.0 toolbox. No Supervisor modification.
[CmdletBinding()]
param(
 [ValidateSet('Plan','Install','Verify')][string]$Mode='Plan',
 [string]$ApprovedPlanSha256,
 [switch]$AcknowledgeToolboxChargesAndAccess,
 [string]$EnvironmentName='dev',
 [string]$ProjectEndpoint='https://jaws-foundry-dev.services.ai.azure.com/api/projects/jaws-dev',
 [string]$ToolboxName='jaws-investigation-a2a-tools',
 [string]$ConnectionName='jaws-investigation-a2a-dev',
 [string]$PlannerAgent='jaws-investigation-planner-dev'
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($EnvironmentName -ceq 'dev'){
 if($ProjectEndpoint -cne 'https://jaws-foundry-dev.services.ai.azure.com/api/projects/jaws-dev' -or
    $ToolboxName -cne 'jaws-investigation-a2a-tools' -or
    $ConnectionName -cne 'jaws-investigation-a2a-dev' -or
    $PlannerAgent -cne 'jaws-investigation-planner-dev'){
  throw 'JAWS-TOOLBOX-010: Unexpected toolbox scope.'
 }
 $planSuffix='dev'
}else{
 Import-Module (Join-Path $PSScriptRoot 'modules/StepCEnvironment.psm1') -Force
 $toolboxContext=Resolve-JawsStepCStepBContext -EnvironmentName $EnvironmentName -InstallerRoot $PSScriptRoot
 if($ProjectEndpoint -cne $toolboxContext.ProjectEndpoint -or $ToolboxName -cne $toolboxContext.ToolboxName -or
    $ConnectionName -cne $toolboxContext.ConnectionName -or $PlannerAgent -cne $toolboxContext.PlannerAgent){
  throw 'JAWS-TOOLBOX-010: Toolbox scope does not match the Step B installation.'
 }
 $planSuffix=$toolboxContext.PlanSuffix
}
$project=$ProjectEndpoint
$name=$ToolboxName
$connName=$ConnectionName
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
$target="$project/agents/$PlannerAgent/endpoint/protocols/a2a"
$directTarget=if($conn.PSObject.Properties['target']){[string]$conn.target}else{''}
$nestedTarget=if($conn.PSObject.Properties['properties'] -and $conn.properties -and $conn.properties.PSObject.Properties['target']){[string]$conn.properties.target}else{''}
if($directTarget -cne $target -and $nestedTarget -cne $target) {
 throw 'JAWS-TOOLBOX-003: Connection target drift; refusing toolbox installation.'
}
$desired=[ordered]@{
 description='JAWS Investigation A2A v1.0 toolbox, read-only planning.'
 tools=@([ordered]@{
  type='a2a'
  a2a_version='1.0'
  project_connection_id=[string]$conn.id
 })
}
$payload=ConvertTo-Json -InputObject $desired -Depth 15 -Compress
$hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($payload))).ToLowerInvariant()
$local=Join-Path $PSScriptRoot '.local'
if(-not(Test-Path $local)){$null=New-Item -ItemType Directory -Force -Path $local}
$planPath=Join-Path $local "jaws-step-c-toolbox-plan.$planSuffix.generated.json"
[pscustomobject]@{ToolboxName=$name;ConnectionId=$conn.id;PlanSha256=$hash;Target=$target;AzureWrites=0} |
 ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $planPath -Encoding utf8
$versionsUrl="$project/toolboxes/$name/versions?api-version=v1"
$existing=Get-Api -Url $versionsUrl -AllowNotFound
$items=@()
if($null -ne $existing) {
 $listProp=$existing.PSObject.Properties['data']
 if($null -eq $listProp){$listProp=$existing.PSObject.Properties['value']}
 if($null -ne $listProp -and $null -ne $listProp.Value){$items=@($listProp.Value)}
}
$invalid=@($items|Where-Object {
 $_ -and $_.PSObject.Properties['tools'] -and @($_.tools|Where-Object {
  $_.type -ceq 'a2a' -and $_.PSObject.Properties['base_url'] -and $_.PSObject.Properties['project_connection_id']
 }).Count -gt 0
})
if($Mode -eq 'Plan') {
 if($invalid.Count -gt 0){Write-Warning 'JAWS-TOOLBOX-009: Existing A2A toolbox version includes both base_url and project_connection_id. Must create corrected version; do not retry original installation.'}
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
$actual=Get-Api -Url $versionsUrl -AllowNotFound
$actualItems=@()
if($null -ne $actual) {
 $listProp=$actual.PSObject.Properties['data']
 if($null -eq $listProp){$listProp=$actual.PSObject.Properties['value']}
 if($null -ne $listProp -and $null -ne $listProp.Value){$actualItems=@($listProp.Value)}
}
if($actualItems.Count -eq 0) {
 throw 'JAWS-TOOLBOX-007: Toolbox version not verifiable.'
}
$toolboxInfo=Get-Api -Url "$project/toolboxes/$($name)?api-version=v1"
$defaultVersion=[string]$toolboxInfo.default_version
$match=@($actualItems | Where-Object {
 $_.name -ceq $name -and [string]$_.version -ceq $defaultVersion -and
 @($_.tools).Count -eq 1 -and $_.tools[0].type -ceq 'a2a' -and
 $_.tools[0].a2a_version -ceq '1.0' -and
 -not $_.tools[0].PSObject.Properties['base_url'] -and
 $_.tools[0].project_connection_id -ceq [string]$conn.id
})
if($match.Count -ne 1){throw 'JAWS-TOOLBOX-008: Existing toolbox version configuration mismatch. No writes.'}
Write-Host "Toolbox default version $defaultVersion verified: $name"
Write-Host 'Supervisor v1 unchanged. Hosted delegation acceptance remains the Step C inference gate.'
