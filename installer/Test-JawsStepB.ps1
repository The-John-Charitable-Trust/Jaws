# Plan, Package, and Install score local reports and do not call Azure.
# Accept re-reads the signed-in subscription. A local receipt alone cannot pass Accept.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Plan','Package','Install','Accept')][string]$Mode,
    [string]$ReportPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-JawsStepBGuid {
    param([AllowNull()][string]$Value)
    $parsed = [guid]::Empty
    return [guid]::TryParse([string]$Value, [ref]$parsed) -and $parsed -ne [guid]::Empty
}

$installerRoot = $PSScriptRoot
$examplePath = Join-Path $installerRoot 'config/jaws-stage-b-plan.example.json'
$example = Get-Content -LiteralPath $examplePath -Raw | ConvertFrom-Json
if ([string]$example.Scope.SubscriptionId -ne '00000000-0000-0000-0000-000000000000') {
    throw 'JAWS-STEP-B-003: Example blueprint subscription is no longer the placeholder. Plan must capture the Azure CLI subscription without editing this file.'
}

if ($Mode -eq 'Plan') {
    if (-not $ReportPath) {
        $ReportPath = Join-Path $installerRoot '.local/jaws-stage-b-plan.tester.offline.generated.json'
    }
    if (-not (Test-Path -LiteralPath $ReportPath -PathType Leaf)) {
        throw "JAWS-STEP-B-001: Step B plan report not found: $ReportPath"
    }
    $plan = Get-Content -LiteralPath $ReportPath -Raw | ConvertFrom-Json
    $source = [string]$plan.SubscriptionSource
    $reasons = @()
    if (-not (Test-JawsStepBGuid ([string]$plan.SubscriptionId))) { $reasons += 'subscription is empty' }
    if ($source -notin @('AzureCli','Parameter','Blueprint')) { $reasons += 'subscription source is missing' }
    if ($plan.AzureWrites -ne 0) { $reasons += 'Azure writes is not 0' }
    if ($plan.CanExecute) { $reasons += 'plan is executable' }
    if ($plan.AzureDiscoveryPerformed) { $reasons += 'plan claims Azure discovery' }
    if ([string]$plan.Status -ne 'BLOCKED_PENDING_AZURE_DISCOVERY_AND_APPROVAL') { $reasons += 'status is not blocked' }
    if ([string]::IsNullOrWhiteSpace([string]$plan.ResourceGroupName) -or [string]::IsNullOrWhiteSpace([string]$plan.Location)) {
        $reasons += 'resource group or location is blank'
    }
    if ($reasons.Count -gt 0) { throw "JAWS-STEP-B-002: Offline plan is not a Step B pass. $($reasons -join '; ')." }
    Write-Host 'STEP-B PLAN PASS'
    Write-Host "Subscription: $($plan.SubscriptionId)"
    Write-Host "Subscription source: $source"
    Write-Host "Resource group: $($plan.ResourceGroupName)"
    Write-Host "Location: $($plan.Location)"
    Write-Host "Status: $($plan.Status)"
    Write-Host 'Can execute: false'
    Write-Host 'Azure writes: 0'
    Write-Host 'Example blueprint: unchanged'
    return
}

if ($Mode -eq 'Install') {
    if (-not $ReportPath) {
        $found = @(Get-ChildItem -LiteralPath (Join-Path $installerRoot '.local') -Filter 'jaws-step-b-install.*.generated.json' -ErrorAction SilentlyContinue)
        if ($found.Count -ne 1) { throw "JAWS-STEP-B-006: Expected one Step B install receipt, found $($found.Count)." }
        $ReportPath = $found[0].FullName
    }
    if (-not (Test-Path -LiteralPath $ReportPath -PathType Leaf)) { throw "JAWS-STEP-B-006: Step B install receipt not found: $ReportPath" }
    $receipt = Get-Content -LiteralPath $ReportPath -Raw | ConvertFrom-Json
    $dev = Get-Content -LiteralPath (Join-Path $installerRoot 'config/jaws-installation-state.dev.json') -Raw
    $reasons = @()
    if ([string]$receipt.Status -ne 'STEP_B_INSTALLED') { $reasons += 'status is not STEP_B_INSTALLED' }
    if ([string]$receipt.AgentStatus -ne 'active' -or [string]$receipt.AgentVersion -ne '1') { $reasons += 'hosted agent is not active version 1' }
    if ([string]$receipt.Image -notmatch '@sha256:[a-f0-9]{64}$') { $reasons += 'image is not digest-pinned' }
    if ([string]$receipt.FoundryAccountName -eq 'jaws-foundry-dev' -or [string]$receipt.ResourceGroupName -eq 'rg-aiops-lab') { $reasons += 'receipt targets the accepted dev project' }
    if ($dev -notmatch 'c52f597b-7753-45b4-a764-67e290dcfd5e') { $reasons += 'dev installation state changed' }
    if (-not (Test-Path -LiteralPath ([string]$receipt.StatePath) -PathType Leaf)) { $reasons += 'generated installation state is missing' }
    if ($reasons.Count -gt 0) { throw "JAWS-STEP-B-007: Step B install receipt is not a pass. $($reasons -join '; ')." }
    Write-Host 'STEP-B INSTALL PASS'
    Write-Host "Foundry account: $($receipt.FoundryAccountName)"
    Write-Host "Project: $($receipt.ProjectName)"
    Write-Host "Model: $($receipt.ModelName) $($receipt.ModelVersion)"
    Write-Host "Image: $($receipt.Image)"
    Write-Host "Agent: $($receipt.AgentName)"
    Write-Host 'Agent version: 1'
    Write-Host 'Agent status: active'
    Write-Host "Azure writes: $($receipt.AzureWrites)"
    Write-Host 'Live Azure read: false'
    return
}

if ($Mode -eq 'Accept') {
    if (-not $ReportPath) {
        $found = @(Get-ChildItem -LiteralPath (Join-Path $installerRoot '.local') -Filter 'jaws-step-b-install.*.generated.json' -ErrorAction SilentlyContinue)
        if ($found.Count -ne 1) { throw "JAWS-STEP-B-006: Expected one Step B install receipt, found $($found.Count)." }
        $ReportPath = $found[0].FullName
    }
    if (-not (Test-Path -LiteralPath $ReportPath -PathType Leaf)) { throw "JAWS-STEP-B-006: Step B install receipt not found: $ReportPath" }
    $receipt = Get-Content -LiteralPath $ReportPath -Raw | ConvertFrom-Json
    & (Join-Path $installerRoot 'Install-Jaws.ps1') -Mode Accept -EnvironmentName ([string]$receipt.EnvironmentName) -ResourceGroupName ([string]$receipt.ResourceGroupName) -Location ([string]$receipt.Location) -ModelName ([string]$receipt.ModelName) -ModelVersion ([string]$receipt.ModelVersion)
    return
}

if (-not $ReportPath) {
    $ReportPath = Join-Path $installerRoot '.local/jaws-step-b-package.generated.json'
}
if (-not (Test-Path -LiteralPath $ReportPath -PathType Leaf)) {
    throw "JAWS-STEP-B-004: Step B package report not found: $ReportPath"
}
$package = Get-Content -LiteralPath $ReportPath -Raw | ConvertFrom-Json
$publishRoot = [System.IO.Path]::GetFullPath((Join-Path $installerRoot '.local/supervisor/publish'))
$outputPath = [System.IO.Path]::GetFullPath([string]$package.OutputPath)
$dllPath = Join-Path $outputPath 'Jaws.Supervisor.Host.dll'
$reasons = @()
if ([string]$package.Status -ne 'LOCAL_PACKAGE_CREATED') { $reasons += 'status is not LOCAL_PACKAGE_CREATED' }
if ($package.AzureWrites -ne 0) { $reasons += 'Azure writes is not 0' }
if ($package.RegistryPushPerformed) { $reasons += 'registry push is recorded' }
if ($package.FoundryDeploymentPerformed) { $reasons += 'Foundry deployment is recorded' }
if (-not $outputPath.StartsWith($publishRoot, [System.StringComparison]::OrdinalIgnoreCase)) { $reasons += 'output is outside the local publish directory' }
if (-not (Test-Path -LiteralPath $dllPath -PathType Leaf)) { $reasons += 'Jaws.Supervisor.Host.dll is missing' }
$project = [string]$package.ProjectPath
if (-not $project.EndsWith('Jaws.Supervisor.Host.csproj') -or -not (Test-Path -LiteralPath $project -PathType Leaf)) {
    $reasons += 'Supervisor host project is missing'
}
if ($package.ContainerBuilt) {
    if ([string]$package.ContainerTag -ne 'jaws-supervisor:local') { $reasons += 'container tag is not jaws-supervisor:local' }
} elseif ($null -ne $package.ContainerTag -and [string]$package.ContainerTag -ne '') {
    $reasons += 'container tag is set without a container build'
}
if ($reasons.Count -gt 0) { throw "JAWS-STEP-B-005: Local package is not a Step B pass. $($reasons -join '; ')." }
Write-Host 'STEP-B PACKAGE PASS'
Write-Host 'Status: LOCAL_PACKAGE_CREATED'
Write-Host 'Azure writes: 0'
Write-Host 'Registry push: false'
Write-Host 'Foundry deployment: false'
Write-Host ("Container built: " + $(if ($package.ContainerBuilt) {'true'} else {'false'}))
if ($package.ContainerBuilt) { Write-Host "Container tag: jaws-supervisor:local" }
Write-Host "Output: $outputPath"
