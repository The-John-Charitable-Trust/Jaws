BeforeAll {
 Import-Module (Join-Path $PSScriptRoot '../../installer/modules/DelegationEvidence.psm1') -Force
}
Describe 'Step C delegation evidence classification' {
 It 'detects no invocation' {
  $r=[pscustomobject]@{status='completed';output=@([pscustomobject]@{type='message'})}
  (Get-JawsDelegationEvidence $r).Classification | Should -Be 'TOOL_NOT_INVOKED'
 }
 It 'detects a failed tool invocation with a matching call_id' {
  $r=[pscustomobject]@{status='completed';output=@(
    [pscustomobject]@{type='function_call';call_id='call-1';name='jaws-investigation-a2a-dev'},
    [pscustomobject]@{type='function_call_output';call_id='call-1';output='Error: Function failed.'}
   )}
  $actual=Get-JawsDelegationEvidence $r
  $actual.Classification | Should -Be 'TOOL_INVOKED_FAILED'
  $actual.InvestigationSuccessCount | Should -Be 0
 }
 It 'classifies successful investigation tool output conservatively' {
  $r=[pscustomobject]@{status='completed';output=@(
    [pscustomobject]@{type='function_call';call_id='c';name='jaws-investigation-a2a-dev'},
    [pscustomobject]@{type='function_call_output';call_id='c';output='Read-only evidence plan from Investigation: collect Azure boot diagnostics.'}
   )}
  $actual=Get-JawsDelegationEvidence $r
  $actual.Classification | Should -Be 'TOOL_INVOKED_SUCCEEDED'
  $actual.InvestigationSuccessCount | Should -Be 1
 }
 It 'does not accept missing function results' {
  $r=[pscustomobject]@{status='completed';output=@([pscustomobject]@{type='function_call';call_id='c';name='jaws-investigation-a2a-dev'})}
  (Get-JawsDelegationEvidence $r).Classification | Should -Be 'INDETERMINATE'
 }
 It 'rejects failed unrelated calls even with an investigation answer' {
  $r=[pscustomobject]@{status='completed';output=@(
    [pscustomobject]@{type='function_call';call_id='a';name='jaws-investigation-a2a-dev'},
    [pscustomobject]@{type='function_call_output';call_id='a';output='Read-only diagnostic plan'},
    [pscustomobject]@{type='function_call';call_id='b';name='other'},
    [pscustomobject]@{type='function_call_output';call_id='b';output='Function failed'}
   )}
  (Get-JawsDelegationEvidence $r).Classification | Should -Be 'TOOL_INVOKED_FAILED'
 }
}
