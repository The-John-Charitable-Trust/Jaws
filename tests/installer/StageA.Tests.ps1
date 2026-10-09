# Pester 5 tests. Execute only through Codex testing workflow.
BeforeAll {
    $root=Join-Path $PSScriptRoot '../../installer/modules'
    Import-Module (Join-Path $root 'ResourceDiscovery.psm1') -Force
    Import-Module (Join-Path $root 'ResourceManifest.psm1') -Force
    $sub='00000000-0000-0000-0000-000000000001'
    $rg='rg-test'
    $id="/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.KeyVault/vaults/kv-test"
}
Describe 'JAWS Stage A discovery and manifest' {
    It 'returns Missing for an empty authorized result' {
        $r=Resolve-JawsDiscoveryMatch -Items @() -Name 'kv-test' -Type 'Microsoft.KeyVault/vaults'
        $r.Status | Should -Be 'Missing'
    }
    It 'rejects a discovered resource without a valid ID' {
        { Resolve-JawsDiscoveryMatch -Items @([pscustomobject]@{
            name='kv-test';type='Microsoft.KeyVault/vaults';id='wrong'
        }) -Name 'kv-test' -Type 'Microsoft.KeyVault/vaults' } | Should -Throw
    }
    It 'rejects resource ID from another subscription' {
        { Resolve-JawsDiscoveryMatch -Items @([pscustomobject]@{
            name='kv-test';type='Microsoft.KeyVault/vaults';id=$id
        }) -Name 'kv-test' -Type 'Microsoft.KeyVault/vaults' `
          -ExpectedSubscriptionId '00000000-0000-0000-0000-000000000999' } | Should -Throw
    }
    It 'preserves ownership only for the same Azure resource ID' {
        $m=New-JawsResourceManifest -SubscriptionId $sub -ResourceGroupName $rg -EnvironmentName 't'
        $d=[pscustomobject]@{Name='kv-test';Type='Microsoft.KeyVault/vaults'
            ResourceId=$id;Status='Discovered';Location='eastus'}
        $m=Add-JawsManifestResource -Manifest $m -DiscoveryResult $d
        $m.Resources[0].CreatedByInstaller=$true
        $m.Resources[0].Ownership='Installer'
        $m=Add-JawsManifestResource -Manifest $m -DiscoveryResult $d
        $m.Resources[0].CreatedByInstaller | Should -BeTrue
        $m.Resources.Count | Should -Be 1
        $d.ResourceId="$id-new"
        $m=Add-JawsManifestResource -Manifest $m -DiscoveryResult $d
        $m.Resources[0].CreatedByInstaller | Should -BeFalse
        $m.Resources[0].RecommendedAction | Should -Be 'ReviewResourceIdentityChange'
    }
    It 'reports model version drift' {
        $m=New-JawsResourceManifest -SubscriptionId $sub -ResourceGroupName $rg -EnvironmentName 't'
        $d=[pscustomobject]@{Name='mini';Type='Microsoft.CognitiveServices/accounts/deployments'
            ResourceId="/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.CognitiveServices/accounts/f/deployments/mini"
            Status='Discovered';Location='eastus'
            ObservedConfiguration=[pscustomobject]@{ModelName='gpt-5-mini';ModelVersion='wrong';ProvisioningState='Succeeded'}}
        $expected=[pscustomobject]@{ModelName='gpt-5-mini';ModelVersion='2025-08-07'}
        $m=Add-JawsManifestResource -Manifest $m -DiscoveryResult $d -ExpectedConfiguration $expected
        $m.Resources[0].ValidationResult | Should -Be 'Drift'
    }
    It 'rejects loading a manifest from another environment' {
        $temp=Join-Path $TestDrive 'test.generated.json'
        $m=New-JawsResourceManifest -SubscriptionId $sub -ResourceGroupName $rg -EnvironmentName 'one'
        Save-JawsResourceManifest -Manifest $m -Path $temp | Out-Null
        { New-JawsResourceManifest -SubscriptionId $sub -ResourceGroupName $rg -EnvironmentName 'two' -ExistingPath $temp } | Should -Throw
    }
    It 'preserves the manifest after a repeated save' {
        $temp=Join-Path $TestDrive 'repeat.generated.json'
        $m=New-JawsResourceManifest -SubscriptionId $sub -ResourceGroupName $rg -EnvironmentName 'repeat'
        Save-JawsResourceManifest -Manifest $m -Path $temp | Out-Null
        $m2=New-JawsResourceManifest -SubscriptionId $sub -ResourceGroupName $rg -EnvironmentName 'repeat' -ExistingPath $temp
        Save-JawsResourceManifest -Manifest $m2 -Path $temp | Out-Null
        (Get-Content $temp -Raw | ConvertFrom-Json).EnvironmentName | Should -Be 'repeat'
    }
}
