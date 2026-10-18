BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../installer/modules/StepBInstall.psm1') -Force
    $script:root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $script:sub = '22222222-2222-2222-2222-222222222222'
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
    payload = {"name": "rg-jaws-lab1", "location": "eastus", "tags": tags}
    save("group", payload)
    emit(payload)
if args[:3] == ["cognitiveservices", "account", "show"]:
    emit(load("foundry")) if exists("foundry") else missing()
if args[:3] == ["cognitiveservices", "account", "create"]:
    payload = {"name": "jaws-foundry-lab1", "kind": "AIServices", "properties": {"provisioningState": "Succeeded", "customSubDomainName": "jaws-foundry-lab1"}, "tags": tags}
    save("foundry", payload)
    emit(payload)
if args[:3] == ["cognitiveservices", "account", "list-models"]:
    if os.environ.get("JAWS_STEPB_STUB_HIDE_MODEL") == "1":
        emit([])
    emit([{"format": "OpenAI", "name": "gpt-5-mini", "version": "2025-08-07", "skus": [{"name": "GlobalStandard"}]}])
if args[:4] == ["cognitiveservices", "account", "project", "show"]:
    emit(load("project")) if exists("project") else missing()
if args[:4] == ["cognitiveservices", "account", "project", "create"]:
    payload = {"name": "jaws-lab1", "properties": {"provisioningState": "Succeeded"}, "identity": {"type": "SystemAssigned", "principalId": principal}}
    save("project", payload)
    emit(payload)
if args[:4] == ["cognitiveservices", "account", "deployment", "show"]:
    emit(load("deployment")) if exists("deployment") else missing()
if args[:4] == ["cognitiveservices", "account", "deployment", "create"]:
    payload = {"name": "gpt-5-mini", "properties": {"provisioningState": "Succeeded", "model": {"name": "gpt-5-mini", "version": "2025-08-07"}}}
    save("deployment", payload)
    emit(payload)
if args[:2] == ["keyvault", "show"]:
    emit(load("vault")) if exists("vault") else missing()
if args[:2] == ["keyvault", "create"]:
    payload = {"name": "kvjawslab1", "properties": {"enableRbacAuthorization": True, "enablePurgeProtection": True}, "tags": tags}
    save("vault", payload)
    emit(payload)
if args[:2] == ["acr", "show"]:
    emit(load("registry")) if exists("registry") else missing()
if args[:2] == ["acr", "create"]:
    payload = {"name": "jawsacrlab1", "loginServer": "jawsacrlab1.azurecr.io", "sku": {"name": "Basic"}, "adminUserEnabled": False, "tags": tags}
    save("registry", payload)
    emit(payload)
if args[:2] == ["acr", "login"]:
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
    Set-Content -LiteralPath (Join-Path $script:stub 'docker') -Encoding ascii -Value @'
#!/bin/bash
if [[ "$1" == "image" && "$2" == "inspect" ]]; then
  printf '%s\n' 'sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
  exit 0
fi
exit 0
'@
    foreach ($name in @('az','docker')) { chmod +x (Join-Path $script:stub $name) | Out-Null }
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
            $env:PATH = $script:stub + [System.IO.Path]::PathSeparator + $env:PATH
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
            $receipt.AgentStatus | Should -Be 'active'
            $receipt.Image | Should -Match '@sha256:[a-f]{64}$'
            $receipt.AzureWrites | Should -BeGreaterThan 0
            & (Join-Path $script:root 'installer/Test-JawsStepB.ps1') -Mode Install
            & (Join-Path $script:root 'installer/Install-Jaws.ps1') -Mode Install -EnvironmentName 'lab1' -ResourceGroupName 'rg-jaws-lab1' -Location 'eastus' -ApprovedPlanSha256 $plan.PlanSha256 -AcknowledgeStepBInstall
            $log = Get-Content -LiteralPath (Join-Path $state 'log.txt') -Raw
            @('group create','cognitiveservices account create','project create','deployment create','keyvault create','acr create','role assignment create','rest --method POST').ForEach({ $log | Should -Match ([regex]::Escape($_)) })
            ([regex]::Matches($log, 'cognitiveservices account create')).Count | Should -Be 1
            ([regex]::Matches($log, '/agents\?api-version=v1')).Count | Should -Be 1
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
}
