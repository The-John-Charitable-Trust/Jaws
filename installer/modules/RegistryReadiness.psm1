# Stage B2 milestone 1: strictly read-only ACR assessment. Never provisions or pushes.
Set-StrictMode -Version Latest
function Test-JawsRegistryObservation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RegistryName,
        [Parameter(Mandatory)][string]$SubscriptionId,
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)]$Observed
    )
    if ($RegistryName -cnotmatch '^[a-zA-Z0-9]{5,50}$') { throw 'JAWS-ACR-001: Invalid registry name.' }
    $expectedId="/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.ContainerRegistry/registries/$RegistryName"
    if ([string]$Observed.id -ine $expectedId -or [string]$Observed.name -ine $RegistryName) {
        throw 'JAWS-ACR-002: Registry identity or scope mismatch. No adoption permitted.'
    }
    $loginServer="$RegistryName.azurecr.io"
    if ([string]$Observed.loginServer -ine $loginServer) {
        throw 'JAWS-ACR-003: Unexpected registry login server.'
    }
    $admin=$Observed.PSObject.Properties['adminUserEnabled']
    $adminEnabled=if ($null -eq $admin) {$null} else {$admin.Value}
    $sku=if ($null -ne $Observed.PSObject.Properties['sku']) {[string]$Observed.sku.name} else {$null}
    $network=$null
    if ($null -ne $Observed.PSObject.Properties['publicNetworkAccess']) { $network=[string]$Observed.publicNetworkAccess }
    $issues=@()
    if ($adminEnabled -ne $false) { $issues+='AdministratorAccountDisabledNotVerified' }
    if ([string]::IsNullOrWhiteSpace($sku)) { $issues+='SkuNotVerified' }
    if ($null -eq $network) { $issues+='NetworkAccessNotVerified' }
    [pscustomobject]@{
        RegistryName=$RegistryName
        RegistryResourceId=$expectedId
        LoginServer=$loginServer
        Sku=$sku
        AdminUserEnabled=$adminEnabled
        PublicNetworkAccess=$network
        ExistingResourceVerified=$true
        Ownership='RequiresOperatorOwnershipConfirmation'
        ImagePushAuthorized=$false
        HostedAgentPullAuthorized=$false
        PriceAndQuotaVerified=$false
        AzureWrites=0
        CanPublish=$false
        Status=if ($issues.Count) {'BLOCKED_ACR_CONFIGURATION_REVIEW'} else {'BLOCKED_PENDING_RBAC_COST_AND_APPROVAL'}
        Issues=@($issues)
    }
}
function Get-JawsRegistryReadOnlyAssessment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RegistryName,
        [Parameter(Mandatory)][string]$SubscriptionId,
        [Parameter(Mandatory)][string]$ResourceGroupName
    )
    if ($RegistryName -cnotmatch '^[a-zA-Z0-9]{5,50}$') { throw 'JAWS-ACR-001: Invalid registry name.' }
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) { throw 'JAWS-ACR-004: Azure CLI required.' }
    # Allowlisted read command. No ACR login/build/push/provisioning occurs.
    $out=& az acr show --name $RegistryName --subscription $SubscriptionId --resource-group $ResourceGroupName --output json --only-show-errors 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'JAWS-ACR-005: Registry not readable or absent; no create attempted.' }
    try { $observed=($out | Out-String) | ConvertFrom-Json -ErrorAction Stop }
    catch { throw 'JAWS-ACR-006: Invalid ACR read response.' }
    Test-JawsRegistryObservation -RegistryName $RegistryName -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -Observed $observed
}
Export-ModuleMember -Function Test-JawsRegistryObservation,Get-JawsRegistryReadOnlyAssessment
