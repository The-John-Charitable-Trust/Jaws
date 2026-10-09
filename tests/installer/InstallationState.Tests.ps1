BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../installer/modules/InstallationState.psm1') -Force
}
Describe 'JAWS authoritative state validation' {
    It 'rejects legacy inventory entries' {
        $tmp=Join-Path $TestDrive 'bad.json'
        '{"SchemaVersion":"1.1","Platform":"JAWS","EnvironmentName":"test","SubscriptionId":"00000000-0000-0000-0000-000000000001","ResourceGroupName":"rg-test","Resources":[{"Name":"tfang-test","Type":"Microsoft.KeyVault/vaults"}]}' | Set-Content $tmp
        { Read-JawsInstallationState -Path $tmp } | Should -Throw
    }
    It 'returns null when state does not exist' {
        Read-JawsInstallationState -Path (Join-Path $TestDrive 'missing.json') | Should -BeNullOrEmpty
    }
}
