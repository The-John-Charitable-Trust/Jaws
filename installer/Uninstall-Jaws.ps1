# Hard-delete one JAWS environment.
# Foundry agents are force-deleted before the account is purged. A resource-group
# delete alone leaves those agent records, and they return when the same account
# name is created again. The dev project is refused.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$EnvironmentName,
    [string]$SubscriptionId,
    [string]$ResourceGroupName,
    [string]$Location,
    [string]$FoundryAccountName,
    [string]$ProjectName,
    [string]$KeyVaultName,
    [switch]$AcknowledgeJawsUninstall
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$started = Get-Date
Import-Module (Join-Path $root 'modules/Uninstall.psm1') -Force
Import-Module (Join-Path $root 'modules/MilestoneResult.psm1') -Force
$local = Join-Path $root '.local'
if (-not (Test-Path -LiteralPath $local)) { New-Item -ItemType Directory -Path $local | Out-Null }
$evidence = Join-Path $local "jaws-uninstall.$EnvironmentName.generated.json"
try {
    $result = Invoke-JawsUninstall -EnvironmentName $EnvironmentName -InstallerRoot $root -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -Location $Location -FoundryAccountName $FoundryAccountName -ProjectName $ProjectName -KeyVaultName $KeyVaultName -AcknowledgeJawsUninstall:$AcknowledgeJawsUninstall
    $receipt = $result.Receipt
    Write-Host 'JAWS UNINSTALL PASS'
    Write-Host "Environment: $($receipt.EnvironmentName)"
    Write-Host "Resource group: $($receipt.ResourceGroupName)"
    Write-Host "Foundry account: $($receipt.FoundryAccountName)"
    Write-Host "Agents deleted: $($receipt.AgentsDeleted.Count)"
    Write-Host "Toolboxes deleted: $($receipt.ToolboxesDeleted.Count)"
    Write-Host "Connections deleted: $($receipt.ConnectionsDeleted.Count)"
    Write-Host "Deployments deleted: $($receipt.DeploymentsDeleted.Count)"
    Write-Host "Projects deleted: $($receipt.ProjectsDeleted.Count)"
    Write-Host "Role assignments deleted: $($receipt.RoleAssignmentsDeleted.Count)"
    Write-Host "Resources deleted: $($receipt.ResourcesDeleted.Count)"
    Write-Host "Datadog tag removed: $($receipt.DatadogTagRemoved.ToString().ToLowerInvariant())"
    Write-Host "Foundry purged: $($receipt.FoundryPurged.ToString().ToLowerInvariant())"
    Write-Host "Key Vault purge: $($receipt.KeyVaultPurge)"
    if (-not [string]::IsNullOrWhiteSpace([string]$receipt.KeyVaultPurgeNotBefore)) {
        Write-Host "Key Vault purge not before: $($receipt.KeyVaultPurgeNotBefore)"
        Write-Host 'Choose a different Key Vault name for the next install until that purge date.'
    }
    Write-Host 'Resource group deleted: true'
    Write-Host "Azure writes: $($receipt.AzureWrites)"
    Write-Host 'Customer installation accepted: false'
    Write-Host "Receipt: $($result.EvidencePath)"
    Write-JawsMilestoneResult -Result PASS -ReadyForNextStep $true -NextStep 'Step B Plan' -EvidencePath $result.EvidencePath
} catch {
    Save-JawsMilestoneFailure -Path $evidence -Message $_.Exception.Message -Started $started
    Write-Host 'JAWS UNINSTALL FAIL'
    Write-Host 'Customer installation accepted: false'
    Write-JawsMilestoneResult -Result FAIL -ReadyForNextStep $false -NextStep 'Uninstall' -EvidencePath $evidence
    throw
}
