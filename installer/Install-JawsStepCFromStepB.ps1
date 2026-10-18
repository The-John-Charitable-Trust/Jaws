# Step C for the environment created by Step B.
# Validate is read-only. Install applies one known correction per failed gate.
# Supervisor v1 is never patched. The dev project scripts are not called.
[CmdletBinding()]
param(
    [ValidateSet('Validate','Install')][string]$Mode='Validate',
    [Parameter(Mandatory)][string]$EnvironmentName,
    [switch]$AcknowledgeStepCInstall,
    [switch]$AcknowledgeInferenceCharges,
    [string]$ExpectedImage
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
Import-Module (Join-Path $root 'modules/StepCInstall.psm1') -Force
Import-Module (Join-Path $root 'modules/StepCEnvironment.psm1') -Force
if($Mode -eq 'Install' -and -not $AcknowledgeStepCInstall){
    throw 'JAWS-INSTALL-C-001: Install corrections require -AcknowledgeStepCInstall. -Mode Validate performs no Azure writes.'
}
$ctx=Resolve-JawsStepCStepBContext -EnvironmentName $EnvironmentName -InstallerRoot $root
if(-not [string]::IsNullOrWhiteSpace($ExpectedImage) -and $ExpectedImage -cne $ctx.ExpectedImage){
    throw 'JAWS-INSTALL-C-013: Expected Supervisor image does not match the Step B receipt.'
}
$script:gateOrder=@('Prerequisites','State','InvestigationA2A','Planner','Connection','Toolbox','Supervisor','Rbac','Identity','Acceptance')
$script:gates=New-Object System.Collections.Generic.List[object]
$script:corrections=New-Object System.Collections.Generic.List[string]
$local=Join-Path $root '.local'
if(-not (Test-Path -LiteralPath $local)){ $null=New-Item -ItemType Directory -Force -Path $local | Out-Null }
$receiptPath=Join-Path $local "jaws-step-c-install.$($ctx.PlanSuffix).generated.json"
$planner=Join-Path $root 'Configure-JawsInvestigationPlanner.ps1'
$connection=Join-Path $root 'Configure-JawsDelegationConnection.ps1'
$toolbox=Join-Path $root 'Configure-JawsDelegationToolbox.ps1'
$rbac=Join-Path $root 'Configure-JawsDelegationConsumerRbac.ps1'
$identity=Join-Path $root 'Test-JawsA2AIdentityContext.ps1'
$route=Join-Path $root 'Publish-JawsStepCSupervisorRoute.ps1'
$accept=Join-Path $root 'Test-JawsStepCFromStepB.ps1'

function Add-Gate([string]$Name,[string]$Result,[string]$ErrorCode,[string]$Detail){
    $script:gates.Add([pscustomobject]@{Name=$Name;Result=$Result;ErrorCode=$ErrorCode;Detail=$Detail}) | Out-Null
}
function Read-PlanSha([string]$FileName){
    $path=Join-Path $local $FileName
    if(-not (Test-Path -LiteralPath $path -PathType Leaf)){ throw "JAWS-INSTALL-C-009: Plan file missing after the read-only check: $FileName" }
    $plan=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    $sha=[string]$plan.PlanSha256
    if($sha -notmatch '^[a-f0-9]{64}$'){ throw "JAWS-INSTALL-C-010: Plan fingerprint is not a SHA-256 digest: $FileName" }
    return $sha
}
function Invoke-StepCCorrection([string]$Action){
    switch($Action){
        'CreatePlanner' {
            $sha=Read-PlanSha "jaws-step-c-planner-plan.$($ctx.PlanSuffix).generated.json"
            & $planner -Mode Install -EnvironmentName $ctx.EnvironmentName -ProjectEndpoint $ctx.ProjectEndpoint -AgentName $ctx.PlannerAgent -ModelName $ctx.ModelName -ApprovedPlanSha256 $sha -AcknowledgePlannerCreate
        }
        'CreateConnection' {
            $sha=Read-PlanSha "jaws-step-c-delegation-connection-plan.$($ctx.PlanSuffix).generated.json"
            & $connection -Mode Install -StateFile $ctx.StateFile -ApprovedPlanSha256 $sha -AcknowledgeA2AConnection
        }
        'RetargetConnection' {
            $sha=Read-PlanSha "jaws-step-c-delegation-connection-plan.$($ctx.PlanSuffix).generated.json"
            & $connection -Mode Retarget -StateFile $ctx.StateFile -ApprovedPlanSha256 $sha -AcknowledgeA2AConnection
        }
        'CreateToolbox' {
            $sha=Read-PlanSha "jaws-step-c-toolbox-plan.$($ctx.PlanSuffix).generated.json"
            & $toolbox -Mode Install -EnvironmentName $ctx.EnvironmentName -ProjectEndpoint $ctx.ProjectEndpoint -ToolboxName $ctx.ToolboxName -ConnectionName $ctx.ConnectionName -PlannerAgent $ctx.PlannerAgent -ApprovedPlanSha256 $sha -AcknowledgeToolboxChargesAndAccess
        }
        'PublishSupervisorRoute' {
            $sha=Read-PlanSha "jaws-step-c-supervisor-route.$($ctx.PlanSuffix).generated.json"
            & $route -Mode Release -EnvironmentName $ctx.EnvironmentName -ExpectedImage $ctx.ExpectedImage -ApprovedPlanSha256 $sha -AcknowledgeSupervisorRoute
        }
        'AssignConsumerRole' {
            $sha=Read-PlanSha "jaws-step-c-delegation-consumer-rbac-plan.$($ctx.PlanSuffix).generated.json"
            & $rbac -Mode Assign -StateFile $ctx.StateFile -ApprovedPlanSha256 $sha -AcknowledgeSecurityRoleAssignment
        }
        default { throw "JAWS-INSTALL-C-011: No correction is defined for $Action." }
    }
}
function Invoke-CorrectableGate([string]$Name,[scriptblock]$Verify){
    try {
        & $Verify
        Add-Gate $Name 'Passed' '' ''
    } catch {
        $message=$_.Exception.Message
        $action=Get-JawsStepCFromStepBCorrection -Gate $Name -ErrorMessage $message -Mode $Mode
        if(-not $action){
            Add-Gate $Name 'Blocked' (Get-JawsErrorCode $message) $message
            throw
        }
        try {
            Invoke-StepCCorrection -Action $action
            & $Verify
            $script:corrections.Add($action) | Out-Null
            Add-Gate $Name 'Repaired' '' $action
        } catch {
            $repairMessage=$_.Exception.Message
            Add-Gate $Name 'Blocked' (Get-JawsErrorCode $repairMessage) $repairMessage
            throw
        }
    }
}
function Invoke-RequiredGate([string]$Name,[scriptblock]$Action){
    try {
        $result=& $Action
        if([string]$result -eq 'Skipped'){ Add-Gate $Name 'Skipped' '' 'Acceptance inference was not requested.' }
        else { Add-Gate $Name 'Passed' '' '' }
    } catch {
        $message=$_.Exception.Message
        Add-Gate $Name 'Blocked' (Get-JawsErrorCode $message) $message
        throw
    }
}
function Read-AzJson([string[]]$Arguments,[string]$Code){
    $out=& az @Arguments 2>&1
    if($LASTEXITCODE -ne 0){ throw "${Code}: $($out | Out-String)" }
    return ($out | Out-String | ConvertFrom-Json -ErrorAction Stop)
}

$failed=$null
$status='BLOCKED'
try {
    Invoke-RequiredGate 'Prerequisites' {
        if($PSVersionTable.PSVersion.Major -lt 7){ throw 'JAWS-INSTALL-C-002: PowerShell 7 or newer is required.' }
        if(-not (Get-Command az -ErrorAction SilentlyContinue)){ throw 'JAWS-INSTALL-C-002: Azure CLI is required before Step C installation.' }
    }
    Invoke-RequiredGate 'State' {
        $account=Read-AzJson @('account','show','--output','json','--only-show-errors') 'JAWS-INSTALL-C-020'
        if([string]$account.id -ine $ctx.SubscriptionId){
            throw 'JAWS-INSTALL-C-020: Azure CLI subscription differs from the Step B receipt. No resources were changed.'
        }
        $foundry=Read-AzJson @('cognitiveservices','account','show','--subscription',$ctx.SubscriptionId,'--resource-group',$ctx.ResourceGroupName,'--name',$ctx.FoundryAccountName,'--output','json','--only-show-errors') 'JAWS-INSTALL-C-016'
        if([string]$foundry.kind -ne 'AIServices' -or [string]$foundry.name -cne $ctx.FoundryAccountName){
            throw 'JAWS-INSTALL-C-016: The Step B Foundry account was not found in this subscription.'
        }
        $v1=Read-AzJson @('rest','--method','get','--url',"$($ctx.ProjectEndpoint)/agents/$($ctx.SupervisorAgent)/versions/1?api-version=v1",'--resource','https://ai.azure.com','--output','json','--only-show-errors') 'JAWS-INSTALL-C-003'
        $v1Image=[string]$v1.definition.container_configuration.image
        $v1Toolbox=''
        if($v1.definition.PSObject.Properties['environment_variables'] -and $v1.definition.environment_variables.PSObject.Properties['JAWS_INVESTIGATION_TOOLBOX_NAME']){
            $v1Toolbox=[string]$v1.definition.environment_variables.JAWS_INVESTIGATION_TOOLBOX_NAME
        }
        if([string]$v1.status -ne 'active' -or $v1.draft -ne $false -or $v1Image -cne $ctx.ExpectedImage -or -not [string]::IsNullOrWhiteSpace($v1Toolbox)){
            throw 'JAWS-INSTALL-C-018: Supervisor v1 does not match the Step B receipt, or it already has the Investigation toolbox. It is not modified.'
        }
    }
    Add-Gate 'InvestigationA2A' 'Skipped' '' 'No hosted Investigation agent is created. RemoteA2A targets the prompt planner. Foundry returns HOSTED_AGENT_NOT_SUPPORTED for hosted-agent A2A.'
    Invoke-CorrectableGate 'Planner' {
        & $planner -Mode Verify -EnvironmentName $ctx.EnvironmentName -ProjectEndpoint $ctx.ProjectEndpoint -AgentName $ctx.PlannerAgent -ModelName $ctx.ModelName
    }
    Invoke-CorrectableGate 'Connection' { & $connection -Mode Verify -StateFile $ctx.StateFile }
    Invoke-CorrectableGate 'Toolbox' {
        & $toolbox -Mode Verify -EnvironmentName $ctx.EnvironmentName -ProjectEndpoint $ctx.ProjectEndpoint -ToolboxName $ctx.ToolboxName -ConnectionName $ctx.ConnectionName -PlannerAgent $ctx.PlannerAgent
    }
    Invoke-CorrectableGate 'Supervisor' { & $route -Mode Verify -EnvironmentName $ctx.EnvironmentName -ExpectedImage $ctx.ExpectedImage }
    Invoke-CorrectableGate 'Rbac' { & $rbac -Mode Verify -StateFile $ctx.StateFile }
    Invoke-RequiredGate 'Identity' { & $identity -StateFile $ctx.StateFile }
    Invoke-RequiredGate 'Acceptance' {
        if(-not $AcknowledgeInferenceCharges){ return 'Skipped' }
        & $accept -EnvironmentName $ctx.EnvironmentName -ExpectedImage $ctx.ExpectedImage -AcknowledgeInferenceCharges
    }
    $acceptanceRow=@($script:gates.ToArray() | Where-Object { $_.Name -eq 'Acceptance' }) | Select-Object -Last 1
    $acceptance=if($null -eq $acceptanceRow){'Failed'}elseif($acceptanceRow.Result -eq 'Passed'){'Passed'}elseif($acceptanceRow.Result -eq 'Skipped'){'Skipped'}else{'Failed'}
    $status=Get-JawsStepCInstallStatus -GateResults @($script:gates.ToArray()) -Acceptance $acceptance
} catch {
    $failed=$_
    $status='BLOCKED'
} finally {
    $errorCode=if($failed){ Get-JawsErrorCode $failed.Exception.Message }else{''}
    $errorMessage=if($failed){ $failed.Exception.Message }else{''}
    $posted=@($script:corrections.ToArray() | Where-Object { $_ -eq 'PublishSupervisorRoute' }).Count -gt 0
    [pscustomobject]@{
        SchemaVersion='1.0'
        Profile='StepB'
        Mode=$Mode
        Status=$status
        EnvironmentName=$ctx.EnvironmentName
        ProjectEndpoint=$ctx.ProjectEndpoint
        FoundryAccountName=$ctx.FoundryAccountName
        ProjectName=$ctx.ProjectName
        SupervisorAgent=$ctx.SupervisorAgent
        PlannerAgent=$ctx.PlannerAgent
        ConnectionName=$ctx.ConnectionName
        ToolboxName=$ctx.ToolboxName
        ExpectedImage=$ctx.ExpectedImage
        HostedInvestigationConfigured=$false
        GateOrder=@($script:gateOrder)
        Gates=@($script:gates.ToArray())
        Corrections=@($script:corrections.ToArray())
        ErrorCode=$errorCode
        ErrorMessage=$errorMessage
        SupervisorV1Modified=($errorMessage -match 'Supervisor v1 changed')
        SupervisorVersionPosted=$posted
        ApprovedCorrectionCount=$script:corrections.Count
        CustomerInstallationAccepted=$false
        ImageRule='The routed version uses the Step B image digest and the Investigation toolbox variable. Version 1 keeps that digest without the toolbox variable. The dev project still requires a different routed digest.'
        CompletedAtUtc=[DateTime]::UtcNow.ToString('o')
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receiptPath -Encoding utf8
}
Write-Host "Step C source: Step B receipt"
Write-Host "Environment: $($ctx.EnvironmentName)"
Write-Host "Foundry: $($ctx.FoundryAccountName)"
Write-Host "Project: $($ctx.ProjectName)"
Write-Host "Supervisor: $($ctx.SupervisorAgent)"
Write-Host "Planner: $($ctx.PlannerAgent)"
Write-Host "Connection: $($ctx.ConnectionName)"
Write-Host "Toolbox: $($ctx.ToolboxName)"
Write-Host "Image: $($ctx.ExpectedImage)"
Write-Host 'Hosted investigation agent: not created'
Write-Host "Step C install: $status"
foreach($gate in $script:gates.ToArray()){ Write-Host ("  {0,-20} {1}" -f $gate.Name,$gate.Result) }
if($script:corrections.Count -gt 0){ Write-Host ("Corrections: {0}" -f ($script:corrections.ToArray() -join ', ')) }
Write-Host "Supervisor version posted: $(@($script:corrections.ToArray() | Where-Object { $_ -eq 'PublishSupervisorRoute' }).Count -gt 0)"
Write-Host 'Customer installation accepted: false'
Write-Host "Receipt: $receiptPath"
if($status -eq 'VALIDATED'){
    Write-Host "Non-billable Step C gates passed. Re-run .\installer\Install-JawsThroughStepC.ps1 -Mode Validate -EnvironmentName $($ctx.EnvironmentName) -AcknowledgeInferenceCharges to run the Supervisor acceptance call."
}
if($failed){ throw $failed.Exception.Message }
