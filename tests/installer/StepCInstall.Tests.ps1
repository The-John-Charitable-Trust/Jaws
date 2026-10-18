BeforeAll {
    $script:root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    Import-Module (Join-Path $script:root 'installer/modules/StepCInstall.psm1') -Force
    $script:orchestrator = Get-Content -LiteralPath (Join-Path $script:root 'installer/Install-JawsThroughStepC.ps1') -Raw
    $script:acceptance = Get-Content -LiteralPath (Join-Path $script:root 'installer/Test-JawsStepCDelegation.ps1') -Raw
    $script:dispatcher = Get-Content -LiteralPath (Join-Path $script:root 'installer/Install-JawsStepC.ps1') -Raw
    $script:retired = Get-Content -LiteralPath (Join-Path $script:root 'installer/Release-JawsSupervisorDraft.ps1') -Raw
    $script:sub = '22222222-2222-2222-2222-222222222222'
    $script:image = 'jawsacrlab1.azurecr.io/jaws/supervisor@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    $script:stub = Join-Path ([System.IO.Path]::GetTempPath()) ('jaws-stepc-stub-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:stub | Out-Null
    Set-Content -LiteralPath (Join-Path $script:stub 'az') -Encoding ascii -Value @'
#!/bin/bash
exec python3 "$0.py" "$@"
'@
    Set-Content -LiteralPath (Join-Path $script:stub 'az.py') -Encoding utf8 -Value @'
import json, os, sys
args = sys.argv[1:]
state_dir = os.environ["JAWS_STEPC_STUB_STATE"]
sub = os.environ["JAWS_STEPC_STUB_SUB"]
image = os.environ["JAWS_STEPC_STUB_IMAGE"]
v1_toolbox = os.environ.get("JAWS_STEPC_STUB_V1_TOOLBOX", "") == "1"
os.makedirs(state_dir, exist_ok=True)
with open(os.path.join(state_dir, "log.txt"), "a", encoding="utf-8") as handle:
    handle.write(" ".join(args) + "\n")
world_path = os.path.join(state_dir, "world.json")
world = {"planner": False, "patched": False, "connection": None, "toolbox": False, "latest": "1", "roles": []}
if os.path.exists(world_path):
    with open(world_path, encoding="utf-8") as handle:
        world = json.load(handle)

def save():
    with open(world_path, "w", encoding="utf-8") as handle:
        json.dump(world, handle)

def emit(payload, code=0):
    print(json.dumps(payload))
    sys.exit(code)

def missing():
    print("404 ResourceNotFound", file=sys.stderr)
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

conn_id = f"/subscriptions/{sub}/resourceGroups/rg-jaws-lab1/providers/Microsoft.CognitiveServices/accounts/jaws-foundry-lab1/projects/jaws-lab1/connections/jaws-investigation-a2a-lab1"
scope = f"/subscriptions/{sub}/resourceGroups/rg-jaws-lab1/providers/Microsoft.CognitiveServices/accounts/jaws-foundry-lab1/projects/jaws-lab1"
target = "https://jaws-foundry-lab1.services.ai.azure.com/api/projects/jaws-lab1/agents/jaws-investigation-planner-lab1/endpoint/protocols/a2a"
role = "eed3b665-ab3a-47b6-8f48-c9382fb1dad6"
principal = "11111111-1111-1111-1111-111111111111"

def v1():
    env = {"AZURE_AI_MODEL_DEPLOYMENT_NAME": "gpt-5-mini"}
    if v1_toolbox:
        env["JAWS_INVESTIGATION_TOOLBOX_NAME"] = "jaws-investigation-a2a-tools"
    return {
        "name": "jaws-supervisor-lab1", "status": "active", "draft": False, "version": "1",
        "definition": {
            "kind": "hosted", "cpu": "1", "memory": "2Gi",
            "container_configuration": {"image": image},
            "environment_variables": env,
        },
    }

def v2():
    return {
        "name": "jaws-supervisor-lab1", "status": "active", "draft": False, "version": "2",
        "definition": {
            "kind": "hosted", "cpu": "1", "memory": "2Gi",
            "container_configuration": {"image": image},
            "environment_variables": {
                "AZURE_AI_MODEL_DEPLOYMENT_NAME": "gpt-5-mini",
                "JAWS_INVESTIGATION_TOOLBOX_NAME": "jaws-investigation-a2a-tools",
            },
        },
        "instance_identity": {"principal_id": principal, "client_id": "44444444-4444-4444-4444-444444444444"},
        "blueprint": {"client_id": "55555555-5555-5555-5555-555555555555"},
    }

if args[:2] == ["account", "show"]:
    emit({"id": sub, "name": "stub", "state": "Enabled"})
if args[:3] == ["cognitiveservices", "account", "show"]:
    emit({"name": "jaws-foundry-lab1", "kind": "AIServices", "provisioningState": "Succeeded"})
if args[:3] == ["role", "assignment", "list"]:
    emit(world["roles"])
if args[:3] == ["role", "assignment", "create"]:
    world["roles"] = [{
        "roleDefinitionId": f"/subscriptions/{sub}/providers/Microsoft.Authorization/roleDefinitions/{role}",
        "scope": flag("--scope") or scope,
        "principalId": principal,
    }]
    save()
    emit(world["roles"][0])

method = flag("--method").lower()
url = flag("--url")
if "jaws-foundry-dev" in url or "jawsregistrydev001" in url or "jaws-investigation-dev" in url:
    missing()
if method == "get" and "/versions/1" in url and "jaws-supervisor-lab1" in url:
    emit(v1())
if method == "get" and "/versions/2" in url and "jaws-supervisor-lab1" in url:
    if world["latest"] != "2":
        missing()
    emit(v2())
if method == "get" and url.endswith("/agents/jaws-supervisor-lab1?api-version=v1"):
    emit({"name": "jaws-supervisor-lab1", "versions": {"latest": world["latest"]}})
if method == "post" and "/agents/jaws-supervisor-lab1/versions?" in url:
    world["latest"] = "2"
    save()
    emit(v2())
if method == "get" and url.endswith("/agents/jaws-investigation-planner-lab1?api-version=v1"):
    if not world["planner"]:
        missing()
    emit({"name": "jaws-investigation-planner-lab1", "agent_endpoint": {"protocols": ["responses", "a2a"]}})
if method == "get" and "/agents/jaws-investigation-planner-lab1/versions/1" in url:
    if not world["patched"]:
        missing()
    emit({"name": "jaws-investigation-planner-lab1", "status": "active", "definition": {"kind": "prompt", "model": "gpt-5-mini", "instructions": "INVESTIGATION PLANNING ONLY"}})
if method == "post" and "/agents?api-version=v1" in url:
    world["planner"] = True
    save()
    emit({"name": "jaws-investigation-planner-lab1"})
if method == "patch" and "/agents/jaws-investigation-planner-lab1?" in url:
    world["patched"] = True
    save()
    emit({"name": "jaws-investigation-planner-lab1"})
if method in ("get", "put") and "connections/jaws-investigation-a2a-lab1" in url:
    if method == "put":
        stored = json.loads(body_text())
        stored["id"] = conn_id
        world["connection"] = stored
        save()
        with open(os.path.join(state_dir, "connection.json"), "w", encoding="utf-8") as handle:
            handle.write(body_text())
        emit(stored)
    if not world["connection"]:
        missing()
    emit(world["connection"])
if method == "get" and "/toolboxes/jaws-investigation-a2a-tools/versions" in url:
    if not world["toolbox"]:
        missing()
    emit({"data": [{"name": "jaws-investigation-a2a-tools", "version": "1", "tools": [{"type": "a2a", "a2a_version": "1.0", "project_connection_id": conn_id}]}]})
if method == "get" and "/toolboxes/jaws-investigation-a2a-tools?" in url:
    if not world["toolbox"]:
        missing()
    emit({"name": "jaws-investigation-a2a-tools", "default_version": "1"})
if method == "post" and "/toolboxes/jaws-investigation-a2a-tools/versions" in url:
    world["toolbox"] = True
    save()
    emit({"name": "jaws-investigation-a2a-tools", "version": "1"})
if method == "post" and "/protocols/openai/responses" in url:
    limit = int(os.environ.get("JAWS_STEPC_STUB_RATE_LIMITS", "0") or "0")
    used_path = os.path.join(state_dir, "rate-limits-used")
    used = int(open(used_path, encoding="utf-8").read()) if os.path.exists(used_path) else 0
    output = [
        {"type": "function_call", "call_id": "call_stub", "name": "jaws-investigation-a2a-lab1___SendMessage"},
        {"type": "function_call_output", "call_id": "call_stub", "status": "completed", "output": "TASK_STATE_COMPLETED resp_stubplanner123 read-only plan"},
    ]
    if used < limit:
        open(used_path, "w", encoding="utf-8").write(str(used + 1))
        emit({
            "id": "caresp_stub_limited",
            "status": "failed",
            "error": {
                "code": "server_error",
                "message": "Model deployment rate limit exceeded. Your requests to gpt-5-mini for gpt-5-mini in eastus have exceeded request rate limit.",
            },
            "output": output,
        })
    emit({"id": "caresp_stub", "status": "completed", "output": output})
print("unexpected " + " ".join(args), file=sys.stderr)
sys.exit(9)
'@
    chmod +x (Join-Path $script:stub 'az') | Out-Null
}

Describe 'Step C install correction policy' {
    It 'does not correct anything while validating' {
        Get-JawsStepCCorrection -Gate Planner -ErrorMessage 'JAWS-PLANNER-003: missing' -Mode Validate | Should -BeNullOrEmpty
        Get-JawsStepCCorrection -Gate Connection -ErrorMessage 'JAWS-DELEGATE-004: Connection still targets the hosted Investigation agent.' -Mode Validate | Should -BeNullOrEmpty
    }
    It 'creates a missing planner and does not overwrite a mismatch' {
        Get-JawsStepCCorrection -Gate Planner -ErrorMessage 'JAWS-PLANNER-003: Prompt planner is not the expected active A2A target.' -Mode Install | Should -Be 'CreatePlanner'
        Get-JawsStepCCorrection -Gate Planner -ErrorMessage 'JAWS-PLANNER-004: Planner exists but does not match the expected prompt agent. No overwrite.' -Mode Install | Should -BeNullOrEmpty
    }
    It 'retargets only a connection that still points at the hosted agent' {
        Get-JawsStepCCorrection -Gate Connection -ErrorMessage 'JAWS-DELEGATE-003: Expected prompt-agent connection missing or mismatched.' -Mode Install | Should -Be 'CreateConnection'
        Get-JawsStepCCorrection -Gate Connection -ErrorMessage 'JAWS-DELEGATE-004: Connection still targets the hosted Investigation agent. Foundry rejects A2A operations on hosted agents. Run -Mode Retarget with the plan SHA.' -Mode Install | Should -Be 'RetargetConnection'
        Get-JawsStepCCorrection -Gate Connection -ErrorMessage 'JAWS-DELEGATE-004: Existing connection differs; refusing to overwrite.' -Mode Install | Should -BeNullOrEmpty
    }
    It 'repairs only the known toolbox and role gaps' {
        Get-JawsStepCCorrection -Gate Toolbox -ErrorMessage 'JAWS-TOOLBOX-007: Toolbox version not verifiable.' -Mode Install | Should -Be 'CreateToolbox'
        Get-JawsStepCCorrection -Gate Toolbox -ErrorMessage 'JAWS-TOOLBOX-008: Existing toolbox version configuration mismatch. No writes.' -Mode Install | Should -Be 'RepairToolbox'
        Get-JawsStepCCorrection -Gate Toolbox -ErrorMessage 'JAWS-TOOLBOX-003: Connection target drift; refusing toolbox installation.' -Mode Install | Should -BeNullOrEmpty
        Get-JawsStepCCorrection -Gate Rbac -ErrorMessage 'JAWS-DELEGATE-RBAC-007: Routed Supervisor lacks one exact Foundry Agent Consumer assignment at project scope.' -Mode Install | Should -Be 'AssignConsumerRole'
        Get-JawsStepCCorrection -Gate Rbac -ErrorMessage 'JAWS-DELEGATE-RBAC-006: Duplicate matching role assignments detected; no write performed.' -Mode Install | Should -BeNullOrEmpty
    }
    It 'never treats the Supervisor route or identity context as self-correcting on the dev project' {
        Get-JawsStepCCorrection -Gate Supervisor -ErrorMessage 'JAWS-INSTALL-C-007: Routed Supervisor is not the approved release.' -Mode Install | Should -BeNullOrEmpty
        Get-JawsStepCCorrection -Gate Identity -ErrorMessage 'JAWS-A2A-IDENTITY-002: Expected identity or stored connection configuration missing; no changes made.' -Mode Install | Should -BeNullOrEmpty
        Get-JawsStepCFromStepBCorrection -Gate Supervisor -ErrorMessage 'JAWS-INSTALL-C-007: Routed Supervisor is not the approved release.' -Mode Install | Should -BeNullOrEmpty
        Get-JawsStepCFromStepBCorrection -Gate Supervisor -ErrorMessage 'JAWS-INSTALL-C-018: Supervisor v1 changed.' -Mode Install | Should -BeNullOrEmpty
        Get-JawsStepCFromStepBCorrection -Gate Supervisor -ErrorMessage 'JAWS-INSTALL-C-005: Latest routing is not a released Supervisor version after v1.' -Mode Install | Should -Be 'PublishSupervisorRoute'
        Get-JawsStepCFromStepBCorrection -Gate Toolbox -ErrorMessage 'JAWS-TOOLBOX-008: Existing toolbox version configuration mismatch. No writes.' -Mode Install | Should -BeNullOrEmpty
    }
    It 'closes only after acceptance and blocks on any failed gate' {
        $ready = @([pscustomobject]@{Result='Passed'},[pscustomobject]@{Result='Repaired'})
        Get-JawsStepCInstallStatus -GateResults $ready -Acceptance Skipped | Should -Be 'VALIDATED'
        Get-JawsStepCInstallStatus -GateResults $ready -Acceptance Passed | Should -Be 'CLOSED'
        Get-JawsStepCInstallStatus -GateResults (@($ready) + [pscustomobject]@{Result='Blocked'}) -Acceptance Skipped | Should -Be 'BLOCKED'
        Get-JawsStepCInstallStatus -GateResults $ready -Acceptance Failed | Should -Be 'BLOCKED'
        Get-JawsStepCInstallStatus -GateResults @() -Acceptance Passed | Should -Be 'BLOCKED'
    }
}

Describe 'Step C install orchestrator safety' {
    It 'parses and refuses an unacknowledged install before any Azure call' {
        $tokens = $null; $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:root 'installer/Install-JawsThroughStepC.ps1'), [ref]$tokens, [ref]$errors) | Out-Null
        @($errors).Count | Should -Be 0
        { & (Join-Path $script:root 'installer/Install-JawsThroughStepC.ps1') -Mode Install } | Should -Throw '*JAWS-INSTALL-C-001*'
    }
    It 'walks the gates in dependency order and posts no Supervisor version on the dev path' {
        $script:orchestrator | Should -Match '\$script:gateOrder=@\(''Prerequisites'',''State'',''InvestigationA2A'',''Planner'',''Connection'',''Toolbox'',''Rbac'',''Supervisor'',''Identity'',''Acceptance''\)'
        $script:orchestrator | Should -Not -Match 'Release-JawsSupervisor'
        $script:orchestrator | Should -Not -Match 'az role assignment create'
        $script:orchestrator | Should -Not -Match 'az rest --method (put|patch|post|delete)'
        $script:orchestrator | Should -Match 'SupervisorVersionPosted=\$false'
        $script:orchestrator | Should -Match 'Invoke-JawsAzRestGet'
        $script:orchestrator | Should -Match '\$script:gates\.ToArray\(\)'
    }
    It 'keeps acceptance behind an explicit inference acknowledgement' {
        $script:orchestrator | Should -Match 'if\(-not \$AcknowledgeInferenceCharges\)\{ return ''Skipped'' \}'
        $script:orchestrator | Should -Match 'Install-JawsThroughStepC\.ps1 -Mode Validate -AcknowledgeInferenceCharges'
        $script:acceptance | Should -Match '86c556fff7f54eb8ad81c84bc768093fd7bc083e941e9e16bbf1ea8bc0cfa289'
        $script:acceptance | Should -Not -Match '5a9cd89cfc626df4bdd2266194db14cda8fd33f46de1bfbc9c1111cde1c8af54'
        $script:acceptance | Should -Match 'store=\$false'
        $script:acceptance | Should -Match 'TaskState='
        $script:acceptance | Should -Match 'PlannerResponseId='
    }
    It 'exposes the same path from the Step C dispatcher and retires the historical release script' {
        $script:dispatcher | Should -Match 'ThroughStepC'
        $script:dispatcher | Should -Match 'Install-JawsThroughStepC.ps1'
        $script:retired | Should -Match 'JAWS-SUP-REL-010'
        $script:retired | Should -Not -Match 'az rest --method post'
    }
}

Describe 'Step C from a Step B environment' {
    BeforeAll {
        function Write-StepBFixture {
            param([string]$FoundryName = 'jaws-foundry-lab1')
            $local = Join-Path $script:root 'installer/.local'
            if (-not (Test-Path -LiteralPath $local)) { New-Item -ItemType Directory -Path $local | Out-Null }
            $subId = $script:sub
            $stateObject = [pscustomobject]@{
                SchemaVersion = '1.1'
                Platform = 'JAWS'
                InstallerVersion = '0.4.10'
                EnvironmentName = 'lab1'
                SubscriptionId = $subId
                ResourceGroupName = 'rg-jaws-lab1'
                StateAuthority = 'InstallerGenerated'
                Resources = @(
                    [pscustomobject]@{ Name = $FoundryName; Type = 'Microsoft.CognitiveServices/accounts' },
                    [pscustomobject]@{ Name = 'jaws-lab1'; Type = 'Microsoft.CognitiveServices/accounts/projects' },
                    [pscustomobject]@{ Name = 'gpt-5-mini'; Type = 'Microsoft.CognitiveServices/accounts/deployments' },
                    [pscustomobject]@{ Name = 'kvjawslab1'; Type = 'Microsoft.KeyVault/vaults' }
                )
            }
            $receipt = [pscustomobject]@{
                Status = 'STEP_B_INSTALLED'
                EnvironmentName = 'lab1'
                SubscriptionId = $subId
                ResourceGroupName = 'rg-jaws-lab1'
                Location = 'eastus'
                FoundryAccountName = $FoundryName
                ProjectName = 'jaws-lab1'
                ModelDeploymentName = 'gpt-5-mini'
                ModelName = 'gpt-5-mini'
                KeyVaultName = 'kvjawslab1'
                RegistryName = 'jawsacrlab1'
                RegistryLoginServer = 'jawsacrlab1.azurecr.io'
                Image = $script:image
                AgentName = 'jaws-supervisor-lab1'
                AgentVersion = '1'
            }
            $stateObject | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $local 'jaws-installation-state.lab1.generated.json') -Encoding utf8
            $receipt | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $local 'jaws-step-b-install.lab1.generated.json') -Encoding utf8
        }
    }
    BeforeEach {
        $script:state = Join-Path $script:stub ('state-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:state | Out-Null
        $script:savedPath = $env:PATH
        $script:savedState = $env:JAWS_STEPC_STUB_STATE
        $script:savedSub = $env:JAWS_STEPC_STUB_SUB
        $script:savedImage = $env:JAWS_STEPC_STUB_IMAGE
        $script:savedToolbox = $env:JAWS_STEPC_STUB_V1_TOOLBOX
        $script:savedPoll = $env:JAWS_STEPC_POLL_SECONDS
        $script:savedLimits = $env:JAWS_STEPC_STUB_RATE_LIMITS
        $script:savedWait = $env:JAWS_STEPC_RATE_LIMIT_WAIT_SECONDS
        $env:JAWS_STEPC_STUB_STATE = $script:state
        $env:JAWS_STEPC_STUB_SUB = $script:sub
        $env:JAWS_STEPC_STUB_IMAGE = $script:image
        $env:JAWS_STEPC_STUB_V1_TOOLBOX = '0'
        $env:JAWS_STEPC_POLL_SECONDS = '0'
        $env:JAWS_STEPC_RATE_LIMIT_WAIT_SECONDS = '0'
        Remove-Item Env:JAWS_STEPC_STUB_RATE_LIMITS -ErrorAction SilentlyContinue
        $env:PATH = $script:stub + [System.IO.Path]::PathSeparator + $env:PATH
        $script:devBefore = Get-Content -LiteralPath (Join-Path $script:root 'installer/config/jaws-installation-state.dev.json') -Raw
    }
    AfterEach {
        $env:PATH = $script:savedPath
        foreach ($pair in @(
            @{ Name = 'JAWS_STEPC_STUB_STATE'; Value = $script:savedState },
            @{ Name = 'JAWS_STEPC_STUB_SUB'; Value = $script:savedSub },
            @{ Name = 'JAWS_STEPC_STUB_IMAGE'; Value = $script:savedImage },
            @{ Name = 'JAWS_STEPC_STUB_V1_TOOLBOX'; Value = $script:savedToolbox },
            @{ Name = 'JAWS_STEPC_POLL_SECONDS'; Value = $script:savedPoll },
            @{ Name = 'JAWS_STEPC_STUB_RATE_LIMITS'; Value = $script:savedLimits },
            @{ Name = 'JAWS_STEPC_RATE_LIMIT_WAIT_SECONDS'; Value = $script:savedWait }
        )) {
            if ($null -eq $pair.Value) { Remove-Item "Env:$($pair.Name)" -ErrorAction SilentlyContinue } else { Set-Item "Env:$($pair.Name)" $pair.Value }
        }
        (Get-Content -LiteralPath (Join-Path $script:root 'installer/config/jaws-installation-state.dev.json') -Raw) | Should -Be $script:devBefore
    }

    It 'refuses an unacknowledged install for a Step B environment before Azure' {
        Write-StepBFixture
        { & (Join-Path $script:root 'installer/Install-JawsThroughStepC.ps1') -Mode Install -EnvironmentName 'lab1' } | Should -Throw '*JAWS-INSTALL-C-001*'
        Test-Path -LiteralPath (Join-Path $script:state 'log.txt') | Should -BeFalse
    }

    It 'fails closed when the Step B receipt is missing and does not call Azure' {
        Remove-Item -LiteralPath (Join-Path $script:root 'installer/.local/jaws-step-b-install.lab1.generated.json') -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath (Join-Path $script:root 'installer/.local/jaws-installation-state.lab1.generated.json') -ErrorAction SilentlyContinue
        { & (Join-Path $script:root 'installer/Install-JawsThroughStepC.ps1') -Mode Validate -EnvironmentName 'lab1' } | Should -Throw '*JAWS-INSTALL-C-016*'
        Test-Path -LiteralPath (Join-Path $script:state 'log.txt') | Should -BeFalse
    }

    It 'refuses a Step B receipt that names the dev Foundry account' {
        Write-StepBFixture -FoundryName 'jaws-foundry-dev'
        { & (Join-Path $script:root 'installer/Install-JawsThroughStepC.ps1') -Mode Validate -EnvironmentName 'lab1' } | Should -Throw '*JAWS-INSTALL-C-017*'
        Test-Path -LiteralPath (Join-Path $script:state 'log.txt') | Should -BeFalse
    }

    It 'keeps the default command on the dev project' {
        $output = ''
        try { $output = & (Join-Path $script:root 'installer/Install-JawsThroughStepC.ps1') -Mode Validate *>&1 | Out-String } catch { $output += $_.Exception.Message }
        $output | Should -Match 'JAWS-'
        $log = Get-Content -LiteralPath (Join-Path $script:state 'log.txt') -Raw
        $log | Should -Match 'jaws-foundry-dev'
        $log | Should -Not -Match '--method post'
        $log | Should -Not -Match '--method put'
        $log | Should -Not -Match '--method patch'
        $log | Should -Not -Match 'jaws-foundry-lab1'
        $receipt = Get-Content -LiteralPath (Join-Path $script:root 'installer/.local/jaws-step-c-install.dev.generated.json') -Raw | ConvertFrom-Json
        $receipt.Status | Should -Be 'BLOCKED'
        $receipt.SupervisorVersionPosted | Should -BeFalse
    }

    It 'validates a Step B environment without configuration writes' {
        Write-StepBFixture
        { & (Join-Path $script:root 'installer/Install-JawsThroughStepC.ps1') -Mode Validate -EnvironmentName 'lab1' } | Should -Throw '*JAWS-PLANNER-003*'
        $log = Get-Content -LiteralPath (Join-Path $script:state 'log.txt') -Raw
        $log | Should -Not -Match '--method post'
        $log | Should -Not -Match '--method put'
        $log | Should -Not -Match '--method patch'
        $log | Should -Not -Match 'role assignment create'
        $log | Should -Not -Match 'jaws-foundry-dev'
        $log | Should -Not -Match 'jawsregistrydev001'
        $receipt = Get-Content -LiteralPath (Join-Path $script:root 'installer/.local/jaws-step-c-install.lab1.generated.json') -Raw | ConvertFrom-Json
        $receipt.Status | Should -Be 'BLOCKED'
        $receipt.Profile | Should -Be 'StepB'
        $receipt.CustomerInstallationAccepted | Should -BeFalse
        $receipt.SupervisorVersionPosted | Should -BeFalse
        $receipt.ApprovedCorrectionCount | Should -Be 0
        $receipt.ErrorCode | Should -Be 'JAWS-PLANNER-003'
        @($receipt.Gates | Where-Object { $_.Name -eq 'InvestigationA2A' }).Result | Should -Be 'Skipped'
        Test-Path -LiteralPath (Join-Path $script:root 'installer/config/jaws-installation-state.lab1.json') | Should -BeFalse
    }

    It 'refuses to repair Supervisor v1 when that version already has the toolbox' {
        Write-StepBFixture
        $env:JAWS_STEPC_STUB_V1_TOOLBOX = '1'
        { & (Join-Path $script:root 'installer/Install-JawsThroughStepC.ps1') -Mode Install -EnvironmentName 'lab1' -AcknowledgeStepCInstall } | Should -Throw '*JAWS-INSTALL-C-018*'
        $log = Get-Content -LiteralPath (Join-Path $script:state 'log.txt') -Raw
        $log | Should -Not -Match '--method post'
        $log | Should -Not -Match '--method put'
        $log | Should -Not -Match '--method patch'
        $receipt = Get-Content -LiteralPath (Join-Path $script:root 'installer/.local/jaws-step-c-install.lab1.generated.json') -Raw | ConvertFrom-Json
        $receipt.SupervisorV1Modified | Should -BeFalse
        $receipt.SupervisorVersionPosted | Should -BeFalse
    }

    It 'installs the planner, RemoteA2A connection, toolbox, and a new Supervisor version without patching v1' {
        Write-StepBFixture
        $output = & (Join-Path $script:root 'installer/Install-JawsThroughStepC.ps1') -Mode Install -EnvironmentName 'lab1' -AcknowledgeStepCInstall *>&1 | Out-String
        $output | Should -Match 'Step C install: VALIDATED'
        $output | Should -Match 'Customer installation accepted: false'
        $output | Should -Match 'Result: PASS'
        $output | Should -Match 'Ready for next step: true'
        $output | Should -Match 'Next step: Step C inference acceptance'
        $output | Should -Match 'Evidence: '
        $output | Should -Not -Match 'Live Azure read: true'
        $log = Get-Content -LiteralPath (Join-Path $script:state 'log.txt') -Raw
        $log | Should -Match '/agents/jaws-supervisor-lab1/versions\?api-version=v1'
        $log | Should -Not -Match '--method patch .*versions/1'
        $log | Should -Not -Match 'jaws-foundry-dev'
        $log | Should -Not -Match 'jaws-investigation-dev'
        $connection = Get-Content -LiteralPath (Join-Path $script:state 'connection.json') -Raw
        $connection | Should -Match '"isSharedToAll":false'
        $connection | Should -Match 'jaws-investigation-planner-lab1/endpoint/protocols/a2a'
        $receipt = Get-Content -LiteralPath (Join-Path $script:root 'installer/.local/jaws-step-c-install.lab1.generated.json') -Raw | ConvertFrom-Json
        $receipt.SupervisorVersionPosted | Should -BeTrue
        $receipt.SupervisorV1Modified | Should -BeFalse
        $receipt.CustomerInstallationAccepted | Should -BeFalse
        $receipt.ExpectedImage | Should -Be $script:image
        @($receipt.Corrections) | Should -Contain 'PublishSupervisorRoute'
    }

    It 'requires an inference acknowledgement before the delegation call and does not call that a customer receipt' {
        Write-StepBFixture
        $output = & (Join-Path $script:root 'installer/Install-JawsThroughStepC.ps1') -Mode Install -EnvironmentName 'lab1' -AcknowledgeStepCInstall -AcknowledgeInferenceCharges *>&1 | Out-String
        $output | Should -Match 'Step C install: CLOSED'
        $output | Should -Match 'Customer installation accepted: false'
        $output | Should -Match 'Task state: TASK_STATE_COMPLETED'
        $output | Should -Match 'Result: PASS'
        $output | Should -Match 'Ready for next step: true'
        $output | Should -Match 'Next step: Step D Validate'
        $output | Should -Match 'Evidence: '
        $output | Should -Not -Match 'Live Azure read: true'
        $report = Get-Content -LiteralPath (Join-Path $script:root 'installer/.local/jaws-step-c-final-acceptance.lab1.generated.json') -Raw | ConvertFrom-Json
        $report.Status | Should -Be 'PASS'
        $report.TaskState | Should -Be 'TASK_STATE_COMPLETED'
        $report.CustomerInstallationAccepted | Should -BeFalse
        $report.HostedInvestigationAgent | Should -Be ''
        $report.InvestigationAgent | Should -Be 'jaws-investigation-planner-lab1'
        $report.RateLimitAttempts | Should -Be 1
    }

    It 'retries a model rate limit and then accepts the completed Investigation task' {
        Write-StepBFixture
        $env:JAWS_STEPC_STUB_RATE_LIMITS = '1'
        $output = & (Join-Path $script:root 'installer/Install-JawsThroughStepC.ps1') -Mode Install -EnvironmentName 'lab1' -AcknowledgeStepCInstall -AcknowledgeInferenceCharges *>&1 | Out-String
        $output | Should -Match 'Supervisor model rate limit \(attempt 1 of 3\)'
        $output | Should -Match 'Issue: server_error: Model deployment rate limit exceeded'
        $output | Should -Match 'Quota request: https://aka.ms/oai/stuquotarequest'
        $output | Should -Match 'Step C install: CLOSED'
        $output | Should -Match 'Task state: TASK_STATE_COMPLETED'
        $log = Get-Content -LiteralPath (Join-Path $script:state 'log.txt') -Raw
        ([regex]::Matches($log, '/protocols/openai/responses')).Count | Should -Be 2
        $report = Get-Content -LiteralPath (Join-Path $script:root 'installer/.local/jaws-step-c-final-acceptance.lab1.generated.json') -Raw | ConvertFrom-Json
        $report.Status | Should -Be 'PASS'
        $report.RateLimitAttempts | Should -Be 2
        $report.ResponseStatus | Should -Be 'completed'
        $report.CustomerInstallationAccepted | Should -BeFalse
    }

    It 'stops after repeated model rate limits without calling the delegation a tool failure' {
        Write-StepBFixture
        $env:JAWS_STEPC_STUB_RATE_LIMITS = '5'
        $output = ''
        try {
            & (Join-Path $script:root 'installer/Install-JawsThroughStepC.ps1') -Mode Install -EnvironmentName 'lab1' -AcknowledgeStepCInstall -AcknowledgeInferenceCharges *>&1 | ForEach-Object { $output += "$_`n" }
            throw 'Acceptance returned instead of JAWS-C-ACCEPT-010.'
        } catch {
            $output += $_.Exception.Message
        }
        $output | Should -Match 'JAWS-C-ACCEPT-010'
        $output | Should -Not -Match 'JAWS-C-ACCEPT-007'
        $output | Should -Match 'Issue: server_error: Model deployment rate limit exceeded'
        $output | Should -Match 'Action: The Investigation task is not the failure'
        $output | Should -Match 'Quota request: https://aka.ms/oai/stuquotarequest'
        $output | Should -Match 'Result: FAIL'
        $log = Get-Content -LiteralPath (Join-Path $script:state 'log.txt') -Raw
        ([regex]::Matches($log, '/protocols/openai/responses')).Count | Should -Be 3
        $report = Get-Content -LiteralPath (Join-Path $script:root 'installer/.local/jaws-step-c-final-acceptance.lab1.generated.json') -Raw | ConvertFrom-Json
        $report.Status | Should -Be 'FAIL'
        $report.ResponseErrorCode | Should -Be 'server_error'
        $report.ResponseErrorMessage | Should -Match 'rate limit'
        $report.QuotaRequest | Should -Be 'https://aka.ms/oai/stuquotarequest'
        $report.OperatorAction | Should -Match 'request more quota'
        $report.RateLimitAttempts | Should -Be 3
        $report.TaskState | Should -Be 'TASK_STATE_COMPLETED'
        $report.CustomerInstallationAccepted | Should -BeFalse
    }
}
