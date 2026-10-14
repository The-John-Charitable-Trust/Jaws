BeforeAll {
  $root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
  $paths=@('installer/Install-JawsStepC.ps1','installer/Repair-JawsDelegationToolbox.ps1','installer/Configure-JawsDelegationToolbox.ps1')
  $script:contents=@{}
  $script:parseErrors=@()
  foreach($relative in $paths) {
    $file=Join-Path $root $relative
    $script:contents[$relative]=Get-Content -LiteralPath $file -Raw
    $t=$null;$e=$null
    [System.Management.Automation.Language.Parser]::ParseFile($file,[ref]$t,[ref]$e)|Out-Null
    $script:parseErrors+=@($e)
  }
}
Describe 'Step C toolbox promotion regression' {
 It 'all modified PowerShell scripts parse' {$parseErrors | Should -BeNullOrEmpty}
 It 'preserves interactive approval and a rollback mode' {
   $contents['installer/Install-JawsStepC.ps1'] | Should -Match 'ToolboxRepairRollback'
   $contents['installer/Repair-JawsDelegationToolbox.ps1'] | Should -Match "Confirm-Operator 'Promote validated toolbox v2"
 }
 It 'does not depend on standalone MCP tools/list success before switching' {
   $contents['installer/Repair-JawsDelegationToolbox.ps1'] | Should -Not -Match 'MCP_TOOLS_EXPOSED'
 }
 It 'verifies active default toolbox instead of requiring hard-coded version 1' {
   $contents['installer/Configure-JawsDelegationToolbox.ps1'] | Should -Match 'defaultVersion'
   $contents['installer/Configure-JawsDelegationToolbox.ps1'] | Should -Match 'project_connection_id'
 }
 It 'retains strict rejection of base_url plus connection_id' {
   $contents['installer/Configure-JawsDelegationToolbox.ps1'] | Should -Match 'PSObject\.Properties\[''base_url''\]'
 }
}
