BeforeAll {
    $script:root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    Import-Module (Join-Path $script:root 'installer/modules/StepDInstall.psm1') -Force
    $script:image = 'jawsacrlab1.azurecr.io/jaws/supervisor@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    $script:devImage = 'jawsregistrydev001.azurecr.io/jaws/investigation@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
    $script:stub = Join-Path ([System.IO.Path]::GetTempPath()) ('jaws-stepd-stub-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:stub | Out-Null
    Set-Content -LiteralPath (Join-Path $script:stub 'az') -Encoding ascii -Value @'
#!/bin/bash
exec python3 "$0.py" "$@"
'@
    Set-Content -LiteralPath (Join-Path $script:stub 'az.py') -Encoding utf8 -Value @'
import json, os, sys
args = sys.argv[1:]
state_dir = os.environ["JAWS_STEPD_STUB_STATE"]
dev_image = os.environ.get("JAWS_STEPD_STUB_DEV_IMAGE", "")
dev_missing = os.environ.get("JAWS_STEPD_STUB_DEV_MISSING", "") == "1"
os.makedirs(state_dir, exist_ok=True)
with open(os.path.join(state_dir, "log.txt"), "a", encoding="utf-8") as handle:
    handle.write(" ".join(args) + "\n")
world_path = os.path.join(state_dir, "world.json")
world = {"agents": {}}
if os.path.exists(world_path):
    with open(world_path, encoding="utf-8") as handle:
        world = json.load(handle)

def save():
    with open(world_path, "w", encoding="utf-8") as handle:
        json.dump(world, handle)

def tool_name(operation):
    return os.environ.get("JAWS_STEPD_STUB_TOOL_PREFIX", "") + operation

def emit(payload, code=0):
    text = json.dumps(payload)
    if "/protocols/openai/responses" in url:
        text += os.environ.get("JAWS_STEPD_STUB_ANSI_SUFFIX", "")
    print(text)
    sys.exit(code)

def missing():
    print(os.environ.get(
        "JAWS_STEPD_STUB_MISSING",
        '{"error":{"code":"not_found","message":"Not Found"}}',
    ), file=sys.stderr)
    sys.exit(1)

def flag(name):
    if name in args:
        return args[args.index(name) + 1]
    return ""

def body_text():
    raw = flag("--body")
    if raw.startswith("@"):
        raw = raw[1:]
    if not raw:
        return ""
    with open(raw, encoding="utf-8") as handle:
        return handle.read()

method = flag("--method").lower()
url = flag("--url")
if method == "get" and "/versions/1" in url:
    if "jaws-investigation-dev" in url:
        if dev_missing:
            missing()
        emit({
            "name": "jaws-investigation-dev",
            "status": "active",
            "draft": False,
            "version": "1",
            "definition": {"kind": "hosted", "container_configuration": {"image": dev_image}},
        })
    name = url.split("/agents/")[1].split("/versions/")[0]
    agent = world["agents"].get(name)
    if not agent and not name.startswith("jaws-supervisor-"):
        missing()
    if agent:
        emit(agent)
if method == "post" and "/agents?api-version=v1" in url and "/versions" not in url:
    body = json.loads(body_text())
    name = body["name"]
    world["agents"][name] = {
        "name": name,
        "status": "active",
        "draft": False,
        "version": "1",
        "definition": body["definition"],
    }
    save()
    emit(world["agents"][name])
if method == "get" and "/agents/" in url and "/versions/" not in url:
    name = url.split("/agents/")[1].split("?")[0]
    latest = world.get("latest", {}).get(name, "1")
    if os.environ.get("JAWS_STEPD_STUB_LATEST_STRING") == "1":
        latest_value = str(latest)
    else:
        version_value = int(latest) if str(latest).isdigit() else latest
        latest_value = {"agent_guid": "00000000-0000-0000-0000-000000000001", "version": version_value}
    emit({"name": name, "versions": {"latest": latest_value}})
if method == "get" and "/versions/" in url and "/toolboxes/" not in url:
    name = url.split("/agents/")[1].split("/versions/")[0]
    version = url.split("/versions/")[1].split("?")[0]
    stored = world.get("versions", {}).get(name, {}).get(version)
    if stored:
        emit(stored)
    if version == "1" and name.startswith("jaws-supervisor-"):
        image = os.environ.get(
            "JAWS_STEPD_STUB_SUPERVISOR_IMAGE",
            "jawsacrlab1.azurecr.io/jaws/supervisor@sha256:" + ("a" * 64),
        )
        payload = {
            "name": name,
            "status": "active",
            "draft": False,
            "version": "1",
            "definition": {
                "kind": "hosted",
                "container_configuration": {"image": image},
                "cpu": "1",
                "memory": "2Gi",
                "environment_variables": {"AZURE_AI_MODEL_DEPLOYMENT_NAME": "gpt-5-mini"},
            },
        }
        world.setdefault("versions", {}).setdefault(name, {})["1"] = payload
        world.setdefault("agents", {})[name] = payload
        save()
        emit(payload)
if method == "post" and "/versions?api-version=v1" in url and "/toolboxes/" not in url:
    name = url.split("/agents/")[1].split("/versions")[0]
    body = json.loads(body_text())
    versions = world.setdefault("versions", {}).setdefault(name, {})
    numeric = [int(key) for key in versions if str(key).isdigit()]
    version = str(max(numeric + [1]) + 1)
    payload = {
        "name": name,
        "status": "active",
        "draft": False,
        "version": version,
        "definition": body["definition"],
    }
    versions[version] = payload
    world.setdefault("latest", {})[name] = version
    save()
    emit(payload)
if method == "post" and "/protocols/openai/responses" in url:
    world["last-response-body"] = body_text()
    save()
    mode = os.environ.get("JAWS_STEPD_STUB_BROWSER_CALL", "private-ok")
    if mode == "unreachable":
        emit({
            "id": "resp_unreachable",
            "status": "completed",
            "output": [
                {"type": "function_call", "name": tool_name("browser_open"), "call_id": "call_open"},
                {"type": "function_call_output", "call_id": "call_open", "output": "browser_unreachable"},
            ],
        })
    if mode == "capability":
        emit({
            "id": "resp_capability",
            "status": "completed",
            "output": [
                {"type": "function_call", "name": tool_name("browser_navigate"), "call_id": "call_nav"},
                {"type": "function_call_output", "call_id": "call_nav", "output": "EXTRACTED_VALUE=42"},
                {"type": "function_call", "name": tool_name("browser_navigate"), "call_id": "call_deny"},
                {"type": "function_call_output", "call_id": "call_deny", "output": "allow_list_rejected"},
            ],
        })
    if mode == "missing-markers":
        emit({
            "id": "resp_missing",
            "status": "completed",
            "output": [
                {"type": "function_call", "name": tool_name("browser_navigate"), "call_id": "call_nav"},
                {"type": "function_call_output", "call_id": "call_nav", "output": "page loaded"},
            ],
        })
    emit({
        "id": "resp_private",
        "status": "completed",
        "output": [
            {"type": "function_call", "name": tool_name("browser_open"), "call_id": "call_open"},
            {"type": "function_call_output", "call_id": "call_open", "output": "{\"sessionId\":\"abc123\",\"requested_by\":\"jaws-supervisor-cap1\"}"},
            {"type": "function_call", "name": "browser_close", "call_id": "call_close"},
            {"type": "function_call_output", "call_id": "call_close", "output": "closed"},
        ],
    })
if method == "get" and "/toolboxes/jaws-browser-tools" in url:
    toolbox = world.get("toolbox")
    if not toolbox:
        missing()
    emit(toolbox)
if method == "post" and "/toolboxes/jaws-browser-tools/versions" in url:
    body = json.loads(body_text())
    audience = body["tools"][0]["openapi"]["auth"]["security_scheme"]["audience"]
    if audience != "api://jaws-browser":
        print("browser toolbox audience mismatch", file=sys.stderr)
        sys.exit(2)
    server = body["tools"][0]["openapi"]["spec"]["servers"][0]["url"]
    if not server.startswith("https://") or ".internal." not in server:
        print("browser toolbox must use the internal endpoint", file=sys.stderr)
        sys.exit(2)
    toolbox = {"name": "jaws-browser-tools", "default_version": "1", "version": "1"}
    world["toolbox"] = toolbox
    save()
    emit(toolbox)
if args[:2] == ["provider", "show"]:
    emit({"namespace": flag("--namespace"), "registrationState": "Registered"})
if args[:2] == ["account", "show"]:
    emit({"id": "22222222-2222-2222-2222-222222222222", "tenantId": "33333333-3333-3333-3333-333333333333"})
if args[:3] == ["ad", "signed-in-user", "show"]:
    emit({"id": "55555555-5555-5555-5555-555555555555", "userPrincipalName": "installer@contoso.example"})
if args[:3] == ["network", "vnet", "show"]:
    emit(world["vnet"]) if "vnet" in world else missing()
if args[:3] == ["network", "vnet", "create"]:
    world["vnet"] = {"name": flag("--name"), "location": "eastus"}
    save()
    emit(world["vnet"])
if args[:4] == ["network", "vnet", "subnet", "show"]:
    emit(world["subnet"]) if "subnet" in world else missing()
if args[:4] == ["network", "vnet", "subnet", "create"]:
    if "Microsoft.App/environments" not in args:
        print("subnet must be delegated to Microsoft.App/environments", file=sys.stderr)
        sys.exit(2)
    world["subnet"] = {"name": flag("--name"), "id": "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-jaws-lab1/providers/Microsoft.Network/virtualNetworks/vnet/subnets/jaws-br-apps"}
    save()
    emit(world["subnet"])
if args[:3] == ["containerapp", "env", "show"]:
    emit(world["cae"]) if "cae" in world else missing()
if args[:3] == ["containerapp", "env", "create"]:
    if flag("--internal-only") != "true":
        print("container app environment must be internal-only", file=sys.stderr)
        sys.exit(2)
    world["cae"] = {"name": flag("--name")}
    save()
    emit(world["cae"])
if args[:2] == ["acr", "repository"] and "show" in args[:4]:
    image = flag("--image")
    if image.startswith("jaws/supervisor:"):
        emit(world["supervisor-image"]) if "supervisor-image" in world else missing()
    emit(world["browser-image"]) if "browser-image" in world else missing()
if args[:2] == ["acr", "build"]:
    file_arg = flag("--file").replace("\\", "/")
    image = flag("--image")
    if flag("--platform") != "linux/amd64":
        print("platform must be linux/amd64", file=sys.stderr)
        sys.exit(2)
    if "--no-logs" not in args:
        print("acr build requires --no-logs", file=sys.stderr)
        sys.exit(2)
    if file_arg.endswith("src/Jaws.Browser.Host/Dockerfile"):
        world["browser-image"] = {"digest": "sha256:" + ("b" * 64)}
        save()
        sys.exit(0)
    if file_arg.endswith("src/Jaws.Supervisor.Host/Dockerfile") and image.startswith("jaws/supervisor:browser-"):
        world["supervisor-image"] = {"digest": "sha256:" + ("c" * 64)}
        save()
        sys.exit(0)
    print("dockerfile path is required", file=sys.stderr)
    sys.exit(2)
if args[:2] == ["containerapp", "show"]:
    emit(world["app"]) if "app" in world else missing()
if args[:2] == ["containerapp", "create"]:
    if flag("--ingress") != "internal":
        print("ingress must be internal", file=sys.stderr)
        sys.exit(2)
    if flag("--min-replicas") != "0" or flag("--max-replicas") != "3":
        print("browser replica bounds must be 0 and 3", file=sys.stderr)
        sys.exit(2)
    image = flag("--image")
    if "@sha256:" not in image:
        print("browser image must be digest pinned", file=sys.stderr)
        sys.exit(2)
    world["app"] = {
        "name": flag("--name"),
        "identity": {"principalId": "44444444-4444-4444-4444-444444444444"},
        "properties": {"configuration": {"ingress": {"external": False, "fqdn": flag("--name") + ".internal.example"}}},
    }
    save()
    emit(world["app"])
if args[:3] == ["keyvault", "secret", "show"]:
    name = flag("--name")
    secrets = world.get("secrets", {})
    emit(secrets[name]) if name in secrets else missing()
if args[:3] == ["keyvault", "secret", "set"]:
    name = flag("--name")
    world.setdefault("secrets", {})[name] = {"name": name, "id": "https://kvjawslab1.vault.azure.net/secrets/" + name}
    save()
    emit(world["secrets"][name])
if args[:3] == ["role", "assignment", "list"]:
    emit(world.get("roles", []))
if args[:3] == ["role", "assignment", "create"]:
    role = {"roleDefinitionName": flag("--role"), "scope": flag("--scope")}
    world.setdefault("roles", []).append(role)
    save()
    emit(role)
print("unexpected " + " ".join(args), file=sys.stderr)
sys.exit(9)
'@
    chmod +x (Join-Path $script:stub 'az') | Out-Null

    function Write-StepDAcceptance([string]$EnvironmentName) {
        $local = Join-Path $script:root 'installer/.local'
        if (-not (Test-Path -LiteralPath $local)) { New-Item -ItemType Directory -Path $local | Out-Null }
        [pscustomobject]@{
            Status = 'PASS'
            TaskState = 'TASK_STATE_COMPLETED'
            EnvironmentName = $EnvironmentName
            CustomerInstallationAccepted = $false
        } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $local "jaws-step-c-final-acceptance.$EnvironmentName.generated.json") -Encoding utf8
    }

    function Write-StepDReceipt {
        param(
            [string]$EnvironmentName = 'lab1',
            [string]$FoundryAccountName = 'jaws-foundry-lab1',
            [string]$ProjectName = 'jaws-lab1',
            [string]$Image = $script:image,
            [string]$AgentName = 'jaws-supervisor-lab1'
        )
        $local = Join-Path $script:root 'installer/.local'
        if (-not (Test-Path -LiteralPath $local)) { New-Item -ItemType Directory -Path $local | Out-Null }
        [pscustomobject]@{
            Status = 'STEP_B_INSTALLED'
            EnvironmentName = $EnvironmentName
            ResourceGroupName = "rg-jaws-$EnvironmentName"
            FoundryAccountName = $FoundryAccountName
            ProjectName = $ProjectName
            RegistryName = 'jawsacrlab1'
            AgentName = $AgentName
            KeyVaultName = 'kvjawslab1'
            Image = $Image
            ModelDeploymentName = 'gpt-5-mini'
            SubscriptionId = '22222222-2222-2222-2222-222222222222'
            Location = 'eastus'
        } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $local "jaws-step-b-install.$EnvironmentName.generated.json") -Encoding utf8
    }
}

Describe 'Step D catalog' {
    It 'refuses an unknown tool, a phase agent, a second sandbox, and a write without the approval workflow' {
        $agent = 'jaws-vm-specialist-lab1'
        $image = $script:image
        $base = New-JawsStepDCatalog -EnvironmentName 'lab1' -AgentName $agent -Image $image
        { Test-JawsStepDCatalog -Catalog $base } | Should -Not -Throw
        $base.Specialists[0].WritesRequireApproval | Should -BeTrue
        $browserCatalog = New-JawsStepDCatalog -EnvironmentName 'lab1' -AgentName $agent -Image $image -IncludeBrowserTools
        { Test-JawsStepDCatalog -Catalog $browserCatalog } | Should -Not -Throw
        @($browserCatalog.Specialists[0].AllowedTools) | Should -Contain 'browser_navigate'
        @($browserCatalog.Specialists[0].AllowedTools) | Should -Not -Contain 'vm.run-command'

        $unknown = New-JawsStepDCatalog -EnvironmentName 'lab1' -AgentName $agent -Image $image
        $unknown.Specialists[0].AllowedTools = @('vm.get','not-a-tool')
        { Test-JawsStepDCatalog -Catalog $unknown } | Should -Throw '*JAWS-STEP-D-003*'

        $phase = New-JawsStepDCatalog -EnvironmentName 'lab1' -AgentName $agent -Image $image
        $phase.Specialists += [pscustomobject]@{
            Id = 'investigation'; Kind = 'prompt'; ComputeEnvironmentId = $agent
            AllowedTools = @('vm.get'); WritesRequireApproval = $true; ApprovalWorkflow = 'approve-vm-change'
        }
        { Test-JawsStepDCatalog -Catalog $phase } | Should -Throw '*JAWS-STEP-D-004*'

        $second = New-JawsStepDCatalog -EnvironmentName 'lab1' -AgentName $agent -Image $image
        $second.Specialists += [pscustomobject]@{
            Id = 'network'; Kind = 'prompt'; ComputeEnvironmentId = 'other-sandbox'
            AllowedTools = @('vm.get'); WritesRequireApproval = $true; ApprovalWorkflow = 'approve-vm-change'
        }
        { Test-JawsStepDCatalog -Catalog $second } | Should -Throw '*JAWS-STEP-D-006*'

        $hosted = New-JawsStepDCatalog -EnvironmentName 'lab1' -AgentName $agent -Image $image
        $hosted.Specialists += [pscustomobject]@{
            Id = 'other'; Kind = 'hosted'; FoundryAgentName = 'other'; ComputeEnvironmentId = $agent
            AllowedTools = @('vm.get'); WritesRequireApproval = $true; ApprovalWorkflow = 'approve-vm-change'
        }
        { Test-JawsStepDCatalog -Catalog $hosted } | Should -Throw '*JAWS-STEP-D-006*'

        $write = New-JawsStepDCatalog -EnvironmentName 'lab1' -AgentName $agent -Image $image
        $write.Specialists[0].AllowedTools = @('vm.run-command')
        $write.Specialists[0].WritesRequireApproval = $false
        $write.Specialists[0].ApprovalWorkflow = ''
        { Test-JawsStepDCatalog -Catalog $write } | Should -Throw '*JAWS-STEP-D-005*'

        $approved = New-JawsStepDCatalog -EnvironmentName 'lab1' -AgentName $agent -Image $image
        $approved.Specialists[0].AllowedTools = @('vm.get','vm.run-command')
        $prompt = [pscustomobject]@{
            Id = 'network'; Kind = 'prompt'; FoundryAgentName = 'jaws-network-lab1'; ComputeEnvironmentId = $agent
            AllowedTools = @('vm.get'); WritesRequireApproval = $true; ApprovalWorkflow = 'approve-vm-change'
        }
        $approved.Specialists = @($approved.Specialists) + $prompt
        { Test-JawsStepDCatalog -Catalog $approved } | Should -Not -Throw

        $foreignBrowser = New-JawsStepDCatalog -EnvironmentName 'lab1' -AgentName $agent -Image $image -IncludeBrowserTools
        $foreignBrowser.Specialists = @($foreignBrowser.Specialists) + [pscustomobject]@{
            Id = 'network'; Kind = 'prompt'; FoundryAgentName = 'jaws-network-lab1'; ComputeEnvironmentId = $agent
            AllowedTools = @('vm.get','browser_navigate'); WritesRequireApproval = $true; ApprovalWorkflow = 'approve-vm-change'
        }
        { Test-JawsStepDCatalog -Catalog $foreignBrowser } | Should -Throw '*JAWS-STEP-D-034*'
    }

    It 'refuses an exact dev resource name and accepts a name that only contains that text' {
        $installer = Join-Path $script:root 'installer'
        Write-StepDAcceptance 'dev2'
        Write-StepDReceipt -EnvironmentName 'dev2' -FoundryAccountName 'jaws-foundry-dev2' -ProjectName 'jaws-dev2' -AgentName 'jaws-supervisor-dev2'
        $context = Resolve-JawsStepDContext -EnvironmentName 'dev2' -InstallerRoot $installer
        $context.AgentName | Should -Be 'jaws-vm-specialist-dev2'
        $context.FoundryAccountName | Should -Be 'jaws-foundry-dev2'

        Write-StepDReceipt -EnvironmentName 'dev2' -FoundryAccountName 'jaws-foundry-dev' -ProjectName 'jaws-dev2' -AgentName 'jaws-supervisor-dev2'
        { Resolve-JawsStepDContext -EnvironmentName 'dev2' -InstallerRoot $installer } | Should -Throw '*JAWS-STEP-D-017*'

        Write-StepDReceipt -EnvironmentName 'dev2' -FoundryAccountName 'jaws-foundry-dev2' -ProjectName 'jaws-dev2' -AgentName 'jaws-supervisor-dev2' -Image 'jawsregistrydev001.azurecr.io/jaws/supervisor@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        { Resolve-JawsStepDContext -EnvironmentName 'dev2' -InstallerRoot $installer } | Should -Throw '*JAWS-STEP-D-017*'
    }
}

Describe 'Step D installer' {
    AfterAll {
        $local = Join-Path $script:root 'installer/.local'
        foreach ($name in @(
            'jaws-step-b-install.dev2.generated.json',
            'jaws-step-b-install.cap1.generated.json',
            'jaws-step-b-install.cap2.generated.json',
            'jaws-step-c-final-acceptance.dev2.generated.json',
            'jaws-step-c-final-acceptance.cap1.generated.json',
            'jaws-step-c-final-acceptance.cap2.generated.json',
            'jaws-step-c-final-acceptance.lab9.generated.json',
            'jaws-step-d-validate.lab9.generated.json',
            'jaws-step-d-install.cap1.generated.json',
            'jaws-step-d-install.cap2.generated.json',
            'jaws-step-d-browser-image.cap1.generated.json',
            'jaws-step-d-browser-private-path.cap1.generated.json',
            'jaws-step-d-browser-capability.cap1.generated.json',
            'jaws-browser-allow-list.cap1.json',
            'jaws-specialist-catalog.cap1.generated.json',
            'jaws-specialist-catalog.cap2.generated.json'
        )) {
            $path = Join-Path $local $name
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path }
        }
    }

    BeforeEach {
        $script:state = Join-Path $script:stub ('state-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:state | Out-Null
        $script:savedPath = $env:PATH
        $script:savedState = $env:JAWS_STEPD_STUB_STATE
        $script:savedImage = $env:JAWS_STEPD_STUB_DEV_IMAGE
        $script:savedMissing = $env:JAWS_STEPD_STUB_DEV_MISSING
        $script:savedAgentMissing = $env:JAWS_STEPD_STUB_MISSING
        $script:savedPoll = $env:JAWS_STEPD_POLL_SECONDS
        $script:savedBrowserCall = $env:JAWS_STEPD_STUB_BROWSER_CALL
        $script:savedAnsiSuffix = $env:JAWS_STEPD_STUB_ANSI_SUFFIX
        $script:savedToolPrefix = $env:JAWS_STEPD_STUB_TOOL_PREFIX
        $env:JAWS_STEPD_STUB_STATE = $script:state
        $env:JAWS_STEPD_STUB_DEV_IMAGE = $script:devImage
        $env:JAWS_STEPD_STUB_DEV_MISSING = '0'
        Remove-Item Env:JAWS_STEPD_STUB_MISSING -ErrorAction SilentlyContinue
        Remove-Item Env:JAWS_STEPD_STUB_BROWSER_CALL -ErrorAction SilentlyContinue
        Remove-Item Env:JAWS_STEPD_STUB_ANSI_SUFFIX -ErrorAction SilentlyContinue
        Remove-Item Env:JAWS_STEPD_STUB_TOOL_PREFIX -ErrorAction SilentlyContinue
        $env:JAWS_STEPD_POLL_SECONDS = '0'
        $env:PATH = $script:stub + [System.IO.Path]::PathSeparator + $env:PATH
        $script:devBefore = Get-Content -LiteralPath (Join-Path $script:root 'installer/config/jaws-installation-state.dev.json') -Raw
    }
    AfterEach {
        $env:PATH = $script:savedPath
        foreach ($pair in @(
            @{ Name = 'JAWS_STEPD_STUB_STATE'; Value = $script:savedState },
            @{ Name = 'JAWS_STEPD_STUB_DEV_IMAGE'; Value = $script:savedImage },
            @{ Name = 'JAWS_STEPD_STUB_DEV_MISSING'; Value = $script:savedMissing },
            @{ Name = 'JAWS_STEPD_STUB_MISSING'; Value = $script:savedAgentMissing },
            @{ Name = 'JAWS_STEPD_POLL_SECONDS'; Value = $script:savedPoll },
            @{ Name = 'JAWS_STEPD_STUB_BROWSER_CALL'; Value = $script:savedBrowserCall },
            @{ Name = 'JAWS_STEPD_STUB_ANSI_SUFFIX'; Value = $script:savedAnsiSuffix },
            @{ Name = 'JAWS_STEPD_STUB_TOOL_PREFIX'; Value = $script:savedToolPrefix }
        )) {
            if ($null -eq $pair.Value) { Remove-Item "Env:$($pair.Name)" -ErrorAction SilentlyContinue } else { Set-Item "Env:$($pair.Name)" $pair.Value }
        }
        (Get-Content -LiteralPath (Join-Path $script:root 'installer/config/jaws-installation-state.dev.json') -Raw) | Should -Be $script:devBefore
    }

    It 'prints FAIL and writes evidence when Step C is not complete' {
        $evidence = Join-Path $script:root 'installer/.local/jaws-step-d-validate.lab9.generated.json'
        if (Test-Path -LiteralPath $evidence) { Remove-Item -LiteralPath $evidence }
        $output = ''
        try {
            & (Join-Path $script:root 'installer/Install-JawsStepD.ps1') -Mode Validate -EnvironmentName 'lab9' *>&1 | ForEach-Object { $output += "$_`n" }
            throw 'Validate returned instead of JAWS-STEP-D-002.'
        } catch {
            $output += $_.Exception.Message
        }
        $output | Should -Match 'JAWS-STEP-D-002'
        $output | Should -Match 'STEP-D VALIDATE FAIL'
        $output | Should -Match 'Result: FAIL'
        $output | Should -Match 'Ready for next step: false'
        $output | Should -Match 'Evidence: '
        Test-Path -LiteralPath (Join-Path $script:state 'log.txt') | Should -BeFalse
        $file = Get-Content -LiteralPath $evidence -Raw | ConvertFrom-Json
        $file.Result | Should -Be 'FAIL'
        $file.Message | Should -Match 'JAWS-STEP-D-002'
    }

    It 'refuses an unacknowledged install before Azure' {
        Write-StepDAcceptance 'lab1'
        Write-StepDReceipt
        $output = ''
        try {
            & (Join-Path $script:root 'installer/Install-JawsStepD.ps1') -Mode Install -EnvironmentName 'lab1' *>&1 | ForEach-Object { $output += "$_`n" }
            throw 'Install returned instead of JAWS-STEP-D-001.'
        } catch {
            $output += $_.Exception.Message
        }
        $output | Should -Match 'JAWS-STEP-D-001'
        $output | Should -Match 'Result: FAIL'
        $output | Should -Match 'Ready for next step: false'
        Test-Path -LiteralPath (Join-Path $script:state 'log.txt') | Should -BeFalse
        $file = Get-Content -LiteralPath (Join-Path $script:root 'installer/.local/jaws-step-d-install.lab1.generated.json') -Raw | ConvertFrom-Json
        $file.Result | Should -Be 'FAIL'
    }

    It 'creates one hosted specialist, resumes without a second post, and keeps Step E closed' {
        Write-StepDAcceptance 'lab1'
        Write-StepDReceipt
        $output = & (Join-Path $script:root 'installer/Install-JawsStepD.ps1') -Mode Install -EnvironmentName 'lab1' -AcknowledgeStepDInstall *>&1 | Out-String
        $output | Should -Match 'STEP-D INSTALL PASS'
        $output | Should -Match 'Customer installation accepted: false'
        $output | Should -Match 'Azure writes: '
        $output | Should -Not -Match 'Azure writes: 0'
        $output | Should -Match 'Browser toolbox: jaws-browser-tools'
        $output | Should -Match 'Supervisor image rebuilt: false'
        $output | Should -Match 'Browser tools on this image: pending a Supervisor image built from this host'
        $output | Should -Match 'Browser allow-list: empty\. No navigation will succeed until an operator adds a URL\.'
        $output | Should -Match 'Supervisor version 1 unchanged: true'
        $output | Should -Match 'Result: PASS'
        $output | Should -Match 'Ready for next step: true'
        $output | Should -Match 'Next step: Step D Accept'
        $log = Get-Content -LiteralPath (Join-Path $script:state 'log.txt') -Raw
        $agentPost = [regex]::Escape('/agents?api-version=v1')
        ([regex]::Matches($log, $agentPost)).Count | Should -Be 1
        $log | Should -Match 'containerapp env create'
        $log | Should -Match '--internal-only true'
        $log | Should -Match 'containerapp create'
        $log | Should -Match '--ingress internal'
        $log | Should -Match 'src/Jaws\.Browser\.Host/Dockerfile'
        $log | Should -Match 'acr build .*--no-logs'
        $log | Should -Match 'ad signed-in-user show'
        $officer = 'role assignment create --subscription 22222222-2222-2222-2222-222222222222 --assignee-object-id 55555555-5555-5555-5555-555555555555 --assignee-principal-type User --role Key Vault Secrets Officer --scope /subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-jaws-lab1/providers/Microsoft.KeyVault/vaults/kvjawslab1'
        $log | Should -Match ([regex]::Escape($officer))
        $log.IndexOf('Key Vault Secrets Officer') | Should -BeLessThan $log.IndexOf('keyvault secret set')
        $log | Should -Match 'jaws-supervisor-lab1/versions\?api-version=v1'
        $log | Should -Not -Match 'jaws-supervisor-lab1/versions/1 .*--method PATCH'
        $log | Should -Not -Match '--method patch'
        $receipt = Get-Content -LiteralPath (Join-Path $script:root 'installer/.local/jaws-step-d-install.lab1.generated.json') -Raw | ConvertFrom-Json
        $receipt.BrowserToolboxName | Should -Be 'jaws-browser-tools'
        $receipt.BrowserToolsetVersion | Should -Be '1'
        $receipt.PlaywrightServiceEndpoint | Should -Match '^https://.+\.internal\.'
        $receipt.CredentialScopeId | Should -Match '/secrets/jaws-browser-credentials$'
        $receipt.SupervisorV1Unchanged | Should -BeTrue
        @($receipt.BrowserAgents) | Should -Contain 'jaws-supervisor-lab1'
        @($receipt.BrowserAgents) | Should -Contain 'jaws-vm-specialist-lab1'
        $firstPosts = ([regex]::Matches($log, 'rest --method POST')).Count
        & (Join-Path $script:root 'installer/Install-JawsStepD.ps1') -Mode Install -EnvironmentName 'lab1' -AcknowledgeStepDInstall
        $log = Get-Content -LiteralPath (Join-Path $script:state 'log.txt') -Raw
        ([regex]::Matches($log, 'rest --method POST')).Count | Should -Be $firstPosts
        ([regex]::Matches($log, 'containerapp create')).Count | Should -Be 1
        ([regex]::Matches($log, 'acr build')).Count | Should -Be 1
        ([regex]::Matches($log, 'Key Vault Secrets Officer')).Count | Should -Be 1
        $log | Should -Match 'jaws-supervisor-lab1/versions/2\?api-version=v1'
        $log | Should -Not -Match 'agent_guid'
        (Get-Content -LiteralPath (Join-Path $script:root 'installer/config/jaws-installation-state.dev.json') -Raw) | Should -Be $script:devBefore
        $catalog = Get-Content -LiteralPath (Join-Path $script:root 'installer/.local/jaws-specialist-catalog.lab1.generated.json') -Raw | ConvertFrom-Json
        @($catalog.Specialists)[0].ComputeEnvironmentId | Should -Be 'jaws-vm-specialist-lab1'
        @($catalog.Specialists)[0].Image | Should -Be $script:image
        $accept = & (Join-Path $script:root 'installer/Install-JawsStepD.ps1') -Mode Accept -EnvironmentName 'lab1' *>&1 | Out-String
        $accept | Should -Match 'STEP-D ACCEPTANCE PASS'
        $accept | Should -Match 'Customer installation accepted: false'
        $accept | Should -Match 'Result: PASS'
        $accept | Should -Match 'Ready for next step: false'
        $accept | Should -Match 'Next step: Step E is not installable'
        $accept | Should -Match 'Evidence: .+jaws-step-d-acceptance\.lab1\.generated\.json'
        $report = Get-Content -LiteralPath (Join-Path $script:root 'installer/.local/jaws-step-d-acceptance.lab1.generated.json') -Raw | ConvertFrom-Json
        $report.Result | Should -Be 'PASS'
        $report.LiveAzureRead | Should -BeTrue
        $report.CustomerInstallationAccepted | Should -BeFalse
        $report.FreshSubscriptionReceiptArchived | Should -BeFalse
        $report.AzureWrites | Should -Be 0
    }

    It 'binds the existing dev specialist and does not post a second agent' {
        Write-StepDAcceptance 'dev'
        $output = & (Join-Path $script:root 'installer/Install-JawsStepD.ps1') -Mode Install -EnvironmentName 'dev' -AcknowledgeStepDInstall *>&1 | Out-String
        $output | Should -Match 'STEP-D INSTALL PASS'
        $output | Should -Match 'Azure writes: 0'
        $output | Should -Match 'Browser toolbox: not provisioned'
        $output | Should -Match 'Result: PASS'
        $log = Get-Content -LiteralPath (Join-Path $script:state 'log.txt') -Raw
        $log | Should -Match 'jaws-investigation-dev/versions/1'
        $log | Should -Not -Match '--method POST'
        $log | Should -Not -Match '--method post'
        $catalog = Get-Content -LiteralPath (Join-Path $script:root 'installer/.local/jaws-specialist-catalog.dev.generated.json') -Raw | ConvertFrom-Json
        @($catalog.Specialists)[0].FoundryAgentName | Should -Be 'jaws-investigation-dev'
        @($catalog.Specialists)[0].ComputeEnvironmentId | Should -Be 'jaws-investigation-dev'
        (Get-Content -LiteralPath (Join-Path $script:root 'installer/config/jaws-installation-state.dev.json') -Raw) | Should -Be $script:devBefore
    }

    It 'updates the browser allow-list without rebuilding an image' {
        Write-StepDReceipt
        $scriptPath = Join-Path $script:root 'installer/Set-JawsBrowserAllowList.ps1'
        $url = 'https://portal.contoso.example/reports'
        $denied = ''
        try {
            & $scriptPath -Action Add -Url $url -EnvironmentName 'lab1' *>&1 | ForEach-Object { $denied += "$_`n" }
            throw 'Allow-list returned without the acknowledgement.'
        } catch {
            $denied += $_.Exception.Message
        }
        $denied | Should -Match 'JAWS-STEP-D-033'
        $added = & $scriptPath -Action Add -Url $url -EnvironmentName 'lab1' -AcknowledgeBrowserAllowList *>&1 | Out-String
        $added | Should -Match 'Browser allow-list: Add'
        $added | Should -Match 'Azure writes: 1'
        $added | Should -Match 'Customer installation accepted: false'
        $path = Join-Path $script:root 'installer/.local/jaws-browser-allow-list.lab1.json'
        $file = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        @($file.Urls) | Should -Contain $url
        $removed = & $scriptPath -Action Remove -Url $url -EnvironmentName 'lab1' -AcknowledgeBrowserAllowList *>&1 | Out-String
        $removed | Should -Match 'Entries: 0'
        $devDenied = ''
        try {
            & $scriptPath -Action Add -Url $url -EnvironmentName 'dev' -AcknowledgeBrowserAllowList *>&1 | ForEach-Object { $devDenied += "$_`n" }
            throw 'Dev allow-list returned.'
        } catch {
            $devDenied += $_.Exception.Message
        }
        $devDenied | Should -Match 'JAWS-STEP-D-033'
        $devDenied | Should -Match 'accepted dev project'
    }

    It 'reads one JSON value when az leaves ANSI codes and a warning after it' {
        $ansi = [char]27 + '[0m'
        InModuleScope StepDInstall -Parameters @{ Ansi = $ansi } {
            $payload = "warning before`n{`"name`":`"jaws-vm-specialist-lab1`",`"note`":`"brace } inside`"}`n$($Ansi)WARNING after"
            $parsed = ConvertFrom-JawsStepDJson $payload
            $parsed.name | Should -Be 'jaws-vm-specialist-lab1'
            $parsed.note | Should -Be 'brace } inside'
            $array = ConvertFrom-JawsStepDJson ("log`n[{`"a`":1}]" + $Ansi)
            $array[0].a | Should -Be 1
        }
        InModuleScope StepDBrowser -Parameters @{ Ansi = $ansi } {
            $parsed = ConvertFrom-JawsBrowserJson ("{`"digest`":`"sha256:abc`"}" + $Ansi)
            $parsed.digest | Should -Be 'sha256:abc'
        }
    }

    It 'accepts a Foundry-namespaced browser tool and rejects a different operation' {
        InModuleScope StepDBrowser {
            Test-JawsBrowserToolName -Name 'browser_open' -Operation 'browser_open' | Should -BeTrue
            Test-JawsBrowserToolName -Name 'jaws-browser.browser_open' -Operation 'browser_open' | Should -BeTrue
            Test-JawsBrowserToolName -Name 'jaws-browser-tools___browser_open' -Operation 'browser_open' | Should -BeTrue
            Test-JawsBrowserToolName -Name 'jaws-browser_browser_navigate' -Operation 'browser_navigate' | Should -BeTrue
            Test-JawsBrowserToolName -Name 'browser_snapshot' -Operation 'browser_open' | Should -BeFalse
            Test-JawsBrowserToolName -Name 'browser_navigate' -Operation 'browser_open' | Should -BeFalse
        }
    }

    It 'reads versions.latest as a version object or a version string' {
        InModuleScope StepDBrowser {
            $asObject = [pscustomobject]@{ versions = [pscustomobject]@{ latest = [pscustomobject]@{ agent_guid = 'abc'; version = 3 } } }
            Get-JawsBrowserLatestVersion $asObject | Should -Be '3'
            $asString = [pscustomobject]@{ versions = [pscustomobject]@{ latest = '2' } }
            Get-JawsBrowserLatestVersion $asString | Should -Be '2'
        }
    }

    It 'reads a Foundry response when az leaves ANSI after the JSON' {
        InModuleScope StepDBrowser {
            $env:JAWS_STEPD_STUB_ANSI_SUFFIX = [char]27 + '[0m'
            $response = Invoke-JawsBrowserSupervisorResponse -Url 'https://example.test/agents/jaws-supervisor-lab1/endpoint/protocols/openai/responses?api-version=v1' -Body '{"input":"ping"}' -FailureCode 'JAWS-STEP-D-040'
            $response.id | Should -Be 'resp_private'
            @($response.output | Where-Object { $_.type -eq 'function_call' -and $_.name -eq 'browser_open' }).Count | Should -Be 1
        }
    }

    It 'treats a missing ACR tag as absent and still fails without -AllowMissing' {
        InModuleScope StepDBrowser {
            $arguments = @('acr','repository','show','--name','jawsacrlab1','--image','jaws/browser:step-d','--output','json')
            $env:JAWS_STEPD_STUB_MISSING = 'Error: the specified tag does not exist.'
            $result = Invoke-JawsBrowserAz -AllowMissing -Arguments $arguments
            $result | Should -BeNullOrEmpty
            { Invoke-JawsBrowserAz -Arguments $arguments } | Should -Throw '*JAWS-STEP-D-AZ-001*'
        }
    }

    It 'treats Foundry not_found and Not Found as a missing specialist and still fails without -AllowMissing' {
        InModuleScope StepDInstall {
            $arguments = @('rest','--method','GET','--url','https://example.test/agents/jaws-vm-specialist-lab9/versions/1','--output','json')
            foreach ($body in @('{"error":{"code":"not_found"}}', 'Not Found')) {
                $env:JAWS_STEPD_STUB_MISSING = $body
                $result = Invoke-JawsStepDAz -AllowMissing -Arguments $arguments
                $result | Should -BeNullOrEmpty
            }
            $env:JAWS_STEPD_STUB_MISSING = '{"error":{"code":"not_found","message":"Not Found"}}'
            { Invoke-JawsStepDAz -Arguments $arguments } | Should -Throw '*JAWS-STEP-D-AZ-001*'
        }
    }

    It 'publishes a later Supervisor image, proves the private path, and keeps Step E closed' {
        Write-StepDAcceptance 'cap1'
        Write-StepDReceipt -EnvironmentName 'cap1' -FoundryAccountName 'jaws-foundry-cap1' -ProjectName 'jaws-cap1' -AgentName 'jaws-supervisor-cap1'
        & (Join-Path $script:root 'installer/Install-JawsStepD.ps1') -Mode Install -EnvironmentName 'cap1' -AcknowledgeStepDInstall | Out-Null
        $publish = Join-Path $script:root 'installer/Publish-JawsSupervisorBrowserImage.ps1'
        $private = Join-Path $script:root 'installer/Test-JawsBrowserPrivatePath.ps1'
        $capability = Join-Path $script:root 'installer/Test-JawsBrowserCapability.ps1'
        $url = 'https://portal.contoso.example/reports'
        $denied = ''
        try {
            & $publish -EnvironmentName 'cap1' *>&1 | ForEach-Object { $denied += "$_`n" }
            throw 'Image publish returned without the acknowledgement.'
        } catch { $denied += $_.Exception.Message }
        $denied | Should -Match 'JAWS-STEP-D-035'
        $denied | Should -Match 'STEP-D BROWSER IMAGE FAIL'
        $early = ''
        try {
            & $private -EnvironmentName 'cap1' -AcknowledgeBrowserPrivatePath *>&1 | ForEach-Object { $early += "$_`n" }
            throw 'Private path returned before the image publish.'
        } catch { $early += $_.Exception.Message }
        $early | Should -Match 'JAWS-STEP-D-036'
        $devDenied = ''
        try {
            & $publish -EnvironmentName 'dev' -AcknowledgeSupervisorBrowserImage *>&1 | ForEach-Object { $devDenied += "$_`n" }
            throw 'Dev image publish returned.'
        } catch { $devDenied += $_.Exception.Message }
        $devDenied | Should -Match 'JAWS-STEP-D-035'
        $devDenied | Should -Match 'accepted dev project'

        $worldPath = Join-Path $script:state 'world.json'
        $world = Get-Content -LiteralPath $worldPath -Raw | ConvertFrom-Json
        $versionTwo = $world.versions.'jaws-supervisor-cap1'.'2'
        $versionTwo.definition.environment_variables | Add-Member -NotePropertyName JAWS_INVESTIGATION_TOOLBOX_NAME -NotePropertyValue 'jaws-investigation-a2a-tools' -Force
        $world | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $worldPath -Encoding utf8

        $built = & $publish -EnvironmentName 'cap1' -AcknowledgeSupervisorBrowserImage *>&1 | Out-String
        $built | Should -Match 'STEP-D BROWSER IMAGE PASS'
        $built | Should -Match 'Customer installation accepted: false'
        $built | Should -Match 'Supervisor image rebuilt: true'
        $built | Should -Match 'Supervisor image built this run: True'
        $built | Should -Match 'Supervisor version 1 unchanged: true'
        $built | Should -Match 'Ready for next step: true'
        $built | Should -Match 'Next step: Test-JawsBrowserPrivatePath.ps1'
        $built | Should -Not -Match 'Azure writes: 0'
        $log = Get-Content -LiteralPath (Join-Path $script:state 'log.txt') -Raw
        $log | Should -Match 'src/Jaws\.Supervisor\.Host/Dockerfile'
        $log | Should -Match 'jaws/supervisor:browser-'
        $log | Should -Match 'linux/amd64'
        $log | Should -Match 'acr build .*--no-logs'
        $log | Should -Not -Match '\bdocker\b'
        $world = Get-Content -LiteralPath $worldPath -Raw | ConvertFrom-Json
        $versionOne = $world.versions.'jaws-supervisor-cap1'.'1'
        [string]$versionOne.definition.container_configuration.image | Should -Match 'sha256:a{64}$'
        $versionOne.definition.environment_variables.PSObject.Properties['JAWS_BROWSER_TOOLBOX_NAME'] | Should -BeNullOrEmpty
        $published = $world.versions.'jaws-supervisor-cap1'.'3'
        [string]$published.definition.container_configuration.image | Should -Match 'sha256:c{64}$'
        [string]$published.definition.environment_variables.JAWS_BROWSER_TOOLBOX_NAME | Should -Be 'jaws-browser-tools'
        [string]$published.definition.environment_variables.JAWS_INVESTIGATION_TOOLBOX_NAME | Should -Be 'jaws-investigation-a2a-tools'
        $builds = ([regex]::Matches($log, 'acr build')).Count
        $again = & $publish -EnvironmentName 'cap1' -AcknowledgeSupervisorBrowserImage *>&1 | Out-String
        $again | Should -Match 'Azure writes: 0'
        $again | Should -Match 'Supervisor image built this run: False'
        $log = Get-Content -LiteralPath (Join-Path $script:state 'log.txt') -Raw
        ([regex]::Matches($log, 'acr build')).Count | Should -Be $builds

        $env:JAWS_STEPD_STUB_BROWSER_CALL = 'unreachable'
        $blocked = ''
        try {
            & $private -EnvironmentName 'cap1' -AcknowledgeBrowserPrivatePath *>&1 | ForEach-Object { $blocked += "$_`n" }
            throw 'Unreachable private path returned.'
        } catch { $blocked += $_.Exception.Message }
        $blocked | Should -Match 'JAWS-STEP-D-040'
        $blocked | Should -Match 'STEP-D PRIVATE PATH FAIL'
        $blocked | Should -Match 'Ready for next step: false'
        $pathReceipt = Get-Content -LiteralPath (Join-Path $script:root 'installer/.local/jaws-step-d-browser-private-path.cap1.generated.json') -Raw | ConvertFrom-Json
        $pathReceipt.PrivatePathProven | Should -BeFalse

        $env:JAWS_STEPD_STUB_BROWSER_CALL = 'private-ok'
        $env:JAWS_STEPD_STUB_TOOL_PREFIX = 'jaws-browser.'
        $opened = & $private -EnvironmentName 'cap1' -AcknowledgeBrowserPrivatePath *>&1 | Out-String
        Remove-Item Env:JAWS_STEPD_STUB_TOOL_PREFIX -ErrorAction SilentlyContinue
        $opened | Should -Match 'STEP-D PRIVATE PATH PASS'
        $opened | Should -Match 'Customer installation accepted: false'
        $opened | Should -Match 'Navigation attempted: false'
        $opened | Should -Match 'Ready for next step: true'
        $opened | Should -Match 'Next step: Set-JawsBrowserAllowList.ps1, then Test-JawsBrowserCapability.ps1'
        $world = Get-Content -LiteralPath $worldPath -Raw | ConvertFrom-Json
        [string]$world.'last-response-body' | Should -Match 'browser_open'
        [string]$world.'last-response-body' | Should -Not -Match 'browser_navigate'
        $pathReceipt = Get-Content -LiteralPath (Join-Path $script:root 'installer/.local/jaws-step-d-browser-private-path.cap1.generated.json') -Raw | ConvertFrom-Json
        $pathReceipt.PrivatePathProven | Should -BeTrue
        $pathReceipt.BrowserNavigateCalls | Should -Be 0
        $pathReceipt.CustomerInstallationAccepted | Should -BeFalse

        $staleAllow = Join-Path $script:root 'installer/.local/jaws-browser-allow-list.cap1.json'
        if (Test-Path -LiteralPath $staleAllow) { Remove-Item -LiteralPath $staleAllow }
        $missingUrl = ''
        try {
            & $capability -EnvironmentName 'cap1' -Url $url -AcknowledgeBrowserCapability *>&1 | ForEach-Object { $missingUrl += "$_`n" }
            throw 'Capability returned before the allow-list update.'
        } catch { $missingUrl += $_.Exception.Message }
        $missingUrl | Should -Match 'JAWS-STEP-D-039'
        & (Join-Path $script:root 'installer/Set-JawsBrowserAllowList.ps1') -Action Add -Url $url -EnvironmentName 'cap1' -AcknowledgeBrowserAllowList | Out-Null

        $env:JAWS_STEPD_STUB_BROWSER_CALL = 'missing-markers'
        $markers = ''
        try {
            & $capability -EnvironmentName 'cap1' -Url $url -AcknowledgeBrowserCapability *>&1 | ForEach-Object { $markers += "$_`n" }
            throw 'Capability returned without the markers.'
        } catch { $markers += $_.Exception.Message }
        $markers | Should -Match 'JAWS-STEP-D-042'
        $markers | Should -Match 'STEP-D BROWSER CAPABILITY FAIL'

        $env:JAWS_STEPD_STUB_BROWSER_CALL = 'capability'
        $done = & $capability -EnvironmentName 'cap1' -Url $url -AcknowledgeBrowserCapability *>&1 | Out-String
        $done | Should -Match 'STEP-D BROWSER CAPABILITY PASS'
        $done | Should -Match 'Customer installation accepted: false'
        $done | Should -Match 'Ready for next step: false'
        $done | Should -Match 'Next step: Step E is not installable'
        $world = Get-Content -LiteralPath $worldPath -Raw | ConvertFrom-Json
        $urlPattern = [regex]::Escape($url)
        [string]$world.'last-response-body' | Should -Match $urlPattern
        [string]$world.'last-response-body' | Should -Match 'allow_list_rejected'
        $report = Get-Content -LiteralPath (Join-Path $script:root 'installer/.local/jaws-step-d-browser-capability.cap1.generated.json') -Raw | ConvertFrom-Json
        $report.CapabilityProven | Should -BeTrue
        $report.ExtractedValueObserved | Should -BeTrue
        $report.AllowListRejectionObserved | Should -BeTrue
        $report.CustomerInstallationAccepted | Should -BeFalse
        $report.LiveNavigationClaimed | Should -BeFalse
        $report.VaultLoginClaimed | Should -BeFalse
        $report.SignatureValidationClaimed | Should -BeFalse
        $report.FreshSubscriptionReceiptArchived | Should -BeFalse
    }

    It 'refuses a Supervisor image that is neither version 1 nor the published browser image' {
        Write-StepDAcceptance 'cap2'
        Write-StepDReceipt -EnvironmentName 'cap2' -FoundryAccountName 'jaws-foundry-cap2' -ProjectName 'jaws-cap2' -AgentName 'jaws-supervisor-cap2'
        & (Join-Path $script:root 'installer/Install-JawsStepD.ps1') -Mode Install -EnvironmentName 'cap2' -AcknowledgeStepDInstall | Out-Null
        $worldPath = Join-Path $script:state 'world.json'
        $world = Get-Content -LiteralPath $worldPath -Raw | ConvertFrom-Json
        $world.versions.'jaws-supervisor-cap2'.'2'.definition.container_configuration.image = 'other.azurecr.io/jaws/supervisor@sha256:' + ('d' * 64)
        $world | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $worldPath -Encoding utf8
        $builds = ([regex]::Matches((Get-Content -LiteralPath (Join-Path $script:state 'log.txt') -Raw), 'acr build')).Count
        $output = ''
        try {
            & (Join-Path $script:root 'installer/Publish-JawsSupervisorBrowserImage.ps1') -EnvironmentName 'cap2' -AcknowledgeSupervisorBrowserImage *>&1 | ForEach-Object { $output += "$_`n" }
            throw 'Publish returned for a foreign image.'
        } catch { $output += $_.Exception.Message }
        $output | Should -Match 'JAWS-STEP-D-035'
        $output | Should -Match 'differs from version 1'
        ([regex]::Matches((Get-Content -LiteralPath (Join-Path $script:state 'log.txt') -Raw), 'acr build')).Count | Should -Be $builds
    }
}
