# Step C: read-only MCP tools/list probe. No agent invocation, no Azure mutations.
[CmdletBinding()]
param([ValidateSet('1','2')][string]$ToolboxVersion='1')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$endpoint='https://jaws-foundry-dev.services.ai.azure.com/api/projects/jaws-dev/toolboxes/jaws-investigation-a2a-tools/versions/$ToolboxVersion/mcp?api-version=v1'
$reportPath=Join-Path $PSScriptRoot '.local/jaws-step-c-runtime-tool-discovery.dev.generated.json'
$tokenJson=& az account get-access-token --resource https://ai.azure.com --output json --only-show-errors 2>&1
if($LASTEXITCODE -ne 0){throw 'JAWS-MCP-DISCOVERY-001: Azure CLI cannot obtain a Foundry token.'}
$access=($tokenJson|Out-String|ConvertFrom-Json).accessToken
if([string]::IsNullOrWhiteSpace($access)){throw 'JAWS-MCP-DISCOVERY-002: Empty bearer token.'}
$baseHeaders=@{ Authorization="Bearer $access"; Accept='application/json, text/event-stream'; 'MCP-Protocol-Version'='2025-11-25' }
function Invoke-Mcp([hashtable]$payload,[string]$session='', [string]$stage='request') {
 $headers=@{}
 foreach($key in $baseHeaders.Keys){$headers[$key]=$baseHeaders[$key]}
 if($session){$headers['Mcp-Session-Id']=$session}
 $json=ConvertTo-Json -InputObject $payload -Depth 12 -Compress
 try {
  $web=Invoke-WebRequest -Uri $endpoint -Method Post -Headers $headers -Body ([Text.Encoding]::UTF8.GetBytes($json)) -ContentType 'application/json' -TimeoutSec 40 -ErrorAction Stop
 }catch{
  $code=if($_.Exception.Response){[int]$_.Exception.Response.StatusCode}else{0}
  $detail=''
  try { if($_.ErrorDetails.Message){$detail=[string]$_.ErrorDetails.Message} } catch {}
  if(-not $detail -and $_.Exception.Response){
   try {$detail=[string]$_.Exception.Response.Content.ReadAsStringAsync().GetAwaiter().GetResult()} catch {}
  }
  if($detail.Length -gt 800){$detail=$detail.Substring(0,800)}
  $detail=$detail -replace '(?i)Bearer\\s+[^\\s"'']+','Bearer [REDACTED]'
  throw "JAWS-MCP-DISCOVERY-003: $stage failed (HTTP $code). Response: $detail" 
 }
 $id=if($web.Headers['Mcp-Session-Id']){[string]$web.Headers['Mcp-Session-Id']}else{$session}
 $textBody=[string]$web.Content
 if([int]$web.StatusCode -eq 202 -or [int]$web.StatusCode -eq 204){return [pscustomobject]@{Data=@();Session=$id}}
 $data=@()
 if($textBody.TrimStart().StartsWith('{')){
  $data=@($textBody|ConvertFrom-Json)
 }else{
  foreach($line in ($textBody -split "\r?\n")){
   if($line.StartsWith('data: ')){
    try{$data+=($line.Substring(6)|ConvertFrom-Json -ErrorAction Stop)}catch{}
   }
  }
 }
 return [pscustomobject]@{ Data=$data;Session=$id }
}
$init=Invoke-Mcp -stage 'initialize' -payload @{jsonrpc='2.0';id=1;method='initialize';params=@{protocolVersion='2025-11-25';capabilities=@{};clientInfo=@{name='jaws-step-c-diagnostic';version='1.0'}}}
if(-not @($init.Data|Where-Object { $_ -and $_.PSObject.Properties['result'] -and $null -ne $_.result }).Count){throw 'JAWS-MCP-DISCOVERY-004: MCP initialize did not return a result.'}
# Session-aware initialized notification. Do not issue tool calls.
$null=Invoke-Mcp -stage 'notifications/initialized' -payload @{jsonrpc='2.0';method='notifications/initialized'} -session $init.Session
$list=Invoke-Mcp -stage 'tools/list' -payload @{jsonrpc='2.0';id=2;method='tools/list';params=@{}} -session $init.Session
$errors=@($list.Data | Where-Object { $_ -and $_.PSObject.Properties['error'] })
if($errors.Count -gt 0){
 foreach($entry in $errors){
  $code=if($entry.error.PSObject.Properties['code']){[string]$entry.error.code}else{'unknown'}
  $message=if($entry.error.PSObject.Properties['message']){[string]$entry.error.message}else{'unspecified'}
  Write-Warning "MCP tools/list JSON-RPC error: code=$code; message=$message"
 }
 throw 'JAWS-MCP-DISCOVERY-007: MCP server returned a tools/list error. No Azure writes or tool calls.'
}
$matches=@($list.Data | Where-Object { $_ -and $_.PSObject.Properties['result'] -and $null -ne $_.result -and $_.result.PSObject.Properties['tools'] })
if($matches.Count -ne 1){
 $shapes=@($list.Data | ForEach-Object {
  if($_){'['+($_.PSObject.Properties.Name -join ',')+']'}else{'<null>'}
 })
 Write-Warning "MCP tools/list response shapes: $($shapes -join '; '); session present: $(-not [string]::IsNullOrWhiteSpace($list.Session))"
 throw 'JAWS-MCP-DISCOVERY-005: tools/list unavailable or malformed.'
}
$tools=@($matches[0].result.tools)
$names=@($tools|Where-Object { $_ -and $_.PSObject.Properties['name'] }|ForEach-Object { [string]$_.name })
$status=if($names.Count -gt 0){'MCP_TOOLS_EXPOSED'}else{'MCP_TOOL_LIST_EMPTY'}
[pscustomobject]@{
 Status=$status;Toolbox='jaws-investigation-a2a-tools';ToolboxVersion=$ToolboxVersion;ToolCount=$names.Count
 ToolNames=$names;McpInitialized=$true;McpSessionPresent= -not [string]::IsNullOrWhiteSpace($init.Session)
 AzureWrites=0;ToolCallsExecuted=0;InferenceCallsExecuted=0
 VerifiedAtUtc=[datetime]::UtcNow.ToString('o')
}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $reportPath -Encoding utf8
Write-Host "Toolbox MCP discovery: $status; tools: $($names -join ', ')"
Write-Host "Report: $reportPath"
if($names.Count -eq 0){throw 'JAWS-MCP-DISCOVERY-006: No MCP tools returned; investigate toolbox consumer configuration.'}
