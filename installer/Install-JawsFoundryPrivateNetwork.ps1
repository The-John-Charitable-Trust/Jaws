# DEPRECATED. Do not run this command.
# It deletes the Foundry account and recreates it with agent injection while
# public network access stays Enabled. That half-state is not the private profile.
# Create a private account with Install-Jaws.ps1 -NetworkProfile Private.
# This file stays until CJ decides to remove it. A CLI stand-in is not a live Azure receipt.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$EnvironmentName,
    [switch]$AcknowledgeFoundryReplacement
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$started = Get-Date
Import-Module (Join-Path $root 'modules/StepDBrowser.psm1') -Force
Import-Module (Join-Path $root 'modules/MilestoneResult.psm1') -Force
$local = Join-Path $root '.local'
if (-not (Test-Path -LiteralPath $local)) { New-Item -ItemType Directory -Path $local | Out-Null }
$evidencePath = Join-Path $local "jaws-step-d-foundry-network.$EnvironmentName.generated.json"
try {
    $result = Install-JawsFoundryPrivateNetwork -EnvironmentName $EnvironmentName -InstallerRoot $root -AcknowledgeFoundryReplacement:$AcknowledgeFoundryReplacement
    $next = if ($result.Replaced) { 'Step B Install' } else { 'Step D Install' }
    [pscustomobject]@{
        Result = 'PASS'
        EnvironmentName = $EnvironmentName
        FoundryAccountName = $result.FoundryAccountName
        FoundryAccountReplaced = $result.Replaced
        FoundrySubnetId = $result.FoundrySubnetId
        AzureWrites = $result.AzureWrites
        CustomerInstallationAccepted = $false
        FreshSubscriptionReceiptArchived = $false
        EvidenceLimitations = 'A CLI stand-in is not a live Azure receipt. Replacing the account removes the project, model deployment, Supervisor, and Investigation toolbox.'
        CompletedAtUtc = [DateTime]::UtcNow.ToString('o')
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $evidencePath -Encoding utf8
    Write-Host 'STEP-D FOUNDRY NETWORK PASS'
    Write-Host 'Customer installation accepted: false'
    Write-Host "Azure writes: $($result.AzureWrites)"
    Write-Host "Foundry account replaced: $($result.Replaced)"
    Write-Host "Foundry subnet: $($result.FoundrySubnetId)"
    Write-JawsMilestoneResult -Result PASS -ReadyForNextStep $true -NextStep $next -EvidencePath $evidencePath
} catch {
    Save-JawsMilestoneFailure -Path $evidencePath -Message $_.Exception.Message -Started $started
    Write-Host 'STEP-D FOUNDRY NETWORK FAIL'
    Write-Host 'Customer installation accepted: false'
    Write-JawsMilestoneResult -Result FAIL -ReadyForNextStep $false -NextStep 'Install-JawsFoundryPrivateNetwork.ps1' -EvidencePath $evidencePath
    throw
}
