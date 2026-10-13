# B2 Foundry hosted Supervisor deployment: explicit approval, fail-closed checks.
Set-StrictMode -Version Latest
function Resolve-JawsSupervisorPublishReceipt {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$ReceiptContent)
    $items=@($ReceiptContent)
    $structured=@($items | Where-Object {
        $_ -is [pscustomobject] -and
        $_.PSObject.Properties['Status'] -and
        $_.PSObject.Properties['Image'] -and
        $_.PSObject.Properties['RegistryManifestDigest'] -and
        $_.PSObject.Properties['RegistryPushPerformed'] -and
        $_.PSObject.Properties['FoundryDeploymentPerformed']
    })
    if ($structured.Count -ne 1) {
        throw 'JAWS-FOUNDRY-021: Publish receipt must contain exactly one structured result. No deployment plan created.'
    }
    $receipt=$structured[0]
    if ([string]$receipt.Status -cne 'PUBLISHED_AND_DIGEST_VERIFIED' -or
        $receipt.RegistryPushPerformed -ne $true -or
        $receipt.FoundryDeploymentPerformed -ne $false -or
        [string]$receipt.RegistryManifestDigest -cnotmatch '^sha256:[a-f0-9]{64}$') {
        throw 'JAWS-FOUNDRY-003: Immutable verified Supervisor image receipt required.'
    }
    $correct="jawsregistrydev001.azurecr.io/jaws/supervisor@$($receipt.RegistryManifestDigest)"
    $legacy="jawsregistrydev001/jaws/supervisor@$($receipt.RegistryManifestDigest)"
    if ([string]$receipt.Image -cne $correct -and [string]$receipt.Image -cne $legacy) {
        throw 'JAWS-FOUNDRY-003: Immutable verified Supervisor image receipt required.'
    }
    if ([string]$receipt.Image -ceq $legacy) {
        $receipt=$receipt.PSObject.Copy()
        $receipt.Image=$correct
    }
    return $receipt
}
function New-JawsFoundrySupervisorPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$State,[Parameter(Mandatory)]$PublishReceipt,
          [string]$AgentName='jaws-supervisor-dev')
    if ($State.Platform -ne 'JAWS' -or $State.EnvironmentName -ne 'dev' -or
        $AgentName -cnotmatch '^[a-z][a-z0-9-]{2,62}$') {
        throw 'JAWS-FOUNDRY-001: Unexpected state or agent name.'
    }
    $foundry=@($State.Resources | Where-Object Type -eq 'Microsoft.CognitiveServices/accounts')
    $project=@($State.Resources | Where-Object Type -eq 'Microsoft.CognitiveServices/accounts/projects')
    $model=@($State.Resources | Where-Object Type -eq 'Microsoft.CognitiveServices/accounts/deployments')
    if ($foundry.Count -ne 1 -or $project.Count -ne 1 -or $model.Count -ne 1) {
        throw 'JAWS-FOUNDRY-002: Exactly one Foundry, project and deployment required.'
    }
    $PublishReceipt=Resolve-JawsSupervisorPublishReceipt -ReceiptContent $PublishReceipt
    $resource=[string]$foundry[0].Name
    $projectName=[string]$project[0].Name
    if ($project[0].ExpectedConfiguration.ParentResource -ne $resource -or
        $model[0].ExpectedConfiguration.ParentResource -ne $resource) {
        throw 'JAWS-FOUNDRY-004: Foundry project/model relationships differ.'
    }
    $endpoint="https://$resource.services.ai.azure.com/api/projects/$projectName"
    $definition=[ordered]@{
        kind='hosted'
        container_configuration=[ordered]@{image=[string]$PublishReceipt.Image}
        cpu='1';memory='2Gi'
        protocol_versions=@([ordered]@{protocol='responses';version='2.0.0'})
        environment_variables=[ordered]@{FOUNDRY_PROJECT_ENDPOINT=$endpoint;AZURE_AI_MODEL_DEPLOYMENT_NAME=[string]$model[0].Name}
    }
    $request=[ordered]@{name=$AgentName;definition=$definition}
    $payload=[ordered]@{
        SchemaVersion='1.0';Operation='CreateHostedSupervisorVersion'
        SubscriptionId=[string]$State.SubscriptionId
        ResourceGroupName=[string]$State.ResourceGroupName
        ProjectEndpoint=$endpoint;FoundryResource=$resource;ProjectName=$projectName
        AgentName=$AgentName;RegistryName='jawsregistrydev001'
        Image=[string]$PublishReceipt.Image;ApiVersion='v1';Request=$request
    }
    $json=ConvertTo-Json -InputObject $payload -Depth 20 -Compress
    $hash=[System.Security.Cryptography.SHA256]::Create()
    try {$bytes=$hash.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($json))}
    finally {$hash.Dispose()}
    [pscustomobject]@{
        PlanSha256=([BitConverter]::ToString($bytes)).Replace('-','').ToLowerInvariant()
        Plan=$payload;CanDeploy=$false;AzureWrites=0
        Status='BLOCKED_PENDING_FOUNDRY_RBAC_IDENTITY_IMAGE_AND_COST_APPROVAL'
        Cost='Hosted compute/model inference can incur charges. Prices and quota unverified.'
    }
}
function Test-JawsFoundryDeploymentPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$DeploymentPlan)
    if ($DeploymentPlan.Plan.Operation -ne 'CreateHostedSupervisorVersion' -or
        $DeploymentPlan.Plan.ApiVersion -ne 'v1' -or
        $DeploymentPlan.Plan.Image -cnotmatch '^jawsregistrydev001\.azurecr\.io/jaws/supervisor@sha256:[a-f0-9]{64}$' -or
        $DeploymentPlan.Plan.Request.definition.container_configuration.image -cne $DeploymentPlan.Plan.Image -or
        $DeploymentPlan.Plan.Request.definition.kind -ne 'hosted' -or
        $DeploymentPlan.Plan.Request.definition.cpu -ne '1' -or
        $DeploymentPlan.Plan.Request.definition.memory -ne '2Gi') {
        throw 'JAWS-FOUNDRY-005: Unsafe or altered hosted agent plan.'
    }
    $json=ConvertTo-Json -InputObject $DeploymentPlan.Plan -Depth 20 -Compress
    $h=[System.Security.Cryptography.SHA256]::Create()
    try {$bytes=$h.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($json))}
    finally {$h.Dispose()}
    $actual=([BitConverter]::ToString($bytes)).Replace('-','').ToLowerInvariant()
    if ($actual -cne $DeploymentPlan.PlanSha256) {throw 'JAWS-FOUNDRY-006: Fingerprint differs from requested deployment.'}
}
function Test-JawsFoundryAcrPullRole {
    [CmdletBinding()]
    param([AllowNull()][object[]]$Assignments,
          [Parameter(Mandatory)][string]$PrincipalId,
          [Parameter(Mandatory)][string]$RegistryScope)
    foreach ($assignment in @($Assignments)) {
        if ($null -eq $assignment) { continue }
        $props=$assignment.PSObject.Properties
        if (-not $props['principalId'] -or -not $props['scope'] -or
            -not $props['roleDefinitionName']) { continue }
        if ([string]$assignment.principalId -ine $PrincipalId) { continue }
        $scope=[string]$assignment.scope
        $validScope=($RegistryScope -ieq $scope -or
            $RegistryScope.StartsWith(($scope.TrimEnd('/') + '/'),[System.StringComparison]::OrdinalIgnoreCase))
        if (-not $validScope) { continue }
        if ([string]$assignment.roleDefinitionName -in @('AcrPull','Container Registry Repository Reader')) {
            return $true
        }
    }
    return $false
}
function Invoke-JawsFoundrySupervisorDeployment {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$DeploymentPlan)
    Test-JawsFoundryDeploymentPlan -DeploymentPlan $DeploymentPlan
    $p=$DeploymentPlan.Plan
    $sub=[string]$p.SubscriptionId;$rg=[string]$p.ResourceGroupName
    $acct=[string]$p.FoundryResource;$project=[string]$p.ProjectName
    $acrId="/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.ContainerRegistry/registries/$($p.RegistryName)"
    $projectId="/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.CognitiveServices/accounts/$acct/projects/$project"
    $projectJson=& az resource show --ids $projectId --output json --only-show-errors 2>$null
    if ($LASTEXITCODE -ne 0) {throw 'JAWS-FOUNDRY-007: Cannot inspect existing Foundry project.'}
    $projectObj=$projectJson | Out-String | ConvertFrom-Json
    if ([string]$projectObj.id -ine $projectId) {throw 'JAWS-FOUNDRY-008: Project resource mismatch.'}
    $identity=$null
    if ($projectObj.PSObject.Properties['identity'] -and $projectObj.identity -and
        $projectObj.identity.PSObject.Properties['principalId']) {
        $identity=[string]$projectObj.identity.principalId
    }
    if ([string]::IsNullOrWhiteSpace($identity)) {
        throw 'JAWS-FOUNDRY-009: Project managed identity missing; cannot validate image pull permissions.'
    }
    $acrJson=& az acr show --name $p.RegistryName --resource-group $rg --subscription $sub --output json --only-show-errors 2>$null
    if ($LASTEXITCODE -ne 0) {throw 'JAWS-FOUNDRY-010: Registry unavailable.'}
    $acr=$acrJson | Out-String | ConvertFrom-Json
    if ([string]$acr.id -ine $acrId -or $acr.adminUserEnabled -ne $false) {
        throw 'JAWS-FOUNDRY-011: Registry mismatch or insecure admin configuration.'
    }
    $rolesJson=& az role assignment list --assignee-object-id $identity --scope $acrId `
        --include-inherited --fill-principal-name false --output json --only-show-errors 2>$null
    if ($LASTEXITCODE -ne 0) {throw 'JAWS-FOUNDRY-012: Cannot verify project image-pull RBAC.'}
    $roles=@($rolesJson | Out-String | ConvertFrom-Json)
    if (-not (Test-JawsFoundryAcrPullRole -Assignments $roles -PrincipalId $identity -RegistryScope $acrId)) {
        throw 'JAWS-FOUNDRY-013: No verified ACR pull role for project identity. Installer-managed RBAC setup required.'
    }
    # Inspect existing agent. An unavailable API (403/5xx) is not treated as absence.
    $url="$($p.ProjectEndpoint)/agents/$($p.AgentName)?api-version=v1"
    $exists=$null
    $existingOutput=& az rest --method get --url $url --resource https://ai.azure.com --output json --only-show-errors 2>&1
    if ($LASTEXITCODE -eq 0) {$exists=$existingOutput}
    else {
        $errorText=($existingOutput | Out-String)
        if ($errorText -notmatch '(?i)(404|not.?found)') {
            throw 'JAWS-FOUNDRY-014: Could not prove agent name is unused; stop without provisioning.'
        }
    }
    if ($exists) {throw 'JAWS-FOUNDRY-015: Agent already exists; no overwrite or new version without separate approval.'}
    $body=ConvertTo-Json -InputObject $p.Request -Depth 20 -Compress
    # Only approved Azure write. Using documented Foundry v1 REST agent creation.
    $creation=& az rest --method post --url "$($p.ProjectEndpoint)/agents?api-version=v1" --resource https://ai.azure.com --headers 'Content-Type=application/json' --body $body --output json --only-show-errors 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw 'JAWS-FOUNDRY-016: Agent creation failed; inspect for partial deployment before retry.'
    }
    $agent=$creation | Out-String | ConvertFrom-Json
    if ([string]$agent.name -cne [string]$p.AgentName) {throw 'JAWS-FOUNDRY-017: Created agent identity mismatch.'}
    # Foundry POST may return an agent summary with versions.latest rather than
    # the agent.version representation returned by GET. Handle both.
    $version=$null
    if ($agent.PSObject.Properties['version'] -and [string]$agent.version -match '^[0-9]+
    [pscustomobject]@{
        Status='PROVISIONING_STARTED';AgentName=[string]$p.AgentName;Version=$version
        Image=[string]$p.Image;ProjectEndpoint=[string]$p.ProjectEndpoint
        AgentVersionUri="$($p.ProjectEndpoint)/agents/$($p.AgentName)/versions/$version"
        PlanSha256=[string]$DeploymentPlan.PlanSha256;FoundryDeploymentPerformed=$true
        AzureWrites=1;ActiveVerified=$false;InvocationVerified=$false
    }
}
Export-ModuleMember -Function Resolve-JawsSupervisorPublishReceipt,New-JawsFoundrySupervisorPlan,Test-JawsFoundryDeploymentPlan,Invoke-JawsFoundrySupervisorDeployment,Test-JawsFoundryAcrPullRole
) {
        $version=[string]$agent.version
    } elseif ($agent.PSObject.Properties['versions'] -and $null -ne $agent.versions -and
              $agent.versions.PSObject.Properties['latest'] -and $null -ne $agent.versions.latest) {
        $latest=$agent.versions.latest
        if ([string]$latest -match '^[0-9]+
    [pscustomobject]@{
        Status='PROVISIONING_STARTED';AgentName=[string]$p.AgentName;Version=$version
        Image=[string]$p.Image;ProjectEndpoint=[string]$p.ProjectEndpoint
        AgentVersionUri="$($p.ProjectEndpoint)/agents/$($p.AgentName)/versions/$version"
        PlanSha256=[string]$DeploymentPlan.PlanSha256;FoundryDeploymentPerformed=$true
        AzureWrites=1;ActiveVerified=$false;InvocationVerified=$false
    }
}
Export-ModuleMember -Function Resolve-JawsSupervisorPublishReceipt,New-JawsFoundrySupervisorPlan,Test-JawsFoundryDeploymentPlan,Invoke-JawsFoundrySupervisorDeployment,Test-JawsFoundryAcrPullRole
) {
            $version=[string]$latest
        } elseif ($latest.PSObject.Properties['version'] -and [string]$latest.version -match '^[0-9]+
    [pscustomobject]@{
        Status='PROVISIONING_STARTED';AgentName=[string]$p.AgentName;Version=$version
        Image=[string]$p.Image;ProjectEndpoint=[string]$p.ProjectEndpoint
        AgentVersionUri="$($p.ProjectEndpoint)/agents/$($p.AgentName)/versions/$version"
        PlanSha256=[string]$DeploymentPlan.PlanSha256;FoundryDeploymentPerformed=$true
        AzureWrites=1;ActiveVerified=$false;InvocationVerified=$false
    }
}
Export-ModuleMember -Function Resolve-JawsSupervisorPublishReceipt,New-JawsFoundrySupervisorPlan,Test-JawsFoundryDeploymentPlan,Invoke-JawsFoundrySupervisorDeployment,Test-JawsFoundryAcrPullRole
) {
            $version=[string]$latest.version
        }
    }
    if ([string]$version -notmatch '^[0-9]+
    [pscustomobject]@{
        Status='PROVISIONING_STARTED';AgentName=[string]$p.AgentName;Version=$version
        Image=[string]$p.Image;ProjectEndpoint=[string]$p.ProjectEndpoint
        AgentVersionUri="$($p.ProjectEndpoint)/agents/$($p.AgentName)/versions/$version"
        PlanSha256=[string]$DeploymentPlan.PlanSha256;FoundryDeploymentPerformed=$true
        AzureWrites=1;ActiveVerified=$false;InvocationVerified=$false
    }
}
Export-ModuleMember -Function Resolve-JawsSupervisorPublishReceipt,New-JawsFoundrySupervisorPlan,Test-JawsFoundryDeploymentPlan,Invoke-JawsFoundrySupervisorDeployment,Test-JawsFoundryAcrPullRole
) {
        throw 'JAWS-FOUNDRY-018: Creation returned without recognized agent version; inspect existing Azure agent. Do not retry POST.'
    }
    [pscustomobject]@{
        Status='PROVISIONING_STARTED';AgentName=[string]$p.AgentName;Version=$version
        Image=[string]$p.Image;ProjectEndpoint=[string]$p.ProjectEndpoint
        AgentVersionUri="$($p.ProjectEndpoint)/agents/$($p.AgentName)/versions/$version"
        PlanSha256=[string]$DeploymentPlan.PlanSha256;FoundryDeploymentPerformed=$true
        AzureWrites=1;ActiveVerified=$false;InvocationVerified=$false
    }
}
Export-ModuleMember -Function Resolve-JawsSupervisorPublishReceipt,New-JawsFoundrySupervisorPlan,Test-JawsFoundryDeploymentPlan,Invoke-JawsFoundrySupervisorDeployment,Test-JawsFoundryAcrPullRole
