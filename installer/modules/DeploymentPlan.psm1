# JAWS Stage B2: offline-only deployment blueprint validation. No Azure or network calls.
Set-StrictMode -Version Latest

function New-JawsOfflineDeploymentPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$BlueprintPath)

    if (-not (Test-Path -LiteralPath $BlueprintPath -PathType Leaf)) {
        throw "JAWS-PLAN-001: Blueprint not found: $BlueprintPath"
    }
    $blueprint = Get-Content -LiteralPath $BlueprintPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ([string]$blueprint.SchemaVersion -cne '0.1' -or [string]$blueprint.Platform -cne 'JAWS' -or
        [string]$blueprint.PlanKind -cne 'StageBOfflineBlueprint') {
        throw 'JAWS-PLAN-002: Unsupported blueprint schema or platform.'
    }
    $scope = $blueprint.Scope
    if ($null -eq $scope -or [string]::IsNullOrWhiteSpace([string]$scope.ResourceGroupName) -or
        [string]::IsNullOrWhiteSpace([string]$scope.Location) -or
        [string]::IsNullOrWhiteSpace([string]$blueprint.EnvironmentName)) {
        throw 'JAWS-PLAN-003: Environment, resource group and location are required.'
    }
    if ([string]$scope.ResourceGroupName -notmatch '^[a-zA-Z0-9_.()\\-]{1,90}$' -or
        [string]$blueprint.EnvironmentName -notmatch '^[a-zA-Z0-9_-]{1,32}$') {
        throw 'JAWS-PLAN-003: Invalid environment or resource group name.'
    }
    $subId = [guid]::Empty
    if (-not [guid]::TryParse([string]$scope.SubscriptionId, [ref]$subId) -or $subId -eq [guid]::Empty) {
        throw 'JAWS-PLAN-004: Replace the example subscription ID with an authorized subscription ID.'
    }
    if ($blueprint.Constraints.AzureWritesAllowed -ne $false -or
        $blueprint.Constraints.LiveInferenceAllowed -ne $false -or
        $blueprint.Constraints.HumanApprovalForWrites -ne $true -or
        $blueprint.Constraints.UserPermissionCeiling -ne $true -or
        $blueprint.Constraints.ExternalOwnershipMustBePreserved -ne $true) {
        throw 'JAWS-PLAN-005: Unsafe blueprint constraints.'
    }
    $items = @($blueprint.Components)
    if ($items.Count -lt 3) { throw 'JAWS-PLAN-006: Deployment blueprint is incomplete.' }
    $ids = @{}
    foreach ($item in $items) {
        $id = [string]$item.Id
        if ($id -notmatch '^[a-z0-9-]+$' -or $ids.ContainsKey($id) -or
            [string]::IsNullOrWhiteSpace([string]$item.Name) -or
            [string]::IsNullOrWhiteSpace([string]$item.ResourceType) -or
            [string]::IsNullOrWhiteSpace([string]$item.Cost) -or $item.ApprovalRequired -ne $true) {
            throw 'JAWS-PLAN-006: Invalid, duplicate or insufficiently constrained component.'
        }
        $ids[$id] = $true
    }
    $ordered = [System.Collections.Generic.List[object]]::new()
    $remaining = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $items) { $remaining.Add($item) }
    $done = @{}
    while ($remaining.Count -gt 0) {
        $progress = $false
        for ($i = $remaining.Count - 1; $i -ge 0; $i--) {
            $item = $remaining[$i]
            $dependencies = @($item.DependsOn)
            foreach ($dependency in $dependencies) {
                if (-not $ids.ContainsKey([string]$dependency) -or [string]$dependency -eq [string]$item.Id) {
                    throw 'JAWS-PLAN-007: Invalid or self-referencing dependency.'
                }
            }
            $pending = @($dependencies | Where-Object { -not $done.ContainsKey([string]$_) })
            if ($pending.Count -eq 0) {
                $ordered.Add([pscustomobject]@{
                    Id=[string]$item.Id; Name=[string]$item.Name
                    ResourceType=[string]$item.ResourceType
                    DependsOn=@($dependencies); ProposedAction='RequiresAzureDiscovery'
                    AzureState='NotChecked'; PermissionState='NotChecked'
                    EstimatedCost=[string]$item.Cost; ApprovalRequired=$true
                })
                $done[[string]$item.Id] = $true
                $remaining.RemoveAt($i)
                $progress = $true
            }
        }
        if (-not $progress) { throw 'JAWS-PLAN-008: Cyclic component dependencies.' }
    }
    return [pscustomobject]@{
        SchemaVersion='0.1'; Platform='JAWS'; PlanKind='OfflineBlueprint'
        EnvironmentName=[string]$blueprint.EnvironmentName
        SubscriptionId=[string]$scope.SubscriptionId
        ResourceGroupName=[string]$scope.ResourceGroupName
        Location=[string]$scope.Location
        CanExecute=$false; AzureWrites=0; AzureDiscoveryPerformed=$false
        CostsVerified=$false; UserAuthorizationVerified=$false
        Status='BLOCKED_PENDING_AZURE_DISCOVERY_AND_APPROVAL'
        Disclaimer='Offline dependency blueprint only. This is NOT an Azure-validated plan or authorization to deploy.'
        Components=@($ordered.ToArray())
    }
}
Export-ModuleMember -Function New-JawsOfflineDeploymentPlan
