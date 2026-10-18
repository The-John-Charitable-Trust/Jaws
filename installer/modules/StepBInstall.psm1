# Step B foundation install. Writes only after an exact plan digest and -AcknowledgeStepBInstall.
# Refuses the accepted dev project names. Does not call the Step C repair scripts.
Set-StrictMode -Version Latest

function ConvertFrom-JawsStepBJson {
    [CmdletBinding()]
    param([AllowNull()][string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $objectAt = $Text.IndexOf('{')
    $arrayAt = $Text.IndexOf('[')
    $start = $objectAt
    if ($start -lt 0 -or ($arrayAt -ge 0 -and $arrayAt -lt $start)) { $start = $arrayAt }
    if ($start -lt 0) { return $null }
    return ($Text.Substring($start) | ConvertFrom-Json)
}

function Get-JawsStepBSha256 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Text)
    $hash = [System.Security.Cryptography.SHA256]::Create()
    try { $bytes = $hash.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text)) }
    finally { $hash.Dispose() }
    return ([System.BitConverter]::ToString($bytes)).Replace('-','').ToLowerInvariant()
}

function New-JawsStepBResourceNames {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$EnvironmentName,[Parameter(Mandatory)][string]$ModelName)
    if ($EnvironmentName -notmatch '^[a-z][a-z0-9-]{1,20}$') {
        throw 'JAWS-STEP-B-014: Environment name must be 2-21 characters, start with a letter, and use lowercase letters, digits, and hyphens.'
    }
    $compact = ($EnvironmentName -replace '[^a-z0-9]', '')
    if ($compact.Length -lt 2) { throw 'JAWS-STEP-B-014: Environment name needs at least two letters or digits.' }
    $vault = ('kvjaws' + $compact)
    if ($vault.Length -gt 24) { $vault = $vault.Substring(0, 24) }
    $registry = ('jawsacr' + $compact)
    if ($registry.Length -gt 50) { $registry = $registry.Substring(0, 50) }
    [pscustomobject]@{
        FoundryAccountName = "jaws-foundry-$EnvironmentName"
        ProjectName = "jaws-$EnvironmentName"
        ModelDeploymentName = $ModelName
        KeyVaultName = $vault
        RegistryName = $registry
        AgentName = "jaws-supervisor-$EnvironmentName"
    }
}

function New-JawsStepBInstallScope {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SubscriptionId,
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$Location,
        [Parameter(Mandatory)][string]$EnvironmentName,
        [Parameter(Mandatory)][string]$ModelName,
        [Parameter(Mandatory)][string]$ModelVersion
    )
    $parsed = [guid]::Empty
    if (-not [guid]::TryParse($SubscriptionId, [ref]$parsed) -or $parsed -eq [guid]::Empty) {
        throw 'JAWS-STEP-B-014: A real subscription id is required.'
    }
    if ($ResourceGroupName -notmatch '^[a-zA-Z0-9_.()\\-]{1,90}$' -or $Location -notmatch '^[a-z0-9]{1,32}$') {
        throw 'JAWS-STEP-B-014: Resource group or location is invalid.'
    }
    if ($ModelName -notmatch '^[A-Za-z0-9._-]{1,64}$' -or $ModelVersion -notmatch '^[A-Za-z0-9._-]{1,32}$') {
        throw 'JAWS-STEP-B-014: Model name or version is invalid.'
    }
    if ($EnvironmentName -eq 'dev' -or $ResourceGroupName -eq 'rg-aiops-lab') {
        throw 'JAWS-STEP-B-013: Step B install refuses the accepted dev environment and rg-aiops-lab.'
    }
    $names = New-JawsStepBResourceNames -EnvironmentName $EnvironmentName -ModelName $ModelName
    foreach ($reserved in @('jaws-foundry-dev','jaws-dev','jawsregistrydev001','jaws-supervisor-dev','kv-jaws-dev-001')) {
        if ($names.FoundryAccountName -eq $reserved -or $names.ProjectName -eq $reserved -or
            $names.RegistryName -eq $reserved -or $names.AgentName -eq $reserved -or $names.KeyVaultName -eq $reserved) {
            throw "JAWS-STEP-B-017: Refusing reserved dev resource name $reserved."
        }
    }
    $scope = [pscustomobject]@{
        SubscriptionId = $parsed.ToString().ToLowerInvariant()
        ResourceGroupName = $ResourceGroupName
        Location = $Location.ToLowerInvariant()
        EnvironmentName = $EnvironmentName
        FoundryAccountName = [string]$names.FoundryAccountName
        ProjectName = [string]$names.ProjectName
        ModelDeploymentName = [string]$names.ModelDeploymentName
        ModelName = $ModelName
        ModelVersion = $ModelVersion
        KeyVaultName = [string]$names.KeyVaultName
        RegistryName = [string]$names.RegistryName
        AgentName = [string]$names.AgentName
    }
    $scope | Add-Member -NotePropertyName PlanSha256 -NotePropertyValue (Get-JawsStepBScopeSha256 -Scope $scope)
    return $scope
}

function Get-JawsStepBScopeSha256 {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Scope)
    $canonical = @(
        'JAWS-STEP-B-SCOPE-1',
        [string]$Scope.SubscriptionId.ToLowerInvariant(),
        [string]$Scope.ResourceGroupName,
        [string]$Scope.Location.ToLowerInvariant(),
        [string]$Scope.EnvironmentName,
        [string]$Scope.FoundryAccountName,
        [string]$Scope.ProjectName,
        [string]$Scope.ModelDeploymentName,
        [string]$Scope.ModelName,
        [string]$Scope.ModelVersion,
        [string]$Scope.KeyVaultName,
        [string]$Scope.RegistryName,
        [string]$Scope.AgentName
    ) -join "`n"
    return (Get-JawsStepBSha256 -Text $canonical)
}

function Invoke-JawsStepBAz {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Arguments,[switch]$AllowMissing)
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        throw 'JAWS-PREREQ-001: Azure CLI is not installed or not on PATH.'
    }
    $output = & az @Arguments 2>&1
    $code = $LASTEXITCODE
    $text = (@($output) | ForEach-Object { "$_" }) -join "`n"
    if ($code -ne 0) {
        if ($AllowMissing -and $text -match 'MISSING|ResourceNotFound|ResourceGroupNotFound|ParentResourceNotFound|was not found|NotFound') {
            return $null
        }
        if ($text -match 'MissingSubscriptionRegistration|not registered') {
            throw "JAWS-STEP-B-PROVIDER-001: Required resource provider is not registered. $text"
        }
        if ($text -match 'InsufficientQuota|quota') {
            throw "JAWS-STEP-B-MODEL-001: Model quota blocked the deployment. $text"
        }
        throw "JAWS-STEP-B-AZ-001: az $($Arguments -join ' ') failed ($code). $text"
    }
    return (ConvertFrom-JawsStepBJson -Text $text)
}

function Test-JawsStepBOwned {
    param($Resource,[Parameter(Mandatory)][string]$EnvironmentName)
    if ($null -eq $Resource) { return $false }
    $tags = $null
    if ($Resource.PSObject.Properties['tags']) { $tags = $Resource.tags }
    if ($null -eq $tags) { return $false }
    return ([string]$tags.application -eq 'JAWS' -and [string]$tags.managedBy -eq 'JAWS-Installer' -and [string]$tags.environment -eq $EnvironmentName)
}

function Get-JawsStepBProperty {
    param($Object,[Parameter(Mandatory)][string[]]$Names)
    $current = $Object
    foreach ($name in $Names) {
        if ($null -eq $current -or -not $current.PSObject.Properties[$name]) { return $null }
        $current = $current.$name
    }
    return $current
}

function Invoke-JawsStepBInstall {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Scope,
        [Parameter(Mandatory)][string]$ApprovedPlanSha256,
        [Parameter(Mandatory)][string]$InstallerRoot,
        [switch]$AcknowledgeStepBInstall
    )
    if (-not $AcknowledgeStepBInstall) {
        throw 'JAWS-STEP-B-010: Step B install requires -AcknowledgeStepBInstall. No Azure writes were attempted.'
    }
    $recomputed = Get-JawsStepBScopeSha256 -Scope $Scope
    if ($ApprovedPlanSha256 -cnotmatch '^[a-f0-9]{64}$' -or $ApprovedPlanSha256 -cne $recomputed -or $ApprovedPlanSha256 -cne [string]$Scope.PlanSha256) {
        throw 'JAWS-STEP-B-011: Approved plan digest does not match this scope. No Azure writes were attempted.'
    }
    $devState = Join-Path $InstallerRoot 'config/jaws-installation-state.dev.json'
    $devBefore = Get-Content -LiteralPath $devState -Raw
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw 'JAWS-PACKAGE-005: Docker is required before Step B install creates resources.' }
    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) { throw 'JAWS-PACKAGE-003: .NET SDK not found. Install .NET 10 before Step B install.' }
    $account = Invoke-JawsStepBAz -Arguments @('account','show','--output','json','--only-show-errors')
    if ([string]$account.id -ine [string]$Scope.SubscriptionId) {
        throw 'JAWS-STEP-B-019: Azure CLI subscription differs from the approved plan. Run az account set. No resources were created.'
    }
    $writes = 0
    $sub = [string]$Scope.SubscriptionId
    $rg = [string]$Scope.ResourceGroupName
    $tags = @('application=JAWS','managedBy=JAWS-Installer',"environment=$($Scope.EnvironmentName)")
    $group = Invoke-JawsStepBAz -AllowMissing -Arguments @('group','show','--subscription',$sub,'--name',$rg,'--output','json','--only-show-errors')
    if ($null -eq $group) {
        $group = Invoke-JawsStepBAz -Arguments (@('group','create','--subscription',$sub,'--name',$rg,'--location',[string]$Scope.Location,'--output','json','--only-show-errors','--tags') + $tags)
        $writes++
    } elseif ([string]$group.location -ine [string]$Scope.Location) {
        throw 'JAWS-STEP-B-012: Resource group exists in a different location. Nothing was changed.'
    }
    $foundry = Invoke-JawsStepBAz -AllowMissing -Arguments @('cognitiveservices','account','show','--subscription',$sub,'--resource-group',$rg,'--name',[string]$Scope.FoundryAccountName,'--output','json','--only-show-errors')
    if ($null -eq $foundry) {
        $foundry = Invoke-JawsStepBAz -Arguments (@('cognitiveservices','account','create','--subscription',$sub,'--resource-group',$rg,'--name',[string]$Scope.FoundryAccountName,'--kind','AIServices','--sku','S0','--location',[string]$Scope.Location,'--custom-domain',[string]$Scope.FoundryAccountName,'--assign-identity','--allow-project-management','--yes','--output','json','--only-show-errors','--tags') + $tags)
        $writes++
    } elseif (-not (Test-JawsStepBOwned -Resource $foundry -EnvironmentName $Scope.EnvironmentName)) {
        throw 'JAWS-STEP-B-012: Foundry account exists and is not owned by this installer. Refusing adoption.'
    }
    $project = Invoke-JawsStepBAz -AllowMissing -Arguments @('cognitiveservices','account','project','show','--subscription',$sub,'--resource-group',$rg,'--name',[string]$Scope.FoundryAccountName,'--project-name',[string]$Scope.ProjectName,'--output','json','--only-show-errors')
    if ($null -eq $project) {
        $project = Invoke-JawsStepBAz -Arguments @('cognitiveservices','account','project','create','--subscription',$sub,'--resource-group',$rg,'--name',[string]$Scope.FoundryAccountName,'--project-name',[string]$Scope.ProjectName,'--location',[string]$Scope.Location,'--assign-identity','--output','json','--only-show-errors')
        $writes++
    }
    $principal = [string](Get-JawsStepBProperty -Object $project -Names @('identity','principalId'))
    if ([string]::IsNullOrWhiteSpace($principal)) { throw 'JAWS-STEP-B-020: Foundry project has no managed identity principal.' }
    $deployment = Invoke-JawsStepBAz -AllowMissing -Arguments @('cognitiveservices','account','deployment','show','--subscription',$sub,'--resource-group',$rg,'--name',[string]$Scope.FoundryAccountName,'--deployment-name',[string]$Scope.ModelDeploymentName,'--output','json','--only-show-errors')
    if ($null -eq $deployment) {
        $deployment = Invoke-JawsStepBAz -Arguments @('cognitiveservices','account','deployment','create','--subscription',$sub,'--resource-group',$rg,'--name',[string]$Scope.FoundryAccountName,'--deployment-name',[string]$Scope.ModelDeploymentName,'--model-name',[string]$Scope.ModelName,'--model-version',[string]$Scope.ModelVersion,'--model-format','OpenAI','--sku-name','GlobalStandard','--sku-capacity','1','--output','json','--only-show-errors')
        $writes++
    }
    $vault = Invoke-JawsStepBAz -AllowMissing -Arguments @('keyvault','show','--subscription',$sub,'--resource-group',$rg,'--name',[string]$Scope.KeyVaultName,'--output','json','--only-show-errors')
    if ($null -eq $vault) {
        $vault = Invoke-JawsStepBAz -Arguments (@('keyvault','create','--subscription',$sub,'--resource-group',$rg,'--name',[string]$Scope.KeyVaultName,'--location',[string]$Scope.Location,'--enable-rbac-authorization','true','--enable-purge-protection','true','--output','json','--only-show-errors','--tags') + $tags)
        $writes++
    } elseif (-not (Test-JawsStepBOwned -Resource $vault -EnvironmentName $Scope.EnvironmentName)) {
        throw 'JAWS-STEP-B-012: Key Vault exists and is not owned by this installer. Refusing adoption.'
    }
    $registry = Invoke-JawsStepBAz -AllowMissing -Arguments @('acr','show','--subscription',$sub,'--resource-group',$rg,'--name',[string]$Scope.RegistryName,'--output','json','--only-show-errors')
    if ($null -eq $registry) {
        $registry = Invoke-JawsStepBAz -Arguments (@('acr','create','--subscription',$sub,'--resource-group',$rg,'--name',[string]$Scope.RegistryName,'--location',[string]$Scope.Location,'--sku','Basic','--admin-enabled','false','--public-network-enabled','true','--role-assignment-mode','rbac','--output','json','--only-show-errors','--tags') + $tags)
        $writes++
    } elseif (-not (Test-JawsStepBOwned -Resource $registry -EnvironmentName $Scope.EnvironmentName) -or $registry.adminUserEnabled -ne $false) {
        throw 'JAWS-STEP-B-012: Registry exists and is not an installer-owned Basic registry with admin disabled.'
    }
    $registryId = "/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.ContainerRegistry/registries/$($Scope.RegistryName)"
    $roles = @(Invoke-JawsStepBAz -Arguments @('role','assignment','list','--subscription',$sub,'--assignee-object-id',$principal,'--scope',$registryId,'--include-inherited','--fill-principal-name','false','--output','json','--only-show-errors'))
    $hasPull = @($roles | Where-Object { $_ -and [string]$_.roleDefinitionName -in @('AcrPull','Container Registry Repository Reader') }).Count -gt 0
    if (-not $hasPull) {
        $null = Invoke-JawsStepBAz -Arguments @('role','assignment','create','--subscription',$sub,'--assignee-object-id',$principal,'--assignee-principal-type','ServicePrincipal','--role','AcrPull','--scope',$registryId,'--output','json','--only-show-errors')
        $writes++
    }
    $login = "$($Scope.RegistryName).azurecr.io"
    $endpoint = "https://$($Scope.FoundryAccountName).services.ai.azure.com/api/projects/$($Scope.ProjectName)"
    $versionUrl = "$endpoint/agents/$($Scope.AgentName)/versions/1?api-version=v1"
    $existing = Invoke-JawsStepBAz -AllowMissing -Arguments @('rest','--method','GET','--url',$versionUrl,'--resource','https://ai.azure.com','--output','json','--only-show-errors')
    $image = [string](Get-JawsStepBProperty -Object $existing -Names @('definition','container_configuration','image'))
    if ($null -eq $existing) {
        Import-Module (Join-Path $PSScriptRoot 'SupervisorPackage.psm1') -Force
        $package = Get-JawsSupervisorPackagePlan -InstallerRoot $InstallerRoot
        $built = Invoke-JawsSupervisorLocalBuild -PackagePlan $package -BuildContainer
        if (-not $built.ContainerBuilt) { throw 'JAWS-STEP-B-021: Local Supervisor image was not built.' }
        $imageId = (& docker image inspect $package.DockerTag --format '{{.Id}}' 2>$null | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or $imageId -notmatch '^sha256:[a-f0-9]{64}$') { throw 'JAWS-STEP-B-021: Local image id is not a sha256 digest.' }
        $tag = 'build-' + $imageId.Substring(7, 16)
        $target = "$login/jaws/supervisor:$tag"
        $null = Invoke-JawsStepBAz -Arguments @('acr','login','--name',[string]$Scope.RegistryName,'--subscription',$sub,'--only-show-errors')
        & docker tag $package.DockerTag $target
        if ($LASTEXITCODE -ne 0) { throw 'JAWS-PUSH-013: Docker tag failed.' }
        & docker push $target *>&1 | Out-Host
        if ($LASTEXITCODE -ne 0) { throw 'JAWS-PUSH-014: Docker push failed. Inspect the registry before retrying.' }
        $writes++
        $manifest = Invoke-JawsStepBAz -Arguments @('acr','manifest','show-metadata','--registry',[string]$Scope.RegistryName,'--name',"jaws/supervisor:$tag",'--output','json','--only-show-errors')
        $digest = [string]$manifest.digest
        if ($digest -notmatch '^sha256:[a-f0-9]{64}$') { throw 'JAWS-PUSH-016: Registry did not return a valid immutable digest.' }
        $image = "$login/jaws/supervisor@$digest"
        $body = @{
            name = [string]$Scope.AgentName
            definition = @{
                kind = 'hosted'
                container_configuration = @{ image = $image }
                cpu = '1'
                memory = '2Gi'
                protocol_versions = @(@{ protocol = 'responses'; version = '2.0.0' })
                environment_variables = @{ AZURE_AI_MODEL_DEPLOYMENT_NAME = [string]$Scope.ModelDeploymentName }
            }
        } | ConvertTo-Json -Depth 8 -Compress
        $bodyDir = Join-Path $InstallerRoot '.local'
        if (-not (Test-Path -LiteralPath $bodyDir)) { New-Item -ItemType Directory -Path $bodyDir | Out-Null }
        $bodyFile = Join-Path $bodyDir "jaws-step-b-agent-body.$($Scope.EnvironmentName).json"
        Set-Content -LiteralPath $bodyFile -Value $body -Encoding ascii
        $null = Invoke-JawsStepBAz -Arguments @('rest','--method','POST','--url',"$endpoint/agents?api-version=v1",'--resource','https://ai.azure.com','--body',"@$bodyFile",'--output','json','--only-show-errors')
        $writes++
        $existing = $null
        for ($attempt = 0; $attempt -lt 30; $attempt++) {
            $existing = Invoke-JawsStepBAz -AllowMissing -Arguments @('rest','--method','GET','--url',$versionUrl,'--resource','https://ai.azure.com','--output','json','--only-show-errors')
            if ($null -ne $existing -and [string]$existing.status -eq 'failed') { throw 'JAWS-STEP-B-018: Hosted Supervisor provisioning failed.' }
            if ($null -ne $existing -and [string]$existing.status -eq 'active') { break }
            Start-Sleep -Seconds 5
        }
    }
    if ($null -eq $existing) { throw 'JAWS-STEP-B-018: Hosted Supervisor version 1 did not become active.' }
    $observedImage = [string](Get-JawsStepBProperty -Object $existing -Names @('definition','container_configuration','image'))
    $draft = Get-JawsStepBProperty -Object $existing -Names @('draft')
    if ([string]$existing.status -ne 'active' -or $draft -eq $true -or $observedImage -cne $image) {
        throw 'JAWS-STEP-B-018: Hosted Supervisor version 1 is not active on the approved image digest.'
    }
    if ($observedImage -notmatch '@(sha256:[a-f0-9]{64})$') { throw 'JAWS-STEP-B-018: Hosted Supervisor image is not digest-pinned.' }
    $digest = $Matches[1]
    $image = $observedImage
    $local = Join-Path $InstallerRoot '.local'
    if (-not (Test-Path -LiteralPath $local)) { New-Item -ItemType Directory -Path $local | Out-Null }
    $foundryId = "/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.CognitiveServices/accounts/$($Scope.FoundryAccountName)"
    $projectId = "$foundryId/projects/$($Scope.ProjectName)"
    $state = [pscustomobject]@{
        SchemaVersion = '1.1'
        Platform = 'JAWS'
        InstallerVersion = '0.4.8'
        EnvironmentName = [string]$Scope.EnvironmentName
        SubscriptionId = $sub
        ResourceGroupName = $rg
        StateAuthority = 'InstallerGenerated'
        StatePurpose = 'Step B foundation created by the installer for this subscription.'
        Resources = @(
            [pscustomobject]@{ Name = [string]$Scope.FoundryAccountName; Type = 'Microsoft.CognitiveServices/accounts'; ResourceId = $foundryId; Ownership = 'InstallerCreated'; CreatedByInstaller = $true; ExpectedConfiguration = [pscustomobject]@{ Kind = 'AIServices'; Location = [string]$Scope.Location } },
            [pscustomobject]@{ Name = [string]$Scope.ProjectName; Type = 'Microsoft.CognitiveServices/accounts/projects'; ResourceId = $projectId; Ownership = 'InstallerCreated'; CreatedByInstaller = $true; ExpectedConfiguration = [pscustomobject]@{ ParentResource = [string]$Scope.FoundryAccountName } },
            [pscustomobject]@{ Name = [string]$Scope.ModelDeploymentName; Type = 'Microsoft.CognitiveServices/accounts/deployments'; ResourceId = "$foundryId/deployments/$($Scope.ModelDeploymentName)"; Ownership = 'InstallerCreated'; CreatedByInstaller = $true; ExpectedConfiguration = [pscustomobject]@{ ParentResource = [string]$Scope.FoundryAccountName; ModelName = [string]$Scope.ModelName; ModelVersion = [string]$Scope.ModelVersion; ProvisioningState = 'Succeeded' } },
            [pscustomobject]@{ Name = [string]$Scope.KeyVaultName; Type = 'Microsoft.KeyVault/vaults'; ResourceId = "/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.KeyVault/vaults/$($Scope.KeyVaultName)"; Ownership = 'InstallerCreated'; CreatedByInstaller = $true; ExpectedConfiguration = [pscustomobject]@{ Location = [string]$Scope.Location; EnableRbacAuthorization = $true; EnablePurgeProtection = $true } }
        )
    }
    $statePath = Join-Path $local "jaws-installation-state.$($Scope.EnvironmentName).generated.json"
    $state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statePath -Encoding utf8
    $receipt = [pscustomobject]@{
        SchemaVersion = '1.0'
        Status = 'STEP_B_INSTALLED'
        PlanSha256 = $recomputed
        SubscriptionId = $sub
        ResourceGroupName = $rg
        Location = [string]$Scope.Location
        EnvironmentName = [string]$Scope.EnvironmentName
        FoundryAccountName = [string]$Scope.FoundryAccountName
        FoundryAccountId = $foundryId
        ProjectName = [string]$Scope.ProjectName
        ProjectId = $projectId
        ProjectPrincipalId = $principal
        ModelDeploymentName = [string]$Scope.ModelDeploymentName
        ModelName = [string]$Scope.ModelName
        ModelVersion = [string]$Scope.ModelVersion
        KeyVaultName = [string]$Scope.KeyVaultName
        RegistryName = [string]$Scope.RegistryName
        RegistryLoginServer = $login
        Image = $image
        ImageDigest = $digest
        AgentName = [string]$Scope.AgentName
        AgentVersion = '1'
        AgentStatus = 'active'
        AzureWrites = $writes
        StatePath = $statePath
    }
    $receiptPath = Join-Path $local "jaws-step-b-install.$($Scope.EnvironmentName).generated.json"
    $receipt | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $receiptPath -Encoding utf8
    if ((Get-Content -LiteralPath $devState -Raw) -ne $devBefore) {
        throw 'JAWS-STEP-B-022: Step B install changed the dev installation state.'
    }
    return [pscustomobject]@{ Receipt = $receipt; ReceiptPath = $receiptPath; StatePath = $statePath }
}

Export-ModuleMember -Function New-JawsStepBInstallScope,Get-JawsStepBScopeSha256,Invoke-JawsStepBInstall
