BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../installer/modules/StepBInstall.psm1') -Force
    $script:root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $script:sub = '22222222-2222-2222-2222-222222222222'
    $script:image = 'jawsacracc1.azurecr.io/jaws/supervisor@sha256:' + ('a' * 64)
    $script:stub = Join-Path ([System.IO.Path]::GetTempPath()) ('jaws-stepb-model-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:stub | Out-Null
    Set-Content -LiteralPath (Join-Path $script:stub 'az') -Encoding ascii -Value @'
#!/bin/bash
exec python3 "$0.py" "$@"
'@
    Set-Content -LiteralPath (Join-Path $script:stub 'az.py') -Encoding utf8 -Value @'
import json, os, sys
state = os.environ["JAWS_STEPB_STUB_STATE"]
sub = os.environ["JAWS_STEPB_STUB_SUB"]
env = os.environ.get("JAWS_STEPB_STUB_ENV", "m51")
fixture = os.environ.get("JAWS_STEPB_MODEL_FIXTURE", "mini-global")
os.makedirs(state, exist_ok=True)
args = sys.argv[1:]
with open(os.path.join(state, "log.txt"), "a", encoding="utf-8") as handle:
    handle.write(" ".join(args) + "\n")
tags = {"application": "JAWS", "managedBy": "JAWS-Installer", "environment": env}
image = "jawsacracc1.azurecr.io/jaws/supervisor@sha256:" + ("a" * 64)

def emit(payload):
    print(json.dumps(payload))
    sys.exit(0)

def flag(name, default=""):
    return args[args.index(name) + 1] if name in args else default

if args[:2] == ["account", "show"]:
    emit({"id": sub, "name": "stub", "state": "Enabled", "tenantId": "33333333-3333-3333-3333-333333333333", "user": {"name": "installer@stub.example", "type": "user"}})
if args[:2] == ["account", "list-locations"]:
    emit([{"name": "eastus", "displayName": "East US"}])
if args[:2] == ["provider", "show"]:
    emit({"namespace": flag("--namespace", "stub"), "registrationState": "Registered"})
if args[:3] == ["policy", "assignment", "list"]:
    emit([])
if args[:2] == ["group", "show"]:
    emit({"name": "rg-jaws-" + env, "location": "eastus", "tags": tags})
if args[:3] == ["cognitiveservices", "account", "show"]:
    emit({"name": "jaws-foundry-" + env, "kind": "AIServices", "location": "eastus", "tags": tags, "properties": {"provisioningState": "Succeeded", "customSubDomainName": "jaws-foundry-" + env}})
if args[:3] == ["cognitiveservices", "model", "list"]:
    if fixture == "gpt51-standard":
        emit([{"format": "OpenAI", "name": "gpt-5.1", "version": "2025-11-13", "skus": [{"name": "Standard"}, {"name": "GlobalStandard"}]}])
    if fixture == "unknown":
        emit([{"format": "OpenAI", "name": "gpt-5.1", "version": "2025-11-13", "skus": [{"name": "Standard"}]}])
    emit([{"format": "OpenAI", "name": "gpt-5-mini", "version": "2025-08-07", "skus": [{"name": "GlobalStandard"}, {"name": "DataZoneStandard"}, {"name": "DataZoneProvisionedManaged"}, {"name": "GlobalProvisionedManaged"}]}])
if args[:3] == ["cognitiveservices", "usage", "list"]:
    if fixture == "gpt51-standard":
        emit([
            {"name": {"value": "OpenAI.Standard.gpt-5.1"}, "currentValue": 0, "limit": 1},
            {"name": {"value": "OpenAI.GlobalStandard.gpt-5.1"}, "currentValue": 0, "limit": 1}
        ])
    if fixture == "unknown":
        emit([{"name": {"value": "OpenAI.Standard.gpt-5.1"}, "currentValue": 0, "limit": 1}])
    emit([
        {"name": {"value": "OpenAI.GlobalStandard.gpt-5-mini"}, "currentValue": 0, "limit": 1},
        {"name": {"value": "OpenAI.DataZoneStandard.gpt-5-mini"}, "currentValue": 0, "limit": 1}
    ])
if args[:4] == ["cognitiveservices", "account", "project", "show"]:
    emit({"name": "jaws-" + env, "properties": {"provisioningState": "Succeeded"}, "identity": {"type": "SystemAssigned", "principalId": "11111111-1111-1111-1111-111111111111"}})
if args[:4] == ["cognitiveservices", "account", "deployment", "show"]:
    emit({"name": "gpt-5.1", "sku": {"name": "GlobalStandard", "capacity": 1}, "properties": {"provisioningState": "Succeeded", "model": {"name": "gpt-5.1", "version": "2025-11-13"}}})
if args[:2] == ["keyvault", "show"]:
    emit({"name": "kvjaws" + env, "tags": tags, "properties": {"enableRbacAuthorization": True, "enablePurgeProtection": True, "provisioningState": "Succeeded"}})
if args[:2] == ["acr", "show"]:
    emit({"name": "jawsacr" + env, "tags": tags, "sku": {"name": "Basic"}, "adminUserEnabled": False, "properties": {"provisioningState": "Succeeded"}})
if args[:3] == ["role", "assignment", "list"]:
    if "--assignee-object-id" in args:
        emit([{"roleDefinitionName": "AcrPull", "principalId": flag("--assignee-object-id", ""), "scope": "registry"}])
    emit([{"roleDefinitionName": "Owner", "scope": "/subscriptions/" + sub}])
if args[:1] == ["rest"] and "--method" in args:
    url = flag("--url", "")
    if "/versions/1" in url:
        emit({"name": "jaws-supervisor-" + env, "status": "active", "draft": False, "version": "1", "instance_identity": {"principal_id": "33333333-3333-3333-3333-333333333333"}, "definition": {"container_configuration": {"image": image}}})
print("unexpected " + " ".join(args), file=sys.stderr)
sys.exit(9)
'@
    chmod +x (Join-Path $script:stub 'az') | Out-Null

    function Invoke-JawsModelPlan {
        param([Parameter(Mandatory)][string]$EnvironmentName,[hashtable]$Extra)
        $planArgs = @{
            Mode = 'Plan'
            NonInteractive = $true
            EnvironmentName = $EnvironmentName
            ResourceGroupName = "rg-jaws-$EnvironmentName"
            Location = 'eastus'
            SubscriptionId = $script:sub
        }
        foreach ($key in @($Extra.Keys)) { $planArgs[$key] = $Extra[$key] }
        $output = & (Join-Path $script:root 'installer/Install-Jaws.ps1') @planArgs *>&1 | Out-String
        $path = Join-Path $script:root "installer/.local/jaws-stage-b-plan.$EnvironmentName.offline.generated.json"
        return [pscustomobject]@{ Output = $output; Path = $path; Plan = (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json) }
    }

    function Invoke-JawsModelChecked {
        param([Parameter(Mandatory)][scriptblock]$Command)
        $text = ''
        $threw = $false
        try {
            & $Command *>&1 | ForEach-Object { $text += "$_`n" }
        } catch {
            $threw = $true
            $text += $_.Exception.Message
        }
        return [pscustomobject]@{ Threw = $threw; Text = $text }
    }
}

Describe 'Step B model choice' {
    AfterAll {
        $local = Join-Path $script:root 'installer/.local'
        if (Test-Path -LiteralPath $local) {
            foreach ($name in @('gold1','m51','mmini','mnone','acc1')) {
                Get-ChildItem -LiteralPath $local -Filter "*$name*" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'keeps the default Plan file and digest byte-identical to current main' {
        $goldenPath = Join-Path $PSScriptRoot 'fixtures/jaws-stage-b-plan.gold1.offline.json'
        $planned = Invoke-JawsModelPlan -EnvironmentName 'gold1' -Extra @{}
        $expected = [System.IO.File]::ReadAllBytes($goldenPath)
        $actual = [System.IO.File]::ReadAllBytes($planned.Path)
        [System.Linq.Enumerable]::SequenceEqual([byte[]]$expected, [byte[]]$actual) | Should -BeTrue
        $golden = Get-Content -LiteralPath $goldenPath -Raw | ConvertFrom-Json
        $planned.Plan.PlanSha256 | Should -Be $golden.PlanSha256
        $planned.Plan.InstallScope.ModelName | Should -Be 'gpt-5-mini'
        $planned.Plan.InstallScope.ModelVersion | Should -Be '2025-08-07'
        $planned.Output | Should -Match "Plan SHA-256: $($golden.PlanSha256)"
        $planned.Plan.PlanSha256 | Should -Be '5344e84c4215c37784f46c0690dd7cb15fe77850d41c8ffadfbf41dbdfd2c4e6'
    }

    It 'passes Preflight for gpt-5.1 with Dynamic when the location offers regional Standard' {
        $state = Join-Path $script:stub 'state-m51'
        $savedPath = $env:PATH
        try {
            $env:JAWS_STEPB_STUB_STATE = $state
            $env:JAWS_STEPB_STUB_SUB = $script:sub
            $env:JAWS_STEPB_STUB_ENV = 'm51'
            $env:JAWS_STEPB_MODEL_FIXTURE = 'gpt51-standard'
            $env:PATH = $script:stub + [System.IO.Path]::PathSeparator + '/usr/bin'
            $plan = Invoke-JawsModelPlan -EnvironmentName 'm51' -Extra @{ ModelName = 'gpt-5.1'; ModelVersion = '2025-11-13' }
            $checked = Invoke-JawsModelChecked -Command { & (Join-Path $script:root 'installer/Install-Jaws.ps1') -Mode Preflight -EnvironmentName 'm51' -ResourceGroupName 'rg-jaws-m51' -Location 'eastus' -QuotaMode Dynamic }
            $checked.Threw | Should -BeFalse
            $checked.Text | Should -Match 'STEP-B PREFLIGHT PASS'
            $checked.Text | Should -Match 'Model check: passed'
            $checked.Text | Should -Match 'Azure writes: 0'
            $report = Get-Content -LiteralPath (Join-Path $script:root 'installer/.local/jaws-step-b-preflight.m51.generated.json') -Raw | ConvertFrom-Json
            $report.ModelCheck | Should -Be 'passed'
            $report.AzureWrites | Should -Be 0
            $log = Get-Content -LiteralPath (Join-Path $state 'log.txt') -Raw
            $log | Should -Match 'cognitiveservices model list'
            $log | Should -Match 'cognitiveservices usage list'
            $log | Should -Not -Match 'group create'
            $plan.Plan.InstallScope.ModelName | Should -Be 'gpt-5.1'
        } finally {
            $env:PATH = $savedPath
            Remove-Item Env:JAWS_STEPB_STUB_STATE, Env:JAWS_STEPB_STUB_SUB, Env:JAWS_STEPB_STUB_ENV, Env:JAWS_STEPB_MODEL_FIXTURE -ErrorAction SilentlyContinue
        }
    }

    It 'stops gpt-5-mini with Dynamic before any Azure write and names the missing Standard SKU' {
        $state = Join-Path $script:stub 'state-mmini'
        $savedPath = $env:PATH
        try {
            $env:JAWS_STEPB_STUB_STATE = $state
            $env:JAWS_STEPB_STUB_SUB = $script:sub
            $env:JAWS_STEPB_STUB_ENV = 'mmini'
            $env:JAWS_STEPB_MODEL_FIXTURE = 'mini-global'
            $env:PATH = $script:stub + [System.IO.Path]::PathSeparator + '/usr/bin'
            $plan = Invoke-JawsModelPlan -EnvironmentName 'mmini' -Extra @{}
            $preflight = Invoke-JawsModelChecked -Command { & (Join-Path $script:root 'installer/Install-Jaws.ps1') -Mode Preflight -EnvironmentName 'mmini' -ResourceGroupName 'rg-jaws-mmini' -Location 'eastus' -QuotaMode Dynamic }
            $preflight.Threw | Should -BeTrue
            $preflight.Text | Should -Match 'JAWS-STEP-B-030'
            $preflight.Text | Should -Match 'gpt-5-mini'
            $preflight.Text | Should -Match '2025-08-07'
            $preflight.Text | Should -Match 'eastus'
            $preflight.Text | Should -Match 'Dynamic'
            $preflight.Text | Should -Match 'regional Standard'
            $preflight.Text | Should -Match 'GlobalStandard'
            $preflight.Text | Should -Not -Match 'JAWS-STEP-B-026'
            $report = Get-Content -LiteralPath (Join-Path $script:root 'installer/.local/jaws-step-b-preflight.mmini.generated.json') -Raw | ConvertFrom-Json
            $report.AzureWrites | Should -Be 0
            $report.ModelCheck | Should -Be 'failed'
            $install = Invoke-JawsModelChecked -Command { & (Join-Path $script:root 'installer/Install-Jaws.ps1') -Mode Install -EnvironmentName 'mmini' -ResourceGroupName 'rg-jaws-mmini' -Location 'eastus' -QuotaMode Dynamic -ApprovedPlanSha256 $plan.Plan.PlanSha256 -AcknowledgeStepBInstall }
            $install.Threw | Should -BeTrue
            $install.Text | Should -Match 'JAWS-STEP-B-030'
            $install.Text | Should -Match 'gpt-5-mini'
            $install.Text | Should -Match 'regional Standard'
            $log = Get-Content -LiteralPath (Join-Path $state 'log.txt') -Raw
            $log | Should -Not -Match 'group create'
            $log | Should -Not -Match 'account create'
            $log | Should -Not -Match 'deployment create'
        } finally {
            $env:PATH = $savedPath
            Remove-Item Env:JAWS_STEPB_STUB_STATE, Env:JAWS_STEPB_STUB_SUB, Env:JAWS_STEPB_STUB_ENV, Env:JAWS_STEPB_MODEL_FIXTURE -ErrorAction SilentlyContinue
        }
    }

    It 'stops a model the location catalog does not offer' {
        $state = Join-Path $script:stub 'state-mnone'
        $savedPath = $env:PATH
        try {
            $env:JAWS_STEPB_STUB_STATE = $state
            $env:JAWS_STEPB_STUB_SUB = $script:sub
            $env:JAWS_STEPB_STUB_ENV = 'mnone'
            $env:JAWS_STEPB_MODEL_FIXTURE = 'unknown'
            $env:PATH = $script:stub + [System.IO.Path]::PathSeparator + '/usr/bin'
            $plan = Invoke-JawsModelPlan -EnvironmentName 'mnone' -Extra @{ ModelName = 'not-a-model'; ModelVersion = '2099-01-01' }
            $preflight = Invoke-JawsModelChecked -Command { & (Join-Path $script:root 'installer/Install-Jaws.ps1') -Mode Preflight -EnvironmentName 'mnone' -ResourceGroupName 'rg-jaws-mnone' -Location 'eastus' -QuotaMode Dynamic }
            $preflight.Threw | Should -BeTrue
            $preflight.Text | Should -Match 'JAWS-STEP-B-030'
            $preflight.Text | Should -Match 'not-a-model'
            $preflight.Text | Should -Match '2099-01-01'
            $preflight.Text | Should -Match 'is not offered'
            $preflight.Text | Should -Match 'No Azure writes were attempted'
            $install = Invoke-JawsModelChecked -Command { & (Join-Path $script:root 'installer/Install-Jaws.ps1') -Mode Install -EnvironmentName 'mnone' -ResourceGroupName 'rg-jaws-mnone' -Location 'eastus' -QuotaMode Dynamic -ApprovedPlanSha256 $plan.Plan.PlanSha256 -AcknowledgeStepBInstall }
            $install.Threw | Should -BeTrue
            $install.Text | Should -Match 'JAWS-STEP-B-030'
            $log = Get-Content -LiteralPath (Join-Path $state 'log.txt') -Raw
            $log | Should -Not -Match 'group create'
            $log | Should -Not -Match 'account create'
        } finally {
            $env:PATH = $savedPath
            Remove-Item Env:JAWS_STEPB_STUB_STATE, Env:JAWS_STEPB_STUB_SUB, Env:JAWS_STEPB_STUB_ENV, Env:JAWS_STEPB_MODEL_FIXTURE -ErrorAction SilentlyContinue
        }
    }

    It 'trusts the install receipt when Accept is given no model parameters and stops when the caller disagrees' {
        $state = Join-Path $script:stub 'state-acc1'
        $savedPath = $env:PATH
        try {
            $env:JAWS_STEPB_STUB_STATE = $state
            $env:JAWS_STEPB_STUB_SUB = $script:sub
            $env:JAWS_STEPB_STUB_ENV = 'acc1'
            $env:JAWS_STEPB_MODEL_FIXTURE = 'gpt51-standard'
            $env:PATH = $script:stub + [System.IO.Path]::PathSeparator + '/usr/bin'
            $scope = New-JawsStepBInstallScope -SubscriptionId $script:sub -ResourceGroupName 'rg-jaws-acc1' -Location 'eastus' -EnvironmentName 'acc1' -ModelName 'gpt-5.1' -ModelVersion '2025-11-13'
            $local = Join-Path $script:root 'installer/.local'
            if (-not (Test-Path -LiteralPath $local)) { New-Item -ItemType Directory -Path $local | Out-Null }
            [pscustomobject]@{
                Status = 'STEP_B_INSTALLED'
                PlanSha256 = $scope.PlanSha256
                SubscriptionId = $script:sub
                ResourceGroupName = 'rg-jaws-acc1'
                Location = 'eastus'
                EnvironmentName = 'acc1'
                FoundryAccountName = $scope.FoundryAccountName
                ProjectName = $scope.ProjectName
                ProjectPrincipalId = '11111111-1111-1111-1111-111111111111'
                ModelDeploymentName = $scope.ModelDeploymentName
                ModelName = 'gpt-5.1'
                ModelVersion = '2025-11-13'
                ModelSku = 'GlobalStandard'
                QuotaMode = 'Static'
                KeyVaultName = $scope.KeyVaultName
                RegistryName = $scope.RegistryName
                Image = $script:image
                AgentName = $scope.AgentName
                NetworkProfile = 'Public'
            } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $local 'jaws-step-b-install.acc1.generated.json') -Encoding utf8
            $disagreed = Invoke-JawsModelChecked -Command { & (Join-Path $script:root 'installer/Install-Jaws.ps1') -Mode Accept -EnvironmentName 'acc1' -ResourceGroupName 'rg-jaws-acc1' -Location 'eastus' -ModelName 'gpt-5-mini' -ModelVersion '2025-08-07' }
            $disagreed.Threw | Should -BeTrue
            $disagreed.Text | Should -Match 'JAWS-STEP-B-025'
            $disagreed.Text | Should -Match 'gpt-5-mini'
            $disagreed.Text | Should -Match 'gpt-5\.1'
            $disagreed.Text | Should -Match '2025-08-07'
            $disagreed.Text | Should -Match '2025-11-13'
            $logDuringDisagreement = Join-Path $state 'log.txt'
            if (Test-Path -LiteralPath $logDuringDisagreement) {
                (Get-Content -LiteralPath $logDuringDisagreement -Raw) | Should -Not -Match 'account show'
            }
            $accepted = Invoke-JawsModelChecked -Command { & (Join-Path $script:root 'installer/Install-Jaws.ps1') -Mode Accept -EnvironmentName 'acc1' -ResourceGroupName 'rg-jaws-acc1' -Location 'eastus' }
            $accepted.Threw | Should -BeFalse
            $accepted.Text | Should -Match 'STEP-B ACCEPTANCE PASS'
            $accepted.Text | Should -Match 'Model: gpt-5.1 2025-11-13'
            $report = Get-Content -LiteralPath (Join-Path $local 'jaws-step-b-acceptance.acc1.generated.json') -Raw | ConvertFrom-Json
            $report.ModelName | Should -Be 'gpt-5.1'
            $report.ModelVersion | Should -Be '2025-11-13'
            $matched = Invoke-JawsModelChecked -Command { & (Join-Path $script:root 'installer/Install-Jaws.ps1') -Mode Accept -EnvironmentName 'acc1' -ResourceGroupName 'rg-jaws-acc1' -Location 'eastus' -ModelName 'gpt-5.1' -ModelVersion '2025-11-13' }
            $matched.Threw | Should -BeFalse
            $matched.Text | Should -Match 'Model: gpt-5.1 2025-11-13'
        } finally {
            $env:PATH = $savedPath
            Remove-Item Env:JAWS_STEPB_STUB_STATE, Env:JAWS_STEPB_STUB_SUB, Env:JAWS_STEPB_STUB_ENV, Env:JAWS_STEPB_MODEL_FIXTURE -ErrorAction SilentlyContinue
        }
    }
}
