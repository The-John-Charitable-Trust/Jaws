BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../installer/modules/Uninstall.psm1') -Force
    $script:root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $script:sub = '22222222-2222-2222-2222-222222222222'
    $script:stub = Join-Path ([System.IO.Path]::GetTempPath()) ('jaws-uninstall-stub-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:stub | Out-Null
    Set-Content -LiteralPath (Join-Path $script:stub 'az') -Encoding ascii -Value @'
#!/bin/bash
exec python3 "$0.py" "$@"
'@
    Set-Content -LiteralPath (Join-Path $script:stub 'az.py') -Encoding utf8 -Value @'
import json, os, sys
state = os.environ["JAWS_UNINSTALL_STUB_STATE"]
os.makedirs(state, exist_ok=True)
args = sys.argv[1:]
with open(os.path.join(state, "log.txt"), "a", encoding="utf-8") as handle:
    handle.write(" ".join(args) + "\n")
world_path = os.path.join(state, "world.json")
world = {"group": True, "agents": ["jaws-supervisor-uninst1", "jaws-vm-specialist-uninst1"], "toolboxes": ["jaws-browser-tools"], "connections": ["jaws-investigation-a2a-uninst1"], "project": True, "account": True, "vault": True}
if os.path.exists(world_path):
    with open(world_path, encoding="utf-8") as handle:
        world = json.load(handle)

def save():
    with open(world_path, "w", encoding="utf-8") as handle:
        json.dump(world, handle)

def emit(payload):
    print(json.dumps(payload))
    sys.exit(0)

def missing():
    print("ResourceNotFound", file=sys.stderr)
    sys.exit(3)

if args[:2] == ["group", "exists"]:
    print("true" if world["group"] else "false")
    sys.exit(0)
if args[:2] == ["group", "delete"]:
    world["group"] = False
    save()
    emit({})
if args[:3] == ["cognitiveservices", "account", "project"] and args[3] == "show":
    emit({"name": "jaws-uninst1"}) if world["project"] else missing()
if args[:3] == ["cognitiveservices", "account", "project"] and args[3] == "delete":
    world["project"] = False
    save()
    emit({})
if args[:3] == ["cognitiveservices", "account", "show"]:
    emit({"name": "jaws-foundry-uninst1"}) if world["account"] else missing()
if args[:3] == ["cognitiveservices", "account", "delete"]:
    world["account"] = False
    save()
    emit({})
if args[:3] == ["cognitiveservices", "account", "purge"]:
    emit({})
if args[:2] == ["containerapp", "list"] or args[:3] == ["containerapp", "env", "list"]:
    emit([])
if args[:2] == ["keyvault", "show"]:
    emit({"name": "kv-jaws-uninst1"}) if world["vault"] else missing()
if args[:2] == ["keyvault", "delete"]:
    world["vault"] = False
    save()
    emit({})
if args[:2] == ["keyvault", "purge"]:
    if os.environ.get("JAWS_UNINSTALL_STUB_VAULT_PROTECTED") == "1":
        print("purge protection prevents this vault from being purged", file=sys.stderr)
        sys.exit(1)
    emit({})
if args[:2] == ["keyvault", "show-deleted"]:
    emit({"name": "kv-jaws-uninst1", "properties": {"scheduledPurgeDate": "2027-01-18T00:00:00Z"}})
if args[:1] == ["rest"]:
    method = args[args.index("--method") + 1]
    url = args[args.index("--url") + 1]
    if method == "GET" and url.endswith("/agents?api-version=v1"):
        emit({"data": [{"name": name} for name in world["agents"]]})
    if method == "DELETE" and "/agents/" in url:
        if "force=true" not in url:
            print("force=true required", file=sys.stderr)
            sys.exit(2)
        name = url.split("/agents/")[1].split("?")[0]
        world["agents"] = [item for item in world["agents"] if item != name]
        save()
        emit({"deleted": True, "name": name})
    if method == "GET" and url.endswith("/toolboxes?api-version=v1"):
        emit({"data": [{"name": name} for name in world["toolboxes"]]})
    if method == "DELETE" and "/toolboxes/" in url:
        name = url.split("/toolboxes/")[1].split("?")[0]
        world["toolboxes"] = [item for item in world["toolboxes"] if item != name]
        save()
        emit({"deleted": True})
    if method == "GET" and url.endswith("/connections?api-version=v1"):
        emit({"data": [{"name": name} for name in world["connections"]]})
    if method == "DELETE" and "/connections/" in url:
        name = url.split("/connections/")[1].split("?")[0]
        world["connections"] = [item for item in world["connections"] if item != name]
        save()
        emit({"deleted": True})
print("unexpected " + " ".join(args), file=sys.stderr)
sys.exit(9)
'@
    chmod +x (Join-Path $script:stub 'az') | Out-Null
    $script:originalPath = $env:PATH
    function script:New-UninstallState {
        $state = Join-Path $script:stub ('state-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $state | Out-Null
        $env:JAWS_UNINSTALL_STUB_STATE = $state
        $env:JAWS_UNINSTALL_POLL_SECONDS = '0'
        $env:PATH = $script:stub + [System.IO.Path]::PathSeparator + '/usr/bin'
        return $state
    }
}

AfterAll {
    if ($script:originalPath) { $env:PATH = $script:originalPath }
    Remove-Item Env:JAWS_UNINSTALL_POLL_SECONDS -ErrorAction SilentlyContinue
    Remove-Item Env:JAWS_UNINSTALL_STUB_STATE -ErrorAction SilentlyContinue
    Remove-Item Env:JAWS_UNINSTALL_STUB_VAULT_PROTECTED -ErrorAction SilentlyContinue
}

Describe 'JAWS uninstall' {
    It 'refuses the dev environment and an unacknowledged uninstall before Azure is called' {
        { Invoke-JawsUninstall -EnvironmentName 'dev' -InstallerRoot $script:root -AcknowledgeJawsUninstall } | Should -Throw '*JAWS-UNINSTALL-006*'
        $state = New-UninstallState
        try {
            { Invoke-JawsUninstall -EnvironmentName 'uninst1' -InstallerRoot $script:root -SubscriptionId $script:sub -ResourceGroupName 'rg-jaws-uninst1' -Location 'eastus' } | Should -Throw '*JAWS-UNINSTALL-001*'
            Test-Path -LiteralPath (Join-Path $state 'log.txt') | Should -BeFalse
        } finally {
            $env:PATH = $script:originalPath
            Remove-Item Env:JAWS_UNINSTALL_POLL_SECONDS -ErrorAction SilentlyContinue
        }
    }

    It 'force-deletes Foundry agents before purging the account and the resource group' {
        $savedPath = $env:PATH
        $state = New-UninstallState
        $local = Join-Path $script:root 'installer/.local'
        if (-not (Test-Path -LiteralPath $local)) { New-Item -ItemType Directory -Path $local | Out-Null }
        $receiptPath = Join-Path $local 'jaws-step-b-install.uninst1.generated.json'
        $devState = Join-Path $script:root 'installer/config/jaws-installation-state.dev.json'
        $devBefore = Get-Content -LiteralPath $devState -Raw
        try {
            [pscustomobject]@{
                Status = 'STEP_B_INSTALLED'
                EnvironmentName = 'uninst1'
                SubscriptionId = $script:sub
                ResourceGroupName = 'rg-jaws-uninst1'
                Location = 'eastus'
                FoundryAccountName = 'jaws-foundry-uninst1'
                ProjectName = 'jaws-uninst1'
                KeyVaultName = 'kv-jaws-uninst1'
            } | ConvertTo-Json | Set-Content -LiteralPath $receiptPath -Encoding utf8
            $result = Invoke-JawsUninstall -EnvironmentName 'uninst1' -InstallerRoot (Join-Path $script:root 'installer') -AcknowledgeJawsUninstall
            $result.Receipt.Status | Should -Be 'UNINSTALLED'
            $result.Receipt.FoundryPurged | Should -BeTrue
            $result.Receipt.KeyVaultPurge | Should -Be 'purged'
            $result.Receipt.ResourceGroupDeleted | Should -BeTrue
            $result.Receipt.CustomerInstallationAccepted | Should -BeFalse
            @($result.Receipt.AgentsDeleted) | Should -Be @('jaws-supervisor-uninst1', 'jaws-vm-specialist-uninst1')
            $log = Get-Content -LiteralPath (Join-Path $state 'log.txt') -Raw
            $agentDelete = $log.IndexOf('DELETE')
            $accountDelete = $log.IndexOf('cognitiveservices account delete')
            $purge = $log.IndexOf('cognitiveservices account purge')
            $groupDelete = $log.IndexOf('group delete')
            $agentDelete | Should -BeGreaterThan -1
            $agentDelete | Should -BeLessThan $accountDelete
            $accountDelete | Should -BeLessThan $purge
            $purge | Should -BeLessThan $groupDelete
            $log | Should -Match 'force=true'
            $log | Should -Not -Match 'jaws-foundry-dev'
            Test-Path -LiteralPath $receiptPath | Should -BeFalse
            Test-Path -LiteralPath $result.EvidencePath | Should -BeTrue
            (Get-Content -LiteralPath $devState -Raw) | Should -Be $devBefore
        } finally {
            $env:PATH = $savedPath
            Remove-Item Env:JAWS_UNINSTALL_POLL_SECONDS -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath (Join-Path $local 'jaws-uninstall.uninst1.generated.json') -Force -ErrorAction SilentlyContinue
        }
    }

    It 'records a purge-protected Key Vault instead of pretending it was purged' {
        $savedPath = $env:PATH
        $savedProtected = $env:JAWS_UNINSTALL_STUB_VAULT_PROTECTED
        $state = New-UninstallState
        $env:JAWS_UNINSTALL_STUB_VAULT_PROTECTED = '1'
        try {
            $result = Invoke-JawsUninstall -EnvironmentName 'uninst1' -InstallerRoot (Join-Path $script:root 'installer') -SubscriptionId $script:sub -ResourceGroupName 'rg-jaws-uninst1' -Location 'eastus' -FoundryAccountName 'jaws-foundry-uninst1' -ProjectName 'jaws-uninst1' -KeyVaultName 'kv-jaws-uninst1' -AcknowledgeJawsUninstall
            $result.Receipt.KeyVaultPurge | Should -Be 'blocked'
            $result.Receipt.KeyVaultPurgeNotBefore | Should -Be '2027-01-18T00:00:00Z'
            $result.Receipt.FoundryPurged | Should -BeTrue
            $result.Receipt.ResourceGroupDeleted | Should -BeTrue
        } finally {
            $env:PATH = $savedPath
            if ($null -eq $savedProtected) { Remove-Item Env:JAWS_UNINSTALL_STUB_VAULT_PROTECTED -ErrorAction SilentlyContinue } else { $env:JAWS_UNINSTALL_STUB_VAULT_PROTECTED = $savedProtected }
            Remove-Item Env:JAWS_UNINSTALL_POLL_SECONDS -ErrorAction SilentlyContinue
        }
    }
}
