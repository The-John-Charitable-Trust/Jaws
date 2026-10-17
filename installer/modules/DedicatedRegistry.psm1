# JAWS Stage B2: Dedicated registry installer module.
Set-StrictMode -Version Latest
function New-JawsDedicatedRegistryPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$State,[Parameter(Mandatory)][string]$RegistryName)
    if ($State.Platform -ne 'JAWS' -or $RegistryName -cnotmatch '^[a-z0-9]{5,50}$') {
        throw 'JAWS-ACR-PLAN-002: Invalid platform or registry name.'
    }
    if ($State.ResourceGroupName -notmatch '^[a-zA-Z0-9_.()\\-]{1,90}$') {
        throw 'JAWS-ACR-PLAN-003: Invalid resource group.'
    }
    $guid=[guid]::Empty
    if (-not [guid]::TryParse([string]$State.SubscriptionId,[ref]$guid) -or $guid -eq [guid]::Empty) {
        throw 'JAWS-ACR-PLAN-004: Invalid subscription.'
    }
    $foundry=@($State.Resources | Where-Object Type -eq 'Microsoft.CognitiveServices/accounts')
    if ($foundry.Count -ne 1 -or [string]$foundry[0].ExpectedConfiguration.Location -ne 'eastus') {
        throw 'JAWS-ACR-PLAN-005: Expected eastus Foundry baseline missing.'
    }
    $p=[ordered]@{
        SchemaVersion='1.0'
        Action='CreateDedicatedJawsAcr'
        SubscriptionId=[string]$State.SubscriptionId
        ResourceGroupName=[string]$State.ResourceGroupName
        EnvironmentName=[string]$State.EnvironmentName
        RegistryName=$RegistryName
        Location='eastus'
        Sku='Basic'
        AdminEnabled=$false
        PublicNetworkAccess='Enabled'
        RoleAssignmentMode='rbac'
        Tags=[ordered]@{application='JAWS';managedBy='JAWS-Installer';environment=[string]$State.EnvironmentName}
    }
    $serialized=ConvertTo-Json -InputObject $p -Compress -Depth 12
    $hash=[System.Security.Cryptography.SHA256]::Create()
    try { $digest=$hash.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($serialized)) }
    finally { $hash.Dispose() }
    $fingerprint=([System.BitConverter]::ToString($digest)).Replace('-','').ToLowerInvariant()
    [pscustomobject]@{
        PlanSha256=$fingerprint
        Plan=$p
        SubscriptionId=$p.SubscriptionId
        ResourceGroupName=$p.ResourceGroupName
        RegistryName=$p.RegistryName
        Location=$p.Location
        Sku=$p.Sku
        Cost='Billable Basic ACR, ongoing charge. Exact region pricing has not been verified.'
        CostAcknowledgmentRequired=$true
        NetworkReviewRequired=$true
        DeploymentWritesAllowedOnlyWithExactApproval=$true
        AzureWrites=0
        Status='BLOCKED_PENDING_COST_ACKNOWLEDGMENT_AND_EXACT_APPROVAL'
    }
}
function Invoke-JawsDedicatedRegistryCreate {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Plan)
    if ($Plan.Plan.Action -ne 'CreateDedicatedJawsAcr' -or
        $Plan.Plan.Sku -ne 'Basic' -or $Plan.Plan.AdminEnabled -ne $false -or
        $Plan.Plan.PublicNetworkAccess -ne 'Enabled' -or
        $Plan.Plan.RoleAssignmentMode -ne 'rbac' -or
        $Plan.PlanSha256 -cnotmatch '^[0-9a-f]{64}$') {
        throw 'JAWS-ACR-SEC-001: Unsafe registry plan.'
    }
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        throw 'JAWS-ACR-PREREQ-001: Azure CLI is required.'
    }
    $sub=[string]$Plan.SubscriptionId; $rg=[string]$Plan.ResourceGroupName
    $name=[string]$Plan.RegistryName
    $accounts=& az account list --all --output json --only-show-errors 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'JAWS-ACR-AUTH-001: Cannot read authorized subscriptions.' }
    $visible=@(($accounts | Out-String | ConvertFrom-Json) | Where-Object { $_.id -ieq $sub -and $_.state -eq 'Enabled' })
    if ($visible.Count -ne 1) { throw 'JAWS-ACR-AUTH-002: Target subscription is not enabled or accessible.' }
    $groupJson=& az group show --subscription $sub --name $rg --output json --only-show-errors 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'JAWS-ACR-AUTH-003: Target resource group not accessible.' }
    $group=($groupJson | Out-String | ConvertFrom-Json)
    if ([string]$group.name -ine $rg -or [string]$group.location -ine [string]$Plan.Location) {
        throw 'JAWS-ACR-AUTH-004: Target group identity or location differs from approved plan.'
    }
    # Do not adopt existing registries, even if a name collides.
    $existsJson=& az acr show --subscription $sub --resource-group $rg --name $name --output json --only-show-errors 2>$null
    if ($LASTEXITCODE -eq 0) {
        $existing=($existsJson | Out-String | ConvertFrom-Json)
        throw "JAWS-ACR-OWNERSHIP-001: Registry already exists ($($existing.id)). Refusing adoption or mutation."
    }
    $checkJson=& az acr check-name --name $name --output json --only-show-errors 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'JAWS-ACR-NAME-001: Global registry-name availability check failed.' }
    $available=($checkJson | Out-String | ConvertFrom-Json)
    if ($available.nameAvailable -ne $true) { throw 'JAWS-ACR-NAME-002: Registry name not globally available; nothing created.' }
    # This is the ONLY billable Azure write. All inputs derive from the exact digest-bound plan.
    $createJson=& az acr create --subscription $sub --resource-group $rg --name $name --location $Plan.Location --sku Basic --admin-enabled false --public-network-enabled true --role-assignment-mode rbac --tags "application=JAWS" "managedBy=JAWS-Installer" "environment=$($Plan.Plan.EnvironmentName)" --output json --only-show-errors 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'JAWS-ACR-CREATE-001: Registry creation failed. Check Azure for partial creation before retry.' }
    $created=($createJson | Out-String | ConvertFrom-Json)
    $expected="/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.ContainerRegistry/registries/$name"
    if ([string]$created.id -ine $expected -or [string]$created.loginServer -ine "$name.azurecr.io" -or
        $created.adminUserEnabled -ne $false -or [string]$created.sku.name -ne 'Basic') {
        throw 'JAWS-ACR-VERIFY-001: Created registry does not match approved plan. Investigate; do not mutate automatically.'
    }
    [pscustomobject]@{Status='CREATED_AND_VERIFIED';RegistryResourceId=$expected;LoginServer="$name.azurecr.io";Ownership='InstallerCreated';CreatedByInstaller=$true;Sku='Basic';AdminEnabled=$false;AzureWrites=1}
}
Export-ModuleMember -Function New-JawsDedicatedRegistryPlan,Invoke-JawsDedicatedRegistryCreate
