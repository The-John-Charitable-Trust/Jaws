# Read-only discovery for a subscription that has no JAWS state file.
# Does not create resources and does not write installer/config.
Set-StrictMode -Version Latest

function ConvertTo-JawsStepAList {
    param($Value)
    if ($null -eq $Value) { return @() }
    return @($Value | Where-Object { $null -ne $_ })
}

function Get-JawsStepAProperty {
    param($Object,[Parameter(Mandatory)][string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Invoke-JawsStepAGreenfieldDiscovery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$EnvironmentName,
        [string]$SubscriptionId,
        [string]$ResourceGroupName,
        [string]$Location,
        [Parameter(Mandatory)][string]$InstallerRoot,
        [switch]$NonInteractive
    )
    Import-Module (Join-Path $PSScriptRoot 'AzurePreflight.psm1') -Force
    $devState = Join-Path $InstallerRoot 'config/jaws-installation-state.dev.json'
    $devBefore = Get-Content -LiteralPath $devState -Raw
    $context = Get-JawsAuthorizedSubscriptions -NonInteractive:$NonInteractive
    $cliId = [string]$context.Account.id
    if ($SubscriptionId -and $SubscriptionId -ine $cliId) {
        throw 'JAWS-AUTH-007: -SubscriptionId does not match the Azure CLI account. Run az account set. No resources were created.'
    }
    $selected = Select-JawsSubscription -Subscriptions $context.Subscriptions -SubscriptionId $cliId -NonInteractive
    $subscription = [string]$selected.id
    $tenant = [string]$selected.tenantId
    if ([string]::IsNullOrWhiteSpace($tenant)) { throw 'JAWS-AUTH-006: The selected subscription has no tenant id.' }
    $groupsValue = Invoke-JawsPreflightRead -Arguments @('group','list','--subscription',$subscription,'--output','json','--only-show-errors') -Operation 'greenfield resource group inventory'
    $groups = ConvertTo-JawsStepAList $groupsValue
    $resourcesValue = Invoke-JawsPreflightRead -Arguments @('resource','list','--subscription',$subscription,'--output','json','--only-show-errors') -Operation 'greenfield resource inventory'
    $resources = ConvertTo-JawsStepAList $resourcesValue
    $intendedExists = $false
    $intendedLocation = $null
    if ($ResourceGroupName) {
        $match = @($groups | Where-Object { [string](Get-JawsStepAProperty $_ 'name') -ieq $ResourceGroupName })
        $intendedExists = $match.Count -eq 1
        if ($intendedExists) { $intendedLocation = [string](Get-JawsStepAProperty $match[0] 'location') }
    }
    $candidates = @()
    foreach ($resource in $resources) {
        $name = [string](Get-JawsStepAProperty $resource 'name')
        $rg = [string](Get-JawsStepAProperty $resource 'resourceGroup')
        $tags = Get-JawsStepAProperty $resource 'tags'
        $tagMatch = $false
        if ($null -ne $tags) {
            foreach ($key in @($tags.PSObject.Properties | ForEach-Object { $_.Name })) {
                $value = [string](Get-JawsStepAProperty $tags $key)
                if ($value -match '(?i)jaws|tight.?fang|tfang') { $tagMatch = $true; break }
            }
        }
        if ($name -match '(?i)jaws|tight.?fang|tfang' -or $rg -match '(?i)jaws|tight.?fang|tfang' -or $tagMatch) {
            $candidates += [pscustomobject]@{
                Name = $name
                Type = [string](Get-JawsStepAProperty $resource 'type')
                ResourceGroup = $rg
                ResourceId = [string](Get-JawsStepAProperty $resource 'id')
            }
        }
    }
    $environmentOk = $EnvironmentName -match '^[a-z][a-z0-9-]{1,20}$' -and $EnvironmentName -ne 'dev'
    $reservedRg = $ResourceGroupName -eq 'rg-aiops-lab'
    $locationConflict = $intendedExists -and $Location -and $intendedLocation -and ($intendedLocation -ine $Location)
    $prepared = $environmentOk -and -not $reservedRg -and -not $locationConflict
    $reason = $null
    if (-not $environmentOk) { $reason = 'Environment name is not accepted by Step B. Use 2-21 lowercase letters, digits, or hyphens, and do not use dev.' }
    elseif ($reservedRg) { $reason = 'rg-aiops-lab is reserved for the accepted dev project.' }
    elseif ($locationConflict) { $reason = "Resource group $ResourceGroupName already exists in $intendedLocation." }
    $next = ".\installer\Install-Jaws.ps1 -Mode Plan -NonInteractive -EnvironmentName $EnvironmentName"
    if ($ResourceGroupName) { $next += " -ResourceGroupName $ResourceGroupName" }
    if ($Location) { $next += " -Location $Location" }
    $local = Join-Path $InstallerRoot '.local'
    if (-not (Test-Path -LiteralPath $local)) { New-Item -ItemType Directory -Path $local -Force | Out-Null }
    $receipt = [pscustomobject]@{
        SchemaVersion = '1.0'
        Status = 'STEP_A_DISCOVERED'
        DiscoveryKind = 'Greenfield'
        SubscriptionSource = 'AzureCli'
        SubscriptionId = $subscription.ToLowerInvariant()
        TenantId = $tenant
        AccountName = [string](Get-JawsStepAProperty $context.Account 'name')
        EnvironmentName = $EnvironmentName
        ResourceGroupName = $(if ($ResourceGroupName) { $ResourceGroupName } else { $null })
        IntendedResourceGroupExists = [bool]$intendedExists
        IntendedResourceGroupLocation = $intendedLocation
        Location = $(if ($Location) { $Location.ToLowerInvariant() } else { $null })
        ResourceGroupCount = @($groups).Count
        ResourceCount = @($resources).Count
        CandidateCount = @($candidates).Count
        Candidates = @($candidates)
        StateFileRequired = $false
        StateFileWritten = $false
        AzureWrites = 0
        PreparedForStepB = [bool]$prepared
        PreparedForStepBReason = $reason
        NextCommand = $next
    }
    $receiptPath = Join-Path $local "jaws-step-a-discovery.$EnvironmentName.generated.json"
    $receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receiptPath -Encoding utf8
    if ((Get-Content -LiteralPath $devState -Raw) -ne $devBefore) {
        throw 'JAWS-STEP-A-022: Greenfield discovery changed the dev installation state.'
    }
    $configWrites = @(Get-ChildItem -LiteralPath (Join-Path $InstallerRoot 'config') -Filter "jaws-installation-state.$EnvironmentName.json" -ErrorAction SilentlyContinue)
    if ($EnvironmentName -ne 'dev' -and $configWrites.Count -gt 0) {
        throw "JAWS-STEP-A-022: Greenfield discovery wrote $EnvironmentName state into installer/config."
    }
    return [pscustomobject]@{ Receipt = $receipt; ReceiptPath = $receiptPath }
}

Export-ModuleMember -Function Invoke-JawsStepAGreenfieldDiscovery
