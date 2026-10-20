# Read-only A2A identity context: verify Supervisor identity and management-plane connection metadata.
[CmdletBinding()]
param(
    [string]$StateFile=(Join-Path $PSScriptRoot 'config/jaws-installation-state.dev.json')
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'modules/InstallationState.psm1') -Force

$state=Read-JawsInstallationState -Path $StateFile
if($null -eq $state -or $state.Platform -cne 'JAWS' -or [string]::IsNullOrWhiteSpace([string]$state.SubscriptionId)){
    throw 'JAWS-A2A-IDENTITY-000: Installation state unexpected.'
}
if([string]$state.EnvironmentName -ceq 'dev'){
    if($state.ResourceGroupName -cne 'rg-aiops-lab'){ throw 'JAWS-A2A-IDENTITY-000: Installation state unexpected.' }
    $accountName='jaws-foundry-dev'
    $projectName='jaws-dev'
    $agentName='jaws-supervisor-dev'
    $connectionName='jaws-investigation-a2a-dev'
    $plannerName='jaws-investigation-planner-dev'
    $planSuffix='dev'
}else{
    Import-Module (Join-Path $PSScriptRoot 'modules/StepCEnvironment.psm1') -Force
    $identityContext=Resolve-JawsStepCStepBContext -EnvironmentName ([string]$state.EnvironmentName) -InstallerRoot $PSScriptRoot
    if($state.ResourceGroupName -cne $identityContext.ResourceGroupName){ throw 'JAWS-A2A-IDENTITY-000: Installation state unexpected.' }
    $accountName=$identityContext.FoundryAccountName
    $projectName=$identityContext.ProjectName
    $agentName=$identityContext.SupervisorAgent
    $connectionName=$identityContext.ConnectionName
    $plannerName=$identityContext.PlannerAgent
    $planSuffix=$identityContext.PlanSuffix
}
$project="https://$accountName.services.ai.azure.com/api/projects/$projectName"
if([string]$state.EnvironmentName -ceq 'dev'){
    $a2aProject=$project
}else{
    $a2aProject=Get-JawsStepCA2AEndpoint -ProjectEndpoint $project -EnvironmentName ([string]$state.EnvironmentName)
}
$id="/subscriptions/$($state.SubscriptionId)/resourceGroups/$($state.ResourceGroupName)/providers/Microsoft.CognitiveServices/accounts/$accountName/projects/$projectName/connections/$connectionName"
$armUrl="https://management.azure.com/$($id.TrimStart('/'))?api-version=2025-04-01-preview"
function Read-Json([string]$url,[string]$resource) {
    $out=& az rest --method get --url $url --resource $resource --output json --only-show-errors 2>&1
    if($LASTEXITCODE -ne 0){throw "JAWS-A2A-IDENTITY-001: Azure state read failed; inspect CLI authorization: $($out | Out-String)"}
    return ($out | Out-String | ConvertFrom-Json -ErrorAction Stop)
}
function Get-OptionalProperty($obj,[string]$key){
    if($null -eq $obj){return $null}
    $property=$obj.PSObject.Properties[$key]
    if($null -ne $property){return $property.Value}
    return $null
}
$summary=Read-Json "$project/agents/${agentName}?api-version=v1" 'https://ai.azure.com'
$latestValue=Get-OptionalProperty (Get-OptionalProperty $summary 'versions') 'latest'
$routedVersion=if($latestValue -is [string] -or $latestValue -is [ValueType]){[string]$latestValue}
 elseif($null -ne $latestValue -and $latestValue.PSObject.Properties['version']){[string]$latestValue.version}
 else{''}
if($routedVersion -notmatch '^[0-9]+$' -or $routedVersion -eq '1'){
 throw 'JAWS-A2A-IDENTITY-003: Latest routing is not a released Supervisor version after v1.'
}
$supervisor=Read-Json "$project/agents/$agentName/versions/$($routedVersion)?api-version=v1" 'https://ai.azure.com'
$connection=Read-Json $armUrl 'https://management.azure.com/'
$props=Get-OptionalProperty $connection 'properties'
$identity=Get-OptionalProperty $supervisor 'instance_identity'
$blueprint=Get-OptionalProperty $supervisor 'blueprint'
$instanceClientId=[string](Get-OptionalProperty $identity 'client_id')
$blueprintClientId=[string](Get-OptionalProperty $blueprint 'client_id')
$authType=[string](Get-OptionalProperty $props 'authType')
$category=[string](Get-OptionalProperty $props 'category')
$target=[string](Get-OptionalProperty $props 'target')
$expectedTarget="$a2aProject/agents/$plannerName/endpoint/protocols/a2a"
$contextAvailable= -not [string]::IsNullOrWhiteSpace($instanceClientId) -and -not [string]::IsNullOrWhiteSpace($blueprintClientId)
$connectionValid=([string](Get-OptionalProperty $connection 'id') -ieq $id -and $authType -ceq 'AgenticIdentityToken' -and $category -ceq 'RemoteA2A' -and $target -ceq $expectedTarget)
$status=if($contextAvailable -and $connectionValid){'IDENTITY_CONTEXT_AVAILABLE'}else{'IDENTITY_CONTEXT_INCOMPLETE'}
$result=[pscustomobject]@{
    Status=$status
    SupervisorVersion=[string](Get-OptionalProperty $supervisor 'version')
    InstanceClientIdPresent= -not [string]::IsNullOrWhiteSpace($instanceClientId)
    BlueprintClientIdPresent= -not [string]::IsNullOrWhiteSpace($blueprintClientId)
    ConnectionAuthType=$authType
    ConnectionCategory=$category
    TargetMatchesExpected=($target -ceq $expectedTarget)
    ConnectionMatchesExpected=$connectionValid
    Source='Azure Resource Manager (connection) and Foundry project API (Supervisor)'
    Limitation='This verifies stored configuration only, not propagation of hosted caller identity to MCP.'
    AzureWrites=0
    VerifiedAtUtc=[datetime]::UtcNow.ToString('o')
}
$file=Join-Path $PSScriptRoot ".local/jaws-step-c-identity-context.$planSuffix.generated.json"
$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $file -Encoding utf8
Write-Host "Step C A2A identity context: $status"
Write-Host "Supervisor instance/blueprint IDs present: $($result.InstanceClientIdPresent)/$($result.BlueprintClientIdPresent)"
Write-Host "Connection authentication: $authType; expected connection: $connectionValid"
Write-Host "Report: $file"
if($status -ne 'IDENTITY_CONTEXT_AVAILABLE'){throw 'JAWS-A2A-IDENTITY-002: Expected identity or stored connection configuration missing; no changes made.'}
