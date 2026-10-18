# Post one new Supervisor version for a Step B environment.
# Version 1 is read and left unchanged. The dev release script is not used.
[CmdletBinding()]
param(
    [ValidateSet('Plan','Verify','Release')][string]$Mode='Verify',
    [Parameter(Mandatory)][string]$EnvironmentName,
    [string]$ApprovedPlanSha256,
    [switch]$AcknowledgeSupervisorRoute,
    [string]$ExpectedImage
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
Import-Module (Join-Path $root 'modules/StepCEnvironment.psm1') -Force
$ctx=Resolve-JawsStepCStepBContext -EnvironmentName $EnvironmentName -InstallerRoot $root
if(-not [string]::IsNullOrWhiteSpace($ExpectedImage) -and $ExpectedImage -cne $ctx.ExpectedImage){
    throw 'JAWS-INSTALL-C-013: Expected Supervisor image does not match the Step B receipt.'
}
$image=$ctx.ExpectedImage
$endpoint=$ctx.ProjectEndpoint
$agent=$ctx.SupervisorAgent
function Read-Foundry([string]$Url,[switch]$AllowNotFound){
    $out=& az rest --method get --url $Url --resource https://ai.azure.com --output json --only-show-errors 2>&1
    if($LASTEXITCODE -eq 0){ return ($out | Out-String | ConvertFrom-Json -ErrorAction Stop) }
    $err=$out | Out-String
    if($AllowNotFound -and $err -match '(?i)(404|not found|doesn''t exist)'){ return $null }
    throw "JAWS-INSTALL-C-003: Foundry read failed: $err"
}
function Get-Field($Object,[string[]]$Names){
    $current=$Object
    foreach($name in $Names){
        if($null -eq $current){ return $null }
        $property=$current.PSObject.Properties[$name]
        if($null -eq $property){ return $null }
        $current=$property.Value
    }
    return $current
}
function Get-Latest([object]$Summary){
    $latestValue=Get-Field $Summary @('versions','latest')
    if($null -eq $latestValue){ return '' }
    if($latestValue -is [string] -or $latestValue -is [ValueType]){ return [string]$latestValue }
    if($latestValue.PSObject.Properties['version']){ return [string]$latestValue.version }
    return ''
}
$v1=Read-Foundry "$endpoint/agents/$agent/versions/1?api-version=v1"
$v1Image=[string](Get-Field $v1 @('definition','container_configuration','image'))
$v1Toolbox=[string](Get-Field $v1 @('definition','environment_variables','JAWS_INVESTIGATION_TOOLBOX_NAME'))
$v1Model=[string](Get-Field $v1 @('definition','environment_variables','AZURE_AI_MODEL_DEPLOYMENT_NAME'))
if($v1.status -ne 'active' -or $v1.draft -ne $false -or $v1Image -cne $image -or $v1Model -cne $ctx.ModelDeploymentName -or -not [string]::IsNullOrWhiteSpace($v1Toolbox)){
    throw 'JAWS-INSTALL-C-018: Supervisor v1 does not match the Step B receipt, or it already has the Investigation toolbox. It is not modified.'
}
$summary=Read-Foundry "$endpoint/agents/${agent}?api-version=v1"
$latest=Get-Latest $summary
$definition=[ordered]@{
    kind='hosted'
    container_configuration=[ordered]@{ image=$image }
    cpu=[string](Get-Field $v1 @('definition','cpu'))
    memory=[string](Get-Field $v1 @('definition','memory'))
    protocol_versions=@([ordered]@{ protocol='responses'; version='2.0.0' })
    environment_variables=[ordered]@{
        AZURE_AI_MODEL_DEPLOYMENT_NAME=$ctx.ModelDeploymentName
        JAWS_INVESTIGATION_TOOLBOX_NAME=$ctx.ToolboxName
    }
}
$payload=[ordered]@{ draft=$false; definition=$definition }
$json=ConvertTo-Json -InputObject $payload -Depth 15 -Compress
$sha=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($json))).ToLowerInvariant()
$local=Join-Path $root '.local'
if(-not (Test-Path -LiteralPath $local)){ $null=New-Item -ItemType Directory -Force -Path $local | Out-Null }
$planPath=Join-Path $local "jaws-step-c-supervisor-route.$($ctx.PlanSuffix).generated.json"
$operation=if($latest -match '^[0-9]+$' -and $latest -ne '1'){'AlreadyRouted'}else{'CreateRoutedVersion'}
[pscustomobject]@{
    Operation=$operation
    Agent=$agent
    Image=$image
    PlanSha256=$sha
    LeavesSupervisorV1Unchanged=$true
    MayChangeLatestRouting=($operation -eq 'CreateRoutedVersion')
    Toolbox=$ctx.ToolboxName
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $planPath -Encoding utf8
if($operation -eq 'AlreadyRouted'){
    $routed=Read-Foundry "$endpoint/agents/$agent/versions/${latest}?api-version=v1"
    $routedImage=[string](Get-Field $routed @('definition','container_configuration','image'))
    $routedToolbox=[string](Get-Field $routed @('definition','environment_variables','JAWS_INVESTIGATION_TOOLBOX_NAME'))
    if([string]$routed.status -cne 'active' -or $routed.draft -ne $false -or $routedImage -cne $image -or $routedToolbox -cne $ctx.ToolboxName){
        throw 'JAWS-INSTALL-C-007: Routed Supervisor is not the active Step B image with the Investigation toolbox. No version is posted.'
    }
    $v1AfterImage=[string](Get-Field $v1 @('definition','container_configuration','image'))
    if($v1AfterImage -cne $image){ throw 'JAWS-INSTALL-C-008: Supervisor v1 image changed. Refusing the routed release.' }
    if($Mode -ne 'Release'){
        Write-Host "Supervisor route already version $latest. Version 1 unchanged."
        return
    }
    Write-Host "Supervisor route already version $latest. No write."
    return
}
if($Mode -eq 'Plan'){
    Write-Host "Supervisor route plan SHA-256: $sha"
    Write-Host "Plan: $planPath"
    Write-Host 'PLAN ONLY: no Azure writes. Supervisor v1 is not modified.'
    return
}
if($Mode -eq 'Verify'){
    throw 'JAWS-INSTALL-C-005: Latest routing is not a released Supervisor version after v1. No version is posted.'
}
if(-not $AcknowledgeSupervisorRoute -or $ApprovedPlanSha256 -cne $sha){
    throw 'JAWS-INSTALL-C-022: Exact plan approval and -AcknowledgeSupervisorRoute are required to post a Supervisor version.'
}
$tmp=[IO.Path]::GetTempFileName()
try{
    [IO.File]::WriteAllText($tmp,$json,[Text.UTF8Encoding]::new($false))
    $out=& az rest --method post --url "$endpoint/agents/$agent/versions?api-version=v1" --resource https://ai.azure.com --headers 'Content-Type=application/json' --body "@$tmp" --output json --only-show-errors 2>&1
    if($LASTEXITCODE -ne 0){ throw "JAWS-INSTALL-C-023: Supervisor route result uncertain. Inspect the agent before retrying: $($out | Out-String)" }
    $created=$out | Out-String | ConvertFrom-Json
} finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
if($created.draft -ne $false -or [string](Get-Field $created @('definition','container_configuration','image')) -cne $image){
    throw 'JAWS-INSTALL-C-023: Release response did not match the approved image. Inspect Azure state; do not retry.'
}
$createdVersion=[string]$created.version
if($createdVersion -notmatch '^[0-9]+$' -or $createdVersion -eq '1'){
    throw 'JAWS-INSTALL-C-023: Foundry did not return a Supervisor version after v1.'
}
$delay=10
if($env:JAWS_STEPC_POLL_SECONDS -match '^\d+$'){ $delay=[int]$env:JAWS_STEPC_POLL_SECONDS }
$observed=$null
for($attempt=0; $attempt -lt 60; $attempt++){
    $observed=Read-Foundry "$endpoint/agents/$agent/versions/${createdVersion}?api-version=v1" -AllowNotFound
    if($null -ne $observed -and [string]$observed.status -eq 'failed'){ throw 'JAWS-INSTALL-C-023: Supervisor route provisioning failed. Version 1 was not patched.' }
    if($null -ne $observed -and [string]$observed.status -eq 'active' -and $observed.draft -eq $false){ break }
    if($delay -gt 0){ Start-Sleep -Seconds $delay }
}
if($null -eq $observed -or [string]$observed.status -ne 'active'){
    throw 'JAWS-INSTALL-C-023: Supervisor route did not become active. Inspect Foundry before retrying.'
}
$v1After=Read-Foundry "$endpoint/agents/$agent/versions/1?api-version=v1"
$v1AfterImage=[string](Get-Field $v1After @('definition','container_configuration','image'))
$v1AfterToolbox=[string](Get-Field $v1After @('definition','environment_variables','JAWS_INVESTIGATION_TOOLBOX_NAME'))
if($v1After.status -ne 'active' -or $v1After.draft -ne $false -or $v1AfterImage -cne $v1Image -or -not [string]::IsNullOrWhiteSpace($v1AfterToolbox)){
    throw 'JAWS-INSTALL-C-018: Supervisor v1 changed while posting the route. Stop and inspect Azure state.'
}
Write-Host "Supervisor route created: $createdVersion. Version 1 unchanged."
