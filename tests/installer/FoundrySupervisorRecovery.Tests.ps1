Describe 'Foundry Supervisor recovery is read-only and fail-closed' {
    BeforeAll {
        $script:path=Join-Path $PSScriptRoot '../../installer/Recover-JawsSupervisorDeployment.ps1'
        $script:source=Get-Content -LiteralPath $script:path -Raw
    }
    It 'parses as PowerShell with no syntax errors' {
        $tokens=$null;$errors=$null
        $null=[System.Management.Automation.Language.Parser]::ParseFile($script:path,[ref]$tokens,[ref]$errors)
        @($errors).Count | Should -Be 0
    }
    It 'queries Azure but never sends an Azure write' {
        $script:source | Should -Match 'az rest --method get'
        $script:source | Should -Not -Match 'az rest --method post'
        $script:source | Should -Not -Match 'az role assignment create'
        $script:source | Should -Not -Match 'az resource create'
    }
    It 'requires a matching approved plan, active version 1 and identical immutable image' {
        $script:source | Should -Match 'Test-JawsFoundryDeploymentPlan'
        $script:source | Should -Match 'ApprovedPlanSha256 -cne \$plan.PlanSha256'
        $script:source | Should -Match 'agent.status -ine ''active'''
        $script:source | Should -Match 'agent.version -cne ''1'''
        $script:source | Should -Match 'container_configuration.image -cne \$p.Image'
    }
    It 'refuses to overwrite an existing receipt or claim inference acceptance' {
        $script:source | Should -Match 'JAWS-RECOVER-006'
        $script:source | Should -Match 'InvocationVerified=\$false'
        $script:source | Should -Match 'AzureWrites=0'
    }
}
