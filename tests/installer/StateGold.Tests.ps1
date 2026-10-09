BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../installer/modules/InstallationState.psm1') -Force
    $script:gold=Read-JawsInstallationState -Path (Join-Path $PSScriptRoot '../../installer/config/jaws-installation-state.dev.json')
}
Describe 'State-first JAWS reconciliation' {
    It 'prepopulates exactly four JAWS targets and no legacy entries' {
        @($gold.Resources).Count | Should -Be 4
        @($gold.Resources | Where-Object Name -Match '(?i)tight.?fang|tfang').Count | Should -Be 0
    }
    It 'rejects a malformed subscription ID in installation state' {
        $path=Join-Path $TestDrive 'invalid-subscription.json'
        $invalid=$gold.PSObject.Copy()
        $invalid.SubscriptionId='not-a-subscription-guid'
        $invalid | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding utf8
        { Read-JawsInstallationState -Path $path } | Should -Throw '*invalid Azure subscription ID*'
    }
    It 'uses the state target to compare tenant candidates' {
        $scan=[pscustomobject]@{Candidates=@([pscustomobject]@{
            Name='jaws-foundry-dev';Type='Microsoft.CognitiveServices/accounts';Platform='JAWS'
            SubscriptionId=$gold.SubscriptionId;ResourceGroup=$gold.ResourceGroupName;ResourceId='/test'
        })}
        $result=Compare-JawsTenantScanToState -State $gold -Scan $scan
        @($result).Count | Should -Be 4
        @($result | Where-Object Status -eq 'CandidateLocated').Count | Should -Be 1
    }
    It 'flags model version drift in targeted discovery' {
        $results=@()
        foreach($r in $gold.Resources) {
            $a=[pscustomobject]@{Name=$r.Name;Type=$r.Type;Status='Discovered';ResourceId='/test'}
            if($r.Type -eq 'Microsoft.CognitiveServices/accounts/deployments') {
                $a | Add-Member -NotePropertyName ObservedConfiguration -NotePropertyValue ([pscustomobject]@{ModelName='gpt-5-mini';ModelVersion='wrong'})
            }
            $results+=$a
        }
        $comparison=Compare-JawsTargetDiscoveryToState -State $gold -Results $results
        @($comparison | Where-Object Status -eq 'ConfigurationDrift').Count | Should -Be 1
    }
}
