BeforeAll {
    $script:root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    Import-Module (Join-Path $script:root 'installer/modules/LaterSteps.psm1') -Force
    Import-Module (Join-Path $script:root 'installer/modules/StepRoadmap.psm1') -Force
    $script:devBefore = Get-Content -LiteralPath (Join-Path $script:root 'installer/config/jaws-installation-state.dev.json') -Raw
    $script:stub = Join-Path ([System.IO.Path]::GetTempPath()) ('jaws-later-stub-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:stub | Out-Null
    Set-Content -LiteralPath (Join-Path $script:stub 'az') -Encoding ascii -Value @'
#!/bin/bash
exec python3 "$0.py" "$@"
'@
    Set-Content -LiteralPath (Join-Path $script:stub 'az.py') -Encoding utf8 -Value @'
import json, os, sys
args = sys.argv[1:]
state = os.environ["JAWS_LATER_STUB_STATE"]
os.makedirs(state, exist_ok=True)
with open(os.path.join(state, "log.txt"), "a", encoding="utf-8") as handle:
    handle.write(" ".join(args) + "\n")

def flag(name):
    return args[args.index(name) + 1] if name in args else ""

if args[:2] == ["account", "show"]:
    print("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
    sys.exit(0)
if args[:3] == ["deployment", "group", "create"]:
    print(json.dumps({"properties": {"outputs": {"botId": {"value": "/subscriptions/sub/resourceGroups/rg-jaws-lab1/providers/Microsoft.BotService/botServices/jaws-teams-lab1"}}}}))
    sys.exit(0)
if args[:2] == ["resource", "show"]:
    endpoint = "https://jaws-foundry-lab1.services.ai.azure.com/api/projects/jaws-lab1/agents/jaws-supervisor-lab1/endpoint/protocols/activityProtocol"
    print(json.dumps({"id": flag("--ids"), "properties": {"endpoint": endpoint, "publicNetworkAccess": "Disabled"}}))
    sys.exit(0)
method = flag("--method").lower()
url = flag("--url")
if method == "get" and url.endswith("/versions/1?api-version=v1"):
    name = url.split("/agents/")[1].split("/versions/")[0]
    if name.startswith("jaws-observability-"):
        print(json.dumps({"name": name, "status": "active", "definition": {"kind": "prompt", "instructions": "Use Azure MCP for AZURE MONITOR AND MICROSOFT DEFENDER only."}}))
    else:
        print(json.dumps({"name": name, "status": "active", "definition": {"kind": "hosted", "container_configuration": {"image": "example.azurecr.io/jaws/supervisor@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}}}))
    sys.exit(0)
if method == "get" and "/agents/" in url:
    print(json.dumps({"name": "jaws-supervisor-lab1", "instance_identity": {"client_id": "00001111-aaaa-2222-bbbb-3333cccc4444"}}))
    sys.exit(0)
if method == "post" and url.endswith("/agents?api-version=v1"):
    print(json.dumps({"name": "jaws-observability-lab1"}))
    sys.exit(0)
if method == "post" and "/microsoft365/publish" in url:
    print(json.dumps({"titleId": "title-1"}))
    sys.exit(0)
print("unexpected", args, file=sys.stderr)
sys.exit(1)
'@
    & chmod a+x (Join-Path $script:stub 'az')
    $script:originalPath = $env:PATH
    $env:PATH = "$script:stub$([IO.Path]::PathSeparator)$env:PATH"
    $env:JAWS_LATER_STUB_STATE = $script:stub
}

AfterAll {
    $env:PATH = $script:originalPath
    Remove-Item -LiteralPath $script:stub -Recurse -Force -ErrorAction SilentlyContinue
    foreach ($name in @('lab1','bad1')) {
        Get-ChildItem -LiteralPath (Join-Path $script:root 'installer/.local') -Filter "*.$name.*" -ErrorAction SilentlyContinue | Remove-Item -Force
        Get-ChildItem -LiteralPath (Join-Path $script:root 'installer/.local') -Filter "*.$name.generated.json" -ErrorAction SilentlyContinue | Remove-Item -Force
    }
}

Describe 'Steps E-I contract' {
    It 'keeps one observability agent on two MCP servers and refuses a crossed grant' {
        $context = [pscustomobject]@{ EnvironmentName = 'lab1'; VmAgent = 'jaws-vm-specialist-lab1'; ObservabilityAgent = 'jaws-observability-lab1' }
        $catalog = New-JawsLaterCatalog -Context $context -Stage 'I' -BrowserTools @('browser_navigate')
        { Test-JawsTargetCatalog -Catalog $catalog -Stage 'I' } | Should -Not -Throw
        $obs = @($catalog.Specialists | Where-Object Id -eq 'observability')[0]
        @($obs.McpServers) | Should -Be @('azure-mcp','jaws-observability')
        $vm = @($catalog.Specialists | Where-Object Id -eq 'virtual-machine')[0]
        $vm.AllowedTools += 'defender.alert.get'
        { Test-JawsTargetCatalog -Catalog $catalog -Stage 'I' } | Should -Throw '*JAWS-CATALOG-008*'
    }

    It 'refuses Step E Install without acknowledgement and does not call Azure' {
        $log = Join-Path $script:stub 'log.txt'
        if (Test-Path $log) { Remove-Item $log }
        $local = Join-Path $script:root 'installer/.local'
        New-Item -ItemType Directory -Path $local -Force | Out-Null
        [pscustomobject]@{ Result = 'PASS' } | ConvertTo-Json | Set-Content (Join-Path $local 'jaws-step-d-acceptance.lab1.generated.json')
        [pscustomobject]@{
            FoundryAccountName = 'jaws-foundry-lab1'; ProjectName = 'jaws-lab1'; AgentName = 'jaws-supervisor-lab1'
            ResourceGroupName = 'rg-jaws-lab1'; SubscriptionId = 'sub'; ModelDeploymentName = 'gpt-5-mini'
        } | ConvertTo-Json | Set-Content (Join-Path $local 'jaws-step-b-install.lab1.generated.json')
        $output = ''
        try { & (Join-Path $script:root 'installer/Install-JawsStepE.ps1') -Mode Install -EnvironmentName 'lab1' *>&1 | ForEach-Object { $output += "$_`n" } } catch { $output += $_.Exception.Message }
        $output | Should -Match 'JAWS-STEP-E-001'
        if (Test-Path $log) { Get-Content $log -Raw | Should -Not -Match 'deployment group create' }
        { & (Join-Path $script:root 'installer/Install-JawsStepE.ps1') -Mode Validate -EnvironmentName 'dev' } | Should -Throw '*JAWS-STEP-E-014*'
    }

    It 'publishes only the Supervisor and then records the later steps without a live incident' {
        $env:JAWS_LATER_STUB_STATE = $script:stub
        Set-Content -LiteralPath (Join-Path $script:stub 'log.txt') -Value '' -Encoding utf8
        $install = & (Join-Path $script:root 'installer/Install-JawsStepE.ps1') -Mode Install -EnvironmentName 'lab1' -AcknowledgeStepEInstall *>&1 | Out-String
        $install | Should -Match 'STEP-E INSTALL PASS'
        $install | Should -Match 'Teams reply recorded: false'
        $install | Should -Match 'FedRAMP Moderate: false'
        $log = Get-Content -LiteralPath (Join-Path $script:stub 'log.txt') -Raw
        $deployAt = $log.IndexOf('deployment group create')
        $publishAt = $log.IndexOf('microsoft365/publish')
        $deployAt | Should -BeGreaterThan -1
        $publishAt | Should -BeGreaterThan $deployAt
        $log | Should -Match 'jaws-supervisor-lab1/microsoft365/publish'
        $log | Should -Not -Match 'jaws-vm-specialist-lab1/microsoft365/publish'
        $body = Get-Content -LiteralPath (Join-Path $script:root 'installer/.local/jaws-step-e-publish.lab1.json') -Raw
        $body | Should -Match 'Shared'
        $accept = & (Join-Path $script:root 'installer/Install-JawsStepE.ps1') -Mode Accept -EnvironmentName 'lab1' *>&1 | Out-String
        $accept | Should -Match 'STEP-E ACCEPTANCE PASS'
        $accept | Should -Match 'Next step: Step F Validate'
        & (Join-Path $script:root 'installer/Install-JawsStepF.ps1') -Mode Install -EnvironmentName 'lab1' -AcknowledgeStepFInstall *>&1 | Out-Null
        $f = & (Join-Path $script:root 'installer/Install-JawsStepF.ps1') -Mode Accept -EnvironmentName 'lab1' *>&1 | Out-String
        $f | Should -Match 'Live tool call: false'
        $f | Should -Match 'Next step: Step G Validate'
        & (Join-Path $script:root 'installer/Install-JawsStepG.ps1') -Mode Install -EnvironmentName 'lab1' -AcknowledgeStepGInstall *>&1 | Out-Null
        $manifest = Get-Content -LiteralPath (Join-Path $script:root 'installer/.local/jaws-observability-manifest.lab1.generated.json') -Raw | ConvertFrom-Json
        @($manifest | ForEach-Object { $_.Module }) | Should -Be @('Datadog','ServiceNow')
        & (Join-Path $script:root 'installer/Install-JawsStepG.ps1') -Mode Accept -EnvironmentName 'lab1' *>&1 | Out-Null
        & (Join-Path $script:root 'installer/Install-JawsStepH.ps1') -Mode Install -EnvironmentName 'lab1' -AcknowledgeStepHInstall *>&1 | Out-Null
        $h = & (Join-Path $script:root 'installer/Install-JawsStepH.ps1') -Mode Accept -EnvironmentName 'lab1' *>&1 | Out-String
        $h | Should -Match 'Change executed: false'
        $catalog = Get-Content -LiteralPath (Join-Path $script:root 'installer/.local/jaws-specialist-catalog.lab1.generated.json') -Raw | ConvertFrom-Json
        $vm = @($catalog.Specialists | Where-Object Id -eq 'virtual-machine')[0]
        @($vm.AllowedTools) | Should -Contain 'vm.run-command'
        @($vm.AllowedTools) | Should -Not -Contain 'defender.alert.get'
        $i = & (Join-Path $script:root 'installer/Install-JawsStepI.ps1') -Mode Accept -EnvironmentName 'lab1' *>&1 | Out-String
        $i | Should -Match 'STEP-I ACCEPTANCE PASS'
        $i | Should -Match 'Live incident: false'
        $i | Should -Match 'Ready for next step: false'
        $i | Should -Match 'Next step: none'
        (Get-Content -LiteralPath (Join-Path $script:root 'installer/config/jaws-installation-state.dev.json') -Raw) | Should -Be $script:devBefore
    }

    It 'refuses a custom module that is not in the build' {
        Import-Module (Join-Path $script:root 'installer/modules/StepRoadmap.psm1') -Force
        $bad = @(
            [pscustomobject]@{ Name = 'monitor.metrics.query'; Module = 'AzureMonitor'; ReadOnly = $true; Secret = 'none' }
            [pscustomobject]@{ Name = 'servicenow.incident.get'; Module = 'ServiceNow'; ReadOnly = $true; Secret = 'jaws-servicenow-password' }
        )
        { Test-JawsObservabilityManifest $bad } | Should -Throw '*JAWS-STEP-G-008*'
    }
}
