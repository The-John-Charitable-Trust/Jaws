BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../installer/modules/StepBInstall.psm1') -Force
    $script:root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $script:sub = '22222222-2222-2222-2222-222222222222'
    $script:stub = Join-Path ([System.IO.Path]::GetTempPath()) ('jaws-stepb-private-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:stub | Out-Null
    Set-Content -LiteralPath (Join-Path $script:stub 'az') -Encoding ascii -Value @'
#!/bin/bash
exec python3 "$0.py" "$@"
'@
    Set-Content -LiteralPath (Join-Path $script:stub 'az.py') -Encoding utf8 -Value @'
import json, os, sys
state = os.environ["JAWS_STEPB_STUB_STATE"]
sub = os.environ["JAWS_STEPB_STUB_SUB"]
env = os.environ.get("JAWS_STEPB_STUB_ENV", "priv1")
os.makedirs(state, exist_ok=True)
args = sys.argv[1:]
with open(os.path.join(state, "log.txt"), "a", encoding="utf-8") as handle:
    handle.write(" ".join(args) + "\n")
tags = {"application": "JAWS", "managedBy": "JAWS-Installer", "environment": env}

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

def flag(name, default=""):
    return args[args.index(name) + 1] if name in args else default

def missing():
    print("MISSING", file=sys.stderr)
    sys.exit(3)

def slot():
    name = flag("--name", "")
    if "--zone-name" in args:
        name += "-" + flag("--zone-name", "")
    if "--endpoint-name" in args:
        name += "-" + flag("--endpoint-name", "")
    return "net-" + "-".join(args[:3]) + "-" + name

if args[:2] == ["account", "show"]:
    emit({"id": sub, "name": "stub", "state": "Enabled", "tenantId": "33333333-3333-3333-3333-333333333333", "user": {"name": "installer@stub.example", "type": "user"}})
if args[:2] == ["account", "list-locations"]:
    emit([{"name": "eastus", "displayName": "East US"}])
if args[:2] == ["provider", "show"]:
    emit({"namespace": flag("--namespace", "stub"), "registrationState": "Registered"})
if args[:3] == ["policy", "assignment", "list"]:
    emit([])
if args[:2] == ["group", "show"]:
    emit(load("group")) if exists("group") else missing()
if args[:2] == ["group", "create"]:
    payload = {"name": flag("--name", "rg"), "location": "eastus", "tags": tags}
    save("group", payload)
    emit(payload)
if args[:3] == ["cognitiveservices", "account", "show"]:
    emit(load("foundry")) if exists("foundry") else missing()
if args[:3] == ["cognitiveservices", "account", "list-models"]:
    emit([{"format": "OpenAI", "name": "gpt-5-mini", "version": "2025-08-07", "skus": [{"name": "GlobalStandard"}, {"name": "Standard"}]}])
if args[:4] == ["cognitiveservices", "account", "project", "show"]:
    emit(load("project")) if exists("project") else missing()
if args[:4] == ["cognitiveservices", "account", "project", "create"]:
    payload = {"name": flag("--project-name", "project"), "properties": {"provisioningState": "Succeeded"}, "identity": {"type": "SystemAssigned", "principalId": "11111111-1111-1111-1111-111111111111"}}
    save("project", payload)
    emit(payload)
if args[:4] == ["cognitiveservices", "account", "deployment", "show"]:
    emit(load("deployment")) if exists("deployment") else missing()
if args[:4] == ["cognitiveservices", "account", "deployment", "create"]:
    payload = {"name": "gpt-5-mini", "sku": {"name": flag("--sku-name", "GlobalStandard"), "capacity": 1}, "properties": {"provisioningState": "Succeeded", "model": {"name": "gpt-5-mini", "version": "2025-08-07"}}}
    save("deployment", payload)
    emit(payload)
if args[:2] == ["keyvault", "show"]:
    emit(load("vault")) if exists("vault") else missing()
if args[:2] == ["keyvault", "create"]:
    payload = {"name": flag("--name", "vault"), "properties": {"enableRbacAuthorization": True, "enablePurgeProtection": True, "provisioningState": "Succeeded"}, "tags": tags}
    save("vault", payload)
    emit(payload)
if args[:2] == ["acr", "show"]:
    emit(load("registry")) if exists("registry") else missing()
if args[:2] == ["acr", "create"]:
    registry_name = flag("--name", "registry")
    payload = {"name": registry_name, "loginServer": registry_name + ".azurecr.io", "sku": {"name": "Basic"}, "adminUserEnabled": False, "tags": tags, "properties": {"provisioningState": "Succeeded"}}
    save("registry", payload)
    emit(payload)
if args[:2] == ["acr", "build"]:
    file_arg = flag("--file", "")
    if not file_arg.replace("\\", "/").endswith("src/Jaws.Supervisor.Host/Dockerfile"):
        print("dockerfile must be the Supervisor Dockerfile path", file=sys.stderr)
        sys.exit(2)
    sys.exit(0)
if args[:3] == ["acr", "manifest", "show-metadata"]:
    emit({"digest": "sha256:" + ("a" * 64)})
if args[:2] == ["acr", "check-name"]:
    emit({"nameAvailable": True})
if args[:3] == ["role", "assignment", "list"]:
    if "--assignee-object-id" in args:
        assignee = flag("--assignee-object-id", "")
        roles = load("roles") if exists("roles") else {}
        emit([roles[assignee]] if assignee in roles else [])
    emit([{"roleDefinitionName": "Owner", "scope": "/subscriptions/" + sub}])
if args[:3] == ["role", "assignment", "create"]:
    assignee = flag("--assignee-object-id", "11111111-1111-1111-1111-111111111111")
    payload = {"roleDefinitionName": "AcrPull", "principalId": assignee, "scope": "registry"}
    roles = load("roles") if exists("roles") else {}
    roles[assignee] = payload
    save("roles", roles)
    emit(payload)
if args[:1] == ["rest"] and "--method" in args:
    method = flag("--method", "").upper()
    url = flag("--url", "")
    if method == "POST" and "checkSkuAvailability" in url:
        emit({"value": [{"skuName": "S0", "skuAvailable": True}]})
    if method == "POST" and ("checkNameAvailability" in url or "checkDomainAvailability" in url):
        emit({"nameAvailable": True, "isSubdomainAvailable": True})
    if method == "GET" and "services.ai.azure.com" in url and "/agents?" in url:
        if os.environ.get("JAWS_STEPB_STUB_PRIVATE_REACHABLE") != "1":
            print("Name or service not known", file=sys.stderr)
            sys.exit(1)
        emit({"value": []})
    if method == "GET" and "api-version=2025-04-01-preview" in url:
        emit(load("foundry")) if exists("foundry") else missing()
    if method == "PUT" and "api-version=2025-04-01-preview" in url:
        with open(flag("--body", "")[1:], encoding="utf-8") as handle:
            body = json.load(handle)
        body["properties"]["provisioningState"] = "Succeeded"
        save("foundry", body)
        emit(body)
    if method == "GET" and "/versions/1" in url:
        if exists("agent"):
            emit(load("agent"))
        print('{"error":{"code":"not_found","message":"Not Found"}}', file=sys.stderr)
        sys.exit(1)
    if method == "POST" and "/agents?api-version=v1" in url:
        with open(flag("--body", "")[1:], encoding="utf-8") as handle:
            body = json.load(handle)
        image = body["definition"]["container_configuration"]["image"]
        payload = {"name": body["name"], "status": "active", "draft": False, "version": "1", "instance_identity": {"principal_id": "33333333-3333-3333-3333-333333333333", "client_id": "33333333-3333-3333-3333-333333333333"}, "definition": {"container_configuration": {"image": image}}}
        save("agent", payload)
        emit(payload)
    if method == "GET" and "/agents/" in url:
        emit(load("agent")) if exists("agent") else missing()
if args and args[0] in ("network", "dns-resolver") and any(word in args for word in ("show", "create", "add", "update")):
    key = slot()
    if "show" in args:
        emit(load(key)) if exists(key) else missing()
    name = flag("--name", "item")
    resource_group = flag("--resource-group", "rg")
    payload = {
        "name": name,
        "id": "/subscriptions/%s/resourceGroups/%s/providers/Microsoft.Network/%s/%s" % (sub, resource_group, args[1], name),
        "properties": {"provisioningState": "Succeeded"},
        "ipConfigurations": [{"privateIpAddress": "10.42.6.4"}],
        "privateIpAddress": "10.42.6.4"
    }
    if "subnet" in args:
        payload["id"] = "/subscriptions/%s/resourceGroups/%s/providers/Microsoft.Network/virtualNetworks/%s/subnets/%s" % (sub, resource_group, flag("--vnet-name", "vnet"), name)
    save(key, payload)
    emit(payload)
print("unexpected " + " ".join(args), file=sys.stderr)
sys.exit(9)
'@
    & chmod a+x (Join-Path $script:stub 'az')
    $script:originalPath = $env:PATH
    $env:PATH = "$script:stub$([IO.Path]::PathSeparator)$env:PATH"
    $env:JAWS_STEPB_STUB_STATE = $script:stub
    $env:JAWS_STEPB_STUB_SUB = $script:sub
    $env:JAWS_STEPB_STUB_ENV = 'priv1'
    $env:JAWS_STEPB_POLL_SECONDS = '0'
}

AfterAll {
    $env:PATH = $script:originalPath
    Remove-Item Env:JAWS_STEPB_STUB_PRIVATE_REACHABLE -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $script:stub -Recurse -Force -ErrorAction SilentlyContinue
    foreach ($name in @('priv1','badp')) {
        Get-ChildItem -LiteralPath (Join-Path $script:root 'installer/.local') -Filter "*$name*" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Step B private profile' {
    It 'keeps the public plan digest and gives the private plan a different digest' {
        $common = @{
            SubscriptionId = $script:sub
            ResourceGroupName = 'rg-jaws-priv1'
            Location = 'eastus'
            EnvironmentName = 'priv1'
            ModelName = 'gpt-5-mini'
            ModelVersion = '2025-08-07'
        }
        $public = New-JawsStepBInstallScope @common -NetworkProfile Public
        $omitted = New-JawsStepBInstallScope @common
        $private = New-JawsStepBInstallScope @common -NetworkProfile Private
        $historical = @(
            'JAWS-STEP-B-SCOPE-1',
            $public.SubscriptionId,
            $public.ResourceGroupName,
            $public.Location,
            $public.EnvironmentName,
            $public.FoundryAccountName,
            $public.ProjectName,
            $public.ModelDeploymentName,
            $public.ModelName,
            $public.ModelVersion,
            $public.KeyVaultName,
            $public.RegistryName,
            $public.AgentName
        ) -join "`n"
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try { $bytes = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($historical)) }
        finally { $sha.Dispose() }
        $historicalSha = ([BitConverter]::ToString($bytes)).Replace('-','').ToLowerInvariant()
        $public.PlanSha256 | Should -Be $historicalSha
        $omitted.PlanSha256 | Should -Be $public.PlanSha256
        $private.PlanSha256 | Should -Not -Be $public.PlanSha256
    }

    It 'plans the private profile with no Azure writes' {
        $output = & (Join-Path $script:root 'installer/Install-Jaws.ps1') -Mode Plan -NonInteractive -EnvironmentName 'priv1' -ResourceGroupName 'rg-jaws-priv1' -Location 'eastus' -SubscriptionId $script:sub -NetworkProfile Private *>&1 | Out-String
        $output | Should -Match 'STEP-B PLAN PASS'
        $output | Should -Match 'Network profile: Private'
        $output | Should -Match 'Azure writes: 0'
        $output | Should -Match 'point-to-site VPN'
        $plan = Get-Content -LiteralPath (Join-Path $script:root 'installer/.local/jaws-stage-b-plan.priv1.offline.generated.json') -Raw | ConvertFrom-Json
        [string]$plan.InstallScope.NetworkProfile | Should -Be 'Private'
    }

    It 'creates the private account from this computer and pauses before the Supervisor' {
        if (Test-Path (Join-Path $script:stub 'log.txt')) { Remove-Item (Join-Path $script:stub 'log.txt') }
        $plan = Get-Content -LiteralPath (Join-Path $script:root 'installer/.local/jaws-stage-b-plan.priv1.offline.generated.json') -Raw | ConvertFrom-Json
        $output = & (Join-Path $script:root 'installer/Install-Jaws.ps1') -Mode Install -EnvironmentName 'priv1' -ResourceGroupName 'rg-jaws-priv1' -Location 'eastus' -ApprovedPlanSha256 $plan.PlanSha256 -NetworkProfile Private -AcknowledgeStepBInstall *>&1 | Out-String
        $output | Should -Match 'STEP-B INSTALL PAUSED'
        $output | Should -Match 'Private posture: verified'
        $output | Should -Match 'Supervisor created: false'
        $output | Should -Match 'jaws-vpn-priv1'
        $output | Should -Match '10\.42\.6\.4'
        $output | Should -Not -Match 'STEP-B INSTALL PASS'
        $log = Get-Content -LiteralPath (Join-Path $script:stub 'log.txt') -Raw
        $log | Should -Match '10\.42\.0\.0/16'
        $log | Should -Match '10\.42\.2\.0/24'
        $log | Should -Match '10\.42\.3\.0/24'
        $log | Should -Match 'GatewaySubnet'
        $log | Should -Match '10\.42\.6\.0/28'
        $log | Should -Match 'rest --method PUT'
        $log | Should -Not -Match 'acr build'
        $body = Get-Content -LiteralPath (Join-Path $script:root 'installer/.local/jaws-step-b-foundry-private.priv1.json') -Raw
        $body | Should -Match '"publicNetworkAccess":"Disabled"'
        $body | Should -Match 'jaws-foundry-agents'
        $body | Should -Not -Match 'networkAcls'
        $body | Should -Not -Match '"publicNetworkAccess":"Enabled"'
        $puts = ([regex]::Matches($log, 'rest --method PUT')).Count
        $again = & (Join-Path $script:root 'installer/Install-Jaws.ps1') -Mode Install -EnvironmentName 'priv1' -ResourceGroupName 'rg-jaws-priv1' -Location 'eastus' -ApprovedPlanSha256 $plan.PlanSha256 -AcknowledgeStepBInstall *>&1 | Out-String
        $again | Should -Match 'STEP-B INSTALL PAUSED'
        $log = Get-Content -LiteralPath (Join-Path $script:stub 'log.txt') -Raw
        ([regex]::Matches($log, 'rest --method PUT')).Count | Should -Be $puts
    }

    It 'continues the same Install after the computer can reach the private data plane' {
        $env:JAWS_STEPB_STUB_PRIVATE_REACHABLE = '1'
        $plan = Get-Content -LiteralPath (Join-Path $script:root 'installer/.local/jaws-stage-b-plan.priv1.offline.generated.json') -Raw | ConvertFrom-Json
        $output = & (Join-Path $script:root 'installer/Install-Jaws.ps1') -Mode Install -EnvironmentName 'priv1' -ResourceGroupName 'rg-jaws-priv1' -Location 'eastus' -ApprovedPlanSha256 $plan.PlanSha256 -AcknowledgeStepBInstall *>&1 | Out-String
        $output | Should -Match 'STEP-B INSTALL PASS'
        $output | Should -Match 'Agent status: active'
        $receipt = Get-Content -LiteralPath (Join-Path $script:root 'installer/.local/jaws-step-b-install.priv1.generated.json') -Raw | ConvertFrom-Json
        [string]$receipt.Status | Should -Be 'STEP_B_INSTALLED'
        [string]$receipt.NetworkProfile | Should -Be 'Private'
        Remove-Item Env:JAWS_STEPB_STUB_PRIVATE_REACHABLE
    }

    It 'refuses to convert an existing public account' {
        $env:JAWS_STEPB_STUB_ENV = 'badp'
        & (Join-Path $script:root 'installer/Install-Jaws.ps1') -Mode Plan -NonInteractive -EnvironmentName 'badp' -ResourceGroupName 'rg-jaws-badp' -Location 'eastus' -SubscriptionId $script:sub -NetworkProfile Private *>&1 | Out-Null
        $plan = Get-Content -LiteralPath (Join-Path $script:root 'installer/.local/jaws-stage-b-plan.badp.offline.generated.json') -Raw | ConvertFrom-Json
        foreach ($name in @('vault','registry','project','deployment','agent','roles')) {
            $file = Join-Path $script:stub $name
            if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force }
        }
        @{
            name = 'jaws-foundry-badp'
            kind = 'AIServices'
            tags = @{ application = 'JAWS'; managedBy = 'JAWS-Installer'; environment = 'badp' }
            properties = @{ provisioningState = 'Succeeded'; publicNetworkAccess = 'Enabled'; customSubDomainName = 'jaws-foundry-badp' }
        } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $script:stub 'foundry') -Encoding utf8
        $output = ''
        try {
            & (Join-Path $script:root 'installer/Install-Jaws.ps1') -Mode Install -EnvironmentName 'badp' -ResourceGroupName 'rg-jaws-badp' -Location 'eastus' -ApprovedPlanSha256 $plan.PlanSha256 -AcknowledgeStepBInstall *>&1 | ForEach-Object { $output += "$_`n" }
        } catch { $output += $_.Exception.Message }
        $output | Should -Match 'JAWS-STEP-B-028'
        $output | Should -Not -Match 'rest --method PUT'
        $env:JAWS_STEPB_STUB_ENV = 'priv1'
    }
}
