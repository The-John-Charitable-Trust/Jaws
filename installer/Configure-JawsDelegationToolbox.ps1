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
function Get-JawsVersionItems($Parsed) {
 if($null -eq $Parsed){ return @() }
 if($Parsed -is [System.Array]){ return @($Parsed | Where-Object { $null -ne $_ }) }
 foreach($propName in @('data','value')){
  $prop=$Parsed.PSObject.Properties[$propName]
  if($null -eq $prop -or $null -eq $prop.Value){ continue }
  if($prop.Value -is [System.Array]){ return @($prop.Value | Where-Object { $null -ne $_ }) }
 }
 return @()
}
function Test-JawsA2AVersion($Version,[string]$ToolboxName,[string]$VersionId,[string]$ConnectionId) {
 if($null -eq $Version -or -not ($Version -is [pscustomobject])){ return $false }
 if(-not $Version.PSObject.Properties['name'] -or [string]$Version.name -cne $ToolboxName){ return $false }
 if(-not $Version.PSObject.Properties['version'] -or [string]$Version.version -cne $VersionId){ return $false }
 if(-not $Version.PSObject.Properties['tools'] -or $null -eq $Version.tools){ return $false }
 $tools=@($Version.tools)
 if($tools.Count -ne 1 -or $null -eq $tools[0] -or -not ($tools[0] -is [pscustomobject])){ return $false }
 $tool=$tools[0]
 if(-not $tool.PSObject.Properties['type'] -or $tool.type -cne 'a2a'){ return $false }
 if(-not $tool.PSObject.Properties['a2a_version'] -or $tool.a2a_version -cne '1.0'){ return $false }
 if($tool.PSObject.Properties['base_url']){ return $false }
 if(-not $tool.PSObject.Properties['project_connection_id'] -or [string]$tool.project_connection_id -cne $ConnectionId){ return $false }
 return $true
}
function Get-JawsToolboxRecord { Get-Api -Url "$project/toolboxes/${name}?api-version=v1" -AllowNotFound }
function Get-DefaultVersionId($Record) {
 if($null -eq $Record -or -not $Record.PSObject.Properties['default_version']){ return '' }
 return [string]$Record.default_version
}
function Get-JawsToolboxVersion([string]$VersionId) {
 if($VersionId -notmatch '^[A-Za-z0-9._-]{1,64}$'){ return $null }
 return Get-Api -Url "$project/toolboxes/$name/versions/${VersionId}?api-version=v1" -AllowNotFound
}
function Invoke-FoundryJson([string]$Method,[string]$Url,[string]$Body,[string]$FailureCode) {
 $file=Join-Path ([IO.Path]::GetTempPath()) (([IO.Path]::GetRandomFileName()) + '.json')
 try {
  [IO.File]::WriteAllText($file,$Body,[Text.UTF8Encoding]::new($false))
  if([IO.File]::ReadAllText($file) -cne $Body){ throw "${FailureCode}: Toolbox request body was not stored before the Foundry call." }
  $out=& az rest --method $Method --url $Url --resource https://ai.azure.com --headers 'Content-Type=application/json' --body "@$file" --output json --only-show-errors 2>&1
  if($LASTEXITCODE -ne 0){ throw "${FailureCode}: $($out | Out-String)" }
  $text=$out | Out-String
  try { $json=$text | ConvertFrom-Json -ErrorAction Stop }
  catch { throw "${FailureCode}: Foundry response was not JSON: $text" }
  return [pscustomobject]@{ Text=$text; Json=$json }
 } finally { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }
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
$items=@(Get-JawsVersionItems (Get-Api -Url $versionsUrl -AllowNotFound))
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
 $record=Get-JawsToolboxRecord
 $defaultId=Get-DefaultVersionId $record
 $existingVersion=Get-JawsToolboxVersion $defaultId
 if($null -ne $existingVersion){
  if(-not (Test-JawsA2AVersion $existingVersion $name $defaultId ([string]$conn.id))){
   throw 'JAWS-TOOLBOX-008: Existing toolbox version configuration mismatch. No writes.'
  }
 } else {
  $sent=Invoke-FoundryJson -Method post -Url $versionsUrl -Body $payload -FailureCode 'JAWS-TOOLBOX-005'
  $createdId=if($sent.Json -and $sent.Json.PSObject.Properties['version']){[string]$sent.Json.version}else{''}
  if(-not (Test-JawsA2AVersion $sent.Json $name $createdId ([string]$conn.id))){
   throw "JAWS-TOOLBOX-011: Foundry did not return an Investigation A2A toolbox version. A toolbox shell is not a version. Response: $($sent.Text)"
  }
  $stored=Get-JawsToolboxVersion $createdId
  if(-not (Test-JawsA2AVersion $stored $name $createdId ([string]$conn.id))){
   throw "JAWS-TOOLBOX-007: Toolbox version $createdId was not readable after create."
  }
  $defaultId=Get-DefaultVersionId (Get-JawsToolboxRecord)
  if($defaultId -cne $createdId){
   $promoted=Invoke-FoundryJson -Method patch -Url "$project/toolboxes/${name}?api-version=v1" -Body ('{"default_version":"'+$createdId+'"}') -FailureCode 'JAWS-TOOLBOX-012'
   $defaultId=Get-DefaultVersionId $promoted.Json
   if($defaultId -cne $createdId){ $defaultId=Get-DefaultVersionId (Get-JawsToolboxRecord) }
   if($defaultId -cne $createdId){ throw "JAWS-TOOLBOX-012: Default toolbox version is '$defaultId' after promotion; expected '$createdId'." }
  }
 }
} elseif($Mode -eq 'Install' -and $items.Count -gt 0) {
 throw 'JAWS-TOOLBOX-006: Existing toolbox versions detected. Refuse to replace or add a version without verified configuration comparison.'
}
$defaultVersion=Get-DefaultVersionId (Get-JawsToolboxRecord)
$proven=Get-JawsToolboxVersion $defaultVersion
if(-not (Test-JawsA2AVersion $proven $name $defaultVersion ([string]$conn.id))){
 throw 'JAWS-TOOLBOX-007: Toolbox version not verifiable.'
}
$listed=@(Get-JawsVersionItems (Get-Api -Url $versionsUrl -AllowNotFound))
if($listed.Count -gt 0){
 $match=@($listed | Where-Object { Test-JawsA2AVersion $_ $name $defaultVersion ([string]$conn.id) })
 if($match.Count -ne 1){ throw 'JAWS-TOOLBOX-008: Existing toolbox version configuration mismatch. No writes.' }
}
Write-Host "Toolbox default version $defaultVersion verified: $name"
Write-Host 'Supervisor v1 unchanged. Hosted delegation acceptance remains the Step C inference gate.'
