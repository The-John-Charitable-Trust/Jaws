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

def emit(payload, code=0):
    print(json.dumps(payload))
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
    if not agent:
        missing()
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
    emit({"name": url.split("/agents/")[1].split("?")[0], "versions": {"latest": "1"}})
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
            'jaws-step-c-final-acceptance.dev2.generated.json',
            'jaws-step-c-final-acceptance.lab9.generated.json',
            'jaws-step-d-validate.lab9.generated.json'
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
        $env:JAWS_STEPD_STUB_STATE = $script:state
        $env:JAWS_STEPD_STUB_DEV_IMAGE = $script:devImage
        $env:JAWS_STEPD_STUB_DEV_MISSING = '0'
        Remove-Item Env:JAWS_STEPD_STUB_MISSING -ErrorAction SilentlyContinue
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
            @{ Name = 'JAWS_STEPD_POLL_SECONDS'; Value = $script:savedPoll }
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
        $output | Should -Match 'Azure writes: 1'
        $output | Should -Match 'Result: PASS'
        $output | Should -Match 'Ready for next step: true'
        $output | Should -Match 'Next step: Step D Accept'
        $log = Get-Content -LiteralPath (Join-Path $script:state 'log.txt') -Raw
        $agentPost = [regex]::Escape('/agents?api-version=v1')
        ([regex]::Matches($log, $agentPost)).Count | Should -Be 1
        $log | Should -Not -Match 'jaws-supervisor-lab1/versions'
        & (Join-Path $script:root 'installer/Install-JawsStepD.ps1') -Mode Install -EnvironmentName 'lab1' -AcknowledgeStepDInstall
        $log = Get-Content -LiteralPath (Join-Path $script:state 'log.txt') -Raw
        $post = [regex]::Escape('rest --method POST')
        ([regex]::Matches($log, $post)).Count | Should -Be 1
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
}
