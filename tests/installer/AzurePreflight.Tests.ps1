BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../installer/modules/AzurePreflight.psm1') -Force
}
Describe 'JAWS Stage A tenant inventory and permissions' {
    InModuleScope AzurePreflight {
        BeforeEach {
            $script:testSubA=[pscustomobject]@{id='sub-a';name='Alpha';tenantId='tenant-a';state='Enabled'}
            $script:testSubB=[pscustomobject]@{id='sub-b';name='Beta';tenantId='tenant-a';state='Enabled'}
            $script:testSubC=[pscustomobject]@{id='sub-c';name='OtherTenant';tenantId='tenant-b';state='Enabled'}
        }
        It 'scans every visible enabled subscription of the selected tenant only' {
            Mock Invoke-JawsPreflightRead {
                if ($Arguments -contains 'sub-a') { return @([pscustomobject]@{name='jaws-foundry';resourceGroup='rg-jaws';type='Microsoft.CognitiveServices/accounts';id='/subscriptions/sub-a/resourceGroups/rg-jaws/providers/Microsoft.CognitiveServices/accounts/jaws-foundry';tags=$null}) }
                return @()
            }
            $scan=Get-JawsTenantInstallationScan -Subscriptions @($script:testSubA,$script:testSubB,$script:testSubC) -TenantId 'tenant-a'
            $scan.SubscriptionCount | Should -Be 2
            $scan.Completed | Should -BeTrue
            $scan.Candidates.Count | Should -Be 1
            Should -Invoke Invoke-JawsPreflightRead -Times 2 -Exactly
        }
        It 'does not claim a complete scan when a subscription fails' {
            Mock Invoke-JawsPreflightRead { throw 'denied' }
            $scan=Get-JawsTenantInstallationScan -Subscriptions @($script:testSubA,$script:testSubB) -TenantId 'tenant-a'
            $scan.Completed | Should -BeFalse
            @($scan.Subscriptions | Where-Object Status -eq 'Failed').Count | Should -Be 2
        }
        It 'fails on an unauthorized selected subscription' {
            { Select-JawsSubscription -Subscriptions @($script:testSubA) -SubscriptionId 'unlisted' -NonInteractive } | Should -Throw
        }
        It 'fails rather than masking resource group authorization errors' {
            Mock Invoke-JawsPreflightRead { throw 'forbidden' }
            { Select-JawsResourceGroup -SubscriptionId 'sub-a' -ResourceGroupName 'rg-jaws' -NonInteractive } | Should -Throw
        }
    }
}

# Tenant scan regression tests for missing optional resource metadata.
Describe 'JAWS tenant scan regressions' {
    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot '../../installer/modules/AzurePreflight.psm1') -Force
    }
    It 'handles missing tags without duplicate scan records' {
        Mock -ModuleName AzurePreflight Invoke-JawsPreflightRead {
            @([pscustomobject]@{name='example-jaws';resourceGroup='rg-x';type='Microsoft.KeyVault/vaults';id='/id'})
        }
        $subs=@([pscustomobject]@{id='sub-1';tenantId='tenant-1';state='Enabled'})
        $result=Get-JawsTenantInstallationScan -Subscriptions $subs -TenantId 'tenant-1'
        $result.Completed | Should -BeTrue
        @($result.Subscriptions).Count | Should -Be 1
        @($result.Candidates).Count | Should -Be 1
    }
    It 'handles non-empty Azure tag objects under StrictMode' {
        Mock -ModuleName AzurePreflight Invoke-JawsPreflightRead {
            @([pscustomobject]@{
                name='unrelated-resource'
                resourceGroup='rg-x'
                type='Microsoft.KeyVault/vaults'
                id='/id'
                tags=[pscustomobject]@{application='JAWS';environment='dev'}
            })
        }
        $subs=@([pscustomobject]@{id='sub-1';tenantId='tenant-1';state='Enabled'})
        $result=Get-JawsTenantInstallationScan -Subscriptions $subs -TenantId 'tenant-1'
        $result.Completed | Should -BeTrue
        @($result.Subscriptions).Count | Should -Be 1
        @($result.Candidates).Count | Should -Be 1
        $result.Candidates[0].Reason | Should -Be 'MatchingTags'
    }
    It 'records one failure if resource listing throws' {
        Mock -ModuleName AzurePreflight Invoke-JawsPreflightRead { throw 'access denied' }
        $subs=@([pscustomobject]@{id='sub-1';tenantId='tenant-1';state='Enabled'})
        $result=Get-JawsTenantInstallationScan -Subscriptions $subs -TenantId 'tenant-1'
        $result.Completed | Should -BeFalse
        @($result.Subscriptions).Count | Should -Be 1
        $result.Subscriptions[0].Status | Should -Be 'Failed'
    }
}
