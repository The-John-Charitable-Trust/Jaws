BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../installer/modules/SupervisorPackage.psm1') -Force
}
Describe 'B2.1 Supervisor local packaging safety' {
    It 'finds the fixed .NET 10 Supervisor host source' {
        $p=Get-JawsSupervisorPackagePlan -InstallerRoot (Join-Path $PSScriptRoot '../../installer')
        $p.ProjectPath | Should -Match 'Jaws.Supervisor.Host.csproj$'
        Test-Path $p.DockerfilePath | Should -BeTrue
        $p.AzureWrites | Should -Be 0
        $p.CanPushToRegistry | Should -BeFalse
    }
    It 'rejects an unsafe package plan' {
        $p=Get-JawsSupervisorPackagePlan -InstallerRoot (Join-Path $PSScriptRoot '../../installer')
        $p.CanPushToRegistry=$true
        { Invoke-JawsSupervisorLocalBuild -PackagePlan $p } | Should -Throw '*JAWS-PACKAGE-002*'
    }
    It 'keeps Cloud Install mode disabled in entrypoint' {
        $entry=Get-Content (Join-Path $PSScriptRoot '../../installer/Install-Jaws.ps1') -Raw
        $entry | Should -Match "ValidateSet\('Discover','Plan','Package'\)"
        $entry | Should -Not -Match "ValidateSet\('Discover','Plan','Package','Install'\)"
        $entry | Should -Match 'if \(\$Mode -eq ''Package''\)'
    }
    It 'uses only a local Docker build and no registry push or login commands' {
        $module=Get-Content (Join-Path $PSScriptRoot '../../installer/modules/SupervisorPackage.psm1') -Raw
        $module | Should -Match '& docker build'
        $module | Should -Not -Match '& docker push'
        $module | Should -Not -Match '& az '
        $module | Should -Not -Match '& azd '
    }
    It 'parses installer entrypoint without encoding-dependent syntax errors' {
        $entryPath=Join-Path $PSScriptRoot '../../installer/Install-Jaws.ps1'
        $tokens=$null
        $errors=$null
        $null=[System.Management.Automation.Language.Parser]::ParseFile($entryPath,[ref]$tokens,[ref]$errors)
        @($errors).Count | Should -Be 0
        $body=Get-Content -LiteralPath $entryPath -Raw
        @($body.ToCharArray() | Where-Object { [int][char]$_ -gt 127 }).Count | Should -Be 0
    }
    It 'has a minimal hosted-agent response path and explicit limits' {
        $repo=Join-Path $PSScriptRoot '../..'
        $source=Get-Content (Join-Path $repo 'src/Jaws.Supervisor.Host/Program.cs') -Raw
        $source | Should -Match 'AddFoundryResponses'
        $source | Should -Match 'MapFoundryResponses'
        $source | Should -Match 'DefaultAzureCredential'
        $source | Should -Match 'Never assert'
    }
}
