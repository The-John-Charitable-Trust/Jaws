# JAWS Foundry hosted agent comparison: pure, read-only, field-specific checks.
Set-StrictMode -Version Latest

function Get-JawsFoundryField {
    param([AllowNull()]$Value,[Parameter(Mandatory)][string[]]$Path)
    $current=$Value
    foreach ($part in $Path) {
        if ($null -eq $current) { return $null }
        if ($current -is [System.Collections.IDictionary]) {
            if (-not $current.Contains($part)) { return $null }
            $current=$current[$part]
        } else {
            $prop=$current.PSObject.Properties[$part]
            if ($null -eq $prop) { return $null }
            $current=$prop.Value
        }
    }
    return $current
}
function Resolve-JawsAzureCliPython {
    param([string]$AzCommandSource)
    if([string]::IsNullOrWhiteSpace($AzCommandSource)){ return $null }
    $leaf=Split-Path -Path $AzCommandSource -Leaf
    if($leaf -notmatch '(?i)\.cmd$'){ return $null }
    $dir=Split-Path -Path $AzCommandSource -Parent
    foreach($candidate in @(
        (Join-Path (Split-Path -Path $dir -Parent) 'python.exe'),
        (Join-Path $dir 'python.exe')
    )){
        if(Test-Path -LiteralPath $candidate){ return $candidate }
    }
    return $null
}
function Get-JawsAzRestGetCommand {
    param([Parameter(Mandatory)][string]$Url,[Parameter(Mandatory)][string]$Resource,[string]$PythonPath)
    # Prefer the CLI's python.exe. It is a real program, so & in include_drafts stays
    # inside one argument. az.cmd is parsed by cmd.exe twice when another batch file
    # calls it, and a single caret is consumed by the first parse.
    if(-not [string]::IsNullOrWhiteSpace($PythonPath)){
        return [pscustomobject]@{
            Runner='python';File=$PythonPath;Batch='';Url=$Url;Resource=$Resource
            Arguments=@('-IBm','azure.cli','rest','--method','get','--url',$Url,'--resource',$Resource,'--output','json','--only-show-errors')
        }
    }
    if($env:OS -eq 'Windows_NT' -and $Url.Contains('&')){
        if($Url -match '["\r\n]' -or $Resource -match '[&"\r\n\s%]'){ throw 'JAWS-AZ-001: Foundry URL cannot be passed through cmd.exe safely.' }
        $escaped=$Url.Replace('%','%%').Replace('&','^^^&')
        $batch="@echo off`r`nsetlocal DisableDelayedExpansion`r`ncall az rest --method get --url $escaped --resource $Resource --output json --only-show-errors`r`nexit /b %ERRORLEVEL%`r`n"
        return [pscustomobject]@{Runner='cmd';File='';Batch=$batch;Url=$Url;Resource=$Resource;Arguments=@()}
    }
    return [pscustomobject]@{
        Runner='az';File='az';Batch='';Url=$Url;Resource=$Resource
        Arguments=@('rest','--method','get','--url',$Url,'--resource',$Resource,'--output','json','--only-show-errors')
    }
}
function Invoke-JawsAzRestGet {
    param([Parameter(Mandatory)][string]$Url,[Parameter(Mandatory)][string]$Resource)
    $python=$null
    if($env:OS -eq 'Windows_NT'){
        $az=Get-Command az -ErrorAction SilentlyContinue
        if($az){ $python=Resolve-JawsAzureCliPython -AzCommandSource $az.Source }
    }
    $plan=Get-JawsAzRestGetCommand -Url $Url -Resource $Resource -PythonPath $python
    $stdout=Join-Path ([IO.Path]::GetTempPath()) ("jaws-az-out-{0}.txt" -f [guid]::NewGuid().ToString('n'))
    $stderr=Join-Path ([IO.Path]::GetTempPath()) ("jaws-az-err-{0}.txt" -f [guid]::NewGuid().ToString('n'))
    $bat=$null
    try {
        if($plan.Runner -eq 'python'){
            & $plan.File @($plan.Arguments) 1> $stdout 2> $stderr
        } elseif($plan.Runner -eq 'cmd'){
            $bat=Join-Path ([IO.Path]::GetTempPath()) ("jaws-az-rest-{0}.cmd" -f [guid]::NewGuid().ToString('n'))
            [IO.File]::WriteAllText($bat,$plan.Batch,[Text.Encoding]::ASCII)
            & cmd.exe /d /c $bat 1> $stdout 2> $stderr
        } else {
            & az @($plan.Arguments) 1> $stdout 2> $stderr
        }
        $code=$LASTEXITCODE
        $outText=if(Test-Path -LiteralPath $stdout){ Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue } else { '' }
        $errText=if(Test-Path -LiteralPath $stderr){ Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue } else { '' }
    } finally {
        Remove-Item -LiteralPath $stdout,$stderr -Force -ErrorAction SilentlyContinue
        if($bat){ Remove-Item -LiteralPath $bat -Force -ErrorAction SilentlyContinue }
    }
    $global:LASTEXITCODE=$code
    if($code -ne 0){
        if($errText){ Write-Output $errText }
        if($outText){ Write-Output $outText }
        return
    }
    if($outText){ Write-Output $outText.TrimEnd() }
}
function Set-JawsSupervisorDraftListing {
    param([Parameter(Mandatory)][string]$Url)
    # Foundry omits drafts unless include_drafts=true. Keep that flag on the first page and
    # on every continuation so a later page cannot hide the candidate.
    $parts=$Url -split '\?',2
    $pairs=New-Object System.Collections.Generic.List[string]
    if($parts.Count -eq 2 -and -not [string]::IsNullOrEmpty($parts[1])){
        foreach($pair in ($parts[1] -split '&')){
            if([string]::IsNullOrEmpty($pair)){ continue }
            if($pair -match '^(?i)include_drafts='){ continue }
            $pairs.Add($pair)
        }
    }
    $pairs.Add('include_drafts=true')
    return ($parts[0] + '?' + ($pairs -join '&'))
}
function Get-JawsFoundryAgentVersion {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Agent)
    $candidate=Get-JawsFoundryField $Agent @('version')
    if ([string]$candidate -match '^[0-9]+$') { return [string]$candidate }
    $latest=Get-JawsFoundryField $Agent @('versions','latest')
    if ($null -ne $latest) {
        if ([string]$latest -match '^[0-9]+$') { return [string]$latest }
        $nested=Get-JawsFoundryField $latest @('version')
        if ([string]$nested -match '^[0-9]+$') { return [string]$nested }
    }
    return $null
}
function Compare-JawsFoundrySupervisorState {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$DeploymentPlan,[Parameter(Mandatory)]$ActualAgent)
    $p=$DeploymentPlan.Plan
    $checks=[System.Collections.Generic.List[object]]::new()
    function Add-Check([string]$Field,[string]$Expected,[AllowNull()]$Actual,[bool]$Sensitive=$false) {
        $actualText=if($null -eq $Actual){'<missing>'}else{[string]$Actual}
        $status=if($Expected -ceq $actualText){'PASS'}else{'FAIL'}
        $checks.Add([pscustomobject]@{Field=$Field;Status=$status;Expected=$Expected;Actual=$actualText})
    }
    Add-Check 'name' ([string]$p.AgentName) (Get-JawsFoundryField $ActualAgent @('name'))
    Add-Check 'id' "$($p.AgentName):1" (Get-JawsFoundryField $ActualAgent @('id'))
    Add-Check 'object' 'agent.version' (Get-JawsFoundryField $ActualAgent @('object'))
    Add-Check 'version' '1' (Get-JawsFoundryAgentVersion $ActualAgent)
    Add-Check 'status' 'active' (Get-JawsFoundryField $ActualAgent @('status'))
    Add-Check 'definition.kind' 'hosted' (Get-JawsFoundryField $ActualAgent @('definition','kind'))
    Add-Check 'definition.cpu' ([string]$p.Request.definition.cpu) (Get-JawsFoundryField $ActualAgent @('definition','cpu'))
    Add-Check 'definition.memory' ([string]$p.Request.definition.memory) (Get-JawsFoundryField $ActualAgent @('definition','memory'))
    Add-Check 'definition.container_configuration.image' ([string]$p.Image) (Get-JawsFoundryField $ActualAgent @('definition','container_configuration','image'))
    Add-Check 'definition.environment_variables.AZURE_AI_MODEL_DEPLOYMENT_NAME' ([string]$p.Request.definition.environment_variables.AZURE_AI_MODEL_DEPLOYMENT_NAME) (Get-JawsFoundryField $ActualAgent @('definition','environment_variables','AZURE_AI_MODEL_DEPLOYMENT_NAME'))
    $actualEnvironment=Get-JawsFoundryField $ActualAgent @('definition','environment_variables')
    $actualEnvironmentNames=if($null -eq $actualEnvironment){@()}else{@($actualEnvironment.PSObject.Properties.Name)}
    $actualReserved=@($actualEnvironmentNames | Where-Object { $_ -match '^(FOUNDRY_|AGENT_)' })
    Add-Check 'definition.environment_variables.reserved_platform_prefixes' '<none>' $(if($actualReserved.Count -eq 0){'<none>'}else{$actualReserved -join ','})
    $protocols=@(Get-JawsFoundryField $ActualAgent @('definition','protocol_versions'))
    $protocolMatch=$false
    foreach($entry in $protocols) {
        if ([string](Get-JawsFoundryField $entry @('protocol')) -ceq 'responses' -and
            [string](Get-JawsFoundryField $entry @('version')) -ceq '2.0.0') {$protocolMatch=$true}
    }
    Add-Check 'definition.protocol_versions.responses' '2.0.0' $(if($protocolMatch){'2.0.0'}else{'<missing>'})
    $failed=@($checks | Where-Object Status -eq 'FAIL')
    [pscustomobject]@{
        SchemaVersion='1.0'
        AgentName=[string]$p.AgentName
        ExpectedProjectEndpoint=[string]$p.ProjectEndpoint
        PlanSha256=[string]$DeploymentPlan.PlanSha256
        OverallStatus=if($failed.Count -eq 0){'MATCH'}else{'DRIFT'}
        AzureWrites=0
        Checks=@($checks.ToArray())
        FailedFields=@($failed | ForEach-Object Field)
    }
}


# Step C candidate state reconciliation. Azure transport is injected for mock testing.
function Resolve-JawsSupervisorCandidate {
 [CmdletBinding()]
 param([AllowEmptyCollection()][Parameter(Mandatory)][object[]]$Versions,[Parameter(Mandatory)][string]$Image,[string]$Toolbox='jaws-investigation-a2a-tools')
 $matches=@($Versions | Where-Object {
  [string](Get-JawsFoundryField $_ @('definition','container_configuration','image')) -ceq $Image -and
  [string](Get-JawsFoundryField $_ @('definition','environment_variables','JAWS_INVESTIGATION_TOOLBOX_NAME')) -ceq $Toolbox
 })
 if($matches.Count -gt 1){throw 'JAWS-RECON-101: Ambiguous versions for approved image.'}
 if($matches.Count -eq 0){return $null}
 $item=$matches[0]
 $version=[string](Get-JawsFoundryField $item @('version'))
 $status=[string](Get-JawsFoundryField $item @('status'))
 $draft=Get-JawsFoundryField $item @('draft')
 if(-not $version -or $null -eq $draft -or -not $status){throw 'JAWS-RECON-102: Missing candidate fields.'}
 return [pscustomobject]@{Version=$version;Status=$status;Draft=[bool]$draft;Image=$Image}
}
function Get-JawsSupervisorVersionInventory {
 [CmdletBinding()]
 param([Parameter(Mandatory)][scriptblock]$ReadPage,[Parameter(Mandatory)][string]$ProjectEndpoint,[int]$MaxPages=20)
 if($MaxPages -lt 1){throw 'JAWS-RECON-103: Invalid page limit.'}
 $url=Set-JawsSupervisorDraftListing "$ProjectEndpoint/agents/jaws-supervisor-dev/versions?api-version=v1"
 $seen=@{};$all=@()
 for($n=0;$n -lt $MaxPages;$n++){
  if($seen.ContainsKey($url)){throw 'JAWS-RECON-104: Pagination cycle.'}
  $seen[$url]=$true
  $page=& $ReadPage $url
  $dataProp=if($null -ne $page){$page.PSObject.Properties['data']}else{$null}
  if($null -eq $dataProp -and $null -ne $page){$dataProp=$page.PSObject.Properties['value']}
  if($null -eq $dataProp){throw 'JAWS-RECON-105: Unrecognized version-list response.'}
  $entries=@()
  if($null -ne $dataProp.Value){$entries=@($dataProp.Value)}
  foreach($entryOriginal in $entries){
   if($null -eq $entryOriginal){throw 'JAWS-RECON-110: Null version entry.'}
   $entry=$entryOriginal
   $version=[string](Get-JawsFoundryField $entry @('version'))
   if($version -notmatch '^(draft-[0-9]+|[0-9]+)$'){throw 'JAWS-RECON-111: Invalid version identifier.'}
   $detailUrl="$ProjectEndpoint/agents/jaws-supervisor-dev/versions/$($version)?api-version=v1"
   $needsDetail=$null -eq (Get-JawsFoundryField $entry @('definition'))
   # A list row can keep status=active after the version detail has failed.
   $confirmActive=[string](Get-JawsFoundryField $entry @('status')) -eq 'active' -and -not $needsDetail
   if($needsDetail -or $confirmActive){
    try{$detail=& $ReadPage $detailUrl}catch{
     if($_.Exception.Message -match '(?i)(404|not.found)'){continue}
     throw
    }
    $detailVersion=[string](Get-JawsFoundryField $detail @('version'))
    if([string]::IsNullOrEmpty($detailVersion)){
     if($needsDetail){throw 'JAWS-RECON-112: Version detail mismatch.'}
    }elseif($detailVersion -cne $version){
     throw 'JAWS-RECON-112: Version detail mismatch.'
    }else{
     $entry=$detail
    }
   }
   $all+=@($entry)
  }
  $next=Get-JawsFoundryField $page @('nextLink')
  if(-not $next){$next=Get-JawsFoundryField $page @('next')}
  if(-not $next){
   if((Get-JawsFoundryField $page @('has_more')) -eq $true){throw 'JAWS-RECON-106: More pages without continuation.'}
   return @($all)
  }
  $prefix="$ProjectEndpoint/agents/jaws-supervisor-dev/versions?"
  if(-not ([string]$next).StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'JAWS-RECON-107: Unexpected continuation URL.'}
  $url=Set-JawsSupervisorDraftListing ([string]$next)
 }
 throw 'JAWS-RECON-108: Pagination limit exceeded.'
}
function Wait-JawsSupervisorCandidate {
 [CmdletBinding()]
 param([Parameter(Mandatory)][scriptblock]$ReadPage,[Parameter(Mandatory)][string]$ProjectEndpoint,
 [Parameter(Mandatory)][string]$Image,[int]$MaxAttempts=12,[int]$DelaySeconds=10,[int]$StableReads=1,
 [scriptblock]$Sleep={param($seconds) Start-Sleep -Seconds $seconds})
 if($MaxAttempts -lt 1 -or $DelaySeconds -lt 0 -or $StableReads -lt 1){throw 'JAWS-RECON-109: Invalid polling parameters.'}
 $stable=0
 $stableVersion=''
 for($i=1;$i -le $MaxAttempts;$i++){
  try{
   $versions=@(Get-JawsSupervisorVersionInventory -ReadPage $ReadPage -ProjectEndpoint $ProjectEndpoint)
   $candidate=Resolve-JawsSupervisorCandidate -Versions $versions -Image $Image
   if($null -ne $candidate){
    if($candidate.Status -match '^(failed|error|canceled|cancelled)$'){
     return [pscustomobject]@{Status='FAILED';Version=$candidate.Version;ActiveVerified=$false;Attempts=$i;Reason=$candidate.Status}
    }
    $activeDraft=$candidate.Status -ceq 'active' -and $candidate.Draft -eq $true -and $candidate.Version -match '^draft-[0-9]+$'
    $activeRelease=$candidate.Status -ceq 'active' -and $candidate.Draft -eq $false -and $candidate.Version -match '^[0-9]+$'
    if($activeDraft -or $activeRelease){
     if($stableVersion -cne $candidate.Version){$stable=0;$stableVersion=$candidate.Version}
     $stable++
     if($stable -ge $StableReads){
      $status=if($activeDraft){'ACTIVE_VERIFIED'}else{'ALREADY_RELEASED'}
      return [pscustomobject]@{Status=$status;Version=$candidate.Version;ActiveVerified=$true;Attempts=$i;Reason=''}
     }
    }else{$stable=0;$stableVersion=''}
   }else{$stable=0;$stableVersion=''}
  }catch{
   if($_.Exception.Message -match '^JAWS-RECON-'){throw}
   if($i -eq $MaxAttempts){throw}
   $stable=0;$stableVersion=''
  }
  if($i -lt $MaxAttempts){& $Sleep $DelaySeconds}
 }
 return [pscustomobject]@{Status='INDETERMINATE';Version='';ActiveVerified=$false;Attempts=$MaxAttempts;Reason='No unique active version before timeout'}
}
Export-ModuleMember -Function Get-JawsFoundryField,Get-JawsFoundryAgentVersion,Compare-JawsFoundrySupervisorState,Resolve-JawsSupervisorCandidate,Get-JawsSupervisorVersionInventory,Wait-JawsSupervisorCandidate,Resolve-JawsAzureCliPython,Get-JawsAzRestGetCommand,Invoke-JawsAzRestGet
