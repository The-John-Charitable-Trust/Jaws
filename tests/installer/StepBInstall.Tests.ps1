BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../installer/modules/StepBInstall.psm1') -Force
    $script:root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $script:sub = '22222222-2222-2222-2222-222222222222'
    $opsLocal = Join-Path $script:root 'installer/.local'
    if (Test-Path -LiteralPath $opsLocal) {
        Get-ChildItem -LiteralPath $opsLocal -Filter '*ops1*' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    }
    $script:stub = Join-Path ([System.IO.Path]::GetTempPath()) ('jaws-stepb-stub-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:stub | Out-Null
    Set-Content -LiteralPath (Join-Path $script:stub 'az') -Encoding ascii -Value @'
#!/bin/bash
exec python3 "$0.py" "$@"
'@
    Set-Content -LiteralPath (Join-Path $script:stub 'az.py') -Encoding utf8 -Value @'
import json, os, sys
state = os.environ["JAWS_STEPB_STUB_STATE"]
sub = os.environ["JAWS_STEPB_STUB_SUB"]
env = os.environ["JAWS_STEPB_STUB_ENV"]
os.makedirs(state, exist_ok=True)
args = sys.argv[1:]
with open(os.path.join(state, "log.txt"), "a", encoding="utf-8") as handle:
    handle.write(" ".join(args) + "\n")
tags = {"application": "JAWS", "managedBy": "JAWS-Installer", "environment": env}
principal = "11111111-1111-1111-1111-111111111111"

def path(name):
    return os.path.join(state, name)

def exists(name):
    return os.path.exists(path(name))

def save(name, payload):
    with open(path(name), "w", encoding="utf-8") as handle:
        json.dump(payload, handle)

def load(name):
    with open(path(name), encoding="utf-8") as handle:
        return json.load(handle)

def emit(payload):
    print(json.dumps(payload))
    sys.exit(0)

def flag(name, default):
    return args[args.index(name) + 1] if name in args else default

def missing():
    print("MISSING", file=sys.stderr)
    sys.exit(3)

if args[:2] == ["account", "show"]:
    emit({"id": sub, "name": "stub", "state": "Enabled", "tenantId": "33333333-3333-3333-3333-333333333333", "user": {"name": "installer@stub.example", "type": "user"}})
if args[:2] == ["account", "list"]:
    emit([{"id": sub, "name": "stub", "state": "Enabled", "tenantId": "33333333-3333-3333-3333-333333333333"}])
if args[:2] == ["account", "list-locations"]:
    if "--subscription" in args:
        print("unrecognized arguments: --subscription", file=sys.stderr)
        sys.exit(2)
    emit([{"name": "eastus", "displayName": "East US"}])
if args[:2] == ["provider", "show"]:
    emit({"namespace": "stub", "registrationState": os.environ.get("JAWS_STEPB_STUB_PROVIDER", "Registered")})
if args[:3] == ["policy", "assignment", "list"]:
    emit([])
if args[:2] == ["group", "show"]:
    emit(load("group")) if exists("group") else missing()
if args[:2] == ["group", "create"]:
    payload = {"name": flag("--name", "rg-jaws-lab1"), "location": "eastus", "tags": tags}
    save("group", payload)
    emit(payload)
if args[:3] == ["cognitiveservices", "account", "show"]:
    emit(load("foundry")) if exists("foundry") else missing()
if args[:3] == ["cognitiveservices", "account", "create"]:
    foundry_name = flag("--name", "jaws-foundry-lab1")
    payload = {"name": foundry_name, "kind": "AIServices", "properties": {"provisioningState": "Succeeded", "customSubDomainName": foundry_name}, "tags": tags}
    save("foundry", payload)
    emit(payload)
if args[:3] == ["cognitiveservices", "account", "list-models"]:
    if os.environ.get("JAWS_STEPB_STUB_HIDE_MODEL") == "1":
        emit([])
    skus = [{"name": "GlobalStandard"}]
    if os.environ.get("JAWS_STEPB_STUB_STANDARD_SKU", "1") == "1":
        skus.append({"name": "Standard"})
    emit([{"format": "OpenAI", "name": "gpt-5-mini", "version": "2025-08-07", "skus": skus}])
if args[:4] == ["cognitiveservices", "account", "project", "show"]:
    emit(load("project")) if exists("project") else missing()
if args[:4] == ["cognitiveservices", "account", "project", "create"]:
    payload = {"name": flag("--project-name", "jaws-lab1"), "properties": {"provisioningState": "Succeeded"}, "identity": {"type": "SystemAssigned", "principalId": principal}}
    save("project", payload)
    emit(payload)
if args[:4] == ["cognitiveservices", "account", "deployment", "show"]:
    emit(load("deployment")) if exists("deployment") else missing()
if args[:4] == ["cognitiveservices", "account", "deployment", "create"]:
    if os.environ.get("JAWS_STEPB_STUB_QUOTA") == "1":
        print('{"error":{"code":"InsufficientQuota","message":"Quota exceeded for model gpt-5-mini in eastus."}}', file=sys.stderr)
        sys.exit(1)
    sku_name = "GlobalStandard"
    if "--sku-name" in args:
        sku_name = args[args.index("--sku-name") + 1]
    capacity = 1
    if "--sku-capacity" in args:
        capacity = int(args[args.index("--sku-capacity") + 1])
    payload = {"name": "gpt-5-mini", "sku": {"name": sku_name, "capacity": capacity}, "properties": {"provisioningState": "Succeeded", "model": {"name": "gpt-5-mini", "version": "2025-08-07"}}}
    save("deployment", payload)
    emit(payload)
if args[:4] == ["cognitiveservices", "account", "deployment", "delete"]:
    if exists("deployment"):
        os.remove(path("deployment"))
    emit({})
if args[:2] == ["keyvault", "show"]:
    emit(load("vault")) if exists("vault") else missing()
if args[:2] == ["keyvault", "create"]:
    payload = {"name": flag("--name", "kvjawslab1"), "properties": {"enableRbacAuthorization": True, "enablePurgeProtection": True}, "tags": tags}
    save("vault", payload)
    emit(payload)
if args[:2] == ["acr", "show"]:
    emit(load("registry")) if exists("registry") else missing()
if args[:2] == ["acr", "create"]:
    registry_name = flag("--name", "jawsacrlab1")
    payload = {"name": registry_name, "loginServer": registry_name + ".azurecr.io", "sku": {"name": "Basic"}, "adminUserEnabled": False, "tags": tags}
    save("registry", payload)
    emit(payload)
if args[:2] == ["acr", "login"]:
    sys.exit(0)
if args[:2] == ["acr", "build"]:
    if "--platform" not in args or args[args.index("--platform") + 1] != "linux/amd64":
        print("platform must be linux/amd64", file=sys.stderr)
        sys.exit(2)
    file_arg = args[args.index("--file") + 1] if "--file" in args else ""
    normalized = file_arg.replace("\\", "/")
    if file_arg == "Dockerfile" or not normalized.endswith("src/Jaws.Supervisor.Host/Dockerfile"):
        print("dockerfile must be the Supervisor Dockerfile path", file=sys.stderr)
        sys.exit(2)
    sys.exit(0)
if args[:3] == ["acr", "manifest", "show-metadata"]:
    emit({"digest": "sha256:" + ("a" * 64)})
if args[:2] == ["acr", "check-name"]:
    emit({"nameAvailable": True})
if args[:3] == ["role", "assignment", "list"]:
    if "--assignee-object-id" in args:
        emit([load("role")] if exists("role") else [])
    emit([{"roleDefinitionName": os.environ.get("JAWS_STEPB_STUB_ROLE", "Owner"), "scope": "/subscriptions/" + sub}])
if args[:3] == ["role", "assignment", "create"]:
    attempts = 0
    if exists("role-attempts"):
        attempts = load("role-attempts")["n"]
    attempts += 1
    save("role-attempts", {"n": attempts})
    if attempts < 2:
        print("PrincipalNotFound: principal not found", file=sys.stderr)
        sys.exit(3)
    payload = {"roleDefinitionName": "AcrPull", "principalId": principal, "scope": "registry"}
    save("role", payload)
    emit(payload)
if args[:1] == ["rest"] and "--method" in args:
    method = args[args.index("--method") + 1]
    url = args[args.index("--url") + 1] if "--url" in args else ""
    if method == "POST" and "checkSkuAvailability" in url:
        emit({"value": [{"skuName": "S0", "skuAvailable": True}]})
    if method == "POST" and ("checkNameAvailability" in url or "checkDomainAvailability" in url):
        emit({"nameAvailable": True, "isSubdomainAvailable": True})
    if method == "GET" and "/versions/1" in url and not exists("agent"):
        print(os.environ.get(
            "JAWS_STEPB_STUB_AGENT_MISSING",
            '{"error":{"code":"not_found","message":"Not Found"}}',
        ), file=sys.stderr)
        sys.exit(1)
    if method.lower() == "patch" and "/deployments/" in url:
        if "api-version=2023-10-01-preview" not in url:
            print("quota patch requires api-version=2023-10-01-preview", file=sys.stderr)
            sys.exit(2)
        body_flag = args[args.index("--body") + 1]
        with open(body_flag[1:], encoding="utf-8") as handle:
            body = json.load(handle)
        enabled = body.get("properties", {}).get("dynamicThrottlingEnabled", None)
        if not isinstance(enabled, bool):
            print("dynamicThrottlingEnabled must be a boolean", file=sys.stderr)
            sys.exit(2)
        current = load("deployment")
        current.setdefault("properties", {})
        current["properties"]["dynamicThrottlingEnabled"] = enabled
        if os.environ.get("JAWS_STEPB_STUB_QUOTA_REJECT") == "1":
            emit(current)
        save("deployment", current)
        emit(current)
    if method == "GET":
        emit(load("agent")) if exists("agent") else missing()
    body_flag = args[args.index("--body") + 1]
    with open(body_flag[1:], encoding="utf-8") as handle:
        body = json.load(handle)
    image = body["definition"]["container_configuration"]["image"]
    payload = {"name": body["name"], "status": "active", "draft": False, "version": "1", "definition": {"container_configuration": {"image": image}}}
    save("agent", payload)
    emit(payload)
print("unexpected " + " ".join(args), file=sys.stderr)
sys.exit(9)
'@
    chmod +x (Join-Path $script:stub 'az') | Out-Null
}

Describe 'Step B foundation install' {
    It 'refuses the dev environment and an unapproved install' {
        { New-JawsStepBInstallScope -SubscriptionId $script:sub -ResourceGroupName 'rg-jaws-lab1' -Location 'eastus' -EnvironmentName 'dev' -ModelName 'gpt-5-mini' -ModelVersion '2025-08-07' } | Should -Throw '*JAWS-STEP-B-013*'
        $scope = New-JawsStepBInstallScope -SubscriptionId $script:sub -ResourceGroupName 'rg-jaws-lab1' -Location 'eastus' -EnvironmentName 'lab1' -ModelName 'gpt-5-mini' -ModelVersion '2025-08-07'
        { Invoke-JawsStepBInstall -Scope $scope -ApprovedPlanSha256 $scope.PlanSha256 -InstallerRoot $script:root } | Should -Throw '*JAWS-STEP-B-010*'
    }

    It 'provisions the foundation from an approved plan and resumes without a second create' {
        $state = Join-Path $script:stub 'state'
        $savedPath = $env:PATH
        $savedState = $env:JAWS_STEPB_STUB_STATE
        $savedSub = $env:JAWS_STEPB_STUB_SUB
        $savedEnv = $env:JAWS_STEPB_STUB_ENV
        try {
            $env:JAWS_STEPB_STUB_STATE = $state
            $env:JAWS_STEPB_STUB_SUB = $script:sub
            $env:JAWS_STEPB_STUB_ENV = 'lab1'
            $env:JAWS_STEPB_POLL_SECONDS = '0'
            $env:PATH = $script:stub + [System.IO.Path]::PathSeparator + '/usr/bin'
            $devBefore = Get-Content -LiteralPath (Join-Path $script:root 'installer/config/jaws-installation-state.dev.json') -Raw
            & (Join-Path $script:root 'installer/Install-Jaws.ps1') -Mode Plan -NonInteractive -EnvironmentName 'lab1' -ResourceGroupName 'rg-jaws-lab1' -Location 'eastus'
            $planPath = Join-Path $script:root 'installer/.local/jaws-stage-b-plan.lab1.offline.generated.json'
            $plan = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
            { & (Join-Path $script:root 'installer/Install-Jaws.ps1') -Mode Install -EnvironmentName 'lab1' -ResourceGroupName 'rg-jaws-lab1' -Location 'eastus' -ApprovedPlanSha256 $plan.PlanSha256 } | Should -Throw '*JAWS-STEP-B-010*'
            $logBefore = Get-Content -LiteralPath (Join-Path $state 'log.txt') -Raw
            $logBefore | Should -Not -Match 'group create'
            & (Join-Path $script:root 'installer/Install-Jaws.ps1') -Mode Install -EnvironmentName 'lab1' -ResourceGroupName 'rg-jaws-lab1' -Location 'eastus' -ApprovedPlanSha256 $plan.PlanSha256 -AcknowledgeStepBInstall
            $receipt = Get-Content -LiteralPath (Join-Path $script:root 'installer/.local/jaws-step-b-install.lab1.generated.json') -Raw | ConvertFrom-Json
            $receipt.Status | Should -Be 'STEP_B_INSTALLED'
            $receipt.QuotaMode | Should -Be 'Static'
            $receipt.ModelSku | Should -Be 'GlobalStandard'
            $receipt.AgentStatus | Should -Be 'active'
            $receipt.Image | Should -Match '@sha256:[a-f]{64}$'
            $receipt.AzureWrites | Should -BeGreaterThan 0
            & (Join-Path $script:root 'installer/Test-JawsStepB.ps1') -Mode Install
            & (Join-Path $script:root 'installer/Install-Jaws.ps1') -Mode Install -EnvironmentName 'lab1' -ResourceGroupName 'rg-jaws-lab1' -Location 'eastus' -ApprovedPlanSha256 $plan.PlanSha256 -AcknowledgeStepBInstall
            $log = Get-Content -LiteralPath (Join-Path $state 'log.txt') -Raw
            @('group create','cognitiveservices account create','project create','deployment create','keyvault create','acr create','role assignment create','rest --method POST').ForEach({ $log | Should -Match ([regex]::Escape($_)) })
            ([regex]::Matches($log, 'cognitiveservices account create')).Count | Should -Be 1
            ([regex]::Matches($log, '/agents\?api-version=v1')).Count | Should -Be 1
            ([regex]::Matches($log, 'acr build')).Count | Should -Be 1
            $log | Should -Match 'acr build --registry jawsacrlab1'
            $log | Should -Match '--platform linux/amd64'
            $log | Should -Match '--file .+src/Jaws\.Supervisor\.Host/Dockerfile'
            $log | Should -Not -Match '--file Dockerfile( |$)'
            $log | Should -Not -Match 'acr login'
            $log | Should -Not -Match '--method patch'
            $log | Should -Match '--sku-name GlobalStandard'
            $log | Should -Not -Match '--sku-name Standard'
            ([regex]::Matches($log, 'deployment delete')).Count | Should -Be 0
            $log | Should -Not -Match 'jaws-foundry-dev'
            $log | Should -Not -Match 'c52f597b-7753-45b4-a764-67e290dcfd5e'
            $log | Should -Match 'account list-locations --output json --only-show-errors'
            $log | Should -Not -Match 'list-locations --subscription'
            (Get-Content -LiteralPath (Join-Path $script:root 'installer/config/jaws-installation-state.dev.json') -Raw) | Should -Be $devBefore
            $accept = & (Join-Path $script:root 'installer/Install-Jaws.ps1') -Mode Accept -EnvironmentName 'lab1' -ResourceGroupName 'rg-jaws-lab1' -Location 'eastus' *>&1 | Out-String
            $accept | Should -Match 'STEP-B ACCEPTANCE PASS'
            $accept | Should -Match 'Live Azure read: true'
            $accept | Should -Match 'Azure writes: 0'
            $accept | Should -Match 'Foundry provisioning: Succeeded'
            $accept | Should -Match 'Deployment: Succeeded'
            $accept | Should -Match 'Quota mode: Static'
            $accept | Should -Match 'Registry admin: false'
            $accept | Should -Match 'AcrPull: true'
            $accept | Should -Match 'Agent status: active'
            $accept | Should -Match 'Dev state: unchanged'
            $accept | Should -Match 'Result: PASS'
            $accept | Should -Match 'Ready for next step: true'
            $accept | Should -Match 'Next step: Step C Validate'
            $accept | Should -Match 'Evidence: '
            $creates = ([regex]::Matches($log, ' create')).Count
            $scored = & (Join-Path $script:root 'installer/Test-JawsStepB.ps1') -Mode Accept *>&1 | Out-String
            $scored | Should -Match 'STEP-B ACCEPTANCE PASS'
            $scored | Should -Match 'Live Azure read: true'
            $logAfterAccept = Get-Content -LiteralPath (Join-Path $state 'log.txt') -Raw
            ([regex]::Matches($logAfterAccept, ' create')).Count | Should -Be $creates
            $empty = Join-Path $script:stub 'empty-state'
            New-Item -ItemType Directory -Path $empty | Out-Null
            $env:JAWS_STEPB_STUB_STATE = $empty
            { & (Join-Path $script:root 'installer/Install-Jaws.ps1') -Mode Accept -EnvironmentName 'lab1' -ResourceGroupName 'rg-jaws-lab1' -Location 'eastus' } | Should -Throw '*JAWS-STEP-B-024*'
            $emptyLog = Get-Content -LiteralPath (Join-Path $empty 'log.txt') -Raw
            $emptyLog | Should -Not -Match ' create'
            $emptyLog | Should -Match 'account show'
        } finally {
            $env:PATH = $savedPath
            $env:JAWS_STEPB_STUB_STATE = $savedState
            $env:JAWS_STEPB_STUB_SUB = $savedSub
            $env:JAWS_STEPB_STUB_ENV = $savedEnv
            Remove-Item Env:JAWS_STEPB_POLL_SECONDS -ErrorAction SilentlyContinue
        }
    }

    It 'refuses a model the account does not offer before creating the deployment' {
        $state = Join-Path $script:stub 'state-no-model'
        $savedPath = $env:PATH
        $savedState = $env:JAWS_STEPB_STUB_STATE
        $savedSub = $env:JAWS_STEPB_STUB_SUB
        $savedEnv = $env:JAWS_STEPB_STUB_ENV
        $savedHide = $env:JAWS_STEPB_STUB_HIDE_MODEL
        try {
            $env:JAWS_STEPB_STUB_STATE = $state
            $env:JAWS_STEPB_STUB_SUB = $script:sub
            $env:JAWS_STEPB_STUB_ENV = 'lab1'
            $env:JAWS_STEPB_STUB_HIDE_MODEL = '1'
            $env:JAWS_STEPB_POLL_SECONDS = '0'
            $env:PATH = $script:stub + [System.IO.Path]::PathSeparator + $env:PATH
            & (Join-Path $script:root 'installer/Install-Jaws.ps1') -Mode Plan -NonInteractive -EnvironmentName 'lab1' -ResourceGroupName 'rg-jaws-lab1' -Location 'eastus'
            $plan = Get-Content -LiteralPath (Join-Path $script:root 'installer/.local/jaws-stage-b-plan.lab1.offline.generated.json') -Raw | ConvertFrom-Json
            { & (Join-Path $script:root 'installer/Install-Jaws.ps1') -Mode Install -EnvironmentName 'lab1' -ResourceGroupName 'rg-jaws-lab1' -Location 'eastus' -ApprovedPlanSha256 $plan.PlanSha256 -AcknowledgeStepBInstall } | Should -Throw '*JAWS-STEP-B-MODEL-001*'
            $log = Get-Content -LiteralPath (Join-Path $state 'log.txt') -Raw
            $log | Should -Match 'list-models'
            $log | Should -Not -Match 'deployment create'
        } finally {
            $env:PATH = $savedPath
            $env:JAWS_STEPB_STUB_STATE = $savedState
            $env:JAWS_STEPB_STUB_SUB = $savedSub
            $env:JAWS_STEPB_STUB_ENV = $savedEnv
            if ($null -eq $savedHide) { Remove-Item Env:JAWS_STEPB_STUB_HIDE_MODEL -ErrorAction SilentlyContinue } else { $env:JAWS_STEPB_STUB_HIDE_MODEL = $savedHide }
            Remove-Item Env:JAWS_STEPB_POLL_SECONDS -ErrorAction SilentlyContinue
        }
    }

    It 'prints the quota request link when model deployment quota is refused' {
        $state = Join-Path $script:stub 'state-quota'
        $savedPath = $env:PATH
        $savedState = $env:JAWS_STEPB_STUB_STATE
        $savedSub = $env:JAWS_STEPB_STUB_SUB
        $savedEnv = $env:JAWS_STEPB_STUB_ENV
        $savedQuota = $env:JAWS_STEPB_STUB_QUOTA
        try {
            $env:JAWS_STEPB_STUB_STATE = $state
            $env:JAWS_STEPB_STUB_SUB = $script:sub
            $env:JAWS_STEPB_STUB_ENV = 'lab1'
            $env:JAWS_STEPB_STUB_QUOTA = '1'
            $env:JAWS_STEPB_POLL_SECONDS = '0'
            $env:PATH = $script:stub + [System.IO.Path]::PathSeparator + '/usr/bin'
            & (Join-Path $script:root 'installer/Install-Jaws.ps1') -Mode Plan -NonInteractive -EnvironmentName 'lab1' -ResourceGroupName 'rg-jaws-lab1' -Location 'eastus'
            $plan = Get-Content -LiteralPath (Join-Path $script:root 'installer/.local/jaws-stage-b-plan.lab1.offline.generated.json') -Raw | ConvertFrom-Json
            $output = ''
            try {
                & (Join-Path $script:root 'installer/Install-Jaws.ps1') -Mode Install -EnvironmentName 'lab1' -ResourceGroupName 'rg-jaws-lab1' -Location 'eastus' -ApprovedPlanSha256 $plan.PlanSha256 -AcknowledgeStepBInstall *>&1 | ForEach-Object { $output += "$_`n" }
                throw 'Install returned instead of JAWS-STEP-B-MODEL-001.'
            } catch {
                $output += $_.Exception.Message
            }
            $output | Should -Match 'JAWS-STEP-B-MODEL-001'
            $output | Should -Match 'Issue: '
            $output | Should -Match 'InsufficientQuota'
            $output | Should -Match 'Action: Request a quota increase'
            $output | Should -Match 'Quota request: https://aka.ms/oai/stuquotarequest'
            $output | Should -Match 'Result: FAIL'
        } finally {
            $env:PATH = $savedPath
            if ($null -eq $savedState) { Remove-Item Env:JAWS_STEPB_STUB_STATE -ErrorAction SilentlyContinue } else { $env:JAWS_STEPB_STUB_STATE = $savedState }
            if ($null -eq $savedSub) { Remove-Item Env:JAWS_STEPB_STUB_SUB -ErrorAction SilentlyContinue } else { $env:JAWS_STEPB_STUB_SUB = $savedSub }
            if ($null -eq $savedEnv) { Remove-Item Env:JAWS_STEPB_STUB_ENV -ErrorAction SilentlyContinue } else { $env:JAWS_STEPB_STUB_ENV = $savedEnv }
            if ($null -eq $savedQuota) { Remove-Item Env:JAWS_STEPB_STUB_QUOTA -ErrorAction SilentlyContinue } else { $env:JAWS_STEPB_STUB_QUOTA = $savedQuota }
            Remove-Item Env:JAWS_STEPB_POLL_SECONDS -ErrorAction SilentlyContinue
        }
    }

    It 'applies dynamic quota without changing the plan digest and can return to static' {
        $state = Join-Path $script:stub 'state-dynamic'
        $savedPath = $env:PATH
        $savedState = $env:JAWS_STEPB_STUB_STATE
        $savedSub = $env:JAWS_STEPB_STUB_SUB
        $savedEnv = $env:JAWS_STEPB_STUB_ENV
        try {
            $env:JAWS_STEPB_STUB_STATE = $state
            $env:JAWS_STEPB_STUB_SUB = $script:sub
            $env:JAWS_STEPB_STUB_ENV = 'lab1'
            $env:JAWS_STEPB_POLL_SECONDS = '0'
            $env:PATH = $script:stub + [System.IO.Path]::PathSeparator + '/usr/bin'
            $planOut = & (Join-Path $script:root 'installer/Install-Jaws.ps1') -Mode Plan -NonInteractive -EnvironmentName 'lab1' -ResourceGroupName 'rg-jaws-lab1' -Location 'eastus' -QuotaMode Dynamic *>&1 | Out-String
            $planOut | Should -Match 'Quota mode: Dynamic'
            $plan = Get-Content -LiteralPath (Join-Path $script:root 'installer/.local/jaws-stage-b-plan.lab1.offline.generated.json') -Raw | ConvertFrom-Json
            $scope = New-JawsStepBInstallScope -SubscriptionId $script:sub -ResourceGroupName 'rg-jaws-lab1' -Location 'eastus' -EnvironmentName 'lab1' -ModelName 'gpt-5-mini' -ModelVersion '2025-08-07'
            $plan.PlanSha256 | Should -Be $scope.PlanSha256
            $install = & (Join-Path $script:root 'installer/Install-Jaws.ps1') -Mode Install -EnvironmentName 'lab1' -ResourceGroupName 'rg-jaws-lab1' -Location 'eastus' -ApprovedPlanSha256 $plan.PlanSha256 -QuotaMode Dynamic -AcknowledgeStepBInstall *>&1 | Out-String
            $install | Should -Match 'STEP-B INSTALL PASS'
            $install | Should -Match 'Quota mode: Dynamic'
            $receipt = Get-Content -LiteralPath (Join-Path $script:root 'installer/.local/jaws-step-b-install.lab1.generated.json') -Raw | ConvertFrom-Json
            $receipt.QuotaMode | Should -Be 'Dynamic'
            $receipt.ModelSku | Should -Be 'Standard'
            $install | Should -Match 'Model SKU: Standard'
            $deployment = Get-Content -LiteralPath (Join-Path $state 'deployment') -Raw | ConvertFrom-Json
            $deployment.sku.name | Should -Be 'Standard'
            $deployment.sku.capacity | Should -Be 1
            $deployment.properties.dynamicThrottlingEnabled | Should -BeTrue
            $log = Get-Content -LiteralPath (Join-Path $state 'log.txt') -Raw
            $log | Should -Match '--sku-name Standard'
            $log | Should -Not -Match '--sku-name GlobalStandard'
            ([regex]::Matches($log, 'deployment delete')).Count | Should -Be 0
            ([regex]::Matches($log, '--method patch')).Count | Should -Be 1
            $log | Should -Match 'api-version=2023-10-01-preview'
            $log | Should -Match '/deployments/gpt-5-mini'
            $dynamicAccept = & (Join-Path $script:root 'installer/Install-Jaws.ps1') -Mode Accept -EnvironmentName 'lab1' -ResourceGroupName 'rg-jaws-lab1' -Location 'eastus' *>&1 | Out-String
            $dynamicAccept | Should -Match 'Quota mode: Dynamic'
            $dynamicAccept | Should -Match 'STEP-B ACCEPTANCE PASS'
            & (Join-Path $script:root 'installer/Install-Jaws.ps1') -Mode Install -EnvironmentName 'lab1' -ResourceGroupName 'rg-jaws-lab1' -Location 'eastus' -ApprovedPlanSha256 $plan.PlanSha256 -QuotaMode Dynamic -AcknowledgeStepBInstall | Out-Null
            $log = Get-Content -LiteralPath (Join-Path $state 'log.txt') -Raw
            ([regex]::Matches($log, '--method patch')).Count | Should -Be 1
            ([regex]::Matches($log, 'deployment create')).Count | Should -Be 1
            $static = & (Join-Path $script:root 'installer/Install-Jaws.ps1') -Mode Install -EnvironmentName 'lab1' -ResourceGroupName 'rg-jaws-lab1' -Location 'eastus' -ApprovedPlanSha256 $plan.PlanSha256 -QuotaMode Static -AcknowledgeStepBInstall *>&1 | Out-String
            $static | Should -Match 'Quota mode: Static'
            $log = Get-Content -LiteralPath (Join-Path $state 'log.txt') -Raw
            ([regex]::Matches($log, '--method patch')).Count | Should -Be 2
            $deployment = Get-Content -LiteralPath (Join-Path $state 'deployment') -Raw | ConvertFrom-Json
            $deployment.properties.dynamicThrottlingEnabled | Should -BeFalse
            $deployment.sku.name | Should -Be 'Standard'
            ([regex]::Matches($log, 'deployment delete')).Count | Should -Be 0
            $accept = & (Join-Path $script:root 'installer/Install-Jaws.ps1') -Mode Accept -EnvironmentName 'lab1' -ResourceGroupName 'rg-jaws-lab1' -Location 'eastus' *>&1 | Out-String
            $accept | Should -Match 'Quota mode: Static'
            $accept | Should -Match 'STEP-B ACCEPTANCE PASS'
        } finally {
            $env:PATH = $savedPath
            if ($null -eq $savedState) { Remove-Item Env:JAWS_STEPB_STUB_STATE -ErrorAction SilentlyContinue } else { $env:JAWS_STEPB_STUB_STATE = $savedState }
            if ($null -eq $savedSub) { Remove-Item Env:JAWS_STEPB_STUB_SUB -ErrorAction SilentlyContinue } else { $env:JAWS_STEPB_STUB_SUB = $savedSub }
            if ($null -eq $savedEnv) { Remove-Item Env:JAWS_STEPB_STUB_ENV -ErrorAction SilentlyContinue } else { $env:JAWS_STEPB_STUB_ENV = $savedEnv }
            Remove-Item Env:JAWS_STEPB_POLL_SECONDS -ErrorAction SilentlyContinue
        }
    }

    It 'replaces an existing GlobalStandard deployment before enabling dynamic quota' {
        $state = Join-Path $script:stub 'state-replace-sku'
        $savedPath = $env:PATH
        $savedState = $env:JAWS_STEPB_STUB_STATE
        $savedSub = $env:JAWS_STEPB_STUB_SUB
        $savedEnv = $env:JAWS_STEPB_STUB_ENV
        try {
            $env:JAWS_STEPB_STUB_STATE = $state
            $env:JAWS_STEPB_STUB_SUB = $script:sub
            $env:JAWS_STEPB_STUB_ENV = 'lab1'
            $env:JAWS_STEPB_POLL_SECONDS = '0'
            $env:PATH = $script:stub + [System.IO.Path]::PathSeparator + '/usr/bin'
            & (Join-Path $script:root 'installer/Install-Jaws.ps1') -Mode Plan -NonInteractive -EnvironmentName 'lab1' -ResourceGroupName 'rg-jaws-lab1' -Location 'eastus'
            $plan = Get-Content -LiteralPath (Join-Path $script:root 'installer/.local/jaws-stage-b-plan.lab1.offline.generated.json') -Raw | ConvertFrom-Json
            & (Join-Path $script:root 'installer/Install-Jaws.ps1') -Mode Install -EnvironmentName 'lab1' -ResourceGroupName 'rg-jaws-lab1' -Location 'eastus' -ApprovedPlanSha256 $plan.PlanSha256 -AcknowledgeStepBInstall
            $created = Get-Content -LiteralPath (Join-Path $state 'deployment') -Raw | ConvertFrom-Json
            $created.sku.name | Should -Be 'GlobalStandard'
            $install = & (Join-Path $script:root 'installer/Install-Jaws.ps1') -Mode Install -EnvironmentName 'lab1' -ResourceGroupName 'rg-jaws-lab1' -Location 'eastus' -ApprovedPlanSha256 $plan.PlanSha256 -QuotaMode Dynamic -AcknowledgeStepBInstall *>&1 | Out-String
            $install | Should -Match 'STEP-B INSTALL PASS'
            $install | Should -Match 'Quota mode: Dynamic'
            $install | Should -Match 'Model SKU: Standard'
            $log = Get-Content -LiteralPath (Join-Path $state 'log.txt') -Raw
            ([regex]::Matches($log, 'deployment delete')).Count | Should -Be 1
            ([regex]::Matches($log, '--sku-name Standard')).Count | Should -Be 1
            ([regex]::Matches($log, '--method patch')).Count | Should -Be 1
            $deployment = Get-Content -LiteralPath (Join-Path $state 'deployment') -Raw | ConvertFrom-Json
            $deployment.sku.name | Should -Be 'Standard'
            $deployment.properties.dynamicThrottlingEnabled | Should -BeTrue
            & (Join-Path $script:root 'installer/Install-Jaws.ps1') -Mode Install -EnvironmentName 'lab1' -ResourceGroupName 'rg-jaws-lab1' -Location 'eastus' -ApprovedPlanSha256 $plan.PlanSha256 -QuotaMode Dynamic -AcknowledgeStepBInstall | Out-Null
            $log = Get-Content -LiteralPath (Join-Path $state 'log.txt') -Raw
            ([regex]::Matches($log, 'deployment delete')).Count | Should -Be 1
            ([regex]::Matches($log, '--method patch')).Count | Should -Be 1
        } finally {
            $env:PATH = $savedPath
            if ($null -eq $savedState) { Remove-Item Env:JAWS_STEPB_STUB_STATE -ErrorAction SilentlyContinue } else { $env:JAWS_STEPB_STUB_STATE = $savedState }
            if ($null -eq $savedSub) { Remove-Item Env:JAWS_STEPB_STUB_SUB -ErrorAction SilentlyContinue } else { $env:JAWS_STEPB_STUB_SUB = $savedSub }
            if ($null -eq $savedEnv) { Remove-Item Env:JAWS_STEPB_STUB_ENV -ErrorAction SilentlyContinue } else { $env:JAWS_STEPB_STUB_ENV = $savedEnv }
            Remove-Item Env:JAWS_STEPB_POLL_SECONDS -ErrorAction SilentlyContinue
        }
    }

    It 'refuses dynamic quota when the regional Standard SKU is not offered' {
        $state = Join-Path $script:stub 'state-no-standard'
        $savedPath = $env:PATH
        $savedState = $env:JAWS_STEPB_STUB_STATE
        $savedSub = $env:JAWS_STEPB_STUB_SUB
        $savedEnv = $env:JAWS_STEPB_STUB_ENV
        $savedOffer = $env:JAWS_STEPB_STUB_STANDARD_SKU
        try {
            $env:JAWS_STEPB_STUB_STATE = $state
            $env:JAWS_STEPB_STUB_SUB = $script:sub
            $env:JAWS_STEPB_STUB_ENV = 'lab1'
            $env:JAWS_STEPB_STUB_STANDARD_SKU = '0'
            $env:JAWS_STEPB_POLL_SECONDS = '0'
            $env:PATH = $script:stub + [System.IO.Path]::PathSeparator + '/usr/bin'
            & (Join-Path $script:root 'installer/Install-Jaws.ps1') -Mode Plan -NonInteractive -EnvironmentName 'lab1' -ResourceGroupName 'rg-jaws-lab1' -Location 'eastus'
            $plan = Get-Content -LiteralPath (Join-Path $script:root 'installer/.local/jaws-stage-b-plan.lab1.offline.generated.json') -Raw | ConvertFrom-Json
            $output = ''
            try {
                & (Join-Path $script:root 'installer/Install-Jaws.ps1') -Mode Install -EnvironmentName 'lab1' -ResourceGroupName 'rg-jaws-lab1' -Location 'eastus' -ApprovedPlanSha256 $plan.PlanSha256 -QuotaMode Dynamic -AcknowledgeStepBInstall *>&1 | ForEach-Object { $output += "$_`n" }
                throw 'Install returned instead of JAWS-STEP-B-MODEL-001.'
            } catch {
                $output += $_.Exception.Message
            }
            $output | Should -Match 'JAWS-STEP-B-MODEL-001'
            $output | Should -Match 'regional Standard SKU'
            $output | Should -Match 'Result: FAIL'
            $log = Get-Content -LiteralPath (Join-Path $state 'log.txt') -Raw
            $log | Should -Not -Match 'deployment create'
            Test-Path -LiteralPath (Join-Path $state 'deployment') | Should -BeFalse
        } finally {
            $env:PATH = $savedPath
            if ($null -eq $savedState) { Remove-Item Env:JAWS_STEPB_STUB_STATE -ErrorAction SilentlyContinue } else { $env:JAWS_STEPB_STUB_STATE = $savedState }
            if ($null -eq $savedSub) { Remove-Item Env:JAWS_STEPB_STUB_SUB -ErrorAction SilentlyContinue } else { $env:JAWS_STEPB_STUB_SUB = $savedSub }
            if ($null -eq $savedEnv) { Remove-Item Env:JAWS_STEPB_STUB_ENV -ErrorAction SilentlyContinue } else { $env:JAWS_STEPB_STUB_ENV = $savedEnv }
            if ($null -eq $savedOffer) { Remove-Item Env:JAWS_STEPB_STUB_STANDARD_SKU -ErrorAction SilentlyContinue } else { $env:JAWS_STEPB_STUB_STANDARD_SKU = $savedOffer }
            Remove-Item Env:JAWS_STEPB_POLL_SECONDS -ErrorAction SilentlyContinue
        }
    }

    It 'stops when Azure does not record the requested quota mode' {
        $state = Join-Path $script:stub 'state-quota-reject'
        $savedPath = $env:PATH
        $savedState = $env:JAWS_STEPB_STUB_STATE
        $savedSub = $env:JAWS_STEPB_STUB_SUB
        $savedEnv = $env:JAWS_STEPB_STUB_ENV
        $savedReject = $env:JAWS_STEPB_STUB_QUOTA_REJECT
        try {
            $env:JAWS_STEPB_STUB_STATE = $state
            $env:JAWS_STEPB_STUB_SUB = $script:sub
            $env:JAWS_STEPB_STUB_ENV = 'lab1'
            $env:JAWS_STEPB_STUB_QUOTA_REJECT = '1'
            $env:JAWS_STEPB_POLL_SECONDS = '0'
            $env:PATH = $script:stub + [System.IO.Path]::PathSeparator + '/usr/bin'
            & (Join-Path $script:root 'installer/Install-Jaws.ps1') -Mode Plan -NonInteractive -EnvironmentName 'lab1' -ResourceGroupName 'rg-jaws-lab1' -Location 'eastus'
            $plan = Get-Content -LiteralPath (Join-Path $script:root 'installer/.local/jaws-stage-b-plan.lab1.offline.generated.json') -Raw | ConvertFrom-Json
            $output = ''
            try {
                & (Join-Path $script:root 'installer/Install-Jaws.ps1') -Mode Install -EnvironmentName 'lab1' -ResourceGroupName 'rg-jaws-lab1' -Location 'eastus' -ApprovedPlanSha256 $plan.PlanSha256 -QuotaMode Dynamic -AcknowledgeStepBInstall *>&1 | ForEach-Object { $output += "$_`n" }
                throw 'Install returned instead of JAWS-STEP-B-MODEL-002.'
            } catch {
                $output += $_.Exception.Message
            }
            $output | Should -Match 'JAWS-STEP-B-MODEL-002'
            $output | Should -Match 'Result: FAIL'
            $deployment = Get-Content -LiteralPath (Join-Path $state 'deployment') -Raw | ConvertFrom-Json
            $deployment.properties.PSObject.Properties['dynamicThrottlingEnabled'] | Should -BeNullOrEmpty
        } finally {
            $env:PATH = $savedPath
            if ($null -eq $savedState) { Remove-Item Env:JAWS_STEPB_STUB_STATE -ErrorAction SilentlyContinue } else { $env:JAWS_STEPB_STUB_STATE = $savedState }
            if ($null -eq $savedSub) { Remove-Item Env:JAWS_STEPB_STUB_SUB -ErrorAction SilentlyContinue } else { $env:JAWS_STEPB_STUB_SUB = $savedSub }
            if ($null -eq $savedEnv) { Remove-Item Env:JAWS_STEPB_STUB_ENV -ErrorAction SilentlyContinue } else { $env:JAWS_STEPB_STUB_ENV = $savedEnv }
            if ($null -eq $savedReject) { Remove-Item Env:JAWS_STEPB_STUB_QUOTA_REJECT -ErrorAction SilentlyContinue } else { $env:JAWS_STEPB_STUB_QUOTA_REJECT = $savedReject }
            Remove-Item Env:JAWS_STEPB_POLL_SECONDS -ErrorAction SilentlyContinue
        }
    }

    It 'stops before the first Azure write when the caller cannot assign AcrPull' {
        $state = Join-Path $script:stub 'state-contributor'
        $savedPath = $env:PATH
        $savedState = $env:JAWS_STEPB_STUB_STATE
        $savedSub = $env:JAWS_STEPB_STUB_SUB
        $savedEnv = $env:JAWS_STEPB_STUB_ENV
        $savedRole = $env:JAWS_STEPB_STUB_ROLE
        try {
            $env:JAWS_STEPB_STUB_STATE = $state
            $env:JAWS_STEPB_STUB_SUB = $script:sub
            $env:JAWS_STEPB_STUB_ENV = 'lab1'
            $env:JAWS_STEPB_STUB_ROLE = 'Contributor'
            $env:JAWS_STEPB_POLL_SECONDS = '0'
            $env:PATH = $script:stub + [System.IO.Path]::PathSeparator + $env:PATH
            & (Join-Path $script:root 'installer/Install-Jaws.ps1') -Mode Plan -NonInteractive -EnvironmentName 'lab1' -ResourceGroupName 'rg-jaws-lab1' -Location 'eastus'
            $plan = Get-Content -LiteralPath (Join-Path $script:root 'installer/.local/jaws-stage-b-plan.lab1.offline.generated.json') -Raw | ConvertFrom-Json
            $preflight = ''
            try {
                & (Join-Path $script:root 'installer/Install-Jaws.ps1') -Mode Preflight -EnvironmentName 'lab1' -ResourceGroupName 'rg-jaws-lab1' -Location 'eastus' *>&1 | ForEach-Object { $preflight += "$_`n" }
                throw 'Preflight returned instead of JAWS-STEP-B-026.'
            } catch {
                $preflight += $_.Exception.Message
            }
            $preflight | Should -Match 'JAWS-STEP-B-026'
            $preflight | Should -Match 'Result: FAIL'
            $preflight | Should -Match 'Ready for next step: false'
            $preflight | Should -Match 'Evidence: '
            $log = Get-Content -LiteralPath (Join-Path $state 'log.txt') -Raw
            $log | Should -Not -Match 'group create'
            $log | Should -Match 'role assignment list'
            $log | Should -Match 'account list-locations --output json --only-show-errors'
            $log | Should -Not -Match 'list-locations --subscription'
            $report = Get-Content -LiteralPath (Join-Path $script:root 'installer/.local/jaws-step-b-preflight.lab1.generated.json') -Raw | ConvertFrom-Json
            $report.Status | Should -Be 'NOT_READY'
            $report.AzureWrites | Should -Be 0
            $report.LocationAccepted | Should -BeTrue
            $report.RoleAssignment | Should -BeFalse
            ($report.Reasons -join ' ') | Should -Not -Match 'list subscription locations'
            ($report.Reasons -join ' ') | Should -Not -Match 'is not enabled'
            $report.ModelQuota | Should -Be 'DeferredUntilFoundryAccountExists'
            $report.PolicySimulation | Should -Be 'NotPerformed'
            @($report.AuthorizedWrites).Count | Should -BeGreaterThan 5
        } finally {
            $env:PATH = $savedPath
            $env:JAWS_STEPB_STUB_STATE = $savedState
            $env:JAWS_STEPB_STUB_SUB = $savedSub
            $env:JAWS_STEPB_STUB_ENV = $savedEnv
            if ($null -eq $savedRole) { Remove-Item Env:JAWS_STEPB_STUB_ROLE -ErrorAction SilentlyContinue } else { $env:JAWS_STEPB_STUB_ROLE = $savedRole }
            Remove-Item Env:JAWS_STEPB_POLL_SECONDS -ErrorAction SilentlyContinue
        }
    }

    It 'does not pass --subscription to az account list-locations and skips that call when the CLI subscription differs' {
        $state = Join-Path $script:stub 'state-wrong-subscription'
        $savedPath = $env:PATH
        $savedState = $env:JAWS_STEPB_STUB_STATE
        $savedSub = $env:JAWS_STEPB_STUB_SUB
        $savedEnv = $env:JAWS_STEPB_STUB_ENV
        try {
            $env:JAWS_STEPB_STUB_STATE = $state
            $env:JAWS_STEPB_STUB_SUB = $script:sub
            $env:JAWS_STEPB_STUB_ENV = 'lab2'
            $env:PATH = $script:stub + [System.IO.Path]::PathSeparator + $env:PATH
            $scope = New-JawsStepBInstallScope -SubscriptionId '44444444-4444-4444-4444-444444444444' -ResourceGroupName 'rg-jaws-lab2' -Location 'eastus' -EnvironmentName 'lab2' -ModelName 'gpt-5-mini' -ModelVersion '2025-08-07'
            $devState = Join-Path $script:root 'installer/config/jaws-installation-state.dev.json'
            $devBefore = Get-Content -LiteralPath $devState -Raw
            $checked = Invoke-JawsStepBPreflight -Scope $scope -InstallerRoot (Join-Path $script:root 'installer')
            (Get-Content -LiteralPath $devState -Raw) | Should -Be $devBefore
            $checked.Ready | Should -BeFalse
            $checked.Report.AzureWrites | Should -Be 0
            $checked.Report.LocationAccepted | Should -BeFalse
            $checked.Report.Status | Should -Be 'NOT_READY'
            ($checked.Report.Reasons -join ' ') | Should -Match 'JAWS-STEP-B-019'
            ($checked.Report.Reasons -join ' ') | Should -Not -Match 'list subscription locations'
            ($checked.Report.Reasons -join ' ') | Should -Not -Match 'is not enabled'
            $log = Get-Content -LiteralPath (Join-Path $state 'log.txt') -Raw
            $log | Should -Not -Match 'list-locations'
            $log | Should -Not -Match 'group create'
        } finally {
            $env:PATH = $savedPath
            $env:JAWS_STEPB_STUB_STATE = $savedState
            $env:JAWS_STEPB_STUB_SUB = $savedSub
            $env:JAWS_STEPB_STUB_ENV = $savedEnv
        }
    }

    It 'asks for an environment name and fills the resource group and location' {
        $kept = Resolve-JawsStepBPlanTarget -EnvironmentName 'lab1' -ResourceGroupName 'rg-jaws-lab1' -Location 'eastus' -EnvironmentSupplied -ResourceGroupSupplied -LocationSupplied -NonInteractive
        $kept.Complete | Should -BeTrue
        $kept.EnvironmentName | Should -Be 'lab1'
        $kept.ResourceGroupName | Should -Be 'rg-jaws-lab1'
        $skipped = Resolve-JawsStepBPlanTarget -NonInteractive
        $skipped.Complete | Should -BeFalse
        $answers = [System.Collections.Generic.Queue[string]]::new()
        $answers.Enqueue('customer1')
        $answers.Enqueue('')
        $answers.Enqueue('westus')
        $asked = Resolve-JawsStepBPlanTarget -Prompter { param($Label) $answers.Dequeue() }
        $asked.Complete | Should -BeTrue
        $asked.EnvironmentName | Should -Be 'customer1'
        $asked.ResourceGroupName | Should -Be 'rg-jaws-customer1'
        $asked.Location | Should -Be 'westus'
        $blank = [System.Collections.Generic.Queue[string]]::new()
        $blank.Enqueue('   ')
        { Resolve-JawsStepBPlanTarget -Prompter { param($Label) $blank.Dequeue() } } | Should -Throw '*JAWS-STEP-B-014*'
    }

    It 'lets the operator replace generated resource names and keeps the defaults otherwise' {
        $default = New-JawsStepBInstallScope -SubscriptionId $script:sub -ResourceGroupName 'rg-jaws-lab1' -Location 'eastus' -EnvironmentName 'lab1' -ModelName 'gpt-5-mini' -ModelVersion '2025-08-07'
        $default.FoundryAccountName | Should -Be 'jaws-foundry-lab1'
        $default.ProjectName | Should -Be 'jaws-lab1'
        $default.KeyVaultName | Should -Be 'kvjawslab1'
        $default.RegistryName | Should -Be 'jawsacrlab1'
        $default.AgentName | Should -Be 'jaws-supervisor-lab1'
        $custom = New-JawsStepBInstallScope -SubscriptionId $script:sub -ResourceGroupName 'rg-jaws-lab1' -Location 'eastus' -EnvironmentName 'lab1' -ModelName 'gpt-5-mini' -ModelVersion '2025-08-07' -FoundryAccountName 'jaws-foundry-operator1' -KeyVaultName 'kv-jaws-operator1'
        $custom.FoundryAccountName | Should -Be 'jaws-foundry-operator1'
        $custom.KeyVaultName | Should -Be 'kv-jaws-operator1'
        $custom.ProjectName | Should -Be 'jaws-lab1'
        $custom.RegistryName | Should -Be 'jawsacrlab1'
        $custom.AgentName | Should -Be 'jaws-supervisor-lab1'
        $custom.PlanSha256 | Should -Not -Be $default.PlanSha256
        { New-JawsStepBInstallScope -SubscriptionId $script:sub -ResourceGroupName 'rg-jaws-lab1' -Location 'eastus' -EnvironmentName 'lab1' -ModelName 'gpt-5-mini' -ModelVersion '2025-08-07' -KeyVaultName 'x' } | Should -Throw '*JAWS-STEP-B-027*'
        { New-JawsStepBInstallScope -SubscriptionId $script:sub -ResourceGroupName 'rg-jaws-lab1' -Location 'eastus' -EnvironmentName 'lab1' -ModelName 'gpt-5-mini' -ModelVersion '2025-08-07' -KeyVaultName 'kv--jaws1' } | Should -Throw '*JAWS-STEP-B-027*'
        { New-JawsStepBInstallScope -SubscriptionId $script:sub -ResourceGroupName 'rg-jaws-lab1' -Location 'eastus' -EnvironmentName 'lab1' -ModelName 'gpt-5-mini' -ModelVersion '2025-08-07' -KeyVaultName 'kv-jaws-dev-001' } | Should -Throw '*JAWS-STEP-B-017*'
        { New-JawsStepBInstallScope -SubscriptionId $script:sub -ResourceGroupName 'rg-jaws-lab1' -Location 'eastus' -EnvironmentName 'lab1' -ModelName 'gpt-5-mini' -ModelVersion '2025-08-07' -AcrName 'has-hyphen' } | Should -Throw '*JAWS-STEP-B-027*'
    }

    It 'locks operator resource names in the plan and uses them for install and accept' {
        $state = Join-Path $script:stub 'state-custom-names'
        $savedPath = $env:PATH
        $savedState = $env:JAWS_STEPB_STUB_STATE
        $savedSub = $env:JAWS_STEPB_STUB_SUB
        $savedEnv = $env:JAWS_STEPB_STUB_ENV
        try {
            $env:JAWS_STEPB_STUB_STATE = $state
            $env:JAWS_STEPB_STUB_SUB = $script:sub
            $env:JAWS_STEPB_STUB_ENV = 'ops1'
            $env:JAWS_STEPB_POLL_SECONDS = '0'
            $env:PATH = $script:stub + [System.IO.Path]::PathSeparator + '/usr/bin'
            $planOutput = & (Join-Path $script:root 'installer/Install-Jaws.ps1') -Mode Plan -NonInteractive -EnvironmentName 'ops1' -ResourceGroupName 'rg-jaws-ops1' -Location 'eastus' -FoundryAccountName 'jaws-foundry-ops1b' -KeyVaultName 'kv-jaws-ops1' *>&1 | Out-String
            $planOutput | Should -Match 'STEP-B PLAN PASS'
            $planOutput | Should -Match 'Foundry account: jaws-foundry-ops1b'
            $planOutput | Should -Match 'Key Vault: kv-jaws-ops1'
            $planOutput | Should -Match 'Project: jaws-ops1'
            $planOutput | Should -Match 'Registry: jawsacrops1'
            $planOutput | Should -Match 'Agent: jaws-supervisor-ops1'
            $planPath = Join-Path $script:root 'installer/.local/jaws-stage-b-plan.ops1.offline.generated.json'
            $plan = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
            $scope = New-JawsStepBInstallScope -SubscriptionId $script:sub -ResourceGroupName 'rg-jaws-ops1' -Location 'eastus' -EnvironmentName 'ops1' -ModelName 'gpt-5-mini' -ModelVersion '2025-08-07' -FoundryAccountName 'jaws-foundry-ops1b' -KeyVaultName 'kv-jaws-ops1'
            $plan.PlanSha256 | Should -Be $scope.PlanSha256
            $default = New-JawsStepBInstallScope -SubscriptionId $script:sub -ResourceGroupName 'rg-jaws-ops1' -Location 'eastus' -EnvironmentName 'ops1' -ModelName 'gpt-5-mini' -ModelVersion '2025-08-07'
            $plan.PlanSha256 | Should -Not -Be $default.PlanSha256
            { & (Join-Path $script:root 'installer/Install-Jaws.ps1') -Mode Install -EnvironmentName 'ops1' -ResourceGroupName 'rg-jaws-ops1' -Location 'eastus' -ApprovedPlanSha256 $plan.PlanSha256 -KeyVaultName 'kv-jaws-other1' -AcknowledgeStepBInstall } | Should -Throw '*JAWS-STEP-B-016*'
            $log = if (Test-Path -LiteralPath (Join-Path $state 'log.txt')) { Get-Content -LiteralPath (Join-Path $state 'log.txt') -Raw } else { '' }
            $log | Should -Not -Match 'group create'
            & (Join-Path $script:root 'installer/Install-Jaws.ps1') -Mode Install -EnvironmentName 'ops1' -ResourceGroupName 'rg-jaws-ops1' -Location 'eastus' -ApprovedPlanSha256 $plan.PlanSha256 -AcknowledgeStepBInstall
            $receipt = Get-Content -LiteralPath (Join-Path $script:root 'installer/.local/jaws-step-b-install.ops1.generated.json') -Raw | ConvertFrom-Json
            $receipt.FoundryAccountName | Should -Be 'jaws-foundry-ops1b'
            $receipt.KeyVaultName | Should -Be 'kv-jaws-ops1'
            $receipt.ProjectName | Should -Be 'jaws-ops1'
            $receipt.RegistryName | Should -Be 'jawsacrops1'
            $receipt.AgentName | Should -Be 'jaws-supervisor-ops1'
            $accept = & (Join-Path $script:root 'installer/Install-Jaws.ps1') -Mode Accept -EnvironmentName 'ops1' -ResourceGroupName 'rg-jaws-ops1' -Location 'eastus' *>&1 | Out-String
            $accept | Should -Match 'STEP-B ACCEPTANCE PASS'
            $accept | Should -Match 'Foundry account: jaws-foundry-ops1b'
            $accept | Should -Match 'Key Vault: kv-jaws-ops1'
        } finally {
            $opsLocal = Join-Path $script:root 'installer/.local'
            if (Test-Path -LiteralPath $opsLocal) {
                Get-ChildItem -LiteralPath $opsLocal -Filter '*ops1*' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
            }
            $env:PATH = $savedPath
            if ($null -eq $savedState) { Remove-Item Env:JAWS_STEPB_STUB_STATE -ErrorAction SilentlyContinue } else { $env:JAWS_STEPB_STUB_STATE = $savedState }
            if ($null -eq $savedSub) { Remove-Item Env:JAWS_STEPB_STUB_SUB -ErrorAction SilentlyContinue } else { $env:JAWS_STEPB_STUB_SUB = $savedSub }
            if ($null -eq $savedEnv) { Remove-Item Env:JAWS_STEPB_STUB_ENV -ErrorAction SilentlyContinue } else { $env:JAWS_STEPB_STUB_ENV = $savedEnv }
            Remove-Item Env:JAWS_STEPB_POLL_SECONDS -ErrorAction SilentlyContinue
        }
    }

    It 'treats Foundry not_found and Not Found as a missing Supervisor and still fails without -AllowMissing' {
        $state = Join-Path $script:stub 'state-agent-missing'
        $savedPath = $env:PATH
        $savedState = $env:JAWS_STEPB_STUB_STATE
        $savedSub = $env:JAWS_STEPB_STUB_SUB
        $savedEnv = $env:JAWS_STEPB_STUB_ENV
        $savedMissing = $env:JAWS_STEPB_STUB_AGENT_MISSING
        try {
            $env:JAWS_STEPB_STUB_STATE = $state
            $env:JAWS_STEPB_STUB_SUB = $script:sub
            $env:JAWS_STEPB_STUB_ENV = 'lab1'
            $env:PATH = $script:stub + [System.IO.Path]::PathSeparator + '/usr/bin'
            InModuleScope StepBInstall {
                $arguments = @('rest','--method','GET','--url','https://example.test/agents/jaws-supervisor-lab1/versions/1','--output','json')
                foreach ($body in @('{"error":{"code":"not_found"}}', 'Not Found')) {
                    $env:JAWS_STEPB_STUB_AGENT_MISSING = $body
                    $result = Invoke-JawsStepBAz -AllowMissing -Arguments $arguments
                    $result | Should -BeNullOrEmpty
                }
                $env:JAWS_STEPB_STUB_AGENT_MISSING = '{"error":{"code":"not_found","message":"Not Found"}}'
                { Invoke-JawsStepBAz -Arguments $arguments } | Should -Throw '*JAWS-STEP-B-AZ-001*'
            }
        } finally {
            $env:PATH = $savedPath
            if ($null -eq $savedState) { Remove-Item Env:JAWS_STEPB_STUB_STATE -ErrorAction SilentlyContinue } else { $env:JAWS_STEPB_STUB_STATE = $savedState }
            if ($null -eq $savedSub) { Remove-Item Env:JAWS_STEPB_STUB_SUB -ErrorAction SilentlyContinue } else { $env:JAWS_STEPB_STUB_SUB = $savedSub }
            if ($null -eq $savedEnv) { Remove-Item Env:JAWS_STEPB_STUB_ENV -ErrorAction SilentlyContinue } else { $env:JAWS_STEPB_STUB_ENV = $savedEnv }
            if ($null -eq $savedMissing) { Remove-Item Env:JAWS_STEPB_STUB_AGENT_MISSING -ErrorAction SilentlyContinue } else { $env:JAWS_STEPB_STUB_AGENT_MISSING = $savedMissing }
        }
    }
}
