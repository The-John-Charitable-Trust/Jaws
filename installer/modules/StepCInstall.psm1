Set-StrictMode -Version Latest

function Get-JawsErrorCode([string]$Message) {
 if($Message -match '(JAWS-[A-Z0-9-]+)'){ return $Matches[1] }
 return 'JAWS-INSTALL-C-000'
}

function Get-JawsStepCCorrection {
 [CmdletBinding()]
 param(
  [Parameter(Mandatory)][string]$Gate,
  [Parameter(Mandatory)][string]$ErrorMessage,
  [Parameter(Mandatory)][ValidateSet('Validate','Install')][string]$Mode
 )
 if($Mode -ne 'Install'){ return $null }
 switch($Gate){
  'InvestigationA2A' {
   if($ErrorMessage -match 'JAWS-STEP-C-A2A-007'){ return 'PatchInvestigationA2A' }
  }
  'Planner' {
   if($ErrorMessage -match 'JAWS-PLANNER-003'){ return 'CreatePlanner' }
  }
  'Connection' {
   if($ErrorMessage -match 'JAWS-DELEGATE-003'){ return 'CreateConnection' }
   if($ErrorMessage -match 'JAWS-DELEGATE-004: Connection still targets the hosted'){ return 'RetargetConnection' }
   if($ErrorMessage -match 'JAWS-DELEGATE-010'){ return 'RetargetConnectionHost' }
  }
  'Toolbox' {
   if($ErrorMessage -match 'JAWS-TOOLBOX-007'){ return 'CreateToolbox' }
   if($ErrorMessage -match 'JAWS-TOOLBOX-008'){ return 'RepairToolbox' }
  }
  'Rbac' {
   if($ErrorMessage -match 'JAWS-DELEGATE-RBAC-007'){ return 'AssignConsumerRole' }
  }
 }
 return $null
}

function Get-JawsStepCFromStepBCorrection {
 [CmdletBinding()]
 param(
  [Parameter(Mandatory)][string]$Gate,
  [Parameter(Mandatory)][string]$ErrorMessage,
  [Parameter(Mandatory)][ValidateSet('Validate','Install')][string]$Mode
 )
 if($Mode -ne 'Install'){ return $null }
 switch($Gate){
  'Planner' {
   if($ErrorMessage -match 'JAWS-PLANNER-003'){ return 'CreatePlanner' }
  }
  'Connection' {
   if($ErrorMessage -match 'JAWS-DELEGATE-003'){ return 'CreateConnection' }
   if($ErrorMessage -match 'JAWS-DELEGATE-004: Connection still targets the hosted'){ return 'RetargetConnection' }
   if($ErrorMessage -match 'JAWS-DELEGATE-010'){ return 'RetargetConnectionHost' }
  }
  'Toolbox' {
   if($ErrorMessage -match 'JAWS-TOOLBOX-007'){ return 'CreateToolbox' }
  }
  'Supervisor' {
   if($ErrorMessage -match 'JAWS-INSTALL-C-005'){ return 'PublishSupervisorRoute' }
  }
  'Rbac' {
   if($ErrorMessage -match 'JAWS-DELEGATE-RBAC-007'){ return 'AssignConsumerRole' }
  }
 }
 return $null
}

function Get-JawsStepCInstallStatus {
 [CmdletBinding()]
 param(
  [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$GateResults,
  [Parameter(Mandatory)][ValidateSet('Skipped','Passed','Failed')][string]$Acceptance
 )
 if($GateResults.Count -eq 0){ return 'BLOCKED' }
 $blocked=@($GateResults | Where-Object { $_.Result -eq 'Blocked' })
 if($blocked.Count -gt 0 -or $Acceptance -eq 'Failed'){ return 'BLOCKED' }
 if($Acceptance -eq 'Passed'){ return 'CLOSED' }
 return 'VALIDATED'
}

Export-ModuleMember -Function Get-JawsErrorCode,Get-JawsStepCCorrection,Get-JawsStepCFromStepBCorrection,Get-JawsStepCInstallStatus
