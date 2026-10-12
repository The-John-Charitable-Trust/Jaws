BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../installer/modules/FoundrySupervisorDeployment.psm1') -Force
    $script:state=[pscustomobject]@{
        Platform='JAWS';EnvironmentName='dev'
        SubscriptionId='11111111-1111-1111-1111-111111111111'
        ResourceGroupName='rg-aiops-lab'
        Resources=@(
            [pscustomobject]@{Type='Microsoft.CognitiveServices/accounts';Name='jaws-foundry-dev'},
            [pscustomobject]@{Type='Microsoft.CognitiveServices/accounts/projects';Name='jaws-dev';ExpectedConfiguration=[pscustomobject]@{ParentResource='jaws-foundry-dev'}},
            [pscustomobject]@{Type='Microsoft.CognitiveServices/accounts/deployments';Name='gpt-5-mini';ExpectedConfiguration=[pscustomobject]@{ParentResource='jaws-foundry-dev'}}
        )
    }
    $script:digest='sha256:' + ('a'*64)
    $script:receipt=[pscustomobject]@{
        Status='PUBLISHED_AND_DIGEST_VERIFIED'
        RegistryPushPerformed=$true;FoundryDeploymentPerformed=$false
        Image="jawsregistrydev001.azurecr.io/jaws/supervisor@$script:digest"
        RegistryManifestDigest=$script:digest
    }
}
Describe 'Foundry Supervisor installation safety and specification' {
    It 'creates plan bound to exact verified image with zero writes' {
        $p=New-JawsFoundrySupervisorPlan -State $script:state -PublishReceipt $script:receipt
        $p.PlanSha256 | Should -Match '^[0-9a-f]{64}$'
        $p.AzureWrites | Should -Be 0
        $p.CanDeploy | Should -BeFalse
        $p.Plan.Request.definition.protocol_versions[0].version | Should -Be '2.0.0'
        $p.Plan.Request.definition.environment_variables.MODEL_DEPLOYMENT_NAME | Should -Be 'gpt-5-mini'
        $p.Plan.Image | Should -Be $script:receipt.Image
    }
    It 'generates stable plan fingerprints' {
        $a=New-JawsFoundrySupervisorPlan -State $script:state -PublishReceipt $script:receipt
        $b=New-JawsFoundrySupervisorPlan -State $script:state -PublishReceipt $script:receipt
        $a.PlanSha256 | Should -Be $b.PlanSha256
    }
    It 'rejects a mutable tag or modified image receipt' {
        $bad=$script:receipt.PSObject.Copy()
        $bad.Image='jawsregistrydev001.azurecr.io/jaws/supervisor:latest'
        { New-JawsFoundrySupervisorPlan -State $script:state -PublishReceipt $bad } | Should -Throw '*JAWS-FOUNDRY-003*'
    }
    It 'rejects source receipt without completed registry push' {
        $bad=$script:receipt.PSObject.Copy()
        $bad.RegistryPushPerformed=$false
        { New-JawsFoundrySupervisorPlan -State $script:state -PublishReceipt $bad } | Should -Throw '*JAWS-FOUNDRY-003*'
    }
    It 'refuses deployment when fingerprint-bound payload is changed' {
        $p=New-JawsFoundrySupervisorPlan -State $script:state -PublishReceipt $script:receipt
        $p.Plan.Request.definition.cpu='8'
        { Test-JawsFoundryDeploymentPlan -DeploymentPlan $p } | Should -Throw '*JAWS-FOUNDRY-005*'
    }
    It 'refuses altered agent name even if image remains valid' {
        $p=New-JawsFoundrySupervisorPlan -State $script:state -PublishReceipt $script:receipt
        $p.Plan.AgentName='other-agent'
        { Test-JawsFoundryDeploymentPlan -DeploymentPlan $p } | Should -Throw '*JAWS-FOUNDRY-006*'
    }
    It 'rejects unauthorized or malformed agent names' {
        { New-JawsFoundrySupervisorPlan -State $script:state -PublishReceipt $script:receipt -AgentName '../escape' } | Should -Throw '*JAWS-FOUNDRY-001*'
    }
    It 'requires exact approval and cost acknowledgment for billable Deploy' {
        $entry=Get-Content (Join-Path $PSScriptRoot '../../installer/Deploy-JawsSupervisor.ps1') -Raw
        $entry | Should -Match 'JAWS-FOUNDRY-APPROVAL-001'
        $entry | Should -Match 'AcknowledgeHostingAndInferenceCharges'
        $entry | Should -Match 'ApprovedPlanSha256'
    }
    It 'contains only one guarded Foundry agent creation write' {
        $s=Get-Content (Join-Path $PSScriptRoot '../../installer/modules/FoundrySupervisorDeployment.psm1') -Raw
        @([regex]::Matches($s,'& az rest --method post')).Count | Should -Be 1
        $s | Should -Match 'JAWS-FOUNDRY-013'
        $s | Should -Not -Match '& az role assignment create'
    }
    It 'parses both Foundry installer files' {
        foreach ($path in @('installer/Deploy-JawsSupervisor.ps1','installer/modules/FoundrySupervisorDeployment.psm1')) {
            $file=Join-Path (Join-Path $PSScriptRoot '../..') $path
            $tokens=$null;$errors=$null
            $null=[System.Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)
            @($errors).Count | Should -Be 0
        }
    }
}
