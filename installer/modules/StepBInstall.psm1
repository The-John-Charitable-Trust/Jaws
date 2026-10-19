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
        if ($AllowMissing -and $text -match 'MISSING|ResourceNotFound|ResourceGroupNotFound|ParentResourceNotFound|was not found|NotFound|not_found|Not Found') {
            return $null
        }
        if ($text -match 'MissingSubscriptionRegistration|not registered') {
            throw "JAWS-STEP-B-PROVIDER-001: Required resource provider is not registered. $text"
        }
        if ($text -match 'InsufficientQuota|quota') {
            $issue = (($text -split '\r?\n' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ' ').Trim()
            $action = 'Request a quota increase for this model and region, then run Install again. Dynamic quota does not apply until this capacity-1 deployment exists. Static uses GlobalStandard capacity 1. Dynamic uses the regional Standard SKU at capacity 1.'
            Write-JawsOperatorIssue -Issue $issue -Action $action -QuotaRequest
            throw "JAWS-STEP-B-MODEL-001: Model quota blocked the deployment. $action Quota request: $(Get-JawsQuotaRequestUrl). $issue"
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

function Start-JawsStepBPollSleep {
    [CmdletBinding()]
    param([Parameter(Mandatory)][int]$Seconds)
    $configured = $Seconds
    if ($env:JAWS_STEPB_POLL_SECONDS -match '^\d+$') { $configured = [int]$env:JAWS_STEPB_POLL_SECONDS }
    if ($configured -gt 0) { Start-Sleep -Seconds $configured }
}

function Get-JawsStepBProvisioningState {
    param($Resource)
    if ($null -eq $Resource) { return '' }
    $state = [string](Get-JawsStepBProperty -Object $Resource -Names @('properties','provisioningState'))
    if ([string]::IsNullOrWhiteSpace($state)) {
        $state = [string](Get-JawsStepBProperty -Object $Resource -Names @('provisioningState'))
    }
    return $state
}

function Wait-JawsStepBProvisioned {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Arguments,[Parameter(Mandatory)][string]$Label)
    $resource = $null
    for ($attempt = 0; $attempt -lt 36; $attempt++) {
        $resource = Invoke-JawsStepBAz -AllowMissing -Arguments $Arguments
        $state = Get-JawsStepBProvisioningState -Resource $resource
        if ($null -ne $resource -and ([string]::IsNullOrWhiteSpace($state) -or $state -eq 'Succeeded')) { return $resource }
        if ($state -in @('Failed','Canceled','Cancelled')) {
            throw "JAWS-STEP-B-023: $Label provisioning is $state."
        }
        if ($attempt -eq 35) { break }
        Start-JawsStepBPollSleep -Seconds 5
    }
    throw "JAWS-STEP-B-023: $Label did not reach provisioning state Succeeded."
}

function Get-JawsStepBModelSkuName {
    param([Parameter(Mandatory)][ValidateSet('Static','Dynamic')][string]$QuotaMode)
    if ($QuotaMode -eq 'Dynamic') { return 'Standard' }
    return 'GlobalStandard'
}

function Get-JawsStepBDeploymentSkuName {
    param($Deployment)
    $name = [string](Get-JawsStepBProperty -Object $Deployment -Names @('sku','name'))
    if ([string]::IsNullOrWhiteSpace($name)) {
        $name = [string](Get-JawsStepBProperty -Object $Deployment -Names @('skuName'))
    }
    return $name
}

function Test-JawsStepBModelOffered {
    param($Catalog,[Parameter(Mandatory)][string]$Name,[Parameter(Mandatory)][string]$Version,[Parameter(Mandatory)][string]$SkuName)
    foreach ($item in @($Catalog)) {
        if ($null -eq $item) { continue }
        $model = $item
        if ($item.PSObject.Properties['model'] -and $null -ne $item.model) { $model = $item.model }
        $itemName = [string](Get-JawsStepBProperty -Object $model -Names @('name'))
        if ([string]::IsNullOrWhiteSpace($itemName)) { $itemName = [string](Get-JawsStepBProperty -Object $item -Names @('name')) }
        $itemVersion = [string](Get-JawsStepBProperty -Object $model -Names @('version'))
        if ([string]::IsNullOrWhiteSpace($itemVersion)) { $itemVersion = [string](Get-JawsStepBProperty -Object $item -Names @('version')) }
        $format = [string](Get-JawsStepBProperty -Object $model -Names @('format'))
        if ([string]::IsNullOrWhiteSpace($format)) { $format = [string](Get-JawsStepBProperty -Object $item -Names @('format')) }
        if ($itemName -ne $Name -or $itemVersion -ne $Version) { continue }
        if (-not [string]::IsNullOrWhiteSpace($format) -and $format -ne 'OpenAI') { continue }
        $skus = @()
        if ($model.PSObject.Properties['skus']) { $skus = @($model.skus) }
        elseif ($item.PSObject.Properties['skus']) { $skus = @($item.skus) }
        elseif ($model.PSObject.Properties['sku'] -and $null -ne $model.sku) { $skus = @($model.sku) }
        if ($skus.Count -eq 0) { return $true }
        foreach ($sku in $skus) {
            $offeredSku = [string]$sku
            if ($null -ne $sku -and $sku.PSObject.Properties['name']) { $offeredSku = [string]$sku.name }
            if ($offeredSku -eq $SkuName) { return $true }
        }
    }
    return $false
}

function Get-JawsStepBDeploymentModel {
    param($Deployment)
    $name = [string](Get-JawsStepBProperty -Object $Deployment -Names @('properties','model','name'))
    $version = [string](Get-JawsStepBProperty -Object $Deployment -Names @('properties','model','version'))
    if ([string]::IsNullOrWhiteSpace($name)) { $name = [string](Get-JawsStepBProperty -Object $Deployment -Names @('model','name')) }
    if ([string]::IsNullOrWhiteSpace($version)) { $version = [string](Get-JawsStepBProperty -Object $Deployment -Names @('model','version')) }
    return [pscustomobject]@{ Name = $name; Version = $version }
}

function Test-JawsStepBDynamicQuota {
    param($Deployment)
    return ((Get-JawsStepBProperty -Object $Deployment -Names @('properties','dynamicThrottlingEnabled')) -eq $true)
}

function Set-JawsStepBDeploymentQuotaMode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Scope,
        [Parameter(Mandatory)]$Deployment,
        [Parameter(Mandatory)][ValidateSet('Static','Dynamic')][string]$QuotaMode,
        [Parameter(Mandatory)][string]$InstallerRoot
    )
    $wantDynamic = $QuotaMode -eq 'Dynamic'
    if ((Test-JawsStepBDynamicQuota $Deployment) -eq $wantDynamic) {
        return [pscustomobject]@{ Deployment = $Deployment; Changed = $false }
    }
    $local = Join-Path $InstallerRoot '.local'
    if (-not (Test-Path -LiteralPath $local)) { New-Item -ItemType Directory -Path $local | Out-Null }
    $bodyFile = Join-Path $local "jaws-step-b-quota.$($Scope.EnvironmentName).json"
    @{ properties = @{ dynamicThrottlingEnabled = $wantDynamic } } | ConvertTo-Json -Compress | Set-Content -LiteralPath $bodyFile -Encoding ascii
    $url = "https://management.azure.com/subscriptions/$([string]$Scope.SubscriptionId)/resourceGroups/$([string]$Scope.ResourceGroupName)/providers/Microsoft.CognitiveServices/accounts/$([string]$Scope.FoundryAccountName)/deployments/$([string]$Scope.ModelDeploymentName)?api-version=2023-10-01-preview"
    $null = Invoke-JawsStepBAz -Arguments @('rest','--method','patch','--url',$url,'--body',"@$bodyFile",'--output','json','--only-show-errors')
    $shown = Invoke-JawsStepBAz -Arguments @('cognitiveservices','account','deployment','show','--subscription',[string]$Scope.SubscriptionId,'--resource-group',[string]$Scope.ResourceGroupName,'--name',[string]$Scope.FoundryAccountName,'--deployment-name',[string]$Scope.ModelDeploymentName,'--output','json','--only-show-errors')
    if ((Test-JawsStepBDynamicQuota $shown) -ne $wantDynamic) {
        throw "JAWS-STEP-B-MODEL-002: Quota mode $QuotaMode was not recorded. dynamicThrottlingEnabled does not match. Capacity stays 1. Dynamic uses the regional Standard SKU."
    }
    return [pscustomobject]@{ Deployment = $shown; Changed = $true }
}

function Invoke-JawsStepBRoleAssignment {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Arguments)
    for ($attempt = 1; $attempt -le 12; $attempt++) {
        try { return Invoke-JawsStepBAz -Arguments $Arguments }
        catch {
            if ($attempt -eq 12 -or $_.Exception.Message -notmatch 'PrincipalNotFound') { throw }
            Start-JawsStepBPollSleep -Seconds 5
        }
    }
}

function Get-JawsStepBRegistryDigest {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RegistryName,[Parameter(Mandatory)][string]$ImageName)
    $metadataArguments = @('acr','manifest','show-metadata','--registry',$RegistryName,'--name',$ImageName,'--output','json','--only-show-errors')
    try {
        $manifest = Invoke-JawsStepBAz -Arguments $metadataArguments
        if ([string]$manifest.digest -match '^sha256:[a-f0-9]{64}$') { return $Matches[0] }
    } catch { }
    $shown = Invoke-JawsStepBAz -Arguments @('acr','repository','show','--name',$RegistryName,'--image',$ImageName,'--output','json','--only-show-errors')
    if ([string]$shown.digest -notmatch '^sha256:[a-f0-9]{64}$') {
        throw 'JAWS-PUSH-016: Registry did not return a valid immutable digest.'
    }
    return $Matches[0]
}

function Get-JawsStepBAuthorizedWrites {
    @(
        [pscustomobject]@{ Action = 'CreateIfMissing'; Type = 'Microsoft.Resources/resourceGroups'; BoundTo = 'The approved resource group and location only.' },
        [pscustomobject]@{ Action = 'CreateIfMissing'; Type = 'Microsoft.CognitiveServices/accounts'; BoundTo = 'AIServices S0. Custom domain equals the account name.' },
        [pscustomobject]@{ Action = 'CreateIfMissing'; Type = 'Microsoft.CognitiveServices/accounts/projects'; BoundTo = 'System-assigned project identity only.' },
        [pscustomobject]@{ Action = 'CreateIfMissing'; Type = 'Microsoft.CognitiveServices/accounts/deployments'; BoundTo = 'The approved OpenAI model name and version, capacity 1. Static uses GlobalStandard. Dynamic uses the regional Standard SKU and then sets dynamicThrottlingEnabled. An existing GlobalStandard deployment is replaced when Install uses Dynamic. Quota mode does not change the plan digest. The plan is not changed if that model is absent.' },
        [pscustomobject]@{ Action = 'CreateIfMissing'; Type = 'Microsoft.KeyVault/vaults'; BoundTo = 'RBAC authorization and purge protection.' },
        [pscustomobject]@{ Action = 'CreateIfMissing'; Type = 'Microsoft.ContainerRegistry/registries'; BoundTo = 'Basic SKU, admin disabled, public network enabled.' },
        [pscustomobject]@{ Action = 'CreateIfMissing'; Type = 'Microsoft.Authorization/roleAssignments'; BoundTo = 'AcrPull for this project identity on this registry only.' },
        [pscustomobject]@{ Action = 'CreateIfMissing'; Type = 'Foundry hosted agent version'; BoundTo = 'Supervisor version 1, cpu 1, memory 2Gi. The image is built by az acr build for linux/amd64 and pinned to the registry digest.' }
    )
}

function Test-JawsStepBNameAvailable {
    param($Response)
    if ($null -eq $Response) { return $false }
    $value = Get-JawsStepBProperty -Object $Response -Names @('nameAvailable')
    return ($value -eq $true)
}

function Invoke-JawsStepBPreflight {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Scope,
        [Parameter(Mandatory)][string]$InstallerRoot
    )
    $devState = Join-Path $InstallerRoot 'config/jaws-installation-state.dev.json'
    $devBefore = Get-Content -LiteralPath $devState -Raw
    $reasons = [System.Collections.Generic.List[string]]::new()
    $account = Invoke-JawsStepBAz -Arguments @('account','show','--output','json','--only-show-errors')
    if ([string]$account.id -ine [string]$Scope.SubscriptionId) {
        $reasons.Add('JAWS-STEP-B-019: Azure CLI subscription differs from the approved plan. Run az account set.')
    }
    $sub = [string]$Scope.SubscriptionId
    $rg = [string]$Scope.ResourceGroupName
    $user = [string](Get-JawsStepBProperty -Object $account -Names @('user','name'))
    if ([string]::IsNullOrWhiteSpace($user)) { $reasons.Add('The signed-in account has no user name, so role assignments cannot be checked.') }
    foreach ($namespace in @('Microsoft.CognitiveServices','Microsoft.KeyVault','Microsoft.ContainerRegistry')) {
        try {
            $provider = Invoke-JawsStepBAz -Arguments @('provider','show','--namespace',$namespace,'--subscription',$sub,'--output','json','--only-show-errors')
            if ([string]$provider.registrationState -ne 'Registered') {
                $reasons.Add("$namespace registration is '$([string]$provider.registrationState)'. Run az provider register --namespace $namespace --subscription $sub and wait until it is Registered. Preflight does not register providers.")
            }
        } catch {
            $reasons.Add("Could not read provider ${namespace}. $($_.Exception.Message)")
        }
    }
    $locations = @()
    $locationOk = $false
    if ([string]$account.id -ieq [string]$Scope.SubscriptionId) {
        try {
            $locations = @(Invoke-JawsStepBAz -Arguments @('account','list-locations','--output','json','--only-show-errors'))
        } catch {
            $reasons.Add("Could not list subscription locations. $($_.Exception.Message)")
        }
        $locationOk = @($locations | Where-Object { $_ -and [string]$_.name -eq [string]$Scope.Location }).Count -eq 1
        if (-not $locationOk) { $reasons.Add("Location '$([string]$Scope.Location)' is not enabled for this subscription.") }
    }
    $canWrite = $false
    $canAssign = $false
    if (-not [string]::IsNullOrWhiteSpace($user)) {
        try {
            $assignments = @(Invoke-JawsStepBAz -Arguments @('role','assignment','list','--assignee',$user,'--scope',"/subscriptions/$sub",'--include-inherited','--output','json','--only-show-errors'))
            foreach ($item in $assignments) {
                if ($null -eq $item) { continue }
                $role = [string]$item.roleDefinitionName
                if ($role -in @('Owner','Contributor')) { $canWrite = $true }
                if ($role -in @('Owner','User Access Administrator','Role Based Access Control Administrator')) { $canAssign = $true }
            }
        } catch {
            $reasons.Add("Could not read role assignments for $user. $($_.Exception.Message)")
        }
    }
    if (-not $canWrite) { $reasons.Add('No Owner or Contributor assignment was found at this subscription. Install cannot create the resource group or foundation.') }
    if (-not $canAssign) { $reasons.Add('No Owner, User Access Administrator, or Role Based Access Control Administrator assignment was found. Contributor can create resources and still cannot assign AcrPull.') }
    $group = Invoke-JawsStepBAz -AllowMissing -Arguments @('group','show','--subscription',$sub,'--name',$rg,'--output','json','--only-show-errors')
    if ($null -ne $group -and [string]$group.location -ine [string]$Scope.Location) {
        $reasons.Add("Resource group $rg already exists in '$([string]$group.location)'.")
    }
    $local = Join-Path $InstallerRoot '.local'
    if (-not (Test-Path -LiteralPath $local)) { New-Item -ItemType Directory -Path $local | Out-Null }
    $foundry = Invoke-JawsStepBAz -AllowMissing -Arguments @('cognitiveservices','account','show','--subscription',$sub,'--resource-group',$rg,'--name',[string]$Scope.FoundryAccountName,'--output','json','--only-show-errors')
    if ($null -eq $foundry) {
        $bodyFile = Join-Path $local "jaws-step-b-name.$($Scope.EnvironmentName).json"
        @{ subdomainName = [string]$Scope.FoundryAccountName; type = 'Microsoft.CognitiveServices/accounts'; kind = 'AIServices' } | ConvertTo-Json -Compress | Set-Content -LiteralPath $bodyFile -Encoding ascii
        try {
            $check = Invoke-JawsStepBAz -Arguments @('rest','--method','POST','--url',"https://management.azure.com/subscriptions/$sub/providers/Microsoft.CognitiveServices/checkDomainAvailability?api-version=2024-10-01",'--body',"@$bodyFile",'--output','json','--only-show-errors')
            $domainOk = (Get-JawsStepBProperty -Object $check -Names @('isSubdomainAvailable')) -eq $true
            if (-not $domainOk) { $reasons.Add("Foundry custom domain '$($Scope.FoundryAccountName)' is not available.") }
        } catch {
            $reasons.Add("Could not check Foundry custom domain availability. $($_.Exception.Message)")
        }
        $skuFile = Join-Path $local "jaws-step-b-sku.$($Scope.EnvironmentName).json"
        @{ kind = 'AIServices'; skus = @('S0'); type = 'Microsoft.CognitiveServices/accounts' } | ConvertTo-Json -Compress | Set-Content -LiteralPath $skuFile -Encoding ascii
        try {
            $sku = Invoke-JawsStepBAz -Arguments @('rest','--method','POST','--url',"https://management.azure.com/subscriptions/$sub/providers/Microsoft.CognitiveServices/locations/$([string]$Scope.Location)/checkSkuAvailability?api-version=2024-10-01",'--body',"@$skuFile",'--output','json','--only-show-errors')
            $skuValues = @()
            if ($sku -and $sku.PSObject.Properties['value']) { $skuValues = @($sku.value) } else { $skuValues = @($sku) }
            $s0 = @($skuValues | Where-Object { $_ -and ([string]$_.skuName -eq 'S0') -and ($_.skuAvailable -eq $true) })
            if ($s0.Count -lt 1) { $reasons.Add("AIServices S0 is not available in $([string]$Scope.Location).") }
        } catch {
            $reasons.Add("Could not check AIServices S0 availability. $($_.Exception.Message)")
        }
    } elseif (-not (Test-JawsStepBOwned -Resource $foundry -EnvironmentName $Scope.EnvironmentName)) {
        $reasons.Add('Foundry account already exists and is not owned by this installer.')
    }
    $vault = Invoke-JawsStepBAz -AllowMissing -Arguments @('keyvault','show','--subscription',$sub,'--resource-group',$rg,'--name',[string]$Scope.KeyVaultName,'--output','json','--only-show-errors')
    if ($null -eq $vault) {
        $bodyFile = Join-Path $local "jaws-step-b-vault-name.$($Scope.EnvironmentName).json"
        @{ name = [string]$Scope.KeyVaultName; type = 'Microsoft.KeyVault/vaults' } | ConvertTo-Json -Compress | Set-Content -LiteralPath $bodyFile -Encoding ascii
        try {
            $check = Invoke-JawsStepBAz -Arguments @('rest','--method','POST','--url',"https://management.azure.com/subscriptions/$sub/providers/Microsoft.KeyVault/checkNameAvailability?api-version=2022-07-01",'--body',"@$bodyFile",'--output','json','--only-show-errors')
            if (-not (Test-JawsStepBNameAvailable $check)) { $reasons.Add("Key Vault name '$($Scope.KeyVaultName)' is not available.") }
        } catch {
            $reasons.Add("Could not check Key Vault name availability. $($_.Exception.Message)")
        }
    } elseif (-not (Test-JawsStepBOwned -Resource $vault -EnvironmentName $Scope.EnvironmentName)) {
        $reasons.Add('Key Vault already exists and is not owned by this installer.')
    }
    $registry = Invoke-JawsStepBAz -AllowMissing -Arguments @('acr','show','--subscription',$sub,'--resource-group',$rg,'--name',[string]$Scope.RegistryName,'--output','json','--only-show-errors')
    if ($null -eq $registry) {
        try {
            $check = Invoke-JawsStepBAz -Arguments @('acr','check-name','--name',[string]$Scope.RegistryName,'--output','json','--only-show-errors')
            if (-not (Test-JawsStepBNameAvailable $check)) { $reasons.Add("Registry name '$($Scope.RegistryName)' is not available.") }
        } catch {
            $reasons.Add("Could not check registry name availability. $($_.Exception.Message)")
        }
    } elseif (-not (Test-JawsStepBOwned -Resource $registry -EnvironmentName $Scope.EnvironmentName) -or $registry.adminUserEnabled -ne $false) {
        $reasons.Add('Registry already exists and is not an installer-owned registry with admin disabled.')
    }
    $policyCount = $null
    $policyNote = $null
    try {
        $policies = @(Invoke-JawsStepBAz -Arguments @('policy','assignment','list','--scope',"/subscriptions/$sub",'--disable-scope-strict-match','--output','json','--only-show-errors'))
        $policyCount = @($policies | Where-Object { $null -ne $_ -and $_.PSObject.Properties['name'] }).Count
    } catch {
        $policyNote = $_.Exception.Message
    }
    $ready = $reasons.Count -eq 0
    $report = [pscustomobject]@{
        SchemaVersion = '1.0'
        Status = $(if ($ready) { 'READY_FOR_BOUNDED_WRITES' } else { 'NOT_READY' })
        PlanSha256 = [string]$Scope.PlanSha256
        SubscriptionId = $sub
        ResourceGroupName = $rg
        Location = [string]$Scope.Location
        EnvironmentName = [string]$Scope.EnvironmentName
        AzureWrites = 0
        ResourceWrite = [bool]$canWrite
        RoleAssignment = [bool]$canAssign
        LocationAccepted = [bool]$locationOk
        ModelQuota = 'DeferredUntilFoundryAccountExists'
        ModelBound = "$($Scope.ModelName) $($Scope.ModelVersion) OpenAI capacity 1. Static uses GlobalStandard. Dynamic uses the regional Standard SKU. Quota mode is applied at Install and defaults to Static."
        PolicySimulation = 'NotPerformed'
        PolicyAssignmentCount = $policyCount
        PolicyReadError = $policyNote
        AuthorizedWrites = @(Get-JawsStepBAuthorizedWrites)
        Reasons = @($reasons)
        AuthorizationScope = 'The plan SHA-256 binds the resource names, subscription, and model. This report binds the read-only permission and provider checks. Neither one authorizes an unbounded mutation or an unbounded cost. Model quota is checked again after the Foundry account exists and before the deployment is created. Azure Policy deny effects are not simulated.'
    }
    $reportPath = Join-Path $local "jaws-step-b-preflight.$($Scope.EnvironmentName).generated.json"
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding utf8
    if ((Get-Content -LiteralPath $devState -Raw) -ne $devBefore) {
        throw 'JAWS-STEP-B-022: Step B preflight changed the dev installation state.'
    }
    return [pscustomobject]@{ Report = $report; ReportPath = $reportPath; Ready = $ready }
}

function Invoke-JawsStepBInstall {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Scope,
        [Parameter(Mandatory)][string]$ApprovedPlanSha256,
        [Parameter(Mandatory)][string]$InstallerRoot,
        [ValidateSet('Static','Dynamic')][string]$QuotaMode = 'Static',
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
    $preflight = Invoke-JawsStepBPreflight -Scope $Scope -InstallerRoot $InstallerRoot
    if (-not $preflight.Ready) {
        throw "JAWS-STEP-B-026: Step B preflight is not ready. No Azure writes were attempted. $($preflight.Report.Reasons -join ' ')"
    }
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
        $foundry = Invoke-JawsStepBAz -Arguments (@('cognitiveservices','account','create','--subscription',$sub,'--resource-group',$rg,'--name',[string]$Scope.FoundryAccountName,'--kind','AIServices','--sku','S0','--location',[string]$Scope.Location,'--custom-domain',[string]$Scope.FoundryAccountName,'--assign-identity','--allow-project-management','true','--yes','--output','json','--only-show-errors','--tags') + $tags)
        $writes++
    } elseif (-not (Test-JawsStepBOwned -Resource $foundry -EnvironmentName $Scope.EnvironmentName)) {
        throw 'JAWS-STEP-B-012: Foundry account exists and is not owned by this installer. Refusing adoption.'
    }
    $foundryShow = @('cognitiveservices','account','show','--subscription',$sub,'--resource-group',$rg,'--name',[string]$Scope.FoundryAccountName,'--output','json','--only-show-errors')
    $foundry = Wait-JawsStepBProvisioned -Arguments $foundryShow -Label 'Foundry account'
    $projectShow = @('cognitiveservices','account','project','show','--subscription',$sub,'--resource-group',$rg,'--name',[string]$Scope.FoundryAccountName,'--project-name',[string]$Scope.ProjectName,'--output','json','--only-show-errors')
    $project = Invoke-JawsStepBAz -AllowMissing -Arguments $projectShow
    if ($null -eq $project) {
        $project = Invoke-JawsStepBAz -Arguments @('cognitiveservices','account','project','create','--subscription',$sub,'--resource-group',$rg,'--name',[string]$Scope.FoundryAccountName,'--project-name',[string]$Scope.ProjectName,'--location',[string]$Scope.Location,'--assign-identity','--output','json','--only-show-errors')
        $writes++
    }
    $principal = ''
    for ($attempt = 0; $attempt -lt 36; $attempt++) {
        $project = Wait-JawsStepBProvisioned -Arguments $projectShow -Label 'Foundry project'
        $principal = [string](Get-JawsStepBProperty -Object $project -Names @('identity','principalId'))
        if (-not [string]::IsNullOrWhiteSpace($principal)) { break }
        Start-JawsStepBPollSleep -Seconds 5
    }
    if ([string]::IsNullOrWhiteSpace($principal)) { throw 'JAWS-STEP-B-020: Foundry project has no managed identity principal.' }
    $deploymentShow = @('cognitiveservices','account','deployment','show','--subscription',$sub,'--resource-group',$rg,'--name',[string]$Scope.FoundryAccountName,'--deployment-name',[string]$Scope.ModelDeploymentName,'--output','json','--only-show-errors')
    $deployment = Invoke-JawsStepBAz -AllowMissing -Arguments $deploymentShow
    $skuName = Get-JawsStepBModelSkuName -QuotaMode $QuotaMode
    $replaceSku = $null -ne $deployment -and $QuotaMode -eq 'Dynamic' -and (Get-JawsStepBDeploymentSkuName -Deployment $deployment) -ne 'Standard'
    if ($null -eq $deployment -or $replaceSku) {
        $catalog = Invoke-JawsStepBAz -Arguments @('cognitiveservices','account','list-models','--subscription',$sub,'--resource-group',$rg,'--name',[string]$Scope.FoundryAccountName,'--output','json','--only-show-errors')
        if ($catalog -and $catalog.PSObject.Properties['value']) { $catalog = $catalog.value }
        if (-not (Test-JawsStepBModelOffered -Catalog $catalog -Name $Scope.ModelName -Version $Scope.ModelVersion -SkuName $skuName)) {
            $detail = "$($Scope.ModelName) $($Scope.ModelVersion) OpenAI $skuName is not offered on this Foundry account."
            if ($QuotaMode -eq 'Dynamic') { $detail += ' Dynamic quota requires the regional Standard SKU. GlobalStandard does not support dynamicThrottlingEnabled.' }
            throw "JAWS-STEP-B-MODEL-001: $detail The approved plan was not changed."
        }
        if ($replaceSku) {
            $null = Invoke-JawsStepBAz -Arguments @('cognitiveservices','account','deployment','delete','--subscription',$sub,'--resource-group',$rg,'--name',[string]$Scope.FoundryAccountName,'--deployment-name',[string]$Scope.ModelDeploymentName,'--yes','--output','json','--only-show-errors')
            $writes++
        }
        $deployment = Invoke-JawsStepBAz -Arguments @('cognitiveservices','account','deployment','create','--subscription',$sub,'--resource-group',$rg,'--name',[string]$Scope.FoundryAccountName,'--deployment-name',[string]$Scope.ModelDeploymentName,'--model-name',[string]$Scope.ModelName,'--model-version',[string]$Scope.ModelVersion,'--model-format','OpenAI','--sku-name',$skuName,'--sku-capacity','1','--output','json','--only-show-errors')
        $writes++
    }
    $deployment = Wait-JawsStepBProvisioned -Arguments $deploymentShow -Label 'Model deployment'
    $deployedModel = Get-JawsStepBDeploymentModel -Deployment $deployment
    if ($deployedModel.Name -ne [string]$Scope.ModelName -or $deployedModel.Version -ne [string]$Scope.ModelVersion) {
        throw 'JAWS-STEP-B-MODEL-001: The deployment does not match the approved model name and version. The plan was not changed.'
    }
    $quota = Set-JawsStepBDeploymentQuotaMode -Scope $Scope -Deployment $deployment -QuotaMode $QuotaMode -InstallerRoot $InstallerRoot
    if ($quota.Changed) { $writes++ }
    $deployment = $quota.Deployment
    $vaultShow = @('keyvault','show','--subscription',$sub,'--resource-group',$rg,'--name',[string]$Scope.KeyVaultName,'--output','json','--only-show-errors')
    $vault = Invoke-JawsStepBAz -AllowMissing -Arguments $vaultShow
    if ($null -eq $vault) {
        $vault = Invoke-JawsStepBAz -Arguments (@('keyvault','create','--subscription',$sub,'--resource-group',$rg,'--name',[string]$Scope.KeyVaultName,'--location',[string]$Scope.Location,'--enable-rbac-authorization','true','--enable-purge-protection','true','--output','json','--only-show-errors','--tags') + $tags)
        $writes++
    } elseif (-not (Test-JawsStepBOwned -Resource $vault -EnvironmentName $Scope.EnvironmentName)) {
        throw 'JAWS-STEP-B-012: Key Vault exists and is not owned by this installer. Refusing adoption.'
    }
    $vault = Wait-JawsStepBProvisioned -Arguments $vaultShow -Label 'Key Vault'
    $registryShow = @('acr','show','--subscription',$sub,'--resource-group',$rg,'--name',[string]$Scope.RegistryName,'--output','json','--only-show-errors')
    $registry = Invoke-JawsStepBAz -AllowMissing -Arguments $registryShow
    if ($null -eq $registry) {
        $registry = Invoke-JawsStepBAz -Arguments (@('acr','create','--subscription',$sub,'--resource-group',$rg,'--name',[string]$Scope.RegistryName,'--location',[string]$Scope.Location,'--sku','Basic','--admin-enabled','false','--public-network-enabled','true','--role-assignment-mode','rbac','--output','json','--only-show-errors','--tags') + $tags)
        $writes++
    } elseif (-not (Test-JawsStepBOwned -Resource $registry -EnvironmentName $Scope.EnvironmentName) -or $registry.adminUserEnabled -ne $false) {
        throw 'JAWS-STEP-B-012: Registry exists and is not an installer-owned Basic registry with admin disabled.'
    }
    $registry = Wait-JawsStepBProvisioned -Arguments $registryShow -Label 'Container registry'
    $registryId = "/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.ContainerRegistry/registries/$($Scope.RegistryName)"
    $roles = @(Invoke-JawsStepBAz -Arguments @('role','assignment','list','--subscription',$sub,'--assignee-object-id',$principal,'--scope',$registryId,'--include-inherited','--fill-principal-name','false','--output','json','--only-show-errors'))
    $hasPull = @($roles | Where-Object { $_ -and [string]$_.roleDefinitionName -in @('AcrPull','Container Registry Repository Reader') }).Count -gt 0
    if (-not $hasPull) {
        $null = Invoke-JawsStepBRoleAssignment -Arguments @('role','assignment','create','--subscription',$sub,'--assignee-object-id',$principal,'--assignee-principal-type','ServicePrincipal','--role','AcrPull','--scope',$registryId,'--output','json','--only-show-errors')
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
        $tag = 'build-' + [guid]::NewGuid().ToString('N').Substring(0, 16)
        $imageName = "jaws/supervisor:$tag"
        if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
            throw 'JAWS-PREREQ-001: Azure CLI is not installed or not on PATH.'
        }
        $buildOutput = & az @(
            'acr','build',
            '--registry',[string]$Scope.RegistryName,
            '--subscription',$sub,
            '--image',$imageName,
            '--file',$package.DockerfilePath,
            '--platform','linux/amd64',
            '--output','none',
            $package.BuildContext
        ) 2>&1
        $buildCode = $LASTEXITCODE
        $buildOutput | Out-Host
        if ($buildCode -ne 0) {
            throw "JAWS-STEP-B-021: Azure Container Registry build failed ($buildCode). Docker was not used. $($buildOutput | Out-String)"
        }
        $writes++
        $digest = Get-JawsStepBRegistryDigest -RegistryName ([string]$Scope.RegistryName) -ImageName $imageName
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
        $agentUrl = "$endpoint/agents/$($Scope.AgentName)?api-version=v1"
        $agentExists = Invoke-JawsStepBAz -AllowMissing -Arguments @('rest','--method','GET','--url',$agentUrl,'--resource','https://ai.azure.com','--output','json','--only-show-errors')
        if ($null -eq $agentExists) {
            $null = Invoke-JawsStepBAz -Arguments @('rest','--method','POST','--url',"$endpoint/agents?api-version=v1",'--resource','https://ai.azure.com','--body',"@$bodyFile",'--output','json','--only-show-errors')
            $writes++
        }
        $existing = $null
        for ($attempt = 0; $attempt -lt 60; $attempt++) {
            $existing = Invoke-JawsStepBAz -AllowMissing -Arguments @('rest','--method','GET','--url',$versionUrl,'--resource','https://ai.azure.com','--output','json','--only-show-errors')
            if ($null -ne $existing -and [string]$existing.status -eq 'failed') { throw 'JAWS-STEP-B-018: Hosted Supervisor provisioning failed.' }
            if ($null -ne $existing -and [string]$existing.status -eq 'active') { break }
            Start-JawsStepBPollSleep -Seconds 10
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
        InstallerVersion = '0.4.10'
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
        ModelSku = (Get-JawsStepBDeploymentSkuName -Deployment $deployment)
        QuotaMode = $QuotaMode
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

function Invoke-JawsStepBAccept {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$EnvironmentName,
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$Location,
        [Parameter(Mandatory)][string]$ModelName,
        [Parameter(Mandatory)][string]$ModelVersion,
        [Parameter(Mandatory)][string]$InstallerRoot
    )
    $devState = Join-Path $InstallerRoot 'config/jaws-installation-state.dev.json'
    $devBefore = Get-Content -LiteralPath $devState -Raw
    $receiptPath = Join-Path $InstallerRoot ".local/jaws-step-b-install.$EnvironmentName.generated.json"
    if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) {
        throw "JAWS-STEP-B-006: Step B install receipt not found: $receiptPath"
    }
    $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
    $account = Invoke-JawsStepBAz -Arguments @('account','show','--output','json','--only-show-errors')
    if ([string]$account.id -ine [string]$receipt.SubscriptionId) {
        throw 'JAWS-STEP-B-019: Azure CLI subscription differs from the install receipt. No resources were changed.'
    }
    $scope = New-JawsStepBInstallScope -SubscriptionId ([string]$account.id) -ResourceGroupName $ResourceGroupName -Location $Location -EnvironmentName $EnvironmentName -ModelName $ModelName -ModelVersion $ModelVersion
    $mismatch = @()
    if ([string]$receipt.PlanSha256 -cne [string]$scope.PlanSha256) { $mismatch += 'plan digest' }
    foreach ($name in @('ResourceGroupName','FoundryAccountName','ProjectName','ModelDeploymentName','ModelName','ModelVersion','KeyVaultName','RegistryName','AgentName')) {
        if ([string]$receipt.$name -cne [string]$scope.$name) { $mismatch += $name }
    }
    if ($mismatch.Count -gt 0) {
        throw "JAWS-STEP-B-025: Install receipt does not match this scope ($($mismatch -join ', ')). No resources were changed."
    }
    $sub = [string]$scope.SubscriptionId
    $rg = [string]$scope.ResourceGroupName
    $reasons = @()
    $group = Invoke-JawsStepBAz -AllowMissing -Arguments @('group','show','--subscription',$sub,'--name',$rg,'--output','json','--only-show-errors')
    if ($null -eq $group) { $reasons += 'resource group is missing' }
    elseif ([string]$group.location -ine [string]$scope.Location) { $reasons += 'resource group location differs' }
    $foundry = Invoke-JawsStepBAz -AllowMissing -Arguments @('cognitiveservices','account','show','--subscription',$sub,'--resource-group',$rg,'--name',[string]$scope.FoundryAccountName,'--output','json','--only-show-errors')
    if ($null -eq $foundry) { $reasons += 'Foundry account is missing' }
    else {
        if ((Get-JawsStepBProvisioningState -Resource $foundry) -ne 'Succeeded') { $reasons += 'Foundry provisioning is not Succeeded' }
        if ([string]$foundry.kind -ne 'AIServices') { $reasons += 'Foundry kind is not AIServices' }
        if (-not (Test-JawsStepBOwned -Resource $foundry -EnvironmentName $scope.EnvironmentName)) { $reasons += 'Foundry account is not installer-owned' }
        $domain = [string](Get-JawsStepBProperty -Object $foundry -Names @('properties','customSubDomainName'))
        if (-not [string]::IsNullOrWhiteSpace($domain) -and $domain -ne [string]$scope.FoundryAccountName) { $reasons += 'Foundry custom domain differs' }
    }
    $project = Invoke-JawsStepBAz -AllowMissing -Arguments @('cognitiveservices','account','project','show','--subscription',$sub,'--resource-group',$rg,'--name',[string]$scope.FoundryAccountName,'--project-name',[string]$scope.ProjectName,'--output','json','--only-show-errors')
    $principal = [string](Get-JawsStepBProperty -Object $project -Names @('identity','principalId'))
    if ([string]::IsNullOrWhiteSpace($principal)) { $reasons += 'project identity is missing' }
    elseif ($principal -ine [string]$receipt.ProjectPrincipalId) { $reasons += 'project principal differs from the receipt' }
    $deployment = Invoke-JawsStepBAz -AllowMissing -Arguments @('cognitiveservices','account','deployment','show','--subscription',$sub,'--resource-group',$rg,'--name',[string]$scope.FoundryAccountName,'--deployment-name',[string]$scope.ModelDeploymentName,'--output','json','--only-show-errors')
    $deployedModel = Get-JawsStepBDeploymentModel -Deployment $deployment
    if ($null -eq $deployment) { $reasons += 'model deployment is missing' }
    elseif ((Get-JawsStepBProvisioningState -Resource $deployment) -ne 'Succeeded') { $reasons += 'model deployment is not Succeeded' }
    elseif ($deployedModel.Name -ne [string]$scope.ModelName -or $deployedModel.Version -ne [string]$scope.ModelVersion) { $reasons += 'deployed model differs from the approved plan' }
    $observedQuota = if (Test-JawsStepBDynamicQuota $deployment) { 'Dynamic' } else { 'Static' }
    $observedSku = Get-JawsStepBDeploymentSkuName -Deployment $deployment
    if ($receipt.PSObject.Properties['QuotaMode'] -and [string]$receipt.QuotaMode -cne $observedQuota) {
        $reasons += "quota mode is $observedQuota and the receipt says $([string]$receipt.QuotaMode)"
    }
    if ($observedQuota -eq 'Dynamic' -and $observedSku -ne 'Standard') {
        $reasons += "dynamic quota is on SKU $observedSku and requires the regional Standard SKU"
    }
    if ($receipt.PSObject.Properties['ModelSku'] -and -not [string]::IsNullOrWhiteSpace([string]$receipt.ModelSku) -and [string]$receipt.ModelSku -cne $observedSku) {
        $reasons += "model SKU is $observedSku and the receipt says $([string]$receipt.ModelSku)"
    }
    $vault = Invoke-JawsStepBAz -AllowMissing -Arguments @('keyvault','show','--subscription',$sub,'--resource-group',$rg,'--name',[string]$scope.KeyVaultName,'--output','json','--only-show-errors')
    $rbac = Get-JawsStepBProperty -Object $vault -Names @('properties','enableRbacAuthorization')
    $purge = Get-JawsStepBProperty -Object $vault -Names @('properties','enablePurgeProtection')
    if ($null -eq $vault) { $reasons += 'Key Vault is missing' }
    elseif (-not (Test-JawsStepBOwned -Resource $vault -EnvironmentName $scope.EnvironmentName)) { $reasons += 'Key Vault is not installer-owned' }
    elseif ($rbac -ne $true -or $purge -ne $true) { $reasons += 'Key Vault is missing RBAC authorization or purge protection' }
    $registry = Invoke-JawsStepBAz -AllowMissing -Arguments @('acr','show','--subscription',$sub,'--resource-group',$rg,'--name',[string]$scope.RegistryName,'--output','json','--only-show-errors')
    $skuName = [string](Get-JawsStepBProperty -Object $registry -Names @('sku','name'))
    if ($null -eq $registry) { $reasons += 'registry is missing' }
    elseif (-not (Test-JawsStepBOwned -Resource $registry -EnvironmentName $scope.EnvironmentName) -or $registry.adminUserEnabled -ne $false -or $skuName -ne 'Basic') {
        $reasons += 'registry is not an installer-owned Basic registry with admin disabled'
    }
    $registryId = "/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.ContainerRegistry/registries/$($scope.RegistryName)"
    $roles = @()
    if (-not [string]::IsNullOrWhiteSpace($principal)) {
        $roles = @(Invoke-JawsStepBAz -Arguments @('role','assignment','list','--subscription',$sub,'--assignee-object-id',$principal,'--scope',$registryId,'--include-inherited','--fill-principal-name','false','--output','json','--only-show-errors'))
    }
    $hasPull = @($roles | Where-Object { $_ -and [string]$_.roleDefinitionName -in @('AcrPull','Container Registry Repository Reader') }).Count -gt 0
    if (-not $hasPull) { $reasons += 'project identity is missing AcrPull' }
    $endpoint = "https://$($scope.FoundryAccountName).services.ai.azure.com/api/projects/$($scope.ProjectName)"
    $versionUrl = "$endpoint/agents/$($scope.AgentName)/versions/1?api-version=v1"
    $agent = Invoke-JawsStepBAz -AllowMissing -Arguments @('rest','--method','GET','--url',$versionUrl,'--resource','https://ai.azure.com','--output','json','--only-show-errors')
    $image = [string](Get-JawsStepBProperty -Object $agent -Names @('definition','container_configuration','image'))
    $draft = Get-JawsStepBProperty -Object $agent -Names @('draft')
    if ($null -eq $agent) { $reasons += 'hosted Supervisor version 1 is missing' }
    elseif ([string]$agent.status -ne 'active' -or $draft -eq $true) { $reasons += 'hosted Supervisor version 1 is not active' }
    elseif ($image -cne [string]$receipt.Image -or $image -notmatch '@sha256:[a-f0-9]{64}$') { $reasons += 'hosted Supervisor image is not the receipt digest' }
    if ($reasons.Count -gt 0) {
        throw "JAWS-STEP-B-024: Live Step B acceptance failed. $($reasons -join '; ')."
    }
    if ((Get-Content -LiteralPath $devState -Raw) -ne $devBefore -or $devBefore -notmatch 'c52f597b-7753-45b4-a764-67e290dcfd5e') {
        throw 'JAWS-STEP-B-022: Step B acceptance changed the dev installation state.'
    }
    $report = [pscustomobject]@{
        SchemaVersion = '1.0'
        Status = 'STEP_B_ACCEPTED'
        LiveAzureRead = $true
        AzureWrites = 0
        PlanSha256 = [string]$scope.PlanSha256
        SubscriptionId = $sub
        ResourceGroupName = $rg
        Location = [string]$scope.Location
        EnvironmentName = [string]$scope.EnvironmentName
        FoundryAccountName = [string]$scope.FoundryAccountName
        FoundryProvisioningState = 'Succeeded'
        ProjectName = [string]$scope.ProjectName
        ProjectPrincipalId = $principal
        ModelName = [string]$scope.ModelName
        ModelVersion = [string]$scope.ModelVersion
        QuotaMode = $observedQuota
        ModelSku = $observedSku
        DeploymentProvisioningState = 'Succeeded'
        KeyVaultName = [string]$scope.KeyVaultName
        KeyVaultRbac = $true
        KeyVaultPurgeProtection = $true
        RegistryName = [string]$scope.RegistryName
        RegistryAdminEnabled = $false
        AcrPull = $true
        Image = $image
        AgentName = [string]$scope.AgentName
        AgentVersion = '1'
        AgentStatus = 'active'
        DevStateUnchanged = $true
        ReceiptPath = $receiptPath
    }
    $local = Join-Path $InstallerRoot '.local'
    if (-not (Test-Path -LiteralPath $local)) { New-Item -ItemType Directory -Path $local | Out-Null }
    $reportPath = Join-Path $local "jaws-step-b-acceptance.$EnvironmentName.generated.json"
    $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $reportPath -Encoding utf8
    return [pscustomobject]@{ Report = $report; ReportPath = $reportPath }
}

Export-ModuleMember -Function New-JawsStepBInstallScope,Get-JawsStepBScopeSha256,Get-JawsStepBAuthorizedWrites,Invoke-JawsStepBPreflight,Invoke-JawsStepBInstall,Invoke-JawsStepBAccept
