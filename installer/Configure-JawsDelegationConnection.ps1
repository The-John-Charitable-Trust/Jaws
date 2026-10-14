# Installer-managed Step C: plan and configure a narrowly scoped RemoteA2A connection.
# Existing Supervisor v1 and Investigation v1 remain unchanged. No credentials persisted.
[CmdletBinding()]
param(
 [ValidateSet('Plan','Install','Verify')][string]$Mode='Plan',
 [string]$ApprovedPlanSha256,
 [switch]$AcknowledgeA2AConnection,
 [string]$StateFile=(Join-Path $PSScriptRoot 'config/jaws-installation-state.dev.json')
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'modules/InstallationState.psm1') -Force
$state=Read-JawsInstallationState -Path $StateFile
if($state.Platform -cne 'JAWS' -or $state.EnvironmentName -cne 'dev' -or
 $state.ResourceGroupName -cne 'rg-aiops-lab'){throw 'JAWS-DELEGATE-001: Unauthorized installation state.'}
$foundry='jaws-foundry-dev'; $project='jaws-dev'; $name='jaws-investigation-a2a-dev'
$endpoint="https://$foundry.services.ai.azure.com/api/projects/$project"
$target="$endpoint/agents/jaws-investigation-dev/endpoint/protocols/a2a"
$id="/subscriptions/$($state.SubscriptionId)/resourceGroups/$($state.ResourceGroupName)/providers/Microsoft.CognitiveServices/accounts/$foundry/projects/$project/connections/$name"
# Correct PowerShell interpolation: a question mark immediately after a variable needs $().
$url="https://management.azure.com/$($id.TrimStart('/'))?api-version=2025-04-01-preview"
$payload=[ordered]@{
 name=$name
 properties=[ordered]@{
  authType='AgenticIdentityToken'
  group='ServicesAndApps'
  category='RemoteA2A'
  target=$target
  isSharedToAll=$true
  sharedUserList=@()
  audience='https://ai.azure.com'
  Credentials=[ordered]@{}
  metadata=[ordered]@{ApiType='Azure'}
 }
}
$json=ConvertTo-Json -InputObject $payload -Depth 12 -Compress
$sha=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($json))).ToLowerInvariant()
$dir=Join-Path $PSScriptRoot '.local'
if(-not(Test-Path $dir)){ $null=New-Item -ItemType Directory -Path $dir -Force }
$planFile=Join-Path $dir 'jaws-step-c-delegation-connection-plan.dev.generated.json'
[pscustomobject]@{Action='CreateRemoteA2AConnection';ConnectionResourceId=$id;Target=$target;AuthType='AgenticIdentityToken';Audience='https://ai.azure.com';PlanSha256=$sha;AzureWrites=0} |
 ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $planFile -Encoding utf8
function Read-Connection {
 $out=& az rest --method get --url $url --resource https://management.azure.com/ --output json --only-show-errors 2>&1
 if($LASTEXITCODE -eq 0){return ($out | Out-String | ConvertFrom-Json)}
 $err=($out | Out-String)
 if($err -match '(?i)(404|ResourceNotFound)'){return $null}
 throw "JAWS-DELEGATE-002: Cannot read A2A connection (not assumed absent): $err"
}
function Assert-Connection($conn){
 if($null -eq $conn){throw 'JAWS-DELEGATE-003: Expected connection missing.'}
 $p=$conn.properties
 if([string]$conn.id -ine $id -or [string]$p.target -cne $target -or
   [string]$p.category -cne 'RemoteA2A' -or [string]$p.authType -cne 'AgenticIdentityToken' -or
   [string]$p.audience -cne 'https://ai.azure.com'){
  throw 'JAWS-DELEGATE-004: Existing connection differs; refusing to overwrite.'
 }
}
$current=Read-Connection
if($null -ne $current){Assert-Connection $current}
if($Mode -eq 'Plan'){
 Write-Host "RemoteA2A connection exists: $($null -ne $current)"
 Write-Host "Plan SHA-256: $sha"
 Write-Host "Plan: $planFile"
 Write-Host 'PLAN ONLY: No Azure changes. Role assignment, toolbox, hosted runtime and invocation are separate gates.'
 return
}
if($Mode -eq 'Install' -and $null -eq $current){
 if(-not $AcknowledgeA2AConnection -or $ApprovedPlanSha256 -cne $sha){
  throw 'JAWS-DELEGATE-005: Exact plan approval and acknowledgment required.'
 }
 $tmp=[IO.Path]::GetTempFileName()
 try{
  [IO.File]::WriteAllText($tmp,$json,[Text.UTF8Encoding]::new($false))
  $result=& az rest --method put --url $url --resource https://management.azure.com/ --headers 'Content-Type=application/json' --body "@$tmp" --output json --only-show-errors 2>&1
  if($LASTEXITCODE -ne 0){throw "JAWS-DELEGATE-006: Connection PUT outcome uncertain; inspect live state: $($result | Out-String)"}
 }finally{Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue}
}
Assert-Connection (Read-Connection)
$receipt=Join-Path $dir 'jaws-step-c-delegation-connection-receipt.dev.generated.json'
[pscustomobject]@{Status='REMOTE_A2A_CONNECTION_VERIFIED';ResourceId=$id;Target=$target;AuthType='AgenticIdentityToken';PlanSha256=$sha;SupervisorDelegationVerified=$false;VerifiedAtUtc=[DateTime]::UtcNow.ToString('o')} |
 ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receipt -Encoding utf8
Write-Host "Verified RemoteA2A connection: $name; Receipt: $receipt"
