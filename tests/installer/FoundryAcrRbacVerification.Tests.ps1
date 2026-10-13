BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../installer/modules/FoundryAcrRbac.psm1') -Force
    $script:principal='13a1310b-508a-475a-82c3-9eb2dcef959d'
    $script:scope='/subscriptions/c52f597b-7753-45b4-a764-67e290dcfd5e/resourceGroups/rg-aiops-lab/providers/Microsoft.ContainerRegistry/registries/jawsregistrydev001'
    $script:roleId='/subscriptions/c52f597b-7753-45b4-a764-67e290dcfd5e/providers/Microsoft.Authorization/roleDefinitions/7f951dda-4ed3-4680-a7ca-43fe172d538d'
}
Describe 'Foundry ACR role assignment verification regression' {
    It 'matches a valid roleDefinitionId without roleDefinitionName' {
        $items=@([pscustomobject]@{principalId=$script:principal;scope=$script:scope;roleDefinitionId=$script:roleId})
        Test-JawsExactRoleAssignment -Assignments $items -PrincipalId $script:principal -Scope $script:scope -RoleName 'AcrPull' -RoleDefinitionId $script:roleId | Should -BeTrue
    }
    It 'does not match wrong principal, scope or role ID' {
        $items=@([pscustomobject]@{principalId=$script:principal;scope=$script:scope;roleDefinitionId=$script:roleId})
        Test-JawsExactRoleAssignment -Assignments $items -PrincipalId '00000000-0000-0000-0000-000000000001' -Scope $script:scope -RoleName 'AcrPull' -RoleDefinitionId $script:roleId | Should -BeFalse
        Test-JawsExactRoleAssignment -Assignments $items -PrincipalId $script:principal -Scope '/other' -RoleName 'AcrPull' -RoleDefinitionId $script:roleId | Should -BeFalse
        Test-JawsExactRoleAssignment -Assignments $items -PrincipalId $script:principal -Scope $script:scope -RoleName 'AcrPull' -RoleDefinitionId '/other' | Should -BeFalse
    }
    It 'returns false for empty, malformed and null responses under StrictMode' {
        Test-JawsExactRoleAssignment -Assignments @() -PrincipalId $script:principal -Scope $script:scope -RoleName 'AcrPull' -RoleDefinitionId $script:roleId | Should -BeFalse
        Test-JawsExactRoleAssignment -Assignments @($null,[pscustomobject]@{id='placeholder'}) -PrincipalId $script:principal -Scope $script:scope -RoleName 'AcrPull' -RoleDefinitionId $script:roleId | Should -BeFalse
    }
    It 'has exactly one Azure RBAC assignment write and parses without syntax errors' {
        $path=Join-Path $PSScriptRoot '../../installer/modules/FoundryAcrRbac.psm1'
        $body=Get-Content -LiteralPath $path -Raw
        @([regex]::Matches($body,'& az role assignment create')).Count | Should -Be 1
        @([regex]::Matches($body,'(?m)^Export-ModuleMember')).Count | Should -Be 1
        $tokens=$null;$errors=$null
        $null=[System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
        @($errors).Count | Should -Be 0
    }
}
