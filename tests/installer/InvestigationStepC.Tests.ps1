# Step C structural safety tests. These tests do not need Azure, Docker, or model inference.
BeforeAll {
    $root=[System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $hostProgram=Join-Path $root 'src/Jaws.Investigation.Host/Program.cs'
    $dockerfile=Join-Path $root 'src/Jaws.Investigation.Host/Dockerfile'
    $buildScript=Join-Path $root 'installer/Build-JawsInvestigation.ps1'
    $planScript=Join-Path $root 'installer/Plan-JawsInvestigation.ps1'
    $hostSource=Get-Content -LiteralPath $hostProgram -Raw
    $dockerSource=Get-Content -LiteralPath $dockerfile -Raw
    $buildSource=Get-Content -LiteralPath $buildScript -Raw
    $planSource=Get-Content -LiteralPath $planScript -Raw
}
Describe 'Step C Investigation hosted agent source contracts' {
    It 'hosts via Foundry Responses protocol' {
        $hostSource | Should -Match 'AddFoundryResponses'
        $hostSource | Should -Match 'MapFoundryResponses'
    }
    It 'uses Entra authentication and no embedded model secrets' {
        $hostSource | Should -Match 'DefaultAzureCredential'
        $hostSource | Should -Not -Match '(?i)api[_-]?key\s*='
    }
    It 'does not attach external tools or impersonate verification' {
        $hostSource | Should -Match 'no external tools are attached'
        $hostSource | Should -Match 'do not invent evidence'
    }
    It 'builds a non-root Linux container on port 8088' {
        $dockerSource | Should -Match 'USER \$APP_UID'
        $dockerSource | Should -Match 'EXPOSE 8088'
        $dockerSource | Should -Match 'aspnet:10\.0'
    }
}
Describe 'Step C installer safety contracts' {
    It 'restricts the local build to the fixed Investigation project' {
        $buildSource | Should -Match 'Jaws.Investigation.Host/Jaws.Investigation.Host.csproj'
        $buildSource | Should -Match 'AzureWrites=0'
    }
    It 'requires explicit -BuildContainer for a Docker build' {
        $buildSource | Should -Match 'if \(\$BuildContainer\)'
        $buildSource | Should -Match "jaws-investigation:local"
    }
    It 'blocks deployment in offline Plan' {
        $planSource | Should -Match 'CanDeploy=\$false'
        $planSource | Should -Match 'FoundryDeploymentPerformed=\$false'
        $planSource | Should -Match 'AzureWrites=0'
    }
    It 'does not contain any Azure mutation calls' {
        $planSource | Should -Not -Match '(?im)\baz\s+(?:rest|resource|role|acr)\s+.*(?:post|put|create|assign|delete|update|push)'
        $buildSource | Should -Not -Match '(?im)\baz\s+'
    }
    It 'does not allow reserved Foundry environment variables in user settings' {
        $planSource | Should -Match 'UserProvidedEnvironmentVariables='
        $planSource | Should -Not -Match 'UserProvidedEnvironmentVariables=\[ordered\]@\{FOUNDRY_'
    }
}
