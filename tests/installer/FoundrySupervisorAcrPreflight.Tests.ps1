BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../installer/modules/FoundrySupervisorDeployment.psm1') -Force
    $script:principal='13a1310b-508a-475a-82c3-9eb2dcef959d'
    $script:scope='/subscriptions/c52f597b-7753-45b4-a764-67e290dcfd5e/resourceGroups/rg-aiops-lab/providers/Microsoft.ContainerRegistry/registries/jawsregistrydev001'
    $script:assignment=[pscustomobject]@{
        principalId=$script:principal
        principalName='249390ab-8011-4b0e-a4a0-95ffb2dd476f'
        principalType='ServicePrincipal'
        roleDefinitionName='AcrPull'
        scope=$script:scope
    }
}
Describe 'Supervisor Foundry RBAC preflight regression' {
    It 'recognizes the actual Azure ACR role response with a different principalName' {
        Test-JawsFoundryAcrPullRole -Assignments @($script:assignment) -PrincipalId $script:principal -RegistryScope $script:scope | Should -BeTrue
    }
    It 'does not accept the principalName as the identity' {
        Test-JawsFoundryAcrPullRole -Assignments @($script:assignment) -PrincipalId $script:assignment.principalName -RegistryScope $script:scope | Should -BeFalse
    }
    It 'rejects unrelated scope and unauthorized role' {
        Test-JawsFoundryAcrPullRole -Assignments @($script:assignment) -PrincipalId $script:principal -RegistryScope ($script:scope + 'other') | Should -BeFalse
        $bad=[pscustomobject]@{principalId=$script:principal;scope=$script:scope;roleDefinitionName='Reader'}
        Test-JawsFoundryAcrPullRole -Assignments @($bad) -PrincipalId $script:principal -RegistryScope $script:scope | Should -BeFalse
    }
    It 'handles empty and malformed Azure role records under StrictMode' {
        Test-JawsFoundryAcrPullRole -Assignments @() -PrincipalId $script:principal -RegistryScope $script:scope | Should -BeFalse
        Test-JawsFoundryAcrPullRole -Assignments @($null,[pscustomobject]@{id='test'}) -PrincipalId $script:principal -RegistryScope $script:scope | Should -BeFalse
    }
    It 'uses object-id lookup and has one Azure creation call' {
        $path=Join-Path $PSScriptRoot '../../installer/modules/FoundrySupervisorDeployment.psm1'
        $src=Get-Content -LiteralPath $path -Raw
        $src | Should -Match 'az role assignment list --assignee-object-id'
        @([regex]::Matches($src,'& az rest --method post')).Count | Should -Be 1
        $tokens=$null;$errors=$null
        $null=[System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
        @($errors).Count | Should -Be 0
    }
}
