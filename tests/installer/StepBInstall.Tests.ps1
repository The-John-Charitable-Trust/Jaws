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
    emit({"id": sub, "name": "stub", "state": "Enabled", "tenantId": "33333333-3333-3333-3333-333333333333"})
if args[:2] == ["account", "list"]:
    emit([{"id": sub, "name": "stub", "state": "Enabled", "tenantId": "33333333-3333-3333-3333-333333333333"}])
if args[:2] == ["group", "show"]:
    emit(load("group")) if exists("group") else missing()
if args[:2] == ["group", "create"]:
    payload = {"name": "rg-jaws-lab1", "location": "eastus", "tags": tags}
    save("group", payload)
    emit(payload)
if args[:3] == ["cognitiveservices", "account", "show"]:
    emit(load("foundry")) if exists("foundry") else missing()
if args[:3] == ["cognitiveservices", "account", "create"]:
    payload = {"name": "jaws-foundry-lab1", "kind": "AIServices", "properties": {"provisioningState": "Succeeded"}, "tags": tags}
    save("foundry", payload)
    emit(payload)
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
if args[:3] == ["role", "assignment", "list"]:
    emit([load("role")] if exists("role") else [])
if args[:3] == ["role", "assignment", "create"]:
    payload = {"roleDefinitionName": "AcrPull", "principalId": principal, "scope": "registry"}
    save("role", payload)
    emit(payload)
if args[:1] == ["rest"] and "--method" in args:
    method = args[args.index("--method") + 1]
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
            ([regex]::Matches($log, 'rest --method POST')).Count | Should -Be 1
            $log | Should -Not -Match 'jaws-foundry-dev'
            $log | Should -Not -Match 'c52f597b-7753-45b4-a764-67e290dcfd5e'
            (Get-Content -LiteralPath (Join-Path $script:root 'installer/config/jaws-installation-state.dev.json') -Raw) | Should -Be $devBefore
        } finally {
            $env:PATH = $savedPath
            $env:JAWS_STEPB_STUB_STATE = $savedState
            $env:JAWS_STEPB_STUB_SUB = $savedSub
            $env:JAWS_STEPB_STUB_ENV = $savedEnv
        }
    }
}
