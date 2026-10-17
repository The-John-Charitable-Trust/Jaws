# Step C: read-only/offline plan for first dedicated Foundry Investigation Agent.
# NO Docker push, Foundry creation, RBAC assignment or model inference.
[CmdletBinding()]
param(
    [string]$StateFile=(Join-Path $PSScriptRoot 'config/jaws-installation-state.dev.json'),
    [string]$RegistryName='jawsregistrydev001',
    [string]$AgentName='jaws-investigation-dev',
    [switch]$CheckLocalImage
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'modules/InstallationState.psm1') -Force
$state=Read-JawsInstallationState -Path $StateFile
if ($null -eq $state -or $state.Platform -cne 'JAWS' -or $state.EnvironmentName -cne 'dev')
    { throw 'JAWS-INV-PLAN-001: Authorized JAWS dev state missing or mismatched.' }
if ($RegistryName -cne 'jawsregistrydev001' -or $AgentName -cne 'jaws-investigation-dev')
    { throw 'JAWS-INV-PLAN-002: Unapproved Investigation registry or identity.' }
$foundry=@($state.Resources | Where-Object Type -eq 'Microsoft.CognitiveServices/accounts')
$project=@($state.Resources | Where-Object Type -eq 'Microsoft.CognitiveServices/accounts/projects')
$model=@($state.Resources | Where-Object Type -eq 'Microsoft.CognitiveServices/accounts/deployments')
if ($foundry.Count -ne 1 -or $project.Count -ne 1 -or $model.Count -ne 1)
    { throw 'JAWS-INV-PLAN-003: Invalid Foundry state inventory.' }
if ($project[0].ExpectedConfiguration.ParentResource -cne $foundry[0].Name -or
    $model[0].ExpectedConfiguration.ParentResource -cne $foundry[0].Name)
    { throw 'JAWS-INV-PLAN-004: Foundry project/model state relationship drift.' }
$root=[System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$hostFile=Join-Path $root 'src/Jaws.Investigation.Host/Jaws.Investigation.Host.csproj'
$dockerfile=Join-Path $root 'src/Jaws.Investigation.Host/Dockerfile'
if (-not (Test-Path -LiteralPath $hostFile -PathType Leaf) -or
    -not (Test-Path -LiteralPath $dockerfile -PathType Leaf))
    { throw 'JAWS-INV-PLAN-005: Investigation package incomplete.' }
$imageId=$null
if ($CheckLocalImage) {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue))
        { throw 'JAWS-INV-PLAN-006: Docker CLI unavailable.' }
    $result=& docker image inspect 'jaws-investigation:local' '--format' '{{.Id}}' 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'JAWS-INV-PLAN-007: Local Investigation image missing.' }
    $imageId=($result | Out-String).Trim()
    if ($imageId -cnotmatch '^sha256:[a-f0-9]{64}$')
        { throw 'JAWS-INV-PLAN-008: Local image digest invalid.' }
}
$planPayload=[ordered]@{
    SchemaVersion='1.0'
    Operation='PlanFoundryHostedInvestigation'
    EnvironmentName=[string]$state.EnvironmentName
    SubscriptionId=[string]$state.SubscriptionId
    ResourceGroupName=[string]$state.ResourceGroupName
    FoundryResource=[string]$foundry[0].Name
    ProjectName=[string]$project[0].Name
    ModelDeployment=[string]$model[0].Name
    AgentName=$AgentName
    RegistryName=$RegistryName
    RegistryRepository='jaws/investigation'
    ProjectEndpoint="https://$($foundry[0].Name).services.ai.azure.com/api/projects/$($project[0].Name)"
    RuntimeProject='src/Jaws.Investigation.Host/Jaws.Investigation.Host.csproj'
    Dockerfile='src/Jaws.Investigation.Host/Dockerfile'
    LocalImageTag='jaws-investigation:local'
    LocalImageId=$imageId
    Protocol='responses'
    ProtocolVersion='2.0.0'
    CPU='1'
    Memory='2Gi'
    ExternalToolAccess='NONE'
    UserProvidedEnvironmentVariables=[ordered]@{AZURE_AI_MODEL_DEPLOYMENT_NAME=[string]$model[0].Name}
}
$planJson=ConvertTo-Json -InputObject $planPayload -Depth 16 -Compress
$sha=[System.Security.Cryptography.SHA256]::Create()
try { $hash=($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($planJson)) | ForEach-Object {$_.ToString('x2')}) -join '' }
finally { $sha.Dispose() }
$report=[pscustomobject]@{
    PlanSha256=$hash
    Plan=$planPayload
    Status='BLOCKED_PENDING_IMAGE_PUBLISH_LIVE_DISCOVERY_APPROVAL_AND_DEPLOYMENT'
    CanDeploy=$false
    AzureWrites=0
    RegistryPushPerformed=$false
    FoundryDeploymentPerformed=$false
    RequiredGates=@(
       'Local .NET build + 15 offline tests and installer regressions',
       'Publish immutable Investigation image by separately authorized installer',
       'Read-only verify existing agent name and published digest',
       'Confirm registry pull role, project identity, quotas and billable charges',
       'Obtain operator approval matching final executable deployment plan',
       'Deploy a NEW investigation agent without changing Supervisor v1',
       'Authenticated live Investigation endpoint and delegation acceptance'
    )
}
$local=Join-Path $PSScriptRoot '.local'
if (-not (Test-Path -LiteralPath $local)) { $null=New-Item -ItemType Directory -Path $local -Force }
$dest=Join-Path $local 'jaws-investigation-plan.dev.generated.json'
$report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $dest -Encoding utf8
Write-Host 'JAWS STEP C: OFFLINE DEPLOYMENT READINESS ONLY - ZERO AZURE CALLS OR WRITES'
Write-Host "Agent: $AgentName | Foundry project: $($planPayload.ProjectName)"
Write-Host "Plan SHA-256: $hash"
Write-Host "Report: $dest"
Write-Host "Status: $($report.Status)"
