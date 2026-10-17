# JAWS Step A - read-only discovery report.
# Resource Graph rows are evidence. They are never adopted into installation state.
Set-StrictMode -Version Latest

function Test-JawsStepANameMatch {
    [CmdletBinding()]
    param([string]$Observed,[Parameter(Mandatory)][string]$Expected)
    return ([string]$Observed -ieq $Expected -or [string]$Observed -like "*/$Expected")
}

function Get-JawsStepAPlatform {
    [CmdletBinding()]
    param([string]$Name,[string]$ResourceGroup)
    if ($Name -match '(?i)tight.?fang|tfang' -or $ResourceGroup -match '(?i)tight.?fang|tfang') { return 'LegacyTightFang' }
    if ($Name -match '(?i)jaws' -or $ResourceGroup -match '(?i)jaws') { return 'JAWS' }
    return 'Unclassified'
}

function Get-JawsStepAProperty {
    [CmdletBinding()]
    param([AllowNull()]$InputObject,[Parameter(Mandatory)][string]$PropertyName)
    if ($null -eq $InputObject) { return $null }
    $property=$InputObject.PSObject.Properties[$PropertyName]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-JawsStepARowSubscriptionId {
    [CmdletBinding()]
    param($Row)
    $explicit=[string](Get-JawsStepAProperty -InputObject $Row -PropertyName 'subscriptionId')
    if ($explicit) { return $explicit }
    $id=[string](Get-JawsStepAProperty -InputObject $Row -PropertyName 'id')
    if ($id -match '^/subscriptions/([^/]+)/') { return $Matches[1] }
    return ''
}

function New-JawsStepADiscoveryReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Subscription,
        [Parameter(Mandatory)][string]$AccountTenantId,
        [Parameter(Mandatory)][string]$EnvironmentName,
        [string]$ResourceGroupName,
        [AllowNull()][object[]]$GraphRows,
        $State,
        [string]$StateFile,
        [AllowNull()][object[]]$TargetComparison
    )
    $subscriptionId=[string](Get-JawsStepAProperty -InputObject $Subscription -PropertyName 'id')
    $subscriptionTenant=[string](Get-JawsStepAProperty -InputObject $Subscription -PropertyName 'tenantId')
    if (-not $AccountTenantId -or -not $subscriptionTenant -or $subscriptionTenant -ine $AccountTenantId) {
        throw 'JAWS-AUTH-009: Selected subscription is not in the signed-in Entra tenant.'
    }
    if ($State) {
        if ([string]$State.SubscriptionId -ine $subscriptionId) { throw 'JAWS-STATE-002: Subscription differs from the authoritative state.' }
        if ($ResourceGroupName -and [string]$State.ResourceGroupName -ine $ResourceGroupName) { throw 'JAWS-STATE-002: Resource group differs from the authoritative state.' }
        if ($null -eq $TargetComparison) { throw 'JAWS-STATE-006: State reconciliation requires targeted discovery results.' }
        $ResourceGroupName=[string]$State.ResourceGroupName
    }

    $inSubscription=@()
    $excluded=0
    foreach ($row in @($GraphRows)) {
        if ($null -eq $row) { continue }
        $rowSubscription=Get-JawsStepARowSubscriptionId -Row $row
        if ($rowSubscription -ine $subscriptionId) { $excluded++; continue }
        $inSubscription += $row
    }

    $comparison=@()
    if ($State) {
        foreach ($item in @($TargetComparison)) {
            $expected=@($State.Resources | Where-Object { $_.Name -ieq $item.Name -and $_.Type -ieq $item.Type })
            $status=[string]$item.Status
            $observed=[string]$item.ObservedResourceId
            if ($expected.Count -eq 1) {
                $graphMatches=@($inSubscription | Where-Object {
                    (Test-JawsStepANameMatch -Observed ([string](Get-JawsStepAProperty -InputObject $_ -PropertyName 'name')) -Expected ([string]$expected[0].Name)) -and
                    ([string](Get-JawsStepAProperty -InputObject $_ -PropertyName 'type') -ieq [string]$expected[0].Type)
                })
                $graphId=[string](Get-JawsStepAProperty -InputObject $(if ($graphMatches.Count -eq 1) { $graphMatches[0] } else { $null }) -PropertyName 'id')
                if ($graphMatches.Count -gt 1) { $status='IdentityDrift' }
                elseif ($graphMatches.Count -eq 1 -and $observed -and $graphId -and ($graphId -ine $observed)) {
                    $status='IdentityDrift'
                }
            }
            $comparison += [pscustomobject]@{
                Name=$item.Name; Type=$item.Type; Status=$status
                ExpectedResourceId=$item.ExpectedResourceId; ObservedResourceId=$item.ObservedResourceId
            }
        }
    }

    $inventory=@()
    foreach ($row in $inSubscription) {
        $name=[string](Get-JawsStepAProperty -InputObject $row -PropertyName 'name')
        $type=[string](Get-JawsStepAProperty -InputObject $row -PropertyName 'type')
        $group=[string](Get-JawsStepAProperty -InputObject $row -PropertyName 'resourceGroup')
        $named=$false
        if ($State) {
            $named = @($State.Resources | Where-Object {
                (Test-JawsStepANameMatch -Observed $name -Expected ([string]$_.Name)) -and ($type -ieq [string]$_.Type)
            }).Count -gt 0
        }
        $scope='InScope'
        if ($ResourceGroupName -and $group -ine $ResourceGroupName) { $scope='OutsideResourceGroup' }
        $inventory += [pscustomobject]@{
            Name=$name
            Type=$type
            ResourceId=[string](Get-JawsStepAProperty -InputObject $row -PropertyName 'id')
            ResourceGroup=$group
            Location=[string](Get-JawsStepAProperty -InputObject $row -PropertyName 'location')
            Scope=$scope
            Adoption='Unclaimed'
            NamedInState=$named
            Platform=(Get-JawsStepAPlatform -Name $name -ResourceGroup $group)
        }
    }

    $outcome='NoInstallationState'
    if ($State) {
        $drift=@($comparison | Where-Object Status -ne 'Match')
        $outcome = if ($drift.Count -eq 0 -and $comparison.Count -gt 0) { 'Reconciled' } else { 'Drift' }
    }

    [pscustomobject]@{
        SchemaVersion='1.1'
        Mode='Discover'
        Outcome=$outcome
        EnvironmentName=$EnvironmentName
        SubscriptionId=$subscriptionId
        SubscriptionName=[string](Get-JawsStepAProperty -InputObject $Subscription -PropertyName 'name')
        TenantId=$subscriptionTenant
        ResourceGroupName=$(if ($ResourceGroupName) { $ResourceGroupName } else { $null })
        StateFile=$(if ($StateFile) { $StateFile } else { $null })
        AzureWrites=0
        InstallationStateCreated=$false
        StateFileRewritten=$false
        ExcludedOutsideSubscription=$excluded
        Inventory=@($inventory)
        TargetDiscovery=@($comparison)
        Acceptance=[pscustomobject]@{
            ReadOnlyDiscovery=$true
            InventoryCompared=[bool]$State
            CloudChanges=0
        }
        Disclaimer='Azure Resource Graph rows are read-only evidence for the selected subscription. Unclaimed rows are not adopted. A missing row does not prove a resource is absent. Discover does not create or rewrite installation state.'
        CompletedAtUtc=(Get-Date).ToUniversalTime().ToString('o')
    }
}

Export-ModuleMember -Function New-JawsStepADiscoveryReport
