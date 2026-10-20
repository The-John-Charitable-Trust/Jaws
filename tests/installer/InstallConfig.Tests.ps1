BeforeAll {
    $script:root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $script:sub = '22222222-2222-2222-2222-222222222222'
    $script:vm = "/subscriptions/$($script:sub)/resourceGroups/rg-jaws-stepb-test/providers/Microsoft.Compute/virtualMachines/jaws-stepb-test"
    $script:password = 'super-secret-value'
    $script:apiKey = 'dd-api-secret-value'
    Import-Module (Join-Path $script:root 'installer/modules/InstallConfig.psm1') -Force
    $script:stub = Join-Path ([System.IO.Path]::GetTempPath()) ('jaws-cfg-stub-' + [guid]::NewGuid().ToString('N'))
    $script:state = Join-Path $script:stub 'state'
    New-Item -ItemType Directory -Path $script:state | Out-Null
    Set-Content -LiteralPath (Join-Path $script:stub 'az') -Encoding ascii -Value @'
#!/bin/bash
exec python3 "$0.py" "$@"
'@
    Set-Content -LiteralPath (Join-Path $script:stub 'az.py') -Encoding utf8 -Value @'
import json, os, sys
args = sys.argv[1:]
state = os.environ["JAWS_CFG_STUB_STATE"]
os.makedirs(state, exist_ok=True)
with open(os.path.join(state, "log.txt"), "a", encoding="utf-8") as handle:
    handle.write(" ".join(args) + "\n")
world_path = os.path.join(state, "world.json")
world = {"secrets": {}, "tags": [], "roles": []}
if os.path.exists(world_path):
    with open(world_path, encoding="utf-8") as handle:
        world = json.load(handle)

def save():
    with open(world_path, "w", encoding="utf-8") as handle:
        json.dump(world, handle)

def emit(payload):
    print(json.dumps(payload))
    sys.exit(0)

def flag(name):
    return args[args.index(name) + 1] if name in args else ""

if args[:3] == ["ad", "signed-in-user", "show"]:
    emit({"id": "55555555-5555-5555-5555-555555555555"})
if args[:3] == ["role", "assignment", "list"]:
    emit(world["roles"])
if args[:3] == ["role", "assignment", "create"]:
    world["roles"].append({"roleDefinitionName": flag("--role"), "scope": flag("--scope")})
    save()
    emit(world["roles"][-1])
if args[:3] == ["keyvault", "secret", "set"]:
    path = flag("--file")
    value = open(path, encoding="utf-8").read()
    world["secrets"][flag("--name")] = {"length": len(value)}
    save()
    emit({"name": flag("--name"), "id": "https://kvjawscfg1.vault.azure.net/secrets/" + flag("--name")})
if args[:2] == ["tag", "update"]:
    world["tags"].append({"resource": flag("--resource-id"), "tags": flag("--tags")})
    save()
    emit({"properties": {"tags": {"jaws-datadog-default": "true"}}})
print("unexpected " + " ".join(args), file=sys.stderr)
sys.exit(9)
'@
    chmod +x (Join-Path $script:stub 'az') | Out-Null
    $script:savedPath = $env:PATH
    $env:JAWS_CFG_STUB_STATE = $script:state
    $env:PATH = $script:stub + [System.IO.Path]::PathSeparator + $env:PATH
    $local = Join-Path $script:root 'installer/.local'
    if (-not (Test-Path -LiteralPath $local)) { New-Item -ItemType Directory -Path $local | Out-Null }
    $script:receipt = [pscustomobject]@{
        Status = 'STEP_B_INSTALLED'
        EnvironmentName = 'cfg1'
        SubscriptionId = $script:sub
        ResourceGroupName = 'rg-jaws-cfg1'
        Location = 'eastus'
        FoundryAccountName = 'jaws-foundry-cfg1'
        ProjectName = 'jaws-cfg1'
        ModelDeploymentName = 'gpt-5-mini'
        KeyVaultName = 'kvjawscfg1'
        RegistryName = 'jawsacrcfg1'
        AgentName = 'jaws-supervisor-cfg1'
    }
    $script:receipt | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $local 'jaws-step-b-install.cfg1.generated.json') -Encoding utf8
    $script:configFile = Join-Path $local 'jaws.install.cfg1.json'
    [pscustomobject]@{
        ServiceNowUrl = 'https://devexample.service-now.com/login.do'
        ServiceNowUsername = 'ops'
        ServiceNowPassword = $script:password
        DatadogSite = 'datadoghq.com'
        DatadogApiKey = $script:apiKey
        DatadogAppKey = ''
        DefaultVirtualMachineResourceId = $script:vm
    } | ConvertTo-Json | Set-Content -LiteralPath $script:configFile -Encoding utf8
}

AfterAll {
    $env:PATH = $script:savedPath
    Remove-Item Env:JAWS_CFG_STUB_STATE -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath @(
        (Join-Path $script:root 'installer/.local/jaws-install.cfg1.generated.json'),
        (Join-Path $script:root 'installer/.local/jaws-observability-integration.cfg1.generated.json'),
        (Join-Path $script:root 'installer/.local/jaws-step-b-install.cfg1.generated.json'),
        (Join-Path $script:root 'installer/.local/jaws.install.cfg1.json')
    ) -Force -ErrorAction SilentlyContinue
}

Describe 'Install-time ServiceNow, Datadog, and FedRAMP config' {
    It 'keeps secret values out of the generated JSON and records every resource' {
        $result = Save-JawsInstallConfiguration -EnvironmentName 'cfg1' -InstallerRoot (Join-Path $script:root 'installer') -InstallConfig $script:configFile -AcknowledgeStepBInstall
        $result.ServiceNowConfigured | Should -BeTrue
        $result.DatadogConfigured | Should -BeTrue
        $result.DefaultVirtualMachineConfigured | Should -BeTrue
        $result.FedRampModerate | Should -BeFalse
        $result.OpenResourceCount | Should -Be 10
        $text = Get-Content -LiteralPath $result.Path -Raw
        $text | Should -Not -Match $script:password
        $text | Should -Not -Match $script:apiKey
        $text | Should -Not -Match 'devexample'
        $config = $text | ConvertFrom-Json
        $config.Observability.ServiceNow.PasswordSecret | Should -Be 'jaws-servicenow-password'
        $config.Observability.Datadog.ApiKeySecret | Should -Be 'jaws-datadog-api-key'
        $config.Observability.Datadog.DefaultVirtualMachineSecret | Should -Be 'jaws-datadog-default-vm'
        $config.FedRampModerate.Accepted | Should -BeFalse
        $config.FedRampModerate.CustomerInstallationAccepted | Should -BeFalse
        $config.FedRampModerate.Statement | Should -Match 'not a FedRAMP authorization'
        $names = @($config.FedRampModerate.Resources | ForEach-Object { $_.Type })
        $names | Should -Contain 'Microsoft.KeyVault/vaults'
        $names | Should -Contain 'Microsoft.CognitiveServices/accounts'
        $names | Should -Contain 'Microsoft.ContainerRegistry/registries'
        $names | Should -Contain 'Microsoft.Insights/diagnosticSettings'
        $names | Should -Contain 'Microsoft.Network/virtualNetworks'
        $names | Should -Contain 'Microsoft.App/containerApps'
        $names | Should -Contain 'Microsoft.Compute/virtualMachines'
        @($config.FedRampModerate.Resources | Where-Object { $_.MeetsFedrampModerate }).Count | Should -Be 2
        $log = Get-Content -LiteralPath (Join-Path $script:state 'log.txt') -Raw
        $log | Should -Not -Match $script:password
        $log | Should -Not -Match $script:apiKey
        $log | Should -Match 'jaws-servicenow-password'
        $world = Get-Content -LiteralPath (Join-Path $script:state 'world.json') -Raw | ConvertFrom-Json
        $world.secrets.'jaws-servicenow-password'.length | Should -Be $script:password.Length
        $world.secrets.'jaws-datadog-api-key'.length | Should -Be $script:apiKey.Length
    }

    It 'writes the FedRAMP inventory without calling Azure when no values are supplied' {
        $before = Get-Item -LiteralPath (Join-Path $script:state 'log.txt')
        $result = Save-JawsInstallConfiguration -EnvironmentName 'cfg1' -InstallerRoot (Join-Path $script:root 'installer') -NonInteractive
        $result.ServiceNowConfigured | Should -BeFalse
        $result.DatadogConfigured | Should -BeFalse
        $result.DefaultVirtualMachineConfigured | Should -BeFalse
        $result.FedRampModerate | Should -BeFalse
        $result.OpenResourceCount | Should -Be 10
        (Get-Item -LiteralPath (Join-Path $script:state 'log.txt')).Length | Should -Be $before.Length
        $config = Get-Content -LiteralPath $result.Path -Raw | ConvertFrom-Json
        $config.KeyVaultName | Should -Be 'kvjawscfg1'
        $config.FedRampModerate.Resources | Where-Object { $_.Type -eq 'Microsoft.CognitiveServices/accounts' } | ForEach-Object { $_.MeetsFedrampModerate | Should -BeFalse }
    }

    It 'refuses a partial ServiceNow login and a missing config file' {
        { Save-JawsInstallConfiguration -EnvironmentName 'cfg1' -InstallerRoot (Join-Path $script:root 'installer') -Parameters @{ ServiceNowUrl = 'https://devexample.service-now.com' } -AcknowledgeStepBInstall -NonInteractive } | Should -Throw '*JAWS-OBS-003*'
        { Save-JawsInstallConfiguration -EnvironmentName 'cfg1' -InstallerRoot (Join-Path $script:root 'installer') -InstallConfig (Join-Path $script:root 'installer/.local/missing-install-config.json') -NonInteractive } | Should -Throw '*JAWS-INSTALL-CONFIG-001*'
    }

    It 'lets command parameters replace the config file and does not prompt during a test' {
        $resolved = Resolve-JawsInstallObservability -InstallConfig $script:configFile -Parameters @{ ServiceNowUsername = 'override-user' } -NonInteractive
        $resolved['ServiceNowUsername'] | Should -Be 'override-user'
        $resolved['ServiceNowPassword'] | Should -Be $script:password
        $counter = @{ Count = 0 }
        $skipped = Resolve-JawsInstallObservability -Parameters @{} -Prompter {
            param($Label, $Secret)
            $counter.Count++
            if ($Label -like 'Configure *') { return 'skip' }
            return 'unexpected'
        }
        $counter.Count | Should -Be 2
        $skipped['SkipServiceNow'] | Should -BeTrue
        $skipped['SkipDatadog'] | Should -BeTrue
        $skipped['DefaultVirtualMachineResourceId'] | Should -Be ''
        $silent = Resolve-JawsInstallObservability -Parameters @{}
        $silent['ServiceNowPassword'] | Should -Be ''
        $silent['DatadogApiKey'] | Should -Be ''
        $silent['SkipDatadog'] | Should -BeFalse
    }

    It 'skips Datadog and ServiceNow without a Key Vault write or an agent host' {
        $before = Get-Item -LiteralPath (Join-Path $script:state 'log.txt')
        $result = Save-JawsInstallConfiguration -EnvironmentName 'cfg1' -InstallerRoot (Join-Path $script:root 'installer') -NonInteractive -SkipServiceNow -SkipDatadog
        $result.ServiceNowSkipped | Should -BeTrue
        $result.DatadogSkipped | Should -BeTrue
        $result.ServiceNowConfigured | Should -BeFalse
        $result.DatadogConfigured | Should -BeFalse
        $result.DefaultVirtualMachineConfigured | Should -BeFalse
        $result.DatadogAgentHostRequired | Should -BeFalse
        $result.OpenResourceCount | Should -Be 9
        (Get-Item -LiteralPath (Join-Path $script:state 'log.txt')).Length | Should -Be $before.Length
        $config = Get-Content -LiteralPath $result.Path -Raw | ConvertFrom-Json
        $config.Observability.Datadog.Skipped | Should -BeTrue
        $config.Observability.Datadog.AgentHostRequired | Should -BeFalse
        $hostRow = $config.FedRampModerate.Resources | Where-Object { $_.Name -eq 'datadog-agent-host' }
        $hostRow.MeetsFedrampModerate | Should -BeTrue
        $hostRow.CurrentPosture | Should -Match 'No Datadog Agent host is required'
        { Save-JawsInstallConfiguration -EnvironmentName 'cfg1' -InstallerRoot (Join-Path $script:root 'installer') -NonInteractive -SkipDatadog -Parameters @{ DatadogApiKey = 'dd-api-secret-value'; DatadogSite = 'us5.datadoghq.com' } } | Should -Throw '*JAWS-INSTALL-CONFIG-003*'
        { Resolve-JawsInstallObservability -NonInteractive -Parameters @{ DatadogSite = 'us5.datadoghq.com' } } | Should -Throw '*JAWS-INSTALL-CONFIG-005*'
    }
}
