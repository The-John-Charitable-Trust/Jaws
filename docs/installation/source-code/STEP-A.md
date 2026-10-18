# Step A | JAWS source-code implementation

Greenfield discovery and receipt verification. No Python or C# implementation is used in this stage.

**Provenance:** All listings below are verbatim, contiguous excerpts retrieved from the `main` branch of [The-John-Charitable-Trust/Jaws](https://github.com/The-John-Charitable-Trust/Jaws). No code here is invented, pseudocode, or a Microsoft sample. The line numbers and blob identifiers identify the reviewed snapshot. Other lines are intentionally omitted; open each linked source file for its complete implementation. Executing an excerpt alone is not equivalent to running the full JAWS installer.

## installer/modules/StepADiscovery.psm1

[View complete JAWS source](https://github.com/The-John-Charitable-Trust/Jaws/blob/main/installer/modules/StepADiscovery.psm1) · Reviewed blob `ba7f7a36319833d5446cc39d8f51648d64b9006b`

**Source lines 19–49:**

```powershell
function Invoke-JawsStepAGreenfieldDiscovery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$EnvironmentName,
        [string]$SubscriptionId,
        [string]$ResourceGroupName,
        [string]$Location,
        [Parameter(Mandatory)][string]$InstallerRoot,
        [switch]$NonInteractive
    )
    Import-Module (Join-Path $PSScriptRoot 'AzurePreflight.psm1') -Force
    $devState = Join-Path $InstallerRoot 'config/jaws-installation-state.dev.json'
    $devBefore = Get-Content -LiteralPath $devState -Raw
    $context = Get-JawsAuthorizedSubscriptions -NonInteractive:$NonInteractive
    $cliId = [string]$context.Account.id
    if ($SubscriptionId -and $SubscriptionId -ine $cliId) {
        throw 'JAWS-AUTH-007: -SubscriptionId does not match the Azure CLI account. Run az account set. No resources were created.'
    }
    $selected = Select-JawsSubscription -Subscriptions $context.Subscriptions -SubscriptionId $cliId -NonInteractive
    $subscription = [string]$selected.id
    $tenant = [string]$selected.tenantId
    if ([string]::IsNullOrWhiteSpace($tenant)) { throw 'JAWS-AUTH-006: The selected subscription has no tenant id.' }
    $groupsValue = Invoke-JawsPreflightRead -Arguments @('group','list','--subscription',$subscription,'--output','json','--only-show-errors') -Operation 'greenfield resource group inventory'
    $groups = ConvertTo-JawsStepAList $groupsValue
    $resourcesValue = Invoke-JawsPreflightRead -Arguments @('resource','list','--subscription',$subscription,'--output','json','--only-show-errors') -Operation 'greenfield resource inventory'
    $resources = ConvertTo-JawsStepAList $resourcesValue
    $intendedExists = $false
    $intendedLocation = $null
    if ($ResourceGroupName) {
        $match = @($groups | Where-Object { [string](Get-JawsStepAProperty $_ 'name') -ieq $ResourceGroupName })
        $intendedExists = $match.Count -eq 1
```

**Source lines 99–122:**

```powershell
        ResourceGroupCount = @($groups).Count
        ResourceCount = @($resources).Count
        CandidateCount = @($candidates).Count
        Candidates = @($candidates)
        StateFileRequired = $false
        StateFileWritten = $false
        AzureWrites = 0
        PreparedForStepB = [bool]$prepared
        PreparedForStepBReason = $reason
        NextCommand = $next
    }
    $receiptPath = Join-Path $local "jaws-step-a-discovery.$EnvironmentName.generated.json"
    $receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receiptPath -Encoding utf8
    if ((Get-Content -LiteralPath $devState -Raw) -ne $devBefore) {
        throw 'JAWS-STEP-A-022: Greenfield discovery changed the dev installation state.'
    }
    $configWrites = @(Get-ChildItem -LiteralPath (Join-Path $InstallerRoot 'config') -Filter "jaws-installation-state.$EnvironmentName.json" -ErrorAction SilentlyContinue)
    if ($EnvironmentName -ne 'dev' -and $configWrites.Count -gt 0) {
        throw "JAWS-STEP-A-022: Greenfield discovery wrote $EnvironmentName state into installer/config."
    }
    return [pscustomobject]@{ Receipt = $receipt; ReceiptPath = $receiptPath }
}

Export-ModuleMember -Function Invoke-JawsStepAGreenfieldDiscovery
```

## installer/Test-JawsStepA.ps1

[View complete JAWS source](https://github.com/The-John-Charitable-Trust/Jaws/blob/main/installer/Test-JawsStepA.ps1) · Reviewed blob `b707cca5709f9f377de1196a5aebbc12115fad39`

**Source lines 1–35:**

```powershell
# Scores a greenfield Step A receipt. This script does not call Azure.
[CmdletBinding()]
param([string]$ReportPath)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$installerRoot = $PSScriptRoot
if (-not $ReportPath) {
    $found = @(Get-ChildItem -LiteralPath (Join-Path $installerRoot '.local') -Filter 'jaws-step-a-discovery.*.generated.json' -ErrorAction SilentlyContinue)
    if ($found.Count -ne 1) { throw "JAWS-STEP-A-006: Expected one Step A discovery receipt, found $($found.Count)." }
    $ReportPath = $found[0].FullName
}
if (-not (Test-Path -LiteralPath $ReportPath -PathType Leaf)) { throw "JAWS-STEP-A-006: Step A discovery receipt not found: $ReportPath" }
$receipt = Get-Content -LiteralPath $ReportPath -Raw | ConvertFrom-Json
$dev = Get-Content -LiteralPath (Join-Path $installerRoot 'config/jaws-installation-state.dev.json') -Raw
$parsed = [guid]::Empty
$reasons = @()
if ([string]$receipt.Status -ne 'STEP_A_DISCOVERED') { $reasons += 'status is not STEP_A_DISCOVERED' }
if ([string]$receipt.DiscoveryKind -ne 'Greenfield') { $reasons += 'discovery kind is not Greenfield' }
if ([string]$receipt.SubscriptionSource -ne 'AzureCli') { $reasons += 'subscription source is not AzureCli' }
if (-not [guid]::TryParse([string]$receipt.SubscriptionId, [ref]$parsed) -or $parsed -eq [guid]::Empty) { $reasons += 'subscription is empty' }
if ($receipt.AzureWrites -ne 0) { $reasons += 'Azure writes is not 0' }
if ($receipt.StateFileRequired) { $reasons += 'state file is required' }
if ($receipt.StateFileWritten) { $reasons += 'state file was written' }
if ($dev -notmatch 'c52f597b-7753-45b4-a764-67e290dcfd5e') { $reasons += 'dev installation state changed' }
if ($reasons.Count -gt 0) { throw "JAWS-STEP-A-007: Step A discovery receipt is not a pass. $($reasons -join '; ')." }
Write-Host 'STEP-A DISCOVERY PASS'
Write-Host 'Discovery: Greenfield'
Write-Host "Subscription source: $($receipt.SubscriptionSource)"
Write-Host "Subscription: $($receipt.SubscriptionId)"
Write-Host "Resource groups: $($receipt.ResourceGroupCount)"
Write-Host "Resources: $($receipt.ResourceCount)"
Write-Host "JAWS candidates: $($receipt.CandidateCount)"
Write-Host 'State file required: false'
Write-Host 'State file written: false'
Write-Host 'Azure writes: 0'
```

## Scope and validation

The snippets above reflect the code on `main` at the time this documentation was authored. Do not use them as standalone scripts; use the documented installer commands and test/acceptance gates. After source changes, re-extract excerpts from the changed files and update the listed ranges and blob identifiers.
