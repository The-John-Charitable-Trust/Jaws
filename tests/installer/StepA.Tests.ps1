BeforeAll {
    $script:root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $script:sub = '22222222-2222-2222-2222-222222222222'
    $script:stub = Join-Path ([System.IO.Path]::GetTempPath()) ('jaws-stepa-stub-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:stub | Out-Null
    Set-Content -LiteralPath (Join-Path $script:stub 'az') -Encoding ascii -Value @'
#!/bin/bash
exec python3 "$0.py" "$@"
'@
    Set-Content -LiteralPath (Join-Path $script:stub 'az.py') -Encoding utf8 -Value @'
import json, os, sys
sub = os.environ["JAWS_STEPA_STUB_SUB"]
args = sys.argv[1:]
state = os.environ["JAWS_STEPA_STUB_STATE"]
os.makedirs(state, exist_ok=True)
with open(os.path.join(state, "log.txt"), "a", encoding="utf-8") as handle:
    handle.write(" ".join(args) + "\n")

def emit(payload):
    print(json.dumps(payload))
    sys.exit(0)

if args[:2] == ["account", "show"]:
    emit({"id": sub, "name": "stub", "state": "Enabled", "tenantId": "33333333-3333-3333-3333-333333333333", "user": {"name": "installer@stub.example", "type": "user"}})
if args[:2] == ["account", "list"]:
    emit([{"id": sub, "name": "stub", "state": "Enabled", "tenantId": "33333333-3333-3333-3333-333333333333"}])
if args[:2] == ["group", "list"]:
    emit([])
if args[:2] == ["resource", "list"]:
    emit([])
print("unexpected " + " ".join(args), file=sys.stderr)
sys.exit(9)
'@
    chmod +x (Join-Path $script:stub 'az') | Out-Null
}

Describe 'Step A greenfield discovery' {
    It 'rejects an explicit missing state file without calling Azure' {
        $missing = Join-Path $script:stub 'missing-state.json'
        { & (Join-Path $script:root 'installer/Install-Jaws.ps1') -Mode Discover -EnvironmentName 'lab1' -StateFile $missing -NonInteractive } | Should -Throw '*JAWS-STATE-003*'
    }

    It 'discovers an empty subscription and writes a receipt without creating resources' {
        $state = Join-Path $script:stub 'state'
        $savedPath = $env:PATH
        $savedState = $env:JAWS_STEPA_STUB_STATE
        $savedSub = $env:JAWS_STEPA_STUB_SUB
        try {
            $env:JAWS_STEPA_STUB_STATE = $state
            $env:JAWS_STEPA_STUB_SUB = $script:sub
            $env:PATH = $script:stub + [System.IO.Path]::PathSeparator + $env:PATH
            $devBefore = Get-Content -LiteralPath (Join-Path $script:root 'installer/config/jaws-installation-state.dev.json') -Raw
            $output = & (Join-Path $script:root 'installer/Install-Jaws.ps1') -Mode Discover -NonInteractive -EnvironmentName 'lab1' -ResourceGroupName 'rg-jaws-lab1' -Location 'eastus' *>&1 | Out-String
            $output | Should -Match 'STEP-A DISCOVERY PASS'
            $output | Should -Match 'Discovery: Greenfield'
            $output | Should -Match 'Subscription source: AzureCli'
            $output | Should -Match 'Resource groups: 0'
            $output | Should -Match 'Resources: 0'
            $output | Should -Match 'State file required: false'
            $output | Should -Match 'State file written: false'
            $output | Should -Match 'Azure writes: 0'
            $output | Should -Match 'Prepared for Step B: true'
            $log = Get-Content -LiteralPath (Join-Path $state 'log.txt') -Raw
            $log | Should -Match 'group list'
            $log | Should -Match 'resource list'
            $log | Should -Not -Match ' create'
            Test-Path -LiteralPath (Join-Path $script:root 'installer/config/jaws-installation-state.lab1.json') | Should -BeFalse
            (Get-Content -LiteralPath (Join-Path $script:root 'installer/config/jaws-installation-state.dev.json') -Raw) | Should -Be $devBefore
            $scored = & (Join-Path $script:root 'installer/Test-JawsStepA.ps1') -ReportPath (Join-Path $script:root 'installer/.local/jaws-step-a-discovery.lab1.generated.json') *>&1 | Out-String
            $scored | Should -Match 'STEP-A DISCOVERY PASS'
            $scored | Should -Match 'Live Azure read: false'
        } finally {
            $env:PATH = $savedPath
            if ($null -eq $savedState) { Remove-Item Env:JAWS_STEPA_STUB_STATE -ErrorAction SilentlyContinue } else { $env:JAWS_STEPA_STUB_STATE = $savedState }
            if ($null -eq $savedSub) { Remove-Item Env:JAWS_STEPA_STUB_SUB -ErrorAction SilentlyContinue } else { $env:JAWS_STEPA_STUB_SUB = $savedSub }
        }
    }
}
