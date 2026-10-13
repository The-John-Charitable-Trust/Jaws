Describe 'JAWS hosted Supervisor runtime acceptance guardrails' {
    BeforeAll {
        $script:path=Join-Path $PSScriptRoot '../../installer/Test-JawsSupervisorInvocation.ps1'
        $script:src=Get-Content -LiteralPath $script:path -Raw
    }
    It 'parses with no PowerShell errors' {
        $tokens=$null;$errors=$null
        $null=[System.Management.Automation.Language.Parser]::ParseFile($script:path,[ref]$tokens,[ref]$errors)
        @($errors).Count | Should -Be 0
    }
    It 'targets the dedicated Foundry Responses protocol endpoint' {
        $script:src | Should -Match '/agents/jaws-supervisor-dev/endpoint/protocols/openai/responses\\?api-version=v1'
        $script:src | Should -Match 'az rest --method post'
        $script:src | Should -Match 'az rest --method get'
    }
    It 'requires explicit inference charge acknowledgment and a matching agent version' {
        $script:src | Should -Match 'AcknowledgeInferenceCharges'
        $script:src | Should -Match 'Compare-JawsFoundrySupervisorState'
        $script:src | Should -Match "comparison.OverallStatus -ne 'MATCH'"
    }
    It 'uses JSON file transport and no infrastructure resource mutation' {
        $script:src | Should -Match 'WriteAllText'
        $script:src | Should -Match '"@\\$bodyFile"'
        $script:src | Should -Not -Match 'az role assignment create'
        $script:src | Should -Not -Match 'az resource create'
        $script:src | Should -Not -Match 'az acr build'
    }
    It 'does not mark acceptance on HTTP success with empty output' {
        $script:src | Should -Match 'JAWS-INVOKE-008'
        $script:src | Should -Match "status -cne 'completed'"
        $script:src | Should -Match "IsNullOrWhiteSpace\\(\\$message\\)"
    }
    It 'keeps the deployment receipt unmodified and stores metadata only' {
        $script:src | Should -Match 'jaws-supervisor-invocation-acceptance.dev.generated.json'
        $script:src | Should -Match 'InvocationVerified=\\$true'
        $script:src | Should -Match 'Remove-Item -LiteralPath \\$bodyFile'
        $script:src | Should -Not -Match 'Set-Content -LiteralPath \\$ReceiptFile'
    }
}
