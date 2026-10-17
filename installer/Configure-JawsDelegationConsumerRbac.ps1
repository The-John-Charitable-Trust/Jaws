# Step C: grant the released Supervisor identity least-privilege A2A/toolbox access.
[CmdletBinding()]
param(
 [ValidateSet('Plan','Assign','Verify')][string]$Mode='Plan',
 [string]$ApprovedPlanSha256,
 [switch]$AcknowledgeSecurityRoleAssignment
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'modules/InstallationState.psm1') -Force
$state=Read-JawsInstallationState -Path (Join-Path $PSScriptRoot 'config/jaws-installation-state.dev.json')
if($state.EnvironmentName -cne 'dev' -or $state.ResourceGroupName -cne 'rg-aiops-lab'){
 throw 'JAWS-DELEGATE-RBAC-000: Authoritative JAWS dev state required.'
}
$subscription=[string]$state.SubscriptionId
$resourceGroup=[string]$state.ResourceGroupName
$account=[string]@($state.Resources | Where-Object Type -eq 'Microsoft.CognitiveServices/accounts')[0].Name
$project=[string]@($state.Resources | Where-Object Type -eq 'Microsoft.CognitiveServices/accounts/projects')[0].Name
$agent='jaws-supervisor-dev'
$endpoint="https://$account.services.ai.azure.com/api/projects/$project"
$scope="/subscriptions/$subscription/resourceGroups/$resourceGroup/providers/Microsoft.CognitiveServices/accounts/$account/projects/$project"
$roleDefinitionId='eed3b665-ab3a-47b6-8f48-c9382fb1dad6' # Foundry Agent Consumer

function Read-JsonCommand([scriptblock]$Command,[string]$ErrorCode) {
 $result=& $Command 2>&1
 if($LASTEXITCODE -ne 0){throw "$($ErrorCode): $($result|Out-String)"}
 try{return ($result|Out-String|ConvertFrom-Json -ErrorAction Stop)}
 catch{throw "$($ErrorCode): Azure returned invalid JSON."}
}

$summary=Read-JsonCommand { az rest --method get --url "$endpoint/agents/$($agent)?api-version=v1" --resource https://ai.azure.com --output json --only-show-errors } 'JAWS-DELEGATE-RBAC-001'
$latestValue=$summary.versions.latest
$version=if($latestValue -is [string] -or $latestValue -is [ValueType]){[string]$latestValue}
 elseif($latestValue.PSObject.Properties['version']){[string]$latestValue.version}
 else{''}
if($version -notmatch '^[0-9]+$' -or $version -eq '1'){
 throw 'JAWS-DELEGATE-RBAC-008: Latest routing is not a released Supervisor version after v1.'
}
$supervisor=Read-JsonCommand { az rest --method get --url "$endpoint/agents/$agent/versions/$($version)?api-version=v1" --resource https://ai.azure.com --output json --only-show-errors } 'JAWS-DELEGATE-RBAC-001'
$identityProperty=$supervisor.PSObject.Properties['instance_identity']
$principalProperty=if($null -ne $identityProperty -and $null -ne $identityProperty.Value){$identityProperty.Value.PSObject.Properties['principal_id']}else{$null}
$principalId=if($null -ne $principalProperty){[string]$principalProperty.Value}else{''}
if($supervisor.status -cne 'active' -or $supervisor.draft -ne $false -or $supervisor.version -cne $version -or [string]::IsNullOrWhiteSpace($principalId)){
 throw 'JAWS-DELEGATE-RBAC-002: Active routed Supervisor instance identity was not verified.'
}

$desired=[ordered]@{PrincipalId=$principalId;PrincipalType='ServicePrincipal';RoleDefinitionId=$roleDefinitionId;Scope=$scope}
$payload=ConvertTo-Json -InputObject $desired -Depth 8 -Compress
$hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($payload))).ToLowerInvariant()
$local=Join-Path $PSScriptRoot '.local'
if(-not(Test-Path -LiteralPath $local)){$null=New-Item -ItemType Directory -Force -Path $local}
$planPath=Join-Path $local 'jaws-step-c-delegation-consumer-rbac-plan.dev.generated.json'

function Read-Assignments {
 $assignments=Read-JsonCommand { az role assignment list --assignee-object-id $principalId --scope $scope --output json --only-show-errors } 'JAWS-DELEGATE-RBAC-003'
 return @($assignments)
}
function Find-ExpectedAssignment {
 return @(Read-Assignments | Where-Object {
  $_ -and $_.PSObject.Properties['roleDefinitionId'] -and $_.PSObject.Properties['scope'] -and
  [string]$_.roleDefinitionId -match "(?i)/$([regex]::Escape($roleDefinitionId))$" -and
  [string]$_.scope -ieq $scope
 })
}

$existing=@(Find-ExpectedAssignment)
[pscustomobject]@{Operation='AssignFoundryAgentConsumer';PlanSha256=$hash;PrincipalId=$principalId;RoleDefinitionId=$roleDefinitionId;Scope=$scope;AssignmentExists=($existing.Count -eq 1);AzureWrites=0} |
 ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $planPath -Encoding utf8
if($Mode -eq 'Plan'){
 Write-Host "Routed Supervisor version $version principal: $principalId"
 Write-Host "Foundry Agent Consumer assigned: $($existing.Count -eq 1)"
 Write-Host "Plan SHA-256: $hash"
 Write-Host "Plan: $planPath"
 Write-Host 'PLAN ONLY: no Azure writes.'
 return
}
if($Mode -eq 'Assign' -and $existing.Count -eq 0){
 if($ApprovedPlanSha256 -cne $hash -or -not $AcknowledgeSecurityRoleAssignment){
  throw 'JAWS-DELEGATE-RBAC-004: Exact RBAC plan approval and security acknowledgment required.'
 }
 $created=& az role assignment create --subscription $subscription --assignee-object-id $principalId --assignee-principal-type ServicePrincipal --role $roleDefinitionId --scope $scope --output json --only-show-errors 2>&1
 if($LASTEXITCODE -ne 0){throw "JAWS-DELEGATE-RBAC-005: Role assignment outcome uncertain; inspect Azure before retry: $($created|Out-String)"}
}elseif($Mode -eq 'Assign' -and $existing.Count -gt 1){
 throw 'JAWS-DELEGATE-RBAC-006: Duplicate matching role assignments detected; no write performed.'
}
$verified=@(Find-ExpectedAssignment)
if($verified.Count -ne 1){
 throw 'JAWS-DELEGATE-RBAC-007: Routed Supervisor lacks one exact Foundry Agent Consumer assignment at project scope.'
}
$receiptPath=Join-Path $local 'jaws-step-c-delegation-consumer-rbac-receipt.dev.generated.json'
[pscustomobject]@{Status='FOUNDRY_AGENT_CONSUMER_VERIFIED';PrincipalId=$principalId;RoleDefinitionId=$roleDefinitionId;Scope=$scope;PlanSha256=$hash;VerifiedAtUtc=[DateTime]::UtcNow.ToString('o')} |
 ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receiptPath -Encoding utf8
Write-Host "Verified Foundry Agent Consumer role for Supervisor version $($version): $principalId"
Write-Host "Receipt: $receiptPath"
