BeforeAll {
    $script:root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $script:sub = '22222222-2222-2222-2222-222222222222'
    $script:vm = "/subscriptions/$($script:sub)/resourceGroups/rg-jaws-stepb-test/providers/Microsoft.Compute/virtualMachines/jaws-stepb-test"
    $script:stub = Join-Path ([System.IO.Path]::GetTempPath()) ('jaws-obs-stub-' + [guid]::NewGuid().ToString('N'))
    $script:state = Join-Path $script:stub 'state'
    New-Item -ItemType Directory -Path $script:state | Out-Null
    Set-Content -LiteralPath (Join-Path $script:stub 'az') -Encoding ascii -Value @'
#!/bin/bash
exec python3 "$0.py" "$@"
'@
    Set-Content -LiteralPath (Join-Path $script:stub 'az.py') -Encoding utf8 -Value @'
import json, os, sys
args = sys.argv[1:]
state = os.environ["JAWS_OBS_STUB_STATE"]
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
    emit({"name": flag("--name"), "id": "https://kvjawslab1.vault.azure.net/secrets/" + flag("--name")})
if args[:2] == ["tag", "update"]:
    world["tags"].append({"resource": flag("--resource-id"), "tags": flag("--tags")})
    save()
    emit({"properties": {"tags": {"jaws-datadog-default": "true"}}})
print("unexpected " + " ".join(args), file=sys.stderr)
sys.exit(9)
'@
    chmod +x (Join-Path $script:stub 'az') | Out-Null
    $script:savedPath = $env:PATH
    $env:JAWS_OBS_STUB_STATE = $script:state
    $env:PATH = $script:stub + [System.IO.Path]::PathSeparator + $env:PATH
    $local = Join-Path $script:root 'installer/.local'
    if (-not (Test-Path -LiteralPath $local)) { New-Item -ItemType Directory -Path $local | Out-Null }
    [pscustomobject]@{
        Status = 'STEP_B_INSTALLED'
        EnvironmentName = 'lab1'
        SubscriptionId = $script:sub
        ResourceGroupName = 'rg-jaws-lab1'
        KeyVaultName = 'kvjawslab1'
        FoundryAccountName = 'jaws-foundry-lab1'
        RegistryName = 'jawsacrlab1'
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $local 'jaws-step-b-install.lab1.generated.json') -Encoding utf8
}

AfterAll {
    $env:PATH = $script:savedPath
    Remove-Item Env:JAWS_OBS_STUB_STATE -ErrorAction SilentlyContinue
}

Describe 'Observability integration secrets' {
    It 'refuses an unacknowledged write before Azure is called' {
        { & (Join-Path $script:root 'installer/Set-JawsObservabilityIntegration.ps1') -EnvironmentName 'lab1' -ServiceNowUrl 'https://devexample.service-now.com' -ServiceNowUsername 'ops' -ServiceNowPassword 'super-secret-value' } | Should -Throw '*JAWS-OBS-001*'
        Test-Path -LiteralPath (Join-Path $script:state 'log.txt') | Should -BeFalse
    }

    It 'stores ServiceNow, the default virtual machine, and no secret values' {
        $password = 'super-secret-value'
        $output = & (Join-Path $script:root 'installer/Set-JawsObservabilityIntegration.ps1') -EnvironmentName 'lab1' -AcknowledgeObservabilitySecrets -ServiceNowUrl 'https://devexample.service-now.com/login.do' -ServiceNowUsername 'ops' -ServiceNowPassword $password -DefaultVirtualMachineResourceId $script:vm *>&1 | Out-String
        $output | Should -Match 'Observability integration: recorded'
        $output | Should -Match 'ServiceNow configured: True'
        $output | Should -Match 'Datadog configured: False'
        $output | Should -Match 'Datadog Agent installed: false'
        $output | Should -Match 'Customer installation accepted: false'
        $output | Should -Match 'Ready for next step: false'
        $output | Should -Match 'Next step: Step G is not installable'
        $output | Should -Not -Match $password
        $output | Should -Not -Match 'devexample'
        $evidencePath = Join-Path $script:root 'installer/.local/jaws-observability-integration.lab1.generated.json'
        $evidenceText = Get-Content -LiteralPath $evidencePath -Raw
        $evidenceText | Should -Not -Match $password
        $evidenceText | Should -Not -Match 'devexample'
        $evidence = $evidenceText | ConvertFrom-Json
        $evidence.SecretNames | Should -Contain 'jaws-servicenow-url'
        $evidence.SecretNames | Should -Contain 'jaws-servicenow-password'
        $evidence.SecretNames | Should -Contain 'jaws-datadog-default-vm'
        $evidence.DefaultVirtualMachineResourceId | Should -Be $script:vm
        $evidence.DefaultVirtualMachineTag | Should -Be 'jaws-datadog-default=true'
        $evidence.CustomerInstallationAccepted | Should -BeFalse
        $evidence.DatadogAgentInstalled | Should -BeFalse
        $log = Get-Content -LiteralPath (Join-Path $script:state 'log.txt') -Raw
        $log | Should -Not -Match $password
        $log | Should -Match 'Key Vault Secrets Officer'
        $log | Should -Match 'jaws-datadog-default=true'
        $world = Get-Content -LiteralPath (Join-Path $script:state 'world.json') -Raw | ConvertFrom-Json
        $world.secrets.'jaws-servicenow-url'.length | Should -Be 'https://devexample.service-now.com'.Length
        $world.secrets.'jaws-servicenow-password'.length | Should -Be $password.Length
        $world.tags[0].resource | Should -Be $script:vm
    }

    It 'refuses the dev project and a partial ServiceNow login' {
        { & (Join-Path $script:root 'installer/Set-JawsObservabilityIntegration.ps1') -EnvironmentName 'dev' -AcknowledgeObservabilitySecrets -DefaultVirtualMachineResourceId $script:vm } | Should -Throw '*JAWS-OBS-002*'
        { & (Join-Path $script:root 'installer/Set-JawsObservabilityIntegration.ps1') -EnvironmentName 'lab1' -AcknowledgeObservabilitySecrets -ServiceNowUrl 'https://devexample.service-now.com' } | Should -Throw '*JAWS-OBS-003*'
        { & (Join-Path $script:root 'installer/Set-JawsObservabilityIntegration.ps1') -EnvironmentName 'lab1' -AcknowledgeObservabilitySecrets -DatadogApiKey 'dd-secret' } | Should -Throw '*JAWS-OBS-006*'
    }
}
