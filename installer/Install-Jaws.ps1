# JAWS Installer 0.4.6 — State-first read-only discovery and reconciliation
[CmdletBinding()]
param(
    [ValidateSet('Discover','Plan')][string]$Mode='Discover',
    [string]$PlanFile,
    [string]$SubscriptionId,
    [string]$ResourceGroupName,
    [string]$EnvironmentName='dev',
    [string]$StateFile,
    [switch]$NonInteractive
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
# B2 Plan is an OFFLINE blueprint. It runs before Stage A Azure imports and cannot call Azure.
if ($Mode -eq 'Plan') {
    Import-Module (Join-Path $PSScriptRoot 'modules/DeploymentPlan.psm1') -Force
    if (-not $PlanFile) { $PlanFile = Join-Path $PSScriptRoot 'config/jaws-stage-b-plan.example.json' }
    $offlinePlan = New-JawsOfflineDeploymentPlan -BlueprintPath $PlanFile
    $outputDir = Join-Path $PSScriptRoot '.local'
    if (-not (Test-Path -LiteralPath $outputDir)) { New-Item -ItemType Directory -Path $outputDir -Force | Out-Null }
    $outputPath = Join-Path $outputDir "jaws-stage-b-plan.$($offlinePlan.EnvironmentName).generated.json"
    $offlinePlan | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $outputPath -Encoding utf8
    Write-Host 'JAWS Stage B2 OFFLINE BLUEPRINT — NO AZURE CALLS OR WRITES' -ForegroundColor Cyan
    Write-Host "Target: $($offlinePlan.SubscriptionId) | $($offlinePlan.ResourceGroupName) | $($offlinePlan.Location)"
    foreach ($component in $offlinePlan.Components) {
        Write-Host ("  {0,-20} {1,-29} {2}" -f $component.Id, $component.ProposedAction, $component.EstimatedCost)
    }
    Write-Host "Status: $($offlinePlan.Status)" -ForegroundColor Yellow
    Write-Host "Output: $outputPath"
    Write-Host 'Azure writes: 0 | Azure discovery: not performed | Costs and authorization: not verified'
    return
}
Import-Module (Join-Path $PSScriptRoot 'modules/AzurePreflight.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'modules/ResourceDiscovery.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'modules/ResourceManifest.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'modules/InstallationState.psm1') -Force

# The operator-maintained state is the GOLD COPY. Never overwrite it in Discover.
if (-not $StateFile) { $StateFile=Join-Path $PSScriptRoot "config/jaws-installation-state.$EnvironmentName.json" }
$state=Read-JawsInstallationState -Path $StateFile
if (-not $state) { throw "JAWS-STATE-003: No installation state at '$StateFile'. A new installation requires Stage B Install mode; Discover cannot invent an installation state." }
if ($state.EnvironmentName -ine $EnvironmentName) { throw 'JAWS-STATE-002: Environment name does not match the JAWS state.' }
if ($SubscriptionId -and $SubscriptionId -ine $state.SubscriptionId) { throw 'JAWS-STATE-002: Subscription differs from the authoritative state.' }
if ($ResourceGroupName -and $ResourceGroupName -ine $state.ResourceGroupName) { throw 'JAWS-STATE-002: Resource group differs from the authoritative state.' }
$SubscriptionId=[string]$state.SubscriptionId
$ResourceGroupName=[string]$state.ResourceGroupName
Write-Host "JAWS Installer v0.4.6 | $Mode | State-first verification" -ForegroundColor Cyan
Write-Host "Authoritative state: $StateFile"
Write-Host "Target: $SubscriptionId | $ResourceGroupName"
$context=Get-JawsAuthorizedSubscriptions -NonInteractive:$NonInteractive
$selected=Select-JawsSubscription -Subscriptions $context.Subscriptions -SubscriptionId $SubscriptionId -NonInteractive:$NonInteractive
$tenantId=[string]$selected.tenantId
$null=Select-JawsResourceGroup -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -NonInteractive:$NonInteractive
$scan=Get-JawsTenantInstallationScan -Subscriptions $context.Subscriptions -TenantId $tenantId
$local=Join-Path $PSScriptRoot '.local'
if (-not (Test-Path $local)) { New-Item -ItemType Directory -Path $local -Force | Out-Null }
$scanPath=Join-Path $local "jaws-tenant-scan.$EnvironmentName.generated.json"
$scan | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $scanPath -Encoding utf8
Write-Host "TENANT SCAN: $(@($scan.Subscriptions | Where-Object Status -eq 'Scanned').Count)/$($scan.SubscriptionCount) subscriptions" -ForegroundColor Cyan
foreach($sub in @($scan.Subscriptions)) { Write-Host ("  {0,-38} {1,-8} Resources: {2}" -f $sub.SubscriptionId,$sub.Status,$sub.ResourceCount) }
if (-not $scan.Completed) { throw "JAWS-SCAN-002: Tenant scan incomplete. Report: $scanPath. Authoritative JAWS state unchanged." }
$scanMatches=Compare-JawsTenantScanToState -State $state -Scan $scan
Write-Host 'TENANT SCAN VS. JAWS STATE' -ForegroundColor Cyan
foreach($m in $scanMatches) { Write-Host ("  {0,-26} {1}" -f $m.Name,$m.Status) }
# Ignore legacy infrastructure entirely in the customer-facing JAWS reports.
# Targeted discovery is authoritative on actual presence; tenant naming heuristic is only informative.
$foundry=@($state.Resources | Where-Object Type -eq 'Microsoft.CognitiveServices/accounts')
$project=@($state.Resources | Where-Object Type -eq 'Microsoft.CognitiveServices/accounts/projects')
$model=@($state.Resources | Where-Object Type -eq 'Microsoft.CognitiveServices/accounts/deployments')
$vault=@($state.Resources | Where-Object Type -eq 'Microsoft.KeyVault/vaults')
if ($foundry.Count -ne 1 -or $project.Count -ne 1 -or $model.Count -ne 1 -or $vault.Count -ne 1) { throw 'JAWS-STATE-007: Stage A requires exactly one Foundry resource, project, deployment, and vault in the state JSON.' }
$items=@()
$items+=Get-JawsAzureResource -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -ResourceName $foundry[0].Name -ResourceType $foundry[0].Type
$items+=Get-JawsFoundryProject -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -FoundryResourceName $foundry[0].Name -ProjectName $project[0].Name
$items+=Get-JawsModelDeployment -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -FoundryResourceName $foundry[0].Name -DeploymentName $model[0].Name
$items+=Get-JawsAzureResource -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -ResourceName $vault[0].Name -ResourceType $vault[0].Type
$comparison=Compare-JawsTargetDiscoveryToState -State $state -Results $items
$manifestPath=Join-Path $local "jaws-resources.$EnvironmentName.generated.json"
$manifest=New-JawsResourceManifest -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -EnvironmentName $EnvironmentName -ExistingPath $manifestPath
foreach($item in $items) {
    $ex=@($state.Resources | Where-Object { $_.Name -ieq $item.Name -and $_.Type -ieq $item.Type })[0]
    $expected=$null
    if ($item.Type -eq 'Microsoft.CognitiveServices/accounts/deployments') {
        $expected=[pscustomobject]@{ModelName=$ex.ExpectedConfiguration.ModelName;ModelVersion=$ex.ExpectedConfiguration.ModelVersion;ProvisioningState=$ex.ExpectedConfiguration.ProvisioningState}
    }
    $manifest=Add-JawsManifestResource -Manifest $manifest -DiscoveryResult $item -ExpectedConfiguration $expected
}
# Refuse to persist a current-state manifest over an identity mismatch.
if (@($comparison | Where-Object Status -eq 'IdentityDrift').Count -gt 0) { throw 'JAWS-STATE-008: Resource identity mismatch. State unchanged and manifest not rewritten.' }
Save-JawsResourceManifest -Manifest $manifest -Path $manifestPath | Out-Null
$report=[pscustomobject]@{SchemaVersion='1.0';EnvironmentName=$EnvironmentName;StateFile=$StateFile;TenantScan=$scanMatches;TargetDiscovery=$comparison;CompletedAtUtc=(Get-Date).ToUniversalTime().ToString('o')}
$reportPath=Join-Path $local "jaws-state-comparison.$EnvironmentName.generated.json"
$report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $reportPath -Encoding utf8
Write-Host 'JAWS TARGET RESOURCE COMPARISON' -ForegroundColor Cyan
foreach($m in $comparison) { Write-Host ("  {0,-26} {1,-20} {2}" -f $m.Name,$m.Status,$m.ObservedResourceId) }
Write-Host "Manifest: $manifestPath"
Write-Host "Comparison report: $reportPath"
Write-Host 'JAWS golden state JSON: unchanged (Discover mode).' -ForegroundColor Green
Write-Host 'Azure writes: 0'
