# Stage B2 Foundry project identity to ACR pull-role installer.
Set-StrictMode -Version Latest

function Get-JawsFoundryAcrRbacPlanHash {
    param([Parameter(Mandatory)]$Plan)
    $json=ConvertTo-Json -InputObject $Plan -Depth 20 -Compress
    $hash=[System.Security.Cryptography.SHA256]::Create()
    try { $bytes=$hash.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($json)) }
    finally { $hash.Dispose() }
    ([BitConverter]::ToString($bytes)).Replace('-','').ToLowerInvariant()
}

function New-JawsFoundryAcrRbacPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)][ValidatePattern('^[a-z0-9]{5,50}$')][string]$RegistryName,
        [Parameter(Mandatory)][string]$ProjectPrincipalId,
        [Parameter(Mandatory)][string]$RegistryResourceId,
        [Parameter(Mandatory)][string]$RegistryRoleAssignmentMode,
        [Parameter(Mandatory)][bool]$RegistryAdminEnabled
    )
    if ($State.Platform -ne 'JAWS' -or $State.EnvironmentName -ne 'dev') {
        throw 'JAWS-RBAC-PLAN-001: Unexpected platform or environment.'
    }
    $subscriptionGuid=[guid]::Empty
    $principalGuid=[guid]::Empty
    if (-not [guid]::TryParse([string]$State.SubscriptionId,[ref]$subscriptionGuid) -or
        $subscriptionGuid -eq [guid]::Empty -or
        -not [guid]::TryParse($ProjectPrincipalId,[ref]$principalGuid) -or
        $principalGuid -eq [guid]::Empty) {
        throw 'JAWS-RBAC-PLAN-002: Invalid subscription or project principal identity.'
    }
    $foundry=@($State.Resources | Where-Object Type -eq 'Microsoft.CognitiveServices/accounts')
    $project=@($State.Resources | Where-Object Type -eq 'Microsoft.CognitiveServices/accounts/projects')
    if ($foundry.Count -ne 1 -or $project.Count -ne 1 -or
        $project[0].ExpectedConfiguration.ParentResource -ne $foundry[0].Name) {
        throw 'JAWS-RBAC-PLAN-003: Authoritative Foundry project relationship is missing.'
    }
    $sub=[string]$State.SubscriptionId
    $rg=[string]$State.ResourceGroupName
    $expectedRegistryId="/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.ContainerRegistry/registries/$RegistryName"
    if ($RegistryResourceId -ine $expectedRegistryId -or $RegistryAdminEnabled) {
        throw 'JAWS-RBAC-PLAN-004: Registry identity mismatch or insecure admin authentication.'
    }
    $role=$null
    if ($RegistryRoleAssignmentMode -eq 'LegacyRegistryPermissions') {
        $role='AcrPull'
    } elseif ($RegistryRoleAssignmentMode -eq 'AbacRepositoryPermissions') {
        $role='Container Registry Repository Reader'
    } else {
        throw 'JAWS-RBAC-PLAN-005: Unsupported registry role-assignment mode.'
    }
    $projectId="/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.CognitiveServices/accounts/$($foundry[0].Name)/projects/$($project[0].Name)"
    $payload=[ordered]@{
        SchemaVersion='1.0'
        Action='AssignFoundryProjectAcrPullRole'
        SubscriptionId=$sub
        ResourceGroupName=$rg
        EnvironmentName=[string]$State.EnvironmentName
        ProjectResourceId=$projectId
        ProjectPrincipalId=$ProjectPrincipalId
        RegistryName=$RegistryName
        RegistryResourceId=$expectedRegistryId
        RegistryRoleAssignmentMode=$RegistryRoleAssignmentMode
        RoleDefinitionName=$role
        AssigneePrincipalType='ServicePrincipal'
    }
    [pscustomobject]@{
        PlanSha256=Get-JawsFoundryAcrRbacPlanHash -Plan $payload
        Plan=$payload
        CanAssign=$false
        AzureWrites=0
        SecurityAcknowledgmentRequired=$true
        Status='BLOCKED_PENDING_EXACT_APPROVAL_AND_SECURITY_ACKNOWLEDGMENT'
    }
}

function Get-JawsFoundryAcrRbacLivePlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)][string]$RegistryName
    )
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        throw 'JAWS-RBAC-PREREQ-001: Azure CLI is required.'
    }
    $foundry=@($State.Resources | Where-Object Type -eq 'Microsoft.CognitiveServices/accounts')
    $project=@($State.Resources | Where-Object Type -eq 'Microsoft.CognitiveServices/accounts/projects')
    if ($foundry.Count -ne 1 -or $project.Count -ne 1) {
        throw 'JAWS-RBAC-PLAN-003: Authoritative Foundry project relationship is missing.'
    }
    $sub=[string]$State.SubscriptionId
    $rg=[string]$State.ResourceGroupName
    $projectId="/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.CognitiveServices/accounts/$($foundry[0].Name)/projects/$($project[0].Name)"
    $projectJson=& az resource show --ids $projectId --output json --only-show-errors 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'JAWS-RBAC-DISCOVERY-001: Foundry project is unavailable.' }
    $projectResource=$projectJson | Out-String | ConvertFrom-Json
    $principal=$null
    if ($projectResource.PSObject.Properties['identity'] -and $projectResource.identity -and
        $projectResource.identity.PSObject.Properties['principalId']) {
        $principal=[string]$projectResource.identity.principalId
    }
    if ([string]$projectResource.id -ine $projectId -or [string]::IsNullOrWhiteSpace($principal)) {
        throw 'JAWS-RBAC-DISCOVERY-002: Foundry project identity is missing or mismatched.'
    }
    $acrJson=& az acr show --subscription $sub --resource-group $rg --name $RegistryName --output json --only-show-errors 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'JAWS-RBAC-DISCOVERY-003: Registry is unavailable.' }
    $acr=$acrJson | Out-String | ConvertFrom-Json
    New-JawsFoundryAcrRbacPlan -State $State -RegistryName $RegistryName `
        -ProjectPrincipalId $principal -RegistryResourceId ([string]$acr.id) `
        -RegistryRoleAssignmentMode ([string]$acr.roleAssignmentMode) `
        -RegistryAdminEnabled ([bool]$acr.adminUserEnabled)
}

function Test-JawsFoundryAcrRbacPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$RbacPlan)
    $p=$RbacPlan.Plan
    if ($p.Action -ne 'AssignFoundryProjectAcrPullRole' -or
        $p.AssigneePrincipalType -ne 'ServicePrincipal' -or
        $p.RoleDefinitionName -notin @('AcrPull','Container Registry Repository Reader') -or
        $p.RegistryResourceId -cnotmatch '/providers/Microsoft\.ContainerRegistry/registries/[a-z0-9]{5,50}$' -or
        $p.ProjectResourceId -cnotmatch '/providers/Microsoft\.CognitiveServices/accounts/[a-zA-Z0-9._-]+/projects/[a-zA-Z0-9._-]+$') {
        throw 'JAWS-RBAC-SEC-001: Unsafe or altered role-assignment plan.'
    }
    $actual=Get-JawsFoundryAcrRbacPlanHash -Plan $p
    if ($actual -cne $RbacPlan.PlanSha256) {
        throw 'JAWS-RBAC-SEC-002: Role-assignment plan fingerprint mismatch.'
    }
}

function Test-JawsExactRoleAssignment {
    param([AllowNull()][object[]]$Assignments,[Parameter(Mandatory)][string]$PrincipalId,
          [Parameter(Mandatory)][string]$Scope,[Parameter(Mandatory)][string]$RoleName,
          [string]$RoleDefinitionId)
    foreach ($assignment in @($Assignments)) {
        if ($null -eq $assignment) { continue }
        $properties=$assignment.PSObject.Properties
        if (-not $properties['principalId'] -or -not $properties['scope']) { continue }
        if ([string]$assignment.principalId -ine $PrincipalId -or
            [string]$assignment.scope -ine $Scope) { continue }
        $nameMatches=($properties['roleDefinitionName'] -and
            [string]$assignment.roleDefinitionName -ceq $RoleName)
        $idMatches=($RoleDefinitionId -and $properties['roleDefinitionId'] -and
            [string]$assignment.roleDefinitionId -ieq $RoleDefinitionId)
        if ($nameMatches -or $idMatches) { return $true }
    }
    return $false
}

function Get-JawsApprovedAcrRoleDefinitionId {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RoleName,
          [Parameter(Mandatory)][string]$SubscriptionId,
          [Parameter(Mandatory)][string]$Scope)
    if ($RoleName -notin @('AcrPull','Container Registry Repository Reader')) {
        throw 'JAWS-RBAC-ASSIGN-008: Role is not in the approved allowlist.'
    }
    $json=& az role definition list --name $RoleName --scope $Scope --subscription $SubscriptionId --output json --only-show-errors 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw 'JAWS-RBAC-ASSIGN-009: Could not resolve approved role definition before any write.'
    }
    $roles=@($json | Out-String | ConvertFrom-Json | Where-Object { $null -ne $_ })
    if ($roles.Count -ne 1 -or -not $roles[0].PSObject.Properties['id']) {
        throw 'JAWS-RBAC-ASSIGN-009: Expected one authoritative role definition with an ID.'
    }
    $id=[string]$roles[0].id
    if ($id -notmatch '(?i)/providers/Microsoft.Authorization/roleDefinitions/[0-9a-f-]{36}

function Invoke-JawsFoundryAcrRbacAssignment {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$RbacPlan)
    Test-JawsFoundryAcrRbacPlan -RbacPlan $RbacPlan
    $p=$RbacPlan.Plan
    $projectJson=& az resource show --ids $p.ProjectResourceId --output json --only-show-errors 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'JAWS-RBAC-ASSIGN-001: Cannot revalidate Foundry project.' }
    $project=$projectJson | Out-String | ConvertFrom-Json
    if (-not $project.PSObject.Properties['identity'] -or -not $project.identity -or
        -not $project.identity.PSObject.Properties['principalId'] -or
        [string]$project.identity.principalId -ine [string]$p.ProjectPrincipalId) {
        throw 'JAWS-RBAC-ASSIGN-002: Foundry project identity changed after approval.'
    }
    $acrJson=& az acr show --subscription $p.SubscriptionId --resource-group $p.ResourceGroupName --name $p.RegistryName --output json --only-show-errors 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'JAWS-RBAC-ASSIGN-003: Cannot revalidate registry.' }
    $acr=$acrJson | Out-String | ConvertFrom-Json
    if ([string]$acr.id -ine [string]$p.RegistryResourceId -or $acr.adminUserEnabled -ne $false -or
        [string]$acr.roleAssignmentMode -cne [string]$p.RegistryRoleAssignmentMode) {
        throw 'JAWS-RBAC-ASSIGN-004: Registry changed after approval.'
    }
    $approvedRoleId=Get-JawsApprovedAcrRoleDefinitionId -RoleName $p.RoleDefinitionName `
        -SubscriptionId $p.SubscriptionId -Scope $p.RegistryResourceId
    $existingJson=& az role assignment list --assignee-object-id $p.ProjectPrincipalId --scope $p.RegistryResourceId `
        --include-inherited --fill-principal-name false --output json --only-show-errors 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'JAWS-RBAC-ASSIGN-005: Cannot inspect existing role assignments.' }
    $existing=@($existingJson | Out-String | ConvertFrom-Json)
    if (Test-JawsExactRoleAssignment -Assignments $existing -PrincipalId $p.ProjectPrincipalId -Scope $p.RegistryResourceId -RoleName $p.RoleDefinitionName -RoleDefinitionId $approvedRoleId) {
        return [pscustomobject]@{Status='ALREADY_ASSIGNED_AND_VERIFIED';RoleDefinitionName=$p.RoleDefinitionName;Scope=$p.RegistryResourceId;AzureWrites=0}
    }
    # The only Azure write in this module: exact principal, role and ACR scope from the approved plan.
    $createdJson=& az role assignment create --subscription $p.SubscriptionId `
        --assignee-object-id $p.ProjectPrincipalId --assignee-principal-type ServicePrincipal `
        --role $p.RoleDefinitionName --scope $p.RegistryResourceId --output json --only-show-errors 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'JAWS-RBAC-ASSIGN-006: Role assignment failed; inspect Azure before retry.' }
    $created=$createdJson | Out-String | ConvertFrom-Json
    if ($null -eq $created -or -not $created.PSObject.Properties['id']) {
        throw 'JAWS-RBAC-ASSIGN-007: Role assignment create response omitted its resource identity.'
    }
    # Azure CLI create responses can omit roleDefinitionName. Verify through an authoritative read-back,
    # allowing briefly for role-assignment propagation without issuing another write.
    $verified=$false
    for ($attempt=1; $attempt -le 3 -and -not $verified; $attempt++) {
        $verifyJson=& az role assignment list --assignee-object-id $p.ProjectPrincipalId --scope $p.RegistryResourceId `
            --include-inherited --fill-principal-name false --output json --only-show-errors 2>$null
        if ($LASTEXITCODE -eq 0) {
            $verify=@($verifyJson | Out-String | ConvertFrom-Json)
            $verified=Test-JawsExactRoleAssignment -Assignments $verify -PrincipalId $p.ProjectPrincipalId `
                -Scope $p.RegistryResourceId -RoleName $p.RoleDefinitionName -RoleDefinitionId $approvedRoleId
        }
        if (-not $verified -and $attempt -lt 3) { Start-Sleep -Seconds 2 }
    }
    if (-not $verified) {
        throw 'JAWS-RBAC-ASSIGN-007: Created role assignment does not match approved plan.'
    }
    [pscustomobject]@{Status='ASSIGNED_AND_VERIFIED';RoleDefinitionName=$p.RoleDefinitionName;Scope=$p.RegistryResourceId;AzureWrites=1}
}

Export-ModuleMember -Function New-JawsFoundryAcrRbacPlan,Get-JawsFoundryAcrRbacLivePlan,Test-JawsFoundryAcrRbacPlan,Invoke-JawsFoundryAcrRbacAssignment,Test-JawsExactRoleAssignment
) {
        throw 'JAWS-RBAC-ASSIGN-009: Role definition ID is malformed.'
    }
    return $id
}

function Invoke-JawsFoundryAcrRbacAssignment {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$RbacPlan)
    Test-JawsFoundryAcrRbacPlan -RbacPlan $RbacPlan
    $p=$RbacPlan.Plan
    $projectJson=& az resource show --ids $p.ProjectResourceId --output json --only-show-errors 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'JAWS-RBAC-ASSIGN-001: Cannot revalidate Foundry project.' }
    $project=$projectJson | Out-String | ConvertFrom-Json
    if (-not $project.PSObject.Properties['identity'] -or -not $project.identity -or
        -not $project.identity.PSObject.Properties['principalId'] -or
        [string]$project.identity.principalId -ine [string]$p.ProjectPrincipalId) {
        throw 'JAWS-RBAC-ASSIGN-002: Foundry project identity changed after approval.'
    }
    $acrJson=& az acr show --subscription $p.SubscriptionId --resource-group $p.ResourceGroupName --name $p.RegistryName --output json --only-show-errors 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'JAWS-RBAC-ASSIGN-003: Cannot revalidate registry.' }
    $acr=$acrJson | Out-String | ConvertFrom-Json
    if ([string]$acr.id -ine [string]$p.RegistryResourceId -or $acr.adminUserEnabled -ne $false -or
        [string]$acr.roleAssignmentMode -cne [string]$p.RegistryRoleAssignmentMode) {
        throw 'JAWS-RBAC-ASSIGN-004: Registry changed after approval.'
    }
    $existingJson=& az role assignment list --assignee-object-id $p.ProjectPrincipalId --scope $p.RegistryResourceId `
        --include-inherited --fill-principal-name false --output json --only-show-errors 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'JAWS-RBAC-ASSIGN-005: Cannot inspect existing role assignments.' }
    $existing=@($existingJson | Out-String | ConvertFrom-Json)
    if (Test-JawsExactRoleAssignment -Assignments $existing -PrincipalId $p.ProjectPrincipalId -Scope $p.RegistryResourceId -RoleName $p.RoleDefinitionName) {
        return [pscustomobject]@{Status='ALREADY_ASSIGNED_AND_VERIFIED';RoleDefinitionName=$p.RoleDefinitionName;Scope=$p.RegistryResourceId;AzureWrites=0}
    }
    # The only Azure write in this module: exact principal, role and ACR scope from the approved plan.
    $createdJson=& az role assignment create --subscription $p.SubscriptionId `
        --assignee-object-id $p.ProjectPrincipalId --assignee-principal-type ServicePrincipal `
        --role $p.RoleDefinitionName --scope $p.RegistryResourceId --output json --only-show-errors 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'JAWS-RBAC-ASSIGN-006: Role assignment failed; inspect Azure before retry.' }
    $created=$createdJson | Out-String | ConvertFrom-Json
    if ($null -eq $created -or -not $created.PSObject.Properties['id']) {
        throw 'JAWS-RBAC-ASSIGN-007: Role assignment create response omitted its resource identity.'
    }
    # Azure CLI create responses can omit roleDefinitionName. Verify through an authoritative read-back,
    # allowing briefly for role-assignment propagation without issuing another write.
    $verified=$false
    for ($attempt=1; $attempt -le 3 -and -not $verified; $attempt++) {
        $verifyJson=& az role assignment list --assignee-object-id $p.ProjectPrincipalId --scope $p.RegistryResourceId `
            --include-inherited --fill-principal-name false --output json --only-show-errors 2>$null
        if ($LASTEXITCODE -eq 0) {
            $verify=@($verifyJson | Out-String | ConvertFrom-Json)
            $verified=Test-JawsExactRoleAssignment -Assignments $verify -PrincipalId $p.ProjectPrincipalId `
                -Scope $p.RegistryResourceId -RoleName $p.RoleDefinitionName
        }
        if (-not $verified -and $attempt -lt 3) { Start-Sleep -Seconds 2 }
    }
    if (-not $verified) {
        throw 'JAWS-RBAC-ASSIGN-007: Created role assignment does not match approved plan.'
    }
    [pscustomobject]@{Status='ASSIGNED_AND_VERIFIED';RoleDefinitionName=$p.RoleDefinitionName;Scope=$p.RegistryResourceId;AzureWrites=1}
}

Export-ModuleMember -Function New-JawsFoundryAcrRbacPlan,Get-JawsFoundryAcrRbacLivePlan,Test-JawsFoundryAcrRbacPlan,Invoke-JawsFoundryAcrRbacAssignment
