# Installer-managed Step C: plan and configure a narrowly scoped RemoteA2A connection.
# Existing Supervisor v1 and Investigation v1 remain unchanged. No credentials persisted.
[CmdletBinding()]
param(
 [ValidateSet('Plan','Install','Verify','Retarget')][string]$Mode='Plan',
 [string]$ApprovedPlanSha256,
 [switch]$AcknowledgeA2AConnection,
 [string]$StateFile=(Join-Path $PSScriptRoot 'config/jaws-installation-state.dev.json')
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'modules/InstallationState.psm1') -Force
$state=Read-JawsInstallationState -Path $StateFile
if($null -eq $state -or $state.Platform -cne 'JAWS'){throw 'JAWS-DELEGATE-001: Unauthorized installation state.'}
if([string]$state.EnvironmentName -ceq 'dev'){
 if($state.ResourceGroupName -cne 'rg-aiops-lab'){throw 'JAWS-DELEGATE-001: Unauthorized installation state.'}
 $foundry='jaws-foundry-dev'; $project='jaws-dev'; $name='jaws-investigation-a2a-dev'
 $hostedAgent='jaws-investigation-dev'; $plannerAgent='jaws-investigation-planner-dev'
 $sharedToAll=$true
 $planSuffix='dev'
}else{
 Import-Module (Join-Path $PSScriptRoot 'modules/StepCEnvironment.psm1') -Force
 $connectionContext=Resolve-JawsStepCStepBContext -EnvironmentName ([string]$state.EnvironmentName) -InstallerRoot $PSScriptRoot
 if($state.ResourceGroupName -cne $connectionContext.ResourceGroupName -or [string]$state.SubscriptionId -ine $connectionContext.SubscriptionId){
  throw 'JAWS-DELEGATE-001: Installation state does not match the Step B receipt.'
 }
 $foundry=$connectionContext.FoundryAccountName; $project=$connectionContext.ProjectName; $name=$connectionContext.ConnectionName
 $hostedAgent="jaws-investigation-$($connectionContext.EnvironmentName)"; $plannerAgent=$connectionContext.PlannerAgent
 $sharedToAll=$false
 $planSuffix=$connectionContext.PlanSuffix
}
$endpoint="https://$foundry.services.ai.azure.com/api/projects/$project"
# Foundry rejects A2A operations on hosted agents (HOSTED_AGENT_NOT_SUPPORTED / -32099).
# The prompt planner is the A2A target. A hosted Investigation agent is not created for a Step B environment.
$hostedTarget="$endpoint/agents/$hostedAgent/endpoint/protocols/a2a"
$target="$endpoint/agents/$plannerAgent/endpoint/protocols/a2a"
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
  isSharedToAll=$sharedToAll
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
$planFile=Join-Path $dir "jaws-step-c-delegation-connection-plan.$planSuffix.generated.json"
[pscustomobject]@{Action='CreateRemoteA2AConnection';ConnectionResourceId=$id;Target=$target;AuthType='AgenticIdentityToken';Audience='https://ai.azure.com';PlanSha256=$sha;AzureWrites=0} |
 ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $planFile -Encoding utf8
function Read-Connection {
 $out=& az rest --method get --url $url --resource https://management.azure.com/ --output json --only-show-errors 2>&1
 if($LASTEXITCODE -eq 0){return ($out | Out-String | ConvertFrom-Json)}
 $err=($out | Out-String)
 if($err -match '(?i)(404|ResourceNotFound)'){return $null}
 throw "JAWS-DELEGATE-002: Cannot read A2A connection (not assumed absent): $err"
}
function Test-ConnectionShape($conn,[string]$expectedTarget){
 if($null -eq $conn){return $false}
 $p=$conn.properties
 return ([string]$conn.id -ieq $id -and [string]$p.target -ceq $expectedTarget -and
   [string]$p.category -ceq 'RemoteA2A' -and [string]$p.authType -ceq 'AgenticIdentityToken' -and
   [string]$p.audience -ceq 'https://ai.azure.com')
}
function Assert-Connection($conn){
 if(-not (Test-ConnectionShape $conn $target)){
  throw 'JAWS-DELEGATE-003: Expected prompt-agent connection missing or mismatched.'
 }
}
$current=Read-Connection
if($Mode -eq 'Plan'){
 Write-Host "RemoteA2A connection exists: $($null -ne $current)"
 Write-Host "Targets prompt agent: $(Test-ConnectionShape $current $target)"
 Write-Host "Plan SHA-256: $sha"
 Write-Host "Plan: $planFile"
 Write-Host 'PLAN ONLY: No Azure changes. Role assignment, toolbox, hosted runtime and invocation are separate gates.'
 return
}
if($Mode -eq 'Retarget'){
 if(-not $AcknowledgeA2AConnection -or $ApprovedPlanSha256 -cne $sha){
  throw 'JAWS-DELEGATE-007: Exact plan approval and acknowledgment required to retarget.'
 }
 if(Test-ConnectionShape $current $target){
  Write-Host 'Connection already targets the Investigation prompt agent.'
 } elseif(Test-ConnectionShape $current $hostedTarget){
  $p=$current.properties
  $shared=@()
  if($null -ne $p.sharedUserList){$shared=@($p.sharedUserList)}
  $put=[ordered]@{
   name=$name
   properties=[ordered]@{
    authType=[string]$p.authType
    group=[string]$p.group
    category=[string]$p.category
    target=$target
    isSharedToAll=[bool]$p.isSharedToAll
    sharedUserList=$shared
    audience=[string]$p.audience
    Credentials=[ordered]@{}
    metadata=[ordered]@{ApiType='Azure'}
   }
  }
  $putJson=ConvertTo-Json -InputObject $put -Depth 12 -Compress
  $tmp=[IO.Path]::GetTempFileName()
  try{
   [IO.File]::WriteAllText($tmp,$putJson,[Text.UTF8Encoding]::new($false))
   $result=& az rest --method put --url $url --resource https://management.azure.com/ --headers 'Content-Type=application/json' --body "@$tmp" --output json --only-show-errors 2>&1
   if($LASTEXITCODE -ne 0){throw "JAWS-DELEGATE-008: Connection retarget outcome uncertain; inspect live state: $($result | Out-String)"}
  }finally{Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue}
 } else {
  throw 'JAWS-DELEGATE-009: Connection is not the hosted Investigation target; refusing to retarget.'
 }
 Assert-Connection (Read-Connection)
 $receipt=Join-Path $dir "jaws-step-c-delegation-connection-receipt.$planSuffix.generated.json"
 [pscustomobject]@{Status='REMOTE_A2A_CONNECTION_VERIFIED';ResourceId=$id;Target=$target;AuthType='AgenticIdentityToken';PlanSha256=$sha;SupervisorDelegationVerified=$false;VerifiedAtUtc=[DateTime]::UtcNow.ToString('o')} |
  ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receipt -Encoding utf8
 Write-Host "Retargeted RemoteA2A connection: $name; Receipt: $receipt"
 return
}
if($null -ne $current -and -not (Test-ConnectionShape $current $target)){
 if(Test-ConnectionShape $current $hostedTarget){
  throw 'JAWS-DELEGATE-004: Connection still targets the hosted Investigation agent. Foundry rejects A2A operations on hosted agents. Run -Mode Retarget with the plan SHA.'
 }
 throw 'JAWS-DELEGATE-004: Existing connection differs; refusing to overwrite.'
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
$receipt=Join-Path $dir "jaws-step-c-delegation-connection-receipt.$planSuffix.generated.json"
[pscustomobject]@{Status='REMOTE_A2A_CONNECTION_VERIFIED';ResourceId=$id;Target=$target;AuthType='AgenticIdentityToken';PlanSha256=$sha;SupervisorDelegationVerified=$false;VerifiedAtUtc=[DateTime]::UtcNow.ToString('o')} |
 ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receipt -Encoding utf8
Write-Host "Verified RemoteA2A connection: $name; Receipt: $receipt"
