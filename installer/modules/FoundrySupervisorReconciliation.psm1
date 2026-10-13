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
Export-ModuleMember -Function Get-JawsFoundryAgentVersion,Compare-JawsFoundrySupervisorState
