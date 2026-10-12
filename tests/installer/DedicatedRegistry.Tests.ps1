BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../installer/modules/DedicatedRegistry.psm1') -Force
    $script:state=[pscustomobject]@{
        Platform='JAWS';SubscriptionId='11111111-1111-1111-1111-111111111111'
        ResourceGroupName='rg-aiops-lab';EnvironmentName='dev'
        Resources=@([pscustomobject]@{
            Type='Microsoft.CognitiveServices/accounts'
            ExpectedConfiguration=[pscustomobject]@{Location='eastus'}
        })
    }
}
Describe 'Dedicated JAWS ACR installer plan' {
    It 'produces reproducible fingerprint with no Azure writes' {
        $a=New-JawsDedicatedRegistryPlan -State $script:state -RegistryName 'jawsregistrydev001'
        $b=New-JawsDedicatedRegistryPlan -State $script:state -RegistryName 'jawsregistrydev001'
        $a.PlanSha256 | Should -Be $b.PlanSha256
        $a.PlanSha256 | Should -Match '^[0-9a-f]{64}$'
        $a.AzureWrites | Should -Be 0
        $a.Sku | Should -Be 'Basic'
    }
    It 'defaults to disabled registry admin authentication' {
        $p=New-JawsDedicatedRegistryPlan -State $script:state -RegistryName 'jawsregistrydev001'
        $p.Plan.AdminEnabled | Should -BeFalse
        $p.Plan.Tags.managedBy | Should -Be 'JAWS-Installer'
        $p.CostAcknowledgmentRequired | Should -BeTrue
    }
    It 'rejects invalid registry name before network access' {
        { New-JawsDedicatedRegistryPlan -State $script:state -RegistryName 'Jaws-registry' } | Should -Throw '*JAWS-ACR-PLAN-002*'
    }
    It 'rejects wrong platform and mismatched baseline' {
        $copy=$script:state.PSObject.Copy()
        $copy.Platform='TightFang'
        { New-JawsDedicatedRegistryPlan -State $copy -RegistryName 'jawsregistrydev001' } | Should -Throw '*JAWS-ACR-PLAN-002*'
    }
    It 'rejects unsafe modified plan before Azure CLI' {
        $p=New-JawsDedicatedRegistryPlan -State $script:state -RegistryName 'jawsregistrydev001'
        $p.Plan.AdminEnabled=$true
        { Invoke-JawsDedicatedRegistryCreate -Plan $p } | Should -Throw '*JAWS-ACR-SEC-001*'
    }
    It 'keeps registry Create gated by exact plan and cost acknowledgment' {
        $script=Get-Content (Join-Path $PSScriptRoot '../../installer/Install-JawsRegistry.ps1') -Raw
        $script | Should -Match 'ApprovedPlanSha256'
        $script | Should -Match 'AcknowledgeBillableBasicSku'
        $script | Should -Match 'JAWS-ACR-APPROVAL-001'
    }
    It 'retains only a single billable create operation in module' {
        $body=Get-Content (Join-Path $PSScriptRoot '../../installer/modules/DedicatedRegistry.psm1') -Raw
        @([regex]::Matches($body,'& az acr create')).Count | Should -Be 1
        $body | Should -Not -Match '& az acr (delete|update|import|build|login)'
    }
    It 'parses the registry installer and module in PowerShell' {
        foreach ($path in @('installer/Install-JawsRegistry.ps1','installer/modules/DedicatedRegistry.psm1')) {
            $file=Join-Path (Join-Path $PSScriptRoot '../..') $path
            $tokens=$null; $errors=$null
            $null=[System.Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)
            @($errors).Count | Should -Be 0
        }
    }
}
