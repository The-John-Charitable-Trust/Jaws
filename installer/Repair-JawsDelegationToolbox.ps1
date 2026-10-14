# Repair the invalid JAWS Investigation A2A toolbox v1 without replacing it.
[CmdletBinding()]
param([ValidateSet('Plan','Create','Promote','Verify')][string]$Mode='Plan')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$endpoint='https://jaws-foundry-dev.services.ai.azure.com/api/projects/jaws-dev'
$name='jaws-investigation-a2a-tools'
$connection='jaws-investigation-a2a-dev'
$expectedTarget="$endpoint/agents/jaws-investigation-dev/endpoint/protocols/a2a"
$local=Join-Path $PSScriptRoot '.local'
if(-not (Test-Path $local)){$null=New-Item -ItemType Directory -Path $local -Force}
function Read-Jaws([string]$url){
 $out=& az rest --method get --url $url --resource https://ai.azure.com --output json --only-show-errors 2>&1
 if($LASTEXITCODE -ne 0){throw "JAWS-TOOLBOX-REPAIR-001: Read failed: $($out|Out-String)"}
 return ($out|Out-String|ConvertFrom-Json -ErrorAction Stop)
}
$cn=Read-Jaws "$endpoint/connections/$($connection)?api-version=v1"
$target=if($cn.PSObject.Properties['target']){[string]$cn.target}elseif($cn.properties.PSObject.Properties['target']){[string]$cn.properties.target}else{''}
if($target -cne $expectedTarget -or -not $cn.id){throw 'JAWS-TOOLBOX-REPAIR-002: Connection state mismatch.'}
$tb=Read-Jaws "$endpoint/toolboxes/$($name)?api-version=v1"
$list=Read-Jaws "$endpoint/toolboxes/$name/versions?api-version=v1"
$versions=@($list.data)
$v1=@($versions|Where-Object {[string]$_.version -ceq '1'})
$v2=@($versions|Where-Object {[string]$_.version -ceq '2'})
if($v1.Count -ne 1 -or @($v1[0].tools).Count -ne 1){throw 'JAWS-TOOLBOX-REPAIR-003: Expected toolbox v1 missing.'}
$old=$v1[0].tools[0]
if($old.type -cne 'a2a' -or $old.a2a_version -cne '1.0' -or
 $old.base_url -cne $expectedTarget -or $old.project_connection_id -cne [string]$cn.id){
 throw 'JAWS-TOOLBOX-REPAIR-004: Existing toolbox v1 does not match expected invalid config.'
}
$desired=[ordered]@{description='JAWS Investigation A2A corrected connection-only v2, read-only planning.';tools=@([ordered]@{type='a2a';a2a_version='1.0';project_connection_id=[string]$cn.id})}
$payload=ConvertTo-Json -InputObject $desired -Depth 10 -Compress
$sha=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($payload))).ToLowerInvariant()
$path=Join-Path $local 'jaws-step-c-toolbox-repair-plan.dev.generated.json'
[pscustomobject]@{Toolbox=$name;Operation='CreateVersionThenPromote';PlanSha256=$sha;OriginalDefault=[string]$tb.default_version;ExpectedVersion='2';ConnectionId=[string]$cn.id;Payload=$desired}|ConvertTo-Json -Depth 12|Set-Content $path -Encoding utf8
function Confirm-Operator([string]$message){
 Write-Host "Plan SHA-256: $sha"
 Write-Host "Target: $name; connection: $connection"
 $answer=Read-Host "$message [y/N]"
 if($answer.Trim() -ine 'y'){throw 'JAWS-TOOLBOX-REPAIR-005: User declined.'}
}
if($Mode -eq 'Plan'){
 Write-Host "Invalid toolbox v1 confirmed; existing default: $($tb.default_version); version 2 exists: $($v2.Count -eq 1)"
 Write-Host "Plan: $path"
 Write-Host 'PLAN ONLY: no Azure writes.'
 return
}
if($Mode -eq 'Create'){
 if($v2.Count -ne 0){throw 'JAWS-TOOLBOX-REPAIR-006: Version 2 already exists, no duplicate creation.'}
 Confirm-Operator 'Create corrected immutable toolbox v2? This may incur Azure charges.'
 $tmp=[IO.Path]::GetTempFileName()
 try{
  [IO.File]::WriteAllText($tmp,$payload,[Text.UTF8Encoding]::new($false))
  $out=& az rest --method post --url "$endpoint/toolboxes/$name/versions?api-version=v1" --resource https://ai.azure.com --headers 'Content-Type=application/json' --body "@$tmp" --output json --only-show-errors 2>&1
  if($LASTEXITCODE -ne 0){throw "JAWS-TOOLBOX-REPAIR-007: Create outcome uncertain; reconcile before retry: $($out|Out-String)"}
 }finally{Remove-Item $tmp -Force -ErrorAction SilentlyContinue}
 Write-Host 'Toolbox creation submitted. Verify version 2 MCP tools before promotion.'
 return
}
if($v2.Count -ne 1){throw 'JAWS-TOOLBOX-REPAIR-008: Version 2 not present; create first.'}
$tool=@($v2[0].tools)
if($tool.Count -ne 1 -or $tool[0].type -cne 'a2a' -or $tool[0].a2a_version -cne '1.0' -or
 $tool[0].project_connection_id -cne [string]$cn.id -or $tool[0].PSObject.Properties['base_url']){
 throw 'JAWS-TOOLBOX-REPAIR-009: Version 2 config mismatch.'
}
if($Mode -eq 'Verify'){
 Write-Host "Verified corrected toolbox version 2 configuration; default: $($tb.default_version)"
 Write-Host 'MCP tools/list verification is a separate required gate.'
 return
}
$diagnostic=Join-Path $local 'jaws-step-c-runtime-tool-discovery.dev.generated.json'
if(-not(Test-Path $diagnostic)){throw 'JAWS-TOOLBOX-REPAIR-010: Version 2 MCP discovery receipt missing.'}
$proof=Get-Content $diagnostic -Raw | ConvertFrom-Json
if($proof.Status -cne 'MCP_TOOLS_EXPOSED' -or $proof.ToolboxVersion -cne '2' -or $proof.ToolCount -lt 1){
 throw 'JAWS-TOOLBOX-REPAIR-011: Successful version 2 MCP tool discovery required before promotion.'
}
if([string]$tb.default_version -eq '2'){Write-Host 'Toolbox v2 already default.';return}
if([string]$tb.default_version -ne '1'){throw 'JAWS-TOOLBOX-REPAIR-012: Default changed unexpectedly.'}
Confirm-Operator 'Promote corrected toolbox v2 to default for existing Supervisor? This changes runtime tool availability.'
$tmp=[IO.Path]::GetTempFileName()
try{
 [IO.File]::WriteAllText($tmp,'{"default_version":"2"}',[Text.UTF8Encoding]::new($false))
 $out=& az rest --method patch --url "$endpoint/toolboxes/$($name)?api-version=v1" --resource https://ai.azure.com --headers 'Content-Type=application/json' --body "@$tmp" --output json --only-show-errors 2>&1
 if($LASTEXITCODE -ne 0){throw "JAWS-TOOLBOX-REPAIR-013: Promotion outcome uncertain: $($out|Out-String)"}
}finally{Remove-Item $tmp -Force -ErrorAction SilentlyContinue}
$recheck=Read-Jaws "$endpoint/toolboxes/$($name)?api-version=v1"
if([string]$recheck.default_version -ne '2'){throw 'JAWS-TOOLBOX-REPAIR-014: Promotion not verified.'}
Write-Host 'Corrected toolbox version 2 is now default. Rerun SupervisorV2Verify.'
