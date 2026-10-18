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
Write-Host "Prepared for Step B: $($receipt.PreparedForStepB.ToString().ToLowerInvariant())"
Write-Host 'Live Azure read: false'
Write-Host "Receipt: $ReportPath"
Import-Module (Join-Path $installerRoot 'modules/MilestoneResult.psm1') -Force
Write-JawsMilestoneResult -Result PASS -ReadyForNextStep ([bool]$receipt.PreparedForStepB) -NextStep 'Step B Plan' -EvidencePath $ReportPath
