# Step C offline checks. No Azure calls or writes.
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../installer/modules/FoundryInvestigationDeployment.psm1') -Force
    $state = [pscustomobject]@{
        Platform='JAWS'; EnvironmentName='dev'
        SubscriptionId='11111111-1111-1111-1111-111111111111'
        ResourceGroupName='rg-aiops-lab'
        Resources=@(
            [pscustomobject]@{Type='Microsoft.CognitiveServices/accounts';Name='jaws-foundry-dev'},
            [pscustomobject]@{Type='Microsoft.CognitiveServices/accounts/projects';Name='jaws-dev';ExpectedConfiguration=[pscustomobject]@{ParentResource='jaws-foundry-dev'}},
            [pscustomobject]@{Type='Microsoft.CognitiveServices/accounts/deployments';Name='gpt-5-mini';ExpectedConfiguration=[pscustomobject]@{ParentResource='jaws-foundry-dev'}}
        )
    }
    $digest='sha256:' + ('a' * 64)
    $receipt=[pscustomobject]@{
        Status='PUBLISHED_AND_DIGEST_VERIFIED'
        RegistryPushPerformed=$true; FoundryDeploymentPerformed=$false
        RegistryManifestDigest=$digest
        Image="jawsregistrydev001.azurecr.io/jaws/investigation@$digest"
    }
}
Describe 'Step C Investigation Foundry deployment plan' {
    It 'uses dedicated Investigation identity and immutable image' {
        $plan=New-JawsFoundryInvestigationPlan -State $state -PublishReceipt $receipt
        $plan.Plan.AgentName | Should -Be 'jaws-investigation-dev'
        $plan.Plan.Image | Should -Be $receipt.Image
        $plan.Plan.Operation | Should -Be 'CreateHostedInvestigationVersion'
        $plan.AzureWrites | Should -Be 0
        { Test-JawsFoundryDeploymentPlan -DeploymentPlan $plan } | Should -Not -Throw
    }
    It 'rejects Supervisor image receipts' {
        $bad=$receipt.PSObject.Copy()
        $bad.Image=$bad.Image.Replace('/investigation@','/supervisor@')
        { New-JawsFoundryInvestigationPlan -State $state -PublishReceipt $bad } | Should -Throw
    }
    It 'rejects a modified deployment payload' {
        $plan=New-JawsFoundryInvestigationPlan -State $state -PublishReceipt $receipt
        $plan.Plan.Request.definition.cpu='8'
        { Test-JawsFoundryDeploymentPlan -DeploymentPlan $plan } | Should -Throw
    }
    It 'rejects invalid or missing publication receipt' {
        $bad=$receipt.PSObject.Copy()
        $bad.RegistryPushPerformed=$false
        { New-JawsFoundryInvestigationPlan -State $state -PublishReceipt $bad } | Should -Throw
    }
}
