# JAWS Stage A - Azure read-only discovery
Set-StrictMode -Version Latest

function Get-JawsDiscoveryProperty {
    [CmdletBinding()]
    param([AllowNull()]$InputObject,[Parameter(Mandatory)][string]$PropertyName)
    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [System.Collections.IDictionary]) {
        foreach ($key in $InputObject.Keys) {
            if ([string]$key -ieq $PropertyName) { return $InputObject[$key] }
        }
        return $null
    }
    $property=$InputObject.PSObject.Properties[$PropertyName]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Invoke-JawsAzureRead {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$Operation
    )
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        throw "Azure CLI is not available for $Operation."
    }
    $allowed = @(
        'resource list',
        'cognitiveservices account project list',
        'cognitiveservices account deployment list',
        'identity list'
    )
    $joined = $Arguments -join ' '
    if (-not ($allowed | Where-Object { $joined.StartsWith($_ + ' ') })) {
        throw "Disallowed Azure operation: $Operation"
    }
    # Capture only stdout, never put credentials in errors or logs.
    $output = & az @Arguments 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI discovery failed during $Operation (exit code $LASTEXITCODE). Verify authentication, subscription, RBAC, and Azure CLI support."
    }
    $json = ($output | Out-String).Trim()
    if (-not $json) { throw "Azure CLI returned an empty response for $Operation." }
    try { return (ConvertFrom-Json -InputObject $json) }
    catch { throw "Invalid JSON from Azure CLI during $Operation." }
}

function Resolve-JawsDiscoveryMatch {
    [CmdletBinding()]
    param(
        [AllowNull()][object[]]$Items,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Type,
        [string]$ParentResourceId,
        [string]$ExpectedSubscriptionId
    )
    $matchingResources = @($Items | Where-Object {
        if ($null -eq $_) { return $false }
        $actualName = [string](Get-JawsDiscoveryProperty -InputObject $_ -PropertyName 'name')
        $actualType = [string](Get-JawsDiscoveryProperty -InputObject $_ -PropertyName 'type')
        ($actualName -ieq $Name -or $actualName -like "*/$Name") -and
        ($actualType -ieq $Type -or -not $actualType)
    })
    if ($matchingResources.Count -gt 1) { throw "Ambiguous resource discovery: $Type/$Name." }
    if ($matchingResources.Count -eq 0) {
        return [pscustomobject]@{
            Name=$Name; Type=$Type; Status='Missing'; ResourceId=$null
            Location=$null; Properties=[pscustomobject]@{}
        }
    }
    $r = $matchingResources[0]
    $id = [string](Get-JawsDiscoveryProperty -InputObject $r -PropertyName 'id')
    if (-not $id -or $id -notmatch '^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/') {
        throw "Invalid or missing Azure resource ID for $Type/$Name."
    }
    if ($ExpectedSubscriptionId -and -not $id.StartsWith("/subscriptions/$ExpectedSubscriptionId/", [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Unexpected subscription in ID for $Type/$Name."
    }
    if ($ParentResourceId -and -not $id.StartsWith("$ParentResourceId/", [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Unexpected parent resource in ID for $Type/$Name."
    }
    $properties=Get-JawsDiscoveryProperty -InputObject $r -PropertyName 'properties'
    if ($null -eq $properties) { $properties=[pscustomobject]@{} }
    [pscustomobject]@{
        Name=$Name; Type=$Type; Status='Discovered'; ResourceId=$id
        Location=Get-JawsDiscoveryProperty -InputObject $r -PropertyName 'location'
        Properties=$properties
    }
}

function Get-JawsAzureResource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SubscriptionId,
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$ResourceName,
        [Parameter(Mandatory)][string]$ResourceType
    )
    $results = Invoke-JawsAzureRead -Operation "Resource $ResourceName" -Arguments @(
        'resource','list','--subscription',$SubscriptionId,
        '--resource-group',$ResourceGroupName,'--name',$ResourceName,
        '--resource-type',$ResourceType,'--output','json','--only-show-errors'
    )
    $match = Resolve-JawsDiscoveryMatch -Items @($results) -Name $ResourceName -Type $ResourceType -ExpectedSubscriptionId $SubscriptionId
    if ($match.Status -eq 'Discovered' -and
        -not $match.ResourceId.Contains("/resourceGroups/$ResourceGroupName/")) {
        throw "Unexpected resource group in ID for $ResourceName."
    }
    return $match
}

function Get-JawsFoundryProject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SubscriptionId,
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$FoundryResourceName,
        [Parameter(Mandatory)][string]$ProjectName
    )
    $results = Invoke-JawsAzureRead -Operation "Foundry project $ProjectName" -Arguments @(
        'cognitiveservices','account','project','list','--name',$FoundryResourceName,
        '--resource-group',$ResourceGroupName,'--subscription',$SubscriptionId,
        '--output','json','--only-show-errors'
    )
    $parent = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.CognitiveServices/accounts/$FoundryResourceName"
    Resolve-JawsDiscoveryMatch -Items @($results) -Name $ProjectName `
        -Type 'Microsoft.CognitiveServices/accounts/projects' `
        -ParentResourceId $parent -ExpectedSubscriptionId $SubscriptionId
}

function Get-JawsModelDeployment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SubscriptionId,
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$FoundryResourceName,
        [Parameter(Mandatory)][string]$DeploymentName
    )
    $results = Invoke-JawsAzureRead -Operation "Model deployment $DeploymentName" -Arguments @(
        'cognitiveservices','account','deployment','list','--name',$FoundryResourceName,
        '--resource-group',$ResourceGroupName,'--subscription',$SubscriptionId,
        '--output','json','--only-show-errors'
    )
    $parent = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.CognitiveServices/accounts/$FoundryResourceName"
    $match = Resolve-JawsDiscoveryMatch -Items @($results) -Name $DeploymentName `
        -Type 'Microsoft.CognitiveServices/accounts/deployments' `
        -ParentResourceId $parent -ExpectedSubscriptionId $SubscriptionId
    if ($match.Status -eq 'Discovered') {
        $p = $match.Properties
        $model=Get-JawsDiscoveryProperty -InputObject $p -PropertyName 'model'
        $match | Add-Member -NotePropertyName 'ObservedConfiguration' -NotePropertyValue ([pscustomobject]@{
            ModelName=Get-JawsDiscoveryProperty -InputObject $model -PropertyName 'name'
            ModelVersion=Get-JawsDiscoveryProperty -InputObject $model -PropertyName 'version'
            ProvisioningState=Get-JawsDiscoveryProperty -InputObject $p -PropertyName 'provisioningState'
        })
    }
    return $match
}

Export-ModuleMember -Function Invoke-JawsAzureRead,Resolve-JawsDiscoveryMatch,Get-JawsAzureResource,Get-JawsFoundryProject,Get-JawsModelDeployment
