Import-Module (Join-Path $PSScriptRoot '../../installer/modules/StepADiscovery.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '../../installer/modules/AzurePreflight.psm1') -Force
BeforeAll {
    $script:sub = '00000000-0000-0000-0000-000000000001'
    $script:other = '00000000-0000-0000-0000-000000000002'
    $script:subscription = [pscustomobject]@{ id = $script:sub; name = 'Customer'; tenantId = 'tenant-1' }
    $script:accountTenant = 'tenant-1'
    $script:foundryId = "/subscriptions/$($script:sub)/resourceGroups/rg-jaws/providers/Microsoft.CognitiveServices/accounts/jaws-foundry"
}

Describe 'JAWS Step A read-only discovery' {
    It 'succeeds with an empty subscription and writes nothing' {
        $report = New-JawsStepADiscoveryReport -Subscription $script:subscription -AccountTenantId $script:accountTenant `
            -EnvironmentName 'selected' -GraphRows @() -State $null
        $report.Outcome | Should -Be 'NoInstallationState'
        $report.AzureWrites | Should -Be 0
        $report.InstallationStateCreated | Should -BeFalse
        $report.StateFileRewritten | Should -BeFalse
        $report.Acceptance.ReadOnlyDiscovery | Should -BeTrue
        $report.Acceptance.CloudChanges | Should -Be 0
        @($report.Inventory).Count | Should -Be 0
    }

    It 'leaves every Resource Graph row unclaimed' {
        $rows = @(
            [pscustomobject]@{ name = 'jaws-foundry'; type = 'Microsoft.CognitiveServices/accounts'; id = $script:foundryId; resourceGroup = 'rg-jaws'; location = 'eastus'; subscriptionId = $script:sub }
            [pscustomobject]@{ name = 'tfang-vault'; type = 'Microsoft.KeyVault/vaults'; id = "/subscriptions/$($script:sub)/resourceGroups/rg-old/providers/Microsoft.KeyVault/vaults/tfang-vault"; resourceGroup = 'rg-old'; subscriptionId = $script:sub }
        )
        $report = New-JawsStepADiscoveryReport -Subscription $script:subscription -AccountTenantId $script:accountTenant `
            -EnvironmentName 'selected' -GraphRows $rows -State $null
        @($report.Inventory | Where-Object Adoption -ne 'Unclaimed').Count | Should -Be 0
        @($report.Inventory | Where-Object Platform -eq 'LegacyTightFang').Count | Should -Be 1
        $report.Outcome | Should -Be 'NoInstallationState'
    }

    It 'does not treat a JAWS name as adoption' {
        $rows = @([pscustomobject]@{ name = 'jaws-foundry'; type = 'Microsoft.CognitiveServices/accounts'; id = $script:foundryId; resourceGroup = 'rg-jaws'; subscriptionId = $script:sub })
        $report = New-JawsStepADiscoveryReport -Subscription $script:subscription -AccountTenantId $script:accountTenant `
            -EnvironmentName 'selected' -GraphRows $rows -State $null
        $report.Inventory[0].Platform | Should -Be 'JAWS'
        $report.Inventory[0].Adoption | Should -Be 'Unclaimed'
        $report.Inventory[0].NamedInState | Should -BeFalse
    }

    It 'drops rows from another subscription' {
        $rows = @([pscustomobject]@{ name = 'foreign'; type = 'Microsoft.KeyVault/vaults'; id = "/subscriptions/$($script:other)/resourceGroups/rg/providers/Microsoft.KeyVault/vaults/foreign"; resourceGroup = 'rg'; subscriptionId = $script:other })
        $report = New-JawsStepADiscoveryReport -Subscription $script:subscription -AccountTenantId $script:accountTenant `
            -EnvironmentName 'selected' -GraphRows $rows -State $null
        @($report.Inventory).Count | Should -Be 0
        $report.ExcludedOutsideSubscription | Should -Be 1
    }

    It 'marks rows outside the selected resource group without adopting them' {
        $rows = @(
            [pscustomobject]@{ name = 'in-group'; type = 'Microsoft.KeyVault/vaults'; id = "/subscriptions/$($script:sub)/resourceGroups/rg-a/providers/Microsoft.KeyVault/vaults/in-group"; resourceGroup = 'rg-a'; subscriptionId = $script:sub }
            [pscustomobject]@{ name = 'other-group'; type = 'Microsoft.KeyVault/vaults'; id = "/subscriptions/$($script:sub)/resourceGroups/rg-b/providers/Microsoft.KeyVault/vaults/other-group"; resourceGroup = 'rg-b'; subscriptionId = $script:sub }
        )
        $report = New-JawsStepADiscoveryReport -Subscription $script:subscription -AccountTenantId $script:accountTenant `
            -EnvironmentName 'selected' -ResourceGroupName 'rg-a' -GraphRows $rows -State $null
        @($report.Inventory | Where-Object Scope -eq 'InScope').Name | Should -Be 'in-group'
        @($report.Inventory | Where-Object Scope -eq 'OutsideResourceGroup').Adoption | Should -Be 'Unclaimed'
    }

    It 'rejects a subscription in another Entra tenant' {
        $foreign = [pscustomobject]@{ id = $script:sub; name = 'Other'; tenantId = 'tenant-2' }
        { New-JawsStepADiscoveryReport -Subscription $foreign -AccountTenantId 'tenant-1' -EnvironmentName 'selected' -GraphRows @() -State $null } |
            Should -Throw '*JAWS-AUTH-009*'
    }

    It 'reconciles a supplied state file when the targeted inventory matches' {
        $state = [pscustomobject]@{
            SubscriptionId = $script:sub
            ResourceGroupName = 'rg-jaws'
            Resources = @([pscustomobject]@{ Name = 'jaws-foundry'; Type = 'Microsoft.CognitiveServices/accounts'; ResourceId = $null })
        }
        $comparison = @([pscustomobject]@{ Name = 'jaws-foundry'; Type = 'Microsoft.CognitiveServices/accounts'; Status = 'Match'; ExpectedResourceId = $null; ObservedResourceId = $script:foundryId })
        $rows = @([pscustomobject]@{ name = 'jaws-foundry'; type = 'Microsoft.CognitiveServices/accounts'; id = $script:foundryId; resourceGroup = 'rg-jaws'; subscriptionId = $script:sub })
        $report = New-JawsStepADiscoveryReport -Subscription $script:subscription -AccountTenantId $script:accountTenant `
            -EnvironmentName 'dev' -ResourceGroupName 'rg-jaws' -GraphRows $rows -State $state -StateFile 'state.json' -TargetComparison $comparison
        $report.Outcome | Should -Be 'Reconciled'
        $report.Acceptance.InventoryCompared | Should -BeTrue
        $report.StateFileRewritten | Should -BeFalse
        $report.AzureWrites | Should -Be 0
        $report.Inventory[0].NamedInState | Should -BeTrue
        $report.Inventory[0].Adoption | Should -Be 'Unclaimed'
    }

    It 'flags identity drift when Resource Graph and the targeted read disagree' {
        $state = [pscustomobject]@{
            SubscriptionId = $script:sub
            ResourceGroupName = 'rg-jaws'
            Resources = @([pscustomobject]@{ Name = 'jaws-foundry'; Type = 'Microsoft.CognitiveServices/accounts' })
        }
        $comparison = @([pscustomobject]@{ Name = 'jaws-foundry'; Type = 'Microsoft.CognitiveServices/accounts'; Status = 'Match'; ExpectedResourceId = $null; ObservedResourceId = $script:foundryId })
        $otherId = "/subscriptions/$($script:sub)/resourceGroups/rg-jaws/providers/Microsoft.CognitiveServices/accounts/jaws-foundry-other"
        $rows = @([pscustomobject]@{ name = 'jaws-foundry'; type = 'Microsoft.CognitiveServices/accounts'; id = $otherId; resourceGroup = 'rg-jaws'; subscriptionId = $script:sub })
        $report = New-JawsStepADiscoveryReport -Subscription $script:subscription -AccountTenantId $script:accountTenant `
            -EnvironmentName 'dev' -GraphRows $rows -State $state -TargetComparison $comparison
        $report.Outcome | Should -Be 'Drift'
        $report.TargetDiscovery[0].Status | Should -Be 'IdentityDrift'
    }

    It 'keeps a targeted match when Resource Graph omits the resource' {
        $state = [pscustomobject]@{
            SubscriptionId = $script:sub
            ResourceGroupName = 'rg-jaws'
            Resources = @([pscustomobject]@{ Name = 'gpt-5-mini'; Type = 'Microsoft.CognitiveServices/accounts/deployments' })
        }
        $observed = "/subscriptions/$($script:sub)/resourceGroups/rg-jaws/providers/Microsoft.CognitiveServices/accounts/jaws-foundry/deployments/gpt-5-mini"
        $comparison = @([pscustomobject]@{ Name = 'gpt-5-mini'; Type = 'Microsoft.CognitiveServices/accounts/deployments'; Status = 'Match'; ExpectedResourceId = $null; ObservedResourceId = $observed })
        $report = New-JawsStepADiscoveryReport -Subscription $script:subscription -AccountTenantId $script:accountTenant `
            -EnvironmentName 'dev' -GraphRows @() -State $state -TargetComparison $comparison
        $report.Outcome | Should -Be 'Reconciled'
        $report.TargetDiscovery[0].Status | Should -Be 'Match'
    }

    It 'does not load the development state unless the entry script is given -StateFile' {
        $entry = Get-Content (Join-Path $PSScriptRoot '../../installer/Install-Jaws.ps1') -Raw
        $entry | Should -Match 'No installation state is loaded unless -StateFile is supplied'
        $entry | Should -Not -Match 'c52f597b-7753-45b4-a764-67e290dcfd5e'
        $discover = $entry.Substring($entry.IndexOf('No installation state is loaded unless -StateFile is supplied'))
        $discover | Should -Not -Match 'jaws-installation-state'
        $entry | Should -Match 'Get-JawsResourceGraphInventory'
        $entry | Should -Match "ValidateSet\('Discover','Plan','Package'\)"
        @($entry.ToCharArray() | Where-Object { [int][char]$_ -gt 127 }).Count | Should -Be 0
    }
}

Describe 'JAWS Resource Graph inventory' {
    InModuleScope AzurePreflight {
        It 'allows a Resource Graph read and rejects resource creation' {
            Test-JawsPreflightArguments -Arguments @('graph','query','--graph-query','Resources','--subscriptions','00000000-0000-0000-0000-000000000001') | Should -BeTrue
            Test-JawsPreflightArguments -Arguments @('group','create','--name','rg') | Should -BeFalse
            Test-JawsPreflightArguments -Arguments @('resource','create') | Should -BeFalse
        }
        It 'pages Resource Graph results until the skip token is empty' {
            $script:pages = 0
            Mock Invoke-JawsPreflightRead {
                $script:pages++
                if ($script:pages -eq 1) {
                    return [pscustomobject]@{
                        data = @([pscustomobject]@{ name = 'one'; type = 'microsoft.keyvault/vaults'; id = '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg/providers/Microsoft.KeyVault/vaults/one'; subscriptionId = '00000000-0000-0000-0000-000000000001' })
                        skip_token = 'page-2'
                    }
                }
                return [pscustomobject]@{
                    data = @([pscustomobject]@{ name = 'two'; type = 'microsoft.cognitiveservices/accounts'; id = '/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg/providers/Microsoft.CognitiveServices/accounts/two'; subscriptionId = '00000000-0000-0000-0000-000000000001' })
                    skip_token = $null
                }
            }
            $rows = @(Get-JawsResourceGraphInventory -SubscriptionId '00000000-0000-0000-0000-000000000001')
            $rows.Count | Should -Be 2
            $script:pages | Should -Be 2
        }
        It 'names the missing Reader action when Resource Graph denies the query' {
            Mock Invoke-JawsPreflightRead { throw 'JAWS-AUTH-003: denied' }
            { Get-JawsResourceGraphInventory -SubscriptionId '00000000-0000-0000-0000-000000000001' } | Should -Throw '*JAWS-AUTH-010*'
            { Get-JawsResourceGraphInventory -SubscriptionId '00000000-0000-0000-0000-000000000001' } | Should -Throw '*Microsoft.ResourceGraph/resources/read*'
        }
        It 'rejects a subscription id that is not a GUID' {
            { Get-JawsResourceGraphInventory -SubscriptionId 'not-a-guid' } | Should -Throw '*JAWS-SCAN-004*'
        }
    }
}
