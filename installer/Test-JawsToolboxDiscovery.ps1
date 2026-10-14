# Read-only Step C toolbox discovery diagnostics. Never changes Azure resources.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$project='https://jaws-foundry-dev.services.ai.azure.com/api/projects/jaws-dev'
$name='jaws-investigation-a2a-tools'
$reportPath=Join-Path $PSScriptRoot '.local/jaws-step-c-toolbox-discovery.dev.generated.json'
function Read-Foundry([string]$url){
 $out=& az rest --method get --url $url --resource https://ai.azure.com --output json --only-show-errors 2>&1
 if($LASTEXITCODE -ne 0){throw "JAWS-C-DISCOVERY-001: Could not read Foundry toolbox: $($out | Out-String)"}
 return ($out|Out-String|ConvertFrom-Json -ErrorAction Stop)
}
$toolbox=Read-Foundry "$project/toolboxes/$($name)?api-version=v1"
$versions=Read-Foundry "$project/toolboxes/$name/versions?api-version=v1"
$items=if($versions.PSObject.Properties['data']){@($versions.data)}elseif($versions.PSObject.Properties['value']){@($versions.value)}else{@()}
$version1=@($items|Where-Object { [string]$_.version -ceq '1' })
if($version1.Count -ne 1){throw 'JAWS-C-DISCOVERY-002: Expected toolbox version 1 absent or duplicated.'}
$default=''
foreach($key in @('default_version','defaultVersion')){
 if($toolbox.PSObject.Properties[$key]){$default=[string]$toolbox.$key;break}
}
if(-not $default -and $toolbox.PSObject.Properties['properties']){
 foreach($key in @('default_version','defaultVersion')){
  if($toolbox.properties -and $toolbox.properties.PSObject.Properties[$key]){$default=[string]$toolbox.properties.$key;break}
 }
}
$status=if($default -eq '1'){'DEFAULT_VERSION_VERIFIED'}elseif($default){'DEFAULT_VERSION_MISMATCH'}else{'DEFAULT_VERSION_NOT_ADVERTISED'}
$result=[ordered]@{
 Toolbox=$name
 Version1Exists=$true
 DefaultVersion=$default
 Status=$status
 AvailableTopLevelKeys=@($toolbox.PSObject.Properties.Name)
 Version1ToolTypes=@($version1[0].tools|ForEach-Object {$_.type})
 AzureWrites=0
 TimestampUtc=[DateTime]::UtcNow.ToString('o')
}
$result|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $reportPath -Encoding utf8
Write-Host "Toolbox default-version discovery: $status"
Write-Host "Default: $(if($default){$default}else{'<not provided>'})"
Write-Host "Toolbox properties: $($result.AvailableTopLevelKeys -join ', ')"
Write-Host "Diagnostic report: $reportPath"
if($status -ne 'DEFAULT_VERSION_VERIFIED'){
 Write-Warning 'Hosted toolbox consumer may not be able to enumerate tools. Do not redeploy or rerun billable inference before resolving default-version discovery.'
}
