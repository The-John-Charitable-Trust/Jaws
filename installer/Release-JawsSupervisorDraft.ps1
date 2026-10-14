# Step C Supervisor draft-to-release lifecycle. Plan/Verify read-only.
[CmdletBinding()]
param(
 [ValidateSet('Plan','Release','Verify')][string]$Mode='Plan',
 [string]$ApprovedPlanSha256,
 [switch]$AcknowledgeTrafficAndInferenceCharges
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$endpoint='https://jaws-foundry-dev.services.ai.azure.com/api/projects/jaws-dev'
$name='jaws-supervisor-dev'
$draft='draft-1792013633085'
$expected='jawsregistrydev001.azurecr.io/jaws/supervisor@sha256:5a9cd89cfc626df4bdd2266194db14cda8fd33f46de1bfbc9c1111cde1c8af54'
function Read-Foundry([string]$url) {
 $out=& az rest --method get --url $url --resource https://ai.azure.com --output json --only-show-errors 2>&1
 if($LASTEXITCODE -ne 0){throw "JAWS-SUP-REL-001: Azure state read failed: $($out|Out-String)"}
 return ($out|Out-String|ConvertFrom-Json -ErrorAction Stop)
}
$v1=Read-Foundry "$endpoint/agents/$name/versions/1?api-version=v1"
$d=Read-Foundry "$endpoint/agents/$name/versions/$($draft)?api-version=v1"
if($v1.status -ne 'active' -or $v1.draft -ne $false -or
 $d.status -ne 'active' -or $d.draft -ne $true -or
 $d.name -cne $name -or $d.version -cne $draft -or
 $d.definition.kind -cne 'hosted' -or
 $d.definition.container_configuration.image -cne $expected -or
 $d.definition.environment_variables.JAWS_INVESTIGATION_TOOLBOX_NAME -cne 'jaws-investigation-a2a-tools') {
 throw 'JAWS-SUP-REL-002: Supervisor v1/draft state or toolbox differs; no release.'
}
$versions=Read-Foundry "$endpoint/agents/$name/versions?api-version=v1"
$published=@($versions.data | Where-Object { $_.draft -eq $false })
if(@($published | Where-Object { [int]$_.version -ge 2 }).Count -gt 0){
 throw 'JAWS-SUP-REL-003: Supervisor release version >=2 already exists. Inspect before further writes.'
}
$payload=[ordered]@{draft=$false;definition=$d.definition}
# Exclude server-generated read-only values from creation definition.
$definition=[ordered]@{
 kind='hosted'
 container_configuration=[ordered]@{image=$expected}
 cpu=[string]$d.definition.cpu
 memory=[string]$d.definition.memory
 protocol_versions=@([ordered]@{protocol='responses';version='2.0.0'})
 environment_variables=[ordered]@{
  AZURE_AI_MODEL_DEPLOYMENT_NAME=[string]$d.definition.environment_variables.AZURE_AI_MODEL_DEPLOYMENT_NAME
  JAWS_INVESTIGATION_TOOLBOX_NAME='jaws-investigation-a2a-tools'
 }
}
$payload=[ordered]@{draft=$false;definition=$definition}
$json=ConvertTo-Json -InputObject $payload -Depth 15 -Compress
$sha=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($json))).ToLowerInvariant()
$dir=Join-Path $PSScriptRoot '.local'
if(-not(Test-Path $dir)){$null=New-Item -ItemType Directory -Force -Path $dir}
$path=Join-Path $dir 'jaws-step-c-supervisor-release-plan.dev.generated.json'
[pscustomobject]@{Agent=$name;SourceDraft=$draft;Image=$expected;Operation='CreateNonDraftRelease';PlanSha256=$sha;MayChangeLatestRouting=$true;Payload=$payload} |
 ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding utf8
if($Mode -eq 'Plan'){
 Write-Host 'Source draft: active and matches published image/toolbox.'
 Write-Host 'WARNING: Creating a non-draft release can change latest-version routing. Supervisor v1 remains available by explicit version.'
 Write-Host "Plan SHA-256: $sha"
 Write-Host "Plan: $path"
 Write-Host 'PLAN ONLY: no Azure writes.'
 return
}
if($Mode -eq 'Verify'){
 Write-Host 'Verified original active Supervisor v1 and A2A-enabled draft. No release version created.'
 return
}
if(-not $AcknowledgeTrafficAndInferenceCharges -or $ApprovedPlanSha256 -cne $sha){
 throw 'JAWS-SUP-REL-004: Exact plan approval and acknowledgment of possible traffic change required.'
}
$tmp=[IO.Path]::GetTempFileName()
try {
 [IO.File]::WriteAllText($tmp,$json,[Text.UTF8Encoding]::new($false))
 $out=& az rest --method post --url "$endpoint/agents/$name/versions?api-version=v1" --resource https://ai.azure.com --headers 'Content-Type=application/json' --body "@$tmp" --output json --only-show-errors 2>&1
 if($LASTEXITCODE -ne 0){throw "JAWS-SUP-REL-005: Release result uncertain, inspect live agent before retrying: $($out|Out-String)"}
 $created=$out|Out-String|ConvertFrom-Json
 if($created.draft -ne $false -or [string]$created.version -notmatch '^[0-9]+$'){
  throw 'JAWS-SUP-REL-006: Release response unexpected, inspect Azure state; do not retry.'
 }
 Write-Host "Supervisor release created: $($created.version). Reconcile before acceptance."
}finally{Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue}
