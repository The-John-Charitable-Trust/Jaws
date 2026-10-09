# JAWS Stage A v0.4.0 - installer entry point, read-only Azure discovery
[CmdletBinding()]
param(
    [ValidateSet('Discover')][string]$Mode='Discover',
    [string]$SubscriptionId,
    [string]$ResourceGroupName,
    [string]$FoundryResourceName,
    [string]$FoundryProjectName,
    [string]$ModelDeploymentName,
    [string]$KeyVaultName,
    [string]$ExpectedModelName='gpt-5-mini',
    [string]$ExpectedModelVersion='2025-08-07',
    [ValidatePattern('^[a-zA-Z0-9_-]+$')][string]$EnvironmentName='dev',
    [switch]$NonInteractive
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'modules/AzurePreflight.psm1') -Force -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'modules/ResourceDiscovery.psm1') -Force -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'modules/ResourceManifest.psm1') -Force -ErrorAction Stop

function Resolve-JawsName {
    param([string]$Value,[string]$Prompt,[switch]$NonInteractive)
    if ($Value) { return $Value }
    if ($NonInteractive) { throw "JAWS-CONFIG-006: Missing required name for $Prompt." }
    $answer=Read-Host $Prompt
    if (-not $answer -or -not $answer.Trim()) { throw "JAWS-CONFIG-007: Empty value for $Prompt." }
    return $answer.Trim()
}

Write-Host 'JAWS Installer v0.4.2 | Stage A Pre-install Inventory (read-only)' -ForegroundColor Cyan
$context=Get-JawsAuthorizedSubscriptions -NonInteractive:$NonInteractive
$selected=Select-JawsSubscription -Subscriptions $context.Subscriptions -SubscriptionId $SubscriptionId -NonInteractive:$NonInteractive
$SubscriptionId=[string]$selected.id
$tenantId=[string]$selected.tenantId
Write-Host "Signed in: $($context.Account.user.name) | Tenant: $tenantId"
$ResourceGroupName=Select-JawsResourceGroup -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -NonInteractive:$NonInteractive

# Check every enabled subscription visible to the signed-in account in selected tenant.
Write-Host 'Scanning all accessible enabled subscriptions in selected tenant...' -ForegroundColor Cyan
$scan=Get-JawsTenantInstallationScan -Subscriptions $context.Subscriptions -TenantId $tenantId
$local=Join-Path $PSScriptRoot '.local'
if (-not (Test-Path -LiteralPath $local)) { New-Item -ItemType Directory -Path $local -Force | Out-Null }
$scanPath=Join-Path $local "jaws-tenant-scan.$EnvironmentName.generated.json"
# Save diagnostics even when a subscription scan is incomplete; do not silently claim success.
$scan | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $scanPath -Encoding utf8
Write-Host ''
Write-Host 'TENANT INVENTORY REPORT' -ForegroundColor Cyan
Write-Host '-----------------------'
Write-Host "Tenant: $($scan.TenantId)"
Write-Host "Subscriptions inspected: $(@($scan.Subscriptions | Where-Object Status -eq 'Scanned').Count) of $($scan.SubscriptionCount)"
foreach ($subResult in @($scan.Subscriptions)) {
    $countDisplay = if ($null -eq $subResult.ResourceCount) { 'N/A' } else { $subResult.ResourceCount }
    Write-Host ("  {0,-38} {1,-10} Resources: {2}" -f $subResult.SubscriptionId, $subResult.Status, $countDisplay)
    if ($subResult.Status -ne 'Scanned') {
        Write-Warning "  Subscription scan failed: $($subResult.Error)"
    }
}
Write-Host "Potential JAWS/Tight-Fang matches: $(@($scan.Candidates).Count)"
foreach ($candidate in @($scan.Candidates)) {
    Write-Host ("  POSSIBLE MATCH | {0} | {1} | {2} | {3}" -f $candidate.SubscriptionId, $candidate.ResourceGroup, $candidate.Name, $candidate.Reason)
}
Write-Host 'These are heuristic matches, not confirmed JAWS installations.' 
Write-Host "Tenant scan report: $scanPath"
if (-not $scan.Completed) {
    throw 'JAWS-SCAN-002: One or more visible subscriptions could not be scanned. Inspect the local tenant scan report. Resource manifest not updated.'
}
if (@($scan.Candidates).Count) {
    Write-Warning 'Possible existing JAWS/Tight-Fang resources were detected. Review the tenant scan report before any future install. Stage A makes no changes.'
}

$FoundryResourceName=Resolve-JawsName -Value $FoundryResourceName -Prompt 'Foundry resource name' -NonInteractive:$NonInteractive
$FoundryProjectName=Resolve-JawsName -Value $FoundryProjectName -Prompt 'Foundry project name' -NonInteractive:$NonInteractive
$ModelDeploymentName=Resolve-JawsName -Value $ModelDeploymentName -Prompt 'Model deployment name' -NonInteractive:$NonInteractive
$KeyVaultName=Resolve-JawsName -Value $KeyVaultName -Prompt 'Key Vault name' -NonInteractive:$NonInteractive

$manifestPath=Join-Path $local "jaws-resources.$EnvironmentName.generated.json"
$manifest=New-JawsResourceManifest -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -EnvironmentName $EnvironmentName -ExistingPath $manifestPath
$items=@()
$items+=Get-JawsAzureResource -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -ResourceName $FoundryResourceName -ResourceType 'Microsoft.CognitiveServices/accounts'
$items+=Get-JawsFoundryProject -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -FoundryResourceName $FoundryResourceName -ProjectName $FoundryProjectName
$items+=Get-JawsModelDeployment -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -FoundryResourceName $FoundryResourceName -DeploymentName $ModelDeploymentName
$items+=Get-JawsAzureResource -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -ResourceName $KeyVaultName -ResourceType 'Microsoft.KeyVault/vaults'
foreach($item in $items) {
    $expected=$null
    if ($item.Type -eq 'Microsoft.CognitiveServices/accounts/deployments') {
        $expected=[pscustomobject]@{ModelName=$ExpectedModelName;ModelVersion=$ExpectedModelVersion;ProvisioningState='Succeeded'}
    }
    $manifest=Add-JawsManifestResource -Manifest $manifest -DiscoveryResult $item -ExpectedConfiguration $expected
}
Save-JawsResourceManifest -Manifest $manifest -Path $manifestPath | Out-Null
Write-Host ''
Write-Host 'TARGET RESOURCE MANIFEST REPORT' -ForegroundColor Cyan
Write-Host '-------------------------------'
Write-Host ("{0,-24} {1,-13} {2,-10} {3,-28} {4}" -f 'RESOURCE', 'STATUS', 'OWNERSHIP', 'RECOMMENDED ACTION', 'VALIDATION')
foreach($resource in @($manifest.Resources)) {
    Write-Host ("{0,-24} {1,-13} {2,-10} {3,-28} {4}" -f $resource.Name,$resource.Status,$resource.Ownership,$resource.RecommendedAction,$resource.ValidationResult)
    Write-Host "  Type: $($resource.Type)"
    if ($resource.ResourceId) { Write-Host "  Azure Resource ID: $($resource.ResourceId)" }
    if ($resource.Type -eq 'Microsoft.CognitiveServices/accounts/deployments') {
        Write-Host "  Model expected: $ExpectedModelName ($ExpectedModelVersion)"
        $observed=$resource.ObservedConfiguration
        if ($observed -and $observed.ModelName) {
            Write-Host "  Model observed: $($observed.ModelName) ($($observed.ModelVersion)) | Provisioning: $($observed.ProvisioningState)"
        }
    }
}
Write-Host "Total resources: $(@($manifest.Resources).Count)"
Write-Host "Resource manifest: $manifestPath"
Write-Host 'Azure resource write operations: 0'
