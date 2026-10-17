# Step C Foundry hosted Investigation deployment: explicit approval, fail-closed checks.
Set-StrictMode -Version Latest
function Resolve-JawsInvestigationPublishReceipt {
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
        throw 'JAWS-INV-FOUNDRY-021: Publish receipt must contain exactly one structured result. No deployment plan created.'
    }
    $receipt=$structured[0]
    if ([string]$receipt.Status -cne 'PUBLISHED_AND_DIGEST_VERIFIED' -or
        $receipt.RegistryPushPerformed -ne $true -or
        $receipt.FoundryDeploymentPerformed -ne $false -or
        [string]$receipt.RegistryManifestDigest -cnotmatch '^sha256:[a-f0-9]{64}$') {
        throw 'JAWS-INV-FOUNDRY-003: Immutable verified Investigation image receipt required.'
    }
    $correct="jawsregistrydev001.azurecr.io/jaws/investigation@$($receipt.RegistryManifestDigest)"
    $legacy="jawsregistrydev001/jaws/investigation@$($receipt.RegistryManifestDigest)"
    if ([string]$receipt.Image -cne $correct -and [string]$receipt.Image -cne $legacy) {
        throw 'JAWS-INV-FOUNDRY-003: Immutable verified Investigation image receipt required.'
    }
    if ([string]$receipt.Image -ceq $legacy) {
        $receipt=$receipt.PSObject.Copy()
        $receipt.Image=$correct
    }
    return $receipt
}
function New-JawsFoundryInvestigationPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$State,[Parameter(Mandatory)]$PublishReceipt,
          [string]$AgentName='jaws-investigation-dev')
    if ($State.Platform -ne 'JAWS' -or $State.EnvironmentName -ne 'dev' -or
        $AgentName -cne 'jaws-investigation-dev') {
        throw 'JAWS-INV-FOUNDRY-001: Unexpected state or agent name.'
    }
    $foundry=@($State.Resources | Where-Object Type -eq 'Microsoft.CognitiveServices/accounts')
    $project=@($State.Resources | Where-Object Type -eq 'Microsoft.CognitiveServices/accounts/projects')
    $model=@($State.Resources | Where-Object Type -eq 'Microsoft.CognitiveServices/accounts/deployments')
    if ($foundry.Count -ne 1 -or $project.Count -ne 1 -or $model.Count -ne 1) {
        throw 'JAWS-INV-FOUNDRY-002: Exactly one Foundry, project and deployment required.'
    }
    $PublishReceipt=Resolve-JawsInvestigationPublishReceipt -ReceiptContent $PublishReceipt
    $resource=[string]$foundry[0].Name
    $projectName=[string]$project[0].Name
    if ($project[0].ExpectedConfiguration.ParentResource -ne $resource -or
        $model[0].ExpectedConfiguration.ParentResource -ne $resource) {
        throw 'JAWS-INV-FOUNDRY-004: Foundry project/model relationships differ.'
    }
    $endpoint="https://$resource.services.ai.azure.com/api/projects/$projectName"
    $definition=[ordered]@{
        kind='hosted'
        container_configuration=[ordered]@{image=[string]$PublishReceipt.Image}
        cpu='1';memory='2Gi'
        protocol_versions=@([ordered]@{protocol='responses';version='2.0.0'})
        # Foundry injects FOUNDRY_PROJECT_ENDPOINT at runtime. FOUNDRY_* and AGENT_* are reserved.
        environment_variables=[ordered]@{AZURE_AI_MODEL_DEPLOYMENT_NAME=[string]$model[0].Name}
    }
    $request=[ordered]@{name=$AgentName;definition=$definition}
    $payload=[ordered]@{
        SchemaVersion='1.0';Operation='CreateHostedInvestigationVersion'
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
    $environmentNames=@($DeploymentPlan.Plan.Request.definition.environment_variables.Keys)
    $reservedEnvironmentNames=@($environmentNames | Where-Object { $_ -match '^(FOUNDRY_|AGENT_)' })
    if ($DeploymentPlan.Plan.AgentName -cne 'jaws-investigation-dev' -or
        $DeploymentPlan.Plan.Request.name -cne 'jaws-investigation-dev' -or
        $DeploymentPlan.Plan.Operation -ne 'CreateHostedInvestigationVersion' -or
        $DeploymentPlan.Plan.ApiVersion -ne 'v1' -or
        $DeploymentPlan.Plan.Image -cnotmatch '^jawsregistrydev001\.azurecr\.io/jaws/investigation@sha256:[a-f0-9]{64}$' -or
        $DeploymentPlan.Plan.Request.definition.container_configuration.image -cne $DeploymentPlan.Plan.Image -or
        $DeploymentPlan.Plan.Request.definition.kind -ne 'hosted' -or
        $DeploymentPlan.Plan.Request.definition.cpu -ne '1' -or
        $DeploymentPlan.Plan.Request.definition.memory -ne '2Gi' -or
        $reservedEnvironmentNames.Count -ne 0) {
        throw 'JAWS-INV-FOUNDRY-005: Unsafe or altered hosted agent plan.'
    }
    $json=ConvertTo-Json -InputObject $DeploymentPlan.Plan -Depth 20 -Compress
    $h=[System.Security.Cryptography.SHA256]::Create()
    try {$bytes=$h.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($json))}
    finally {$h.Dispose()}
    $actual=([BitConverter]::ToString($bytes)).Replace('-','').ToLowerInvariant()
    if ($actual -cne $DeploymentPlan.PlanSha256) {throw 'JAWS-INV-FOUNDRY-006: Fingerprint differs from requested deployment.'}
}
function Test-JawsFoundryAcrPullRole {
    [CmdletBinding()]
    param([AllowNull()][object[]]$Assignments,
          [Parameter(Mandatory)][string]$PrincipalId,
          [Parameter(Mandatory)][string]$RegistryScope)
    $flattened=@($Assignments | ForEach-Object { $_ })
    foreach ($assignment in $flattened) {
        if ($null -eq $assignment) { continue }
        $propertyNames=@($assignment.PSObject.Properties.Name)
        if ($propertyNames -notcontains 'principalId' -or $propertyNames -notcontains 'scope' -or
            $propertyNames -notcontains 'roleDefinitionName') { continue }
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
function Invoke-JawsFoundryInvestigationDeployment {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$DeploymentPlan)
    Test-JawsFoundryDeploymentPlan -DeploymentPlan $DeploymentPlan
    $p=$DeploymentPlan.Plan
    $sub=[string]$p.SubscriptionId;$rg=[string]$p.ResourceGroupName
    $acct=[string]$p.FoundryResource;$project=[string]$p.ProjectName
    $acrId="/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.ContainerRegistry/registries/$($p.RegistryName)"
    $projectId="/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.CognitiveServices/accounts/$acct/projects/$project"
    $projectJson=& az resource show --ids $projectId --output json --only-show-errors 2>$null
    if ($LASTEXITCODE -ne 0) {throw 'JAWS-INV-FOUNDRY-007: Cannot inspect existing Foundry project.'}
    $projectObj=$projectJson | Out-String | ConvertFrom-Json
    if ([string]$projectObj.id -ine $projectId) {throw 'JAWS-INV-FOUNDRY-008: Project resource mismatch.'}
    $identity=$null
    if ($projectObj.PSObject.Properties['identity'] -and $projectObj.identity -and
        $projectObj.identity.PSObject.Properties['principalId']) {
        $identity=[string]$projectObj.identity.principalId
    }
    if ([string]::IsNullOrWhiteSpace($identity)) {
        throw 'JAWS-INV-FOUNDRY-009: Project managed identity missing; cannot validate image pull permissions.'
    }
    $acrJson=& az acr show --name $p.RegistryName --resource-group $rg --subscription $sub --output json --only-show-errors 2>$null
    if ($LASTEXITCODE -ne 0) {throw 'JAWS-INV-FOUNDRY-010: Registry unavailable.'}
    $acr=$acrJson | Out-String | ConvertFrom-Json
    if ([string]$acr.id -ine $acrId -or $acr.adminUserEnabled -ne $false) {
        throw 'JAWS-INV-FOUNDRY-011: Registry mismatch or insecure admin configuration.'
    }
    $rolesJson=& az role assignment list --assignee-object-id $identity --scope $acrId `
        --include-inherited --fill-principal-name false --output json --only-show-errors 2>$null
    if ($LASTEXITCODE -ne 0) {throw 'JAWS-INV-FOUNDRY-012: Cannot verify project image-pull RBAC.'}
    $roles=@($rolesJson | Out-String | ConvertFrom-Json)
    if (-not (Test-JawsFoundryAcrPullRole -Assignments $roles -PrincipalId $identity -RegistryScope $acrId)) {
        throw 'JAWS-INV-FOUNDRY-013: No verified ACR pull role for project identity. Installer-managed RBAC setup required.'
    }
    # Inspect existing agent. An unavailable API (403/5xx) is not treated as absence.
    $url="$($p.ProjectEndpoint)/agents/$($p.AgentName)?api-version=v1"
    $exists=$null
    $existingOutput=& az rest --method get --url $url --resource https://ai.azure.com --output json --only-show-errors 2>&1
    if ($LASTEXITCODE -eq 0) {$exists=$existingOutput}
    else {
        $errorText=($existingOutput | Out-String)
        if ($errorText -notmatch '(?i)(404|not.?found)') {
            throw 'JAWS-INV-FOUNDRY-014: Could not prove agent name is unused; stop without provisioning.'
        }
    }
    if ($exists) {throw 'JAWS-INV-FOUNDRY-015: Agent already exists; no overwrite or new version without separate approval.'}
    $body=ConvertTo-Json -InputObject $p.Request -Depth 20 -Compress
    $bodyFile=[System.IO.Path]::GetTempFileName()
    try {
        $utf8NoBom=New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($bodyFile,$body,$utf8NoBom)
        # Only approved Azure write. File input preserves JSON quoting in Windows PowerShell 5.1.
        $creationOutput=& az rest --method post --url "$($p.ProjectEndpoint)/agents?api-version=v1" --resource https://ai.azure.com --headers 'Content-Type=application/json' --body "@$bodyFile" --output json --only-show-errors 2>&1
        $creationExitCode=$LASTEXITCODE
    }
    finally {
        Remove-Item -LiteralPath $bodyFile -Force -ErrorAction SilentlyContinue
    }
    if ($creationExitCode -ne 0) {
        $azureError=($creationOutput | Out-String).Trim()
        throw "JAWS-INV-FOUNDRY-016: Agent creation failed; inspect for partial deployment before retry. Azure response: $azureError"
    }
    $creation=$creationOutput
    $agent=$creation | Out-String | ConvertFrom-Json
    if ([string]$agent.name -cne [string]$p.AgentName) {throw 'JAWS-INV-FOUNDRY-017: Created agent identity mismatch.'}
    # Prefer the version from the creation response. A summary may provide
    # versions.latest instead of the top-level agent.version returned by GET.
    $version=$null
    if ($agent.PSObject.Properties['version']) {
        $candidate=[string]$agent.version
        if ($candidate -match '^[0-9]+$') { $version=$candidate }
    }
    if (-not $version -and $agent.PSObject.Properties['versions'] -and $null -ne $agent.versions) {
        $nested=$agent.versions.PSObject.Properties['latest']
        if ($null -ne $nested -and $null -ne $nested.Value) {
            $latest=$nested.Value
            if ([string]$latest -match '^[0-9]+$') {
                $version=[string]$latest
            } elseif ($latest.PSObject.Properties['version'] -and
                [string]$latest.version -match '^[0-9]+$') {
                $version=[string]$latest.version
            }
        }
    }
    if (-not $version) {
        throw 'JAWS-INV-FOUNDRY-018: Creation response omitted a recognizable version. Inspect existing Azure agent; do not retry POST.'
    }
    [pscustomobject]@{
        Status='PROVISIONING_STARTED';AgentName=[string]$p.AgentName;Version=$version
        Image=[string]$p.Image;ProjectEndpoint=[string]$p.ProjectEndpoint
        AgentVersionUri="$($p.ProjectEndpoint)/agents/$($p.AgentName)/versions/$version"
        PlanSha256=[string]$DeploymentPlan.PlanSha256;FoundryDeploymentPerformed=$true
        AzureWrites=1;ActiveVerified=$false;InvocationVerified=$false
    }
}
Export-ModuleMember -Function Resolve-JawsInvestigationPublishReceipt,New-JawsFoundryInvestigationPlan,Test-JawsFoundryDeploymentPlan,Invoke-JawsFoundryInvestigationDeployment,Test-JawsFoundryAcrPullRole
