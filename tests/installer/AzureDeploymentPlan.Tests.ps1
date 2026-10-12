BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../installer/modules/AzureDeploymentPlan.psm1') -Force
    $script:sub='11111111-1111-1111-1111-111111111111'
    $script:offline=[pscustomobject]@{
        EnvironmentName='dev';SubscriptionId=$script:sub;ResourceGroupName='rg-jaws-test';Location='eastus'
        Components=@(
            [pscustomobject]@{Id='foundry';Name='Foundry';ResourceType='Microsoft.CognitiveServices/accounts';DependsOn=@();EstimatedCost='Unknown'},
            [pscustomobject]@{Id='project';Name='Project';ResourceType='Microsoft.CognitiveServices/accounts/projects';DependsOn=@('foundry');EstimatedCost='Unknown'},
            [pscustomobject]@{Id='model';Name='Model';ResourceType='Microsoft.CognitiveServices/accounts/deployments';DependsOn=@('foundry');EstimatedCost='Unknown'},
            [pscustomobject]@{Id='vault';Name='Vault';ResourceType='Microsoft.KeyVault/vaults';DependsOn=@();EstimatedCost='Unknown'},
            [pscustomobject]@{Id='teams';Name='Teams';ResourceType='TeamsIntegration';DependsOn=@('foundry');EstimatedCost='Unknown'}
        )
    }
    $script:types=@('Microsoft.CognitiveServices/accounts','Microsoft.CognitiveServices/accounts/projects','Microsoft.CognitiveServices/accounts/deployments','Microsoft.KeyVault/vaults')
    $script:names=@('jaws-foundry-dev','jaws-dev','gpt-5-mini','kv-jaws-dev-001')
    $script:state=[pscustomobject]@{
        EnvironmentName='dev';SubscriptionId=$script:sub;ResourceGroupName='rg-jaws-test'
        Resources=@(0..3 | ForEach-Object {
            [pscustomobject]@{Name=$script:names[$_];Type=$script:types[$_];Ownership='External';ResourceId=$null
                ExpectedConfiguration=[pscustomobject]@{ModelName='gpt-5-mini';ModelVersion='2025-08-07'}}
        })
    }
    $script:results=@(0..3 | ForEach-Object {
        [pscustomobject]@{Name=$script:names[$_];Type=$script:types[$_];Status='Discovered'
            ResourceId="/subscriptions/$script:sub/resourceGroups/rg-jaws-test/providers/$($script:types[$_])/$($script:names[$_])"
            ObservedConfiguration=[pscustomobject]@{ModelName='gpt-5-mini';ModelVersion='2025-08-07'}}
    })
}
Describe 'B2 Azure-aware plan evidence — fully mocked/offline' {
    It 'returns blocked state after discovery, not deployable permission evidence' {
        $p=Compare-JawsAzurePlanEvidence -OfflinePlan $script:offline -State $script:state -DiscoveryResults $script:results -TenantId 'tenant-1'
        $p.CanExecute | Should -BeFalse
        $p.AzureWrites | Should -Be 0
        $p.AzureDiscoveryPerformed | Should -BeTrue
        $p.DeploymentPermissionsVerified | Should -BeFalse
        $p.CostsVerified | Should -BeFalse
        $p.Status | Should -Be 'BLOCKED_PENDING_CONFIG_COST_RBAC_AND_APPROVAL'
        @($p.Components | Where-Object ProposedAction -eq 'CandidateForReuseRequiresConfigValidation').Count | Should -Be 4
        @($p.Components | Where-Object ProposedAction -eq 'RequiresDesignAndDiscovery').Count | Should -Be 1
    }
    It 'blocks mismatched subscription before Azure discovery' {
        $other=$script:offline.PSObject.Copy()
        $other.SubscriptionId='22222222-2222-2222-2222-222222222222'
        { Compare-JawsAzurePlanEvidence -OfflinePlan $other -State $script:state -DiscoveryResults $script:results -TenantId 'tenant-1' } | Should -Throw '*JAWS-PLAN-010*'
    }
    It 'fails if targeted discovery omitted a resource' {
        { Compare-JawsAzurePlanEvidence -OfflinePlan $script:offline -State $script:state -DiscoveryResults @($script:results | Select-Object -SkipLast 1) -TenantId 'tenant-1' } | Should -Throw '*JAWS-PLAN-012*'
    }
    It 'blocks model version drift' {
        $observed=@($script:results | ForEach-Object { $_.PSObject.Copy() })
        $observed[2].ObservedConfiguration=[pscustomobject]@{ModelName='gpt-5-mini';ModelVersion='other'}
        $p=Compare-JawsAzurePlanEvidence -OfflinePlan $script:offline -State $script:state -DiscoveryResults $observed -TenantId 'tenant-1'
        $p.Status | Should -Be 'BLOCKED_RESOURCE_DRIFT_OR_OWNERSHIP'
        @($p.Components | Where-Object ProposedAction -eq 'BlockedConfigurationDrift').Count | Should -Be 1
    }
    It 'blocks discovered identity drift' {
        $stateCopy=$script:state.PSObject.Copy()
        $stateCopy.Resources=@($script:state.Resources | ForEach-Object { $_.PSObject.Copy() })
        $stateCopy.Resources[0].ResourceId='/subscriptions/other/resourceGroups/other/providers/Microsoft.CognitiveServices/accounts/untrusted'
        $p=Compare-JawsAzurePlanEvidence -OfflinePlan $script:offline -State $stateCopy -DiscoveryResults $script:results -TenantId 'tenant-1'
        $p.Status | Should -Be 'BLOCKED_RESOURCE_DRIFT_OR_OWNERSHIP'
    }
    It 'blocks unknown ownership even for a discovered resource' {
        $stateCopy=$script:state.PSObject.Copy()
        $stateCopy.Resources=@($script:state.Resources | ForEach-Object { $_.PSObject.Copy() })
        $stateCopy.Resources[0].Ownership='Unknown'
        $p=Compare-JawsAzurePlanEvidence -OfflinePlan $script:offline -State $stateCopy -DiscoveryResults $script:results -TenantId 'tenant-1'
        @($p.Components | Where-Object ProposedAction -eq 'BlockedUnknownOwnership').Count | Should -Be 1
    }
    It 'does not expose Install or run Azure writes in the plan modules' {
        $entry=Get-Content (Join-Path $PSScriptRoot '../../installer/Install-Jaws.ps1') -Raw
        $entry | Should -Match '\[switch\]\$AzureAware'
        $entry | Should -Not -Match "ValidateSet\('Discover','Plan','Install'\)"
        $body=Get-Content (Join-Path $PSScriptRoot '../../installer/modules/AzureDeploymentPlan.psm1') -Raw
        $body | Should -Not -Match '(?m)^\s*(&\s*az|az\s+(?:deployment|group\s+create|resource\s+create|role\s+assignment\s+create))\b'
    }
}
