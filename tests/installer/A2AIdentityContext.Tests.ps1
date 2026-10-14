BeforeAll {
    $root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $file = Join-Path $root 'installer/Test-JawsA2AIdentityContext.ps1'
    $scriptText = Get-Content -LiteralPath $file -Raw
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$parseErrors) | Out-Null
}
Describe 'Step C A2A identity context regression guard' {
    It 'parses as valid PowerShell' {
        $parseErrors | Should -BeNullOrEmpty
    }
    It 'reads connection authentication from ARM rather than a partial project projection' {
        $scriptText | Should -Match 'https://management.azure.com/'
        $scriptText | Should -Match "'https://management.azure.com/'"
        $scriptText | Should -Match "Get-OptionalProperty \\$props 'authType'"
    }
    It 'never dereferences a missing authType property directly' {
        $scriptText | Should -Not -Match '\\$props\\.authType'
    }
    It 'does not persist client identifiers or credentials in its diagnostic report' {
        $scriptText | Should -Match 'InstanceClientIdPresent='
        $scriptText | Should -Match 'BlueprintClientIdPresent='
        $scriptText | Should -Not -Match 'InstanceClientId=\\$instanceClientId'
        $scriptText | Should -Not -Match 'BlueprintClientId=\\$blueprintClientId'
    }
    It 'performs read-only Azure REST requests' {
        $scriptText | Should -Match 'az rest --method get'
        $scriptText | Should -Not -Match 'az rest --method (put|patch|post|delete)'
    }
}
