BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../installer/modules/DeploymentPlan.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot '../../installer/modules/SupervisorPackage.psm1') -Force
    $script:example = Join-Path $PSScriptRoot '../../installer/config/jaws-stage-b-plan.example.json'
    $script:sampleId = '11111111-1111-1111-1111-111111111111'
}

Describe 'Step B subscription capture and local package' {
    It 'leaves the example blueprint as a placeholder' {
        $raw = Get-Content -LiteralPath $script:example -Raw
        $raw | Should -Match '00000000-0000-0000-0000-000000000000'
        { New-JawsOfflineDeploymentPlan -BlueprintPath $script:example } | Should -Throw '*JAWS-PLAN-004*'
        (Get-Content -LiteralPath $script:example -Raw) | Should -Be $raw
    }

    It 'uses a captured subscription without rewriting the example file' {
        $before = Get-Content -LiteralPath $script:example -Raw
        $plan = New-JawsOfflineDeploymentPlan -BlueprintPath $script:example -SubscriptionId $script:sampleId -SubscriptionSource 'AzureCli'
        $plan.SubscriptionId | Should -Be $script:sampleId
        $plan.SubscriptionSource | Should -Be 'AzureCli'
        $plan.CanExecute | Should -BeFalse
        $plan.AzureWrites | Should -Be 0
        $plan.AzureDiscoveryPerformed | Should -BeFalse
        $plan.Status | Should -Be 'BLOCKED_PENDING_AZURE_DISCOVERY_AND_APPROVAL'
        (Get-Content -LiteralPath $script:example -Raw) | Should -Be $before
    }

    It 'captures the selected Azure CLI subscription from the installer entrypoint' {
        $entry = Get-Content (Join-Path $PSScriptRoot '../../installer/Install-Jaws.ps1') -Raw
        $plan = $entry.Substring($entry.IndexOf("if (`$Mode -eq 'Plan')"))
        $plan = $plan.Substring(0, $plan.IndexOf('The operator-maintained state is the GOLD COPY'))
        $plan | Should -Match 'Get-JawsAuthorizedSubscriptions'
        $plan | Should -Match 'subscriptionSource = ''AzureCli'''
        $plan | Should -Match 'Subscription source:'
        $plan | Should -Match 'STEP-B PLAN PASS'
        $plan | Should -Match 'JAWS-PLAN-012'
        $entry | Should -Match "ValidateSet\('Discover','Plan','Preflight','Package','Install','Accept'\)"
        $entry | Should -Match 'STEP-A DISCOVERY PASS'
        $entry | Should -Match 'STEP-B PREFLIGHT PASS'
        $entry | Should -Match 'STEP-B ACCEPTANCE PASS'
        $entry | Should -Match 'Live Azure read: true'
        $entry | Should -Match 'AcknowledgeStepBInstall'
        $installModule = Get-Content (Join-Path $PSScriptRoot '../../installer/modules/StepBInstall.psm1') -Raw
        $installModule | Should -Match 'JAWS-STEP-B-010'
        $installModule | Should -Match 'JAWS-STEP-B-013'
        $installModule | Should -Match 'JAWS-STEP-B-024'
        $installModule | Should -Match 'list-models'
        $installModule | Should -Match 'PrincipalNotFound'
        $installModule | Should -Match 'JAWS-STEP-B-026'
        $installModule | Should -Match 'Get-JawsStepBAuthorizedWrites'
        $installModule | Should -Match 'PolicySimulation'
    }

    It 'finds the Supervisor host and scores a local package without a registry push' {
        $package = Get-JawsSupervisorPackagePlan -InstallerRoot (Join-Path $PSScriptRoot '../../installer')
        $package.ProjectPath | Should -Match 'Jaws.Supervisor.Host.csproj$'
        Test-Path -LiteralPath $package.DockerfilePath | Should -BeTrue
        $package.AzureWrites | Should -Be 0
        $package.CanPushToRegistry | Should -BeFalse
        $entry = Get-Content (Join-Path $PSScriptRoot '../../installer/Install-Jaws.ps1') -Raw
        $entry | Should -Match 'STEP-B PACKAGE PASS'
        $entry | Should -Match 'Registry push: false'
        $entry | Should -Match 'Foundry deployment: false'
        $module = Get-Content (Join-Path $PSScriptRoot '../../installer/modules/SupervisorPackage.psm1') -Raw
        $module | Should -Match '\*>&1 \| Out-Host'
        $module | Should -Not -Match '& docker push'
        $module | Should -Not -Match '& az '
    }
}
