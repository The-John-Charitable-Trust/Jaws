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
  $protocolFailure=($raw -match '(?i)(function failed|HOSTED_AGENT_NOT_SUPPORTED|McpProtocolException|-32099)' -or $resultStatus -match '(?i)failed|error')
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
function Test-JawsSupervisorRateLimit($Response) {
 $errorObject=Get-JawsField $Response 'error'
 $code=[string](Get-JawsField $errorObject 'code')
 $message=[string](Get-JawsField $errorObject 'message')
 return ($message -match '(?i)rate limit' -or $code -match '(?i)rate.?limit|^429$')
}
function Invoke-JawsSupervisorAcceptanceResponse {
 param([Parameter(Mandatory)][string]$Url,[Parameter(Mandatory)][string]$Body)
 $attempts=3
 $wait=60
 if($env:JAWS_STEPC_RATE_LIMIT_WAIT_SECONDS -match '^\d+$'){ $wait=[int]$env:JAWS_STEPC_RATE_LIMIT_WAIT_SECONDS }
 $response=$null
 for($attempt=1; $attempt -le $attempts; $attempt++){
  $tmp=[IO.Path]::GetTempFileName()
  try{
   [IO.File]::WriteAllText($tmp,$Body,[Text.UTF8Encoding]::new($false))
   $raw=& az rest --method post --url $Url --resource https://ai.azure.com --headers 'Content-Type=application/json' --body "@$tmp" --output json --only-show-errors 2>&1
   if($LASTEXITCODE -ne 0){ throw "JAWS-C-ACCEPT-006: Supervisor invocation failed: $($raw | Out-String)" }
   $response=$raw | Out-String | ConvertFrom-Json -ErrorAction Stop
  } finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
  if(-not (Test-JawsSupervisorRateLimit $response) -or $attempt -eq $attempts){
   $response | Add-Member -NotePropertyName JawsRateLimitAttempts -NotePropertyValue $attempt -Force
   return $response
  }
  $errorObject=Get-JawsField $response 'error'
  $issueCode=[string](Get-JawsField $errorObject 'code')
  $issueMessage=[string](Get-JawsField $errorObject 'message')
  $issue=if($issueCode -and $issueMessage){"${issueCode}: $issueMessage"}elseif($issueMessage){$issueMessage}else{'Model deployment rate limit exceeded.'}
  Write-Host "Supervisor model rate limit (attempt $attempt of $attempts). Waiting $wait seconds."
  Write-JawsOperatorIssue -Issue $issue -Action "Waiting $wait seconds, then retrying ($attempt of $attempts). If the limit remains, request more quota for this model and region. The deployment is GlobalStandard capacity 1, and its request rate follows that quota." -QuotaRequest
  if($wait -gt 0){ Start-Sleep -Seconds $wait }
 }
 throw 'JAWS-C-ACCEPT-006: Supervisor invocation produced no response.'
}
function Get-JawsRateLimitAcceptanceFailure($Response) {
 $errorObject=Get-JawsField $Response 'error'
 $code=[string](Get-JawsField $errorObject 'code')
 $message=[string](Get-JawsField $errorObject 'message')
 $issue=if($code -and $message){"${code}: $message"}elseif($message){$message}else{'Model deployment rate limit exceeded.'}
 $attempts=[int](Get-JawsField $Response 'JawsRateLimitAttempts')
 $action="The Investigation task is not the failure. Acceptance tried $attempts times. Retry after the rate-limit window. If it fails again, request more quota for this model and region. The Step B deployment is GlobalStandard capacity 1."
 Write-JawsOperatorIssue -Issue $issue -Action $action -QuotaRequest
 return "JAWS-C-ACCEPT-010: $issue $action Quota request: $(Get-JawsQuotaRequestUrl)"
}
Export-ModuleMember -Function Get-JawsField,Get-JawsDelegationEvidence,Test-JawsSupervisorRateLimit,Invoke-JawsSupervisorAcceptanceResponse,Get-JawsRateLimitAcceptanceFailure
