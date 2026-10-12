# Stage B2 Azure-aware read-only plan extension. No Azure mutation commands.
Set-StrictMode -Version Latest

function Compare-JawsAzurePlanEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$OfflinePlan,
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)][object[]]$DiscoveryResults,
        [Parameter(Mandatory)][string]$TenantId
    )
    if ($OfflinePlan.SubscriptionId -ine $State.SubscriptionId -or
        $OfflinePlan.ResourceGroupName -ine $State.ResourceGroupName -or
        $OfflinePlan.EnvironmentName -ine $State.EnvironmentName) {
        throw 'JAWS-PLAN-010: Blueprint target differs from authoritative state.'
    }
    $expected=@($State.Resources)
    $rows=@()
    $blocked=$false
    foreach ($component in @($OfflinePlan.Components)) {
        $matches=@()
        if ($component.Id -eq 'foundry') {
            $matches=@($expected | Where-Object Type -eq 'Microsoft.CognitiveServices/accounts')
        } elseif ($component.Id -eq 'project') {
            $matches=@($expected | Where-Object Type -eq 'Microsoft.CognitiveServices/accounts/projects')
        } elseif ($component.Id -eq 'model') {
            $matches=@($expected | Where-Object Type -eq 'Microsoft.CognitiveServices/accounts/deployments')
        } elseif ($component.Id -eq 'vault') {
            $matches=@($expected | Where-Object Type -eq 'Microsoft.KeyVault/vaults')
        }
        $action='RequiresDesignAndDiscovery'
        $observed=$null
        $ownership='NotEstablished'
        $status='NotChecked'
        $expectedConfig=$null
        $observedConfig=$null
        $configurationEvidence='NotChecked'
        if ($matches.Count -gt 0) {
            if ($matches.Count -ne 1) { throw 'JAWS-PLAN-011: Ambiguous resource in authoritative state.' }
            $e=$matches[0]
            $d=@($DiscoveryResults | Where-Object { $_.Name -ieq $e.Name -and $_.Type -ieq $e.Type })
            if ($d.Count -ne 1) { throw 'JAWS-PLAN-012: Target resource was not checked exactly once.' }
            $observed=[string]$d[0].ResourceId
            $ownership=[string]$e.Ownership
            # Preserve non-secret expected configuration and only explicitly observed fields.
            $expectedConfig=$e.ExpectedConfiguration
            $observedConfig=[ordered]@{}
            if ($d[0].PSObject.Properties['Location'] -and $d[0].Location) {
                $observedConfig.Location=[string]$d[0].Location
            }
            if ($component.Id -eq 'model' -and $d[0].PSObject.Properties['ObservedConfiguration'] -and $d[0].ObservedConfiguration) {
                $observedConfig.ModelName=[string]$d[0].ObservedConfiguration.ModelName
                $observedConfig.ModelVersion=[string]$d[0].ObservedConfiguration.ModelVersion
                $observedConfig.ProvisioningState=[string]$d[0].ObservedConfiguration.ProvisioningState
            }
            $configurationEvidence='PartialReadOnlyObservation'
            if ($ownership -notin @('External','InstallerCreated')) {
                $action='BlockedUnknownOwnership'; $status='Blocked'; $blocked=$true
            } elseif ($d[0].Status -eq 'Missing') {
                $action='RequiresApprovedProvisioning'; $status='Missing'
            } elseif ($d[0].Status -ne 'Discovered') {
                $action='BlockedUnverifiedResource'; $status='Blocked'; $blocked=$true
            } elseif ([string]$e.ResourceId -and $observed -ine [string]$e.ResourceId) {
                $action='BlockedIdentityDrift'; $status='IdentityDrift'; $blocked=$true
            } elseif ($component.Id -eq 'model' -and
                (($e.ExpectedConfiguration.ModelName -and [string]$d[0].ObservedConfiguration.ModelName -cne [string]$e.ExpectedConfiguration.ModelName) -or
                 ($e.ExpectedConfiguration.ModelVersion -and [string]$d[0].ObservedConfiguration.ModelVersion -cne [string]$e.ExpectedConfiguration.ModelVersion))) {
                $action='BlockedConfigurationDrift'; $status='ConfigurationDrift'; $blocked=$true
            } elseif ($d[0].PSObject.Properties['Location'] -and $d[0].Location -and
                $e.ExpectedConfiguration.PSObject.Properties['Location'] -and
                $e.ExpectedConfiguration.Location -and
                [string]$d[0].Location -ine [string]$e.ExpectedConfiguration.Location) {
                $action='BlockedConfigurationDrift'; $status='ConfigurationDrift'; $blocked=$true
            } else {
                $action='CandidateForReuseRequiresConfigValidation'; $status='Discovered'
            }
        }
        $rows += [pscustomobject]@{
            Id=$component.Id; Name=$component.Name; ResourceType=$component.ResourceType
            DependsOn=@($component.DependsOn); ProposedAction=$action
            AzureState=$status; ObservedResourceId=$observed; Ownership=$ownership
            PermissionState='ReadAccessObservedForDiscoveryOnly'
            ExpectedConfiguration=$expectedConfig
            ObservedConfiguration=$observedConfig
            ConfigurationEvidence=$configurationEvidence
            EstimatedCost=$component.EstimatedCost; ApprovalRequired=$true
        }
    }
    [pscustomobject]@{
        SchemaVersion='0.2'; Platform='JAWS'; PlanKind='AzureAwareReadOnly'
        EnvironmentName=$OfflinePlan.EnvironmentName
        SubscriptionId=$OfflinePlan.SubscriptionId; ResourceGroupName=$OfflinePlan.ResourceGroupName
        TenantId=$TenantId; Location=$OfflinePlan.Location
        CanExecute=$false; AzureWrites=0; AzureDiscoveryPerformed=$true
        CostsVerified=$false; DeploymentPermissionsVerified=$false
        UserAuthorizationVerified=$false
        Status=if ($blocked) {'BLOCKED_RESOURCE_DRIFT_OR_OWNERSHIP'} else {'BLOCKED_PENDING_CONFIG_COST_RBAC_AND_APPROVAL'}
        Disclaimer='Live targeted discovery only. Read access does not prove deployment permissions. No live price, quota, Foundry/Teams/Datadog capability, or complete configuration validation. Not deployable.'
        Components=@($rows)
    }
}

function New-JawsAzureReadOnlyDeploymentPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$OfflinePlan,[Parameter(Mandatory)]$State,[switch]$NonInteractive)
    $context=Get-JawsAuthorizedSubscriptions -NonInteractive:$NonInteractive
    $selected=Select-JawsSubscription -Subscriptions $context.Subscriptions -SubscriptionId $OfflinePlan.SubscriptionId -NonInteractive:$NonInteractive
    $null=Select-JawsResourceGroup -SubscriptionId $OfflinePlan.SubscriptionId -ResourceGroupName $OfflinePlan.ResourceGroupName -NonInteractive:$NonInteractive
    $foundry=@($State.Resources | Where-Object Type -eq 'Microsoft.CognitiveServices/accounts')
    $project=@($State.Resources | Where-Object Type -eq 'Microsoft.CognitiveServices/accounts/projects')
    $model=@($State.Resources | Where-Object Type -eq 'Microsoft.CognitiveServices/accounts/deployments')
    $vault=@($State.Resources | Where-Object Type -eq 'Microsoft.KeyVault/vaults')
    if ($foundry.Count -ne 1 -or $project.Count -ne 1 -or $model.Count -ne 1 -or $vault.Count -ne 1) {
        throw 'JAWS-PLAN-013: Azure-aware plan requires exactly four Stage A target resources in the state.'
    }
    $sub=$OfflinePlan.SubscriptionId; $rg=$OfflinePlan.ResourceGroupName
    $discovery=@()
    $discovery+=Get-JawsAzureResource -SubscriptionId $sub -ResourceGroupName $rg -ResourceName $foundry[0].Name -ResourceType $foundry[0].Type
    $discovery+=Get-JawsFoundryProject -SubscriptionId $sub -ResourceGroupName $rg -FoundryResourceName $foundry[0].Name -ProjectName $project[0].Name
    $discovery+=Get-JawsModelDeployment -SubscriptionId $sub -ResourceGroupName $rg -FoundryResourceName $foundry[0].Name -DeploymentName $model[0].Name
    $discovery+=Get-JawsAzureResource -SubscriptionId $sub -ResourceGroupName $rg -ResourceName $vault[0].Name -ResourceType $vault[0].Type
    Compare-JawsAzurePlanEvidence -OfflinePlan $OfflinePlan -State $State -DiscoveryResults $discovery -TenantId ([string]$selected.tenantId)
}
Export-ModuleMember -Function Compare-JawsAzurePlanEvidence,New-JawsAzureReadOnlyDeploymentPlan
