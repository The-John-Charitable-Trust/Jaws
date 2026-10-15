Set-StrictMode -Version Latest
function Get-JawsField($Object,[string]$Name) {
 if($null -eq $Object){return $null}
 $property=$Object.PSObject.Properties[$Name]
 if($null -eq $property){return $null}
 return $property.Value
}
function Get-JawsDelegationEvidence($Response) {
 $items=@(Get-JawsField $Response 'output')
 $calls=@($items | Where-Object { (Get-JawsField $_ 'type') -eq 'function_call' })
 $outputs=@($items | Where-Object { (Get-JawsField $_ 'type') -eq 'function_call_output' })
 $records=@()
 foreach($call in $calls){
  $id=[string](Get-JawsField $call 'call_id')
  $name=[string](Get-JawsField $call 'name')
  $result=@($outputs | Where-Object { [string](Get-JawsField $_ 'call_id') -ceq $id })
  $raw=if($result.Count -eq 1){[string](Get-JawsField $result[0] 'output')}else{''}
  $resultStatus=if($result.Count -eq 1){[string](Get-JawsField $result[0] 'status')}else{''}
  # A completed A2A task often repeats the caller's words ("failed", "error") inside the plan.
  # Those words are not a tool failure. Protocol failures still fail the call.
  $completedTask=($raw -match 'TASK_STATE_COMPLETED' -and $raw -notmatch 'TASK_STATE_FAILED|TASK_STATE_REJECTED|TASK_STATE_CANCELED')
  $protocolFailure=($raw -match '(?i)(function failed|HOSTED_AGENT_NOT_SUPPORTED|McpProtocolException|\bunauthorized\b|\bforbidden\b|-32099)' -or $resultStatus -match '(?i)failed|error')
  $textFailure=($raw -match '(?i)(function failed|tool.*failed|\berror\b|\bfailed\b|unauthorized|forbidden|exception)')
  $failure=((-not $completedTask) -and ($textFailure -or $resultStatus -match '(?i)failed|error')) -or ($completedTask -and $protocolFailure)
  $records+= [pscustomobject]@{
   CallId=$id
   ToolName=$name
   OutputPresent=($result.Count -eq 1)
   OutputStatus=$resultStatus
   Failed=$failure
   OutputExcerpt=if($raw.Length -gt 600){$raw.Substring(0,600)}else{$raw}
  }
 }
 $investigation=@($records|Where-Object {$_.ToolName -match '(?i)(investigation|a2a)'})
 $successful=@($investigation|Where-Object {$_.OutputPresent -and -not $_.Failed -and -not [string]::IsNullOrWhiteSpace($_.OutputExcerpt)})
 $failed=@($records|Where-Object {$_.Failed})
 $classification=if($calls.Count -eq 0){'TOOL_NOT_INVOKED'}elseif($failed.Count -gt 0){'TOOL_INVOKED_FAILED'}elseif($successful.Count -gt 0){'TOOL_INVOKED_SUCCEEDED'}else{'INDETERMINATE'}
 return [pscustomobject]@{
  Classification=$classification
  Calls=$records
  AttemptCount=$calls.Count
  InvestigationSuccessCount=$successful.Count
  ResponseCompleted=([string](Get-JawsField $Response 'status') -ceq 'completed')
 }
}
Export-ModuleMember -Function Get-JawsDelegationEvidence
