BeforeAll {
 $root=[System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
 Import-Module (Join-Path $root 'installer/modules/StepCInstall.psm1') -Force
 $script:orchestrator=Get-Content -LiteralPath (Join-Path $root 'installer/Install-JawsThroughStepC.ps1') -Raw
 $script:acceptance=Get-Content -LiteralPath (Join-Path $root 'installer/Test-JawsStepCDelegation.ps1') -Raw
 $script:dispatcher=Get-Content -LiteralPath (Join-Path $root 'installer/Install-JawsStepC.ps1') -Raw
 $script:retired=Get-Content -LiteralPath (Join-Path $root 'installer/Release-JawsSupervisorDraft.ps1') -Raw
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
 It 'never treats the Supervisor route or identity context as self-correcting' {
  Get-JawsStepCCorrection -Gate Supervisor -ErrorMessage 'JAWS-INSTALL-C-007: Routed Supervisor is not the approved release.' -Mode Install | Should -BeNullOrEmpty
  Get-JawsStepCCorrection -Gate Identity -ErrorMessage 'JAWS-A2A-IDENTITY-002: Expected identity or stored connection configuration missing; no changes made.' -Mode Install | Should -BeNullOrEmpty
 }
 It 'closes only after acceptance and blocks on any failed gate' {
  $ready=@([pscustomobject]@{Result='Passed'},[pscustomobject]@{Result='Repaired'})
  Get-JawsStepCInstallStatus -GateResults $ready -Acceptance Skipped | Should -Be 'VALIDATED'
  Get-JawsStepCInstallStatus -GateResults $ready -Acceptance Passed | Should -Be 'CLOSED'
  Get-JawsStepCInstallStatus -GateResults (@($ready)+[pscustomobject]@{Result='Blocked'}) -Acceptance Skipped | Should -Be 'BLOCKED'
  Get-JawsStepCInstallStatus -GateResults $ready -Acceptance Failed | Should -Be 'BLOCKED'
  Get-JawsStepCInstallStatus -GateResults @() -Acceptance Passed | Should -Be 'BLOCKED'
 }
}
Describe 'Step C install orchestrator safety' {
 It 'parses and refuses an unacknowledged install before any Azure call' {
  $tokens=$null;$errors=$null
  [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'installer/Install-JawsThroughStepC.ps1'),[ref]$tokens,[ref]$errors)|Out-Null
  @($errors).Count | Should -Be 0
  { & (Join-Path $root 'installer/Install-JawsThroughStepC.ps1') -Mode Install } | Should -Throw '*JAWS-INSTALL-C-001*'
 }
 It 'walks the gates in dependency order and posts no Supervisor version' {
  $orchestrator | Should -Match '\$script:gateOrder=@\(''Prerequisites'',''State'',''InvestigationA2A'',''Planner'',''Connection'',''Toolbox'',''Rbac'',''Supervisor'',''Identity'',''Acceptance''\)'
  $orchestrator | Should -Not -Match 'Release-JawsSupervisor'
  $orchestrator | Should -Not -Match 'az role assignment create'
  $orchestrator | Should -Not -Match 'az rest --method (put|patch|post|delete)'
  $orchestrator | Should -Match 'SupervisorVersionPosted=\$false'
  $orchestrator | Should -Match 'Invoke-JawsAzRestGet'
  $orchestrator | Should -Match '\$script:gates\.ToArray\(\)'
 }
 It 'keeps acceptance behind an explicit inference acknowledgement' {
  $orchestrator | Should -Match 'if\(-not \$AcknowledgeInferenceCharges\)\{ return ''Skipped'' \}'
  $acceptance | Should -Match '86c556fff7f54eb8ad81c84bc768093fd7bc083e941e9e16bbf1ea8bc0cfa289'
  $acceptance | Should -Not -Match '5a9cd89cfc626df4bdd2266194db14cda8fd33f46de1bfbc9c1111cde1c8af54'
  $acceptance | Should -Match 'store=\$false'
  $acceptance | Should -Match 'TaskState='
  $acceptance | Should -Match 'PlannerResponseId='
 }
 It 'exposes the same path from the Step C dispatcher and retires the historical release script' {
  $dispatcher | Should -Match 'ThroughStepC'
  $dispatcher | Should -Match 'Install-JawsThroughStepC.ps1'
  $retired | Should -Match 'JAWS-SUP-REL-010'
  $retired | Should -Not -Match 'az rest --method post'
 }
}
