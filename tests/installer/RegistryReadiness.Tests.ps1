BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../installer/modules/RegistryReadiness.psm1') -Force
    $script:name='jawsregtest001'
    $script:sub='11111111-1111-1111-1111-111111111111'
    $script:rg='rg-jaws-test'
    $script:id="/subscriptions/$script:sub/resourceGroups/$script:rg/providers/Microsoft.ContainerRegistry/registries/$script:name"
    $script:good=[pscustomobject]@{
        id=$script:id;name=$script:name;loginServer="$script:name.azurecr.io"
        sku=[pscustomobject]@{name='Basic'};adminUserEnabled=$false;publicNetworkAccess='Enabled'
    }
}
Describe 'B2 ACR readiness read-only assessment' {
    It 'recognizes scoped registry but refuses to authorize publication' {
        $p=Test-JawsRegistryObservation -RegistryName $script:name -SubscriptionId $script:sub -ResourceGroupName $script:rg -Observed $script:good
        $p.ExistingResourceVerified | Should -BeTrue
        $p.AzureWrites | Should -Be 0
        $p.CanPublish | Should -BeFalse
        $p.ImagePushAuthorized | Should -BeFalse
        $p.HostedAgentPullAuthorized | Should -BeFalse
        $p.Status | Should -Be 'BLOCKED_PENDING_RBAC_COST_AND_APPROVAL'
    }
    It 'rejects wrong subscription or registry scope' {
        { Test-JawsRegistryObservation -RegistryName $script:name -SubscriptionId '22222222-2222-2222-2222-222222222222' -ResourceGroupName $script:rg -Observed $script:good } | Should -Throw '*JAWS-ACR-002*'
    }
    It 'rejects registry login-server mismatch' {
        $bad=$script:good.PSObject.Copy()
        $bad.loginServer='attacker.azurecr.io'
        { Test-JawsRegistryObservation -RegistryName $script:name -SubscriptionId $script:sub -ResourceGroupName $script:rg -Observed $bad } | Should -Throw '*JAWS-ACR-003*'
    }
    It 'flags enabled registry admin credentials' {
        $bad=$script:good.PSObject.Copy()
        $bad.adminUserEnabled=$true
        $p=Test-JawsRegistryObservation -RegistryName $script:name -SubscriptionId $script:sub -ResourceGroupName $script:rg -Observed $bad
        $p.Status | Should -Be 'BLOCKED_ACR_CONFIGURATION_REVIEW'
    }
    It 'flags unknown required registry properties' {
        $bad=[pscustomobject]@{id=$script:id;name=$script:name;loginServer="$script:name.azurecr.io"}
        $p=Test-JawsRegistryObservation -RegistryName $script:name -SubscriptionId $script:sub -ResourceGroupName $script:rg -Observed $bad
        $p.Status | Should -Be 'BLOCKED_ACR_CONFIGURATION_REVIEW'
        $p.CanPublish | Should -BeFalse
    }
    It 'does not include mutating Azure Container Registry commands' {
        $src=Get-Content (Join-Path $PSScriptRoot '../../installer/modules/RegistryReadiness.psm1') -Raw
        $src | Should -Match '& az acr show'
        $src | Should -Not -Match '& az acr (create|update|build|login|import|delete)'
        $src | Should -Not -Match '& docker push'
    }
}
