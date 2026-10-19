# Step D browser control. Provisions one private Playwright service and registers
# the browser toolbox on the Supervisor and the hosted virtual-machine specialist.
# Supervisor version 1 is read and left unchanged. The dev project is not modified.
Set-StrictMode -Version Latest

function Get-JawsBrowserToolNames {
    @(
        'browser_navigate',
        'browser_snapshot',
        'browser_click',
        'browser_type',
        'browser_screenshot',
        'browser_close'
    )
}

function Get-JawsBrowserJsonEnd {
    param([Parameter(Mandatory)][string]$Text,[Parameter(Mandatory)][int]$Start)
    $depth = 0
    $inString = $false
    $escaped = $false
    for ($i = $Start; $i -lt $Text.Length; $i++) {
        $ch = $Text[$i]
        if ($inString) {
            if ($escaped) { $escaped = $false; continue }
            if ($ch -eq '\') { $escaped = $true; continue }
            if ($ch -eq '"') { $inString = $false }
            continue
        }
        if ($ch -eq '"') { $inString = $true; continue }
        if ($ch -eq '{' -or $ch -eq '[') { $depth++ }
        elseif ($ch -eq '}' -or $ch -eq ']') {
            $depth--
            if ($depth -eq 0) { return $i }
        }
    }
    return -1
}

function ConvertFrom-JawsBrowserJson {
    param([AllowNull()][string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $clean = $Text -replace "$([char]27)\[[0-9;?]*[ -/]*[@-~]", ''
    $objectAt = $clean.IndexOf('{')
    $arrayAt = $clean.IndexOf('[')
    $start = $objectAt
    if ($start -lt 0 -or ($arrayAt -ge 0 -and $arrayAt -lt $start)) { $start = $arrayAt }
    if ($start -lt 0) { return $null }
    $end = Get-JawsBrowserJsonEnd -Text $clean -Start $start
    if ($end -lt $start) { return $null }
    return ($clean.Substring($start, ($end - $start) + 1) | ConvertFrom-Json)
}

function Invoke-JawsBrowserAz {
    param([Parameter(Mandatory)][string[]]$Arguments,[switch]$AllowMissing)
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        throw 'JAWS-PREREQ-001: Azure CLI is not installed or not on PATH.'
    }
    $output = & az @Arguments 2>&1
    $code = $LASTEXITCODE
    $text = (@($output) | ForEach-Object { "$_" }) -join "`n"
    if ($code -ne 0) {
        if ($AllowMissing -and $text -match 'MISSING|ResourceNotFound|ResourceGroupNotFound|was not found|NotFound|not_found|Not Found') {
            return $null
        }
        throw "JAWS-STEP-D-AZ-001: az $($Arguments -join ' ') failed ($code). $text"
    }
    return (ConvertFrom-JawsBrowserJson $text)
}

function Get-JawsBrowserProperty {
    param($Object,[string[]]$Names)
    $current = $Object
    foreach ($name in $Names) {
        if ($null -eq $current -or -not $current.PSObject.Properties[$name]) { return $null }
        $current = $current.$name
    }
    return $current
}

function Get-JawsBrowserNames {
    param([Parameter(Mandatory)][string]$EnvironmentName)
    $compact = ($EnvironmentName -replace '[^a-z0-9]', '')
    if ($compact.Length -gt 20) { $compact = $compact.Substring(0, 20) }
    [pscustomobject]@{
        AppName = "jaws-br-$compact"
        EnvironmentName = "jaws-br-env-$compact"
        VnetName = "jaws-br-vnet-$compact"
        SubnetName = 'jaws-br-apps'
        ToolboxName = 'jaws-browser-tools'
        AllowListSecret = 'jaws-browser-allow-list'
        CredentialSecret = 'jaws-browser-credentials'
        ImageRepository = 'jaws/browser:step-d'
        Audience = 'api://jaws-browser'
    }
}

function Get-JawsBrowserAllowListPath {
    param([Parameter(Mandatory)][string]$InstallerRoot,[Parameter(Mandatory)][string]$EnvironmentName)
    Join-Path $InstallerRoot ".local/jaws-browser-allow-list.$EnvironmentName.json"
}

function Save-JawsBrowserAllowList {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Urls)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    [pscustomobject]@{ Urls = @($Urls) } | ConvertTo-Json | Set-Content -LiteralPath $Path -Encoding utf8
}

function Read-JawsBrowserAllowList {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    $file = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if ($null -eq $file -or -not $file.PSObject.Properties['Urls'] -or $null -eq $file.Urls) { return @() }
    return @($file.Urls | ForEach-Object { [string]$_ })
}

function New-JawsBrowserOpenApiBody {
    param([Parameter(Mandatory)][string]$Endpoint)
    $operation = {
        param($name, $path, $description, $schema)
        [ordered]@{
            post = [ordered]@{
                operationId = $name
                description = $description
                requestBody = [ordered]@{
                    required = $true
                    content = [ordered]@{
                        'application/json' = [ordered]@{ schema = $schema }
                    }
                }
                responses = [ordered]@{ '200' = [ordered]@{ description = 'Browser tool result.' } }
            }
        }
    }
    $objectSchema = [ordered]@{ type = 'object'; additionalProperties = $true }
    [ordered]@{
        description = 'JAWS browser tools. The agent never receives vault credentials.'
        tools = @(
            [ordered]@{
                type = 'openapi'
                openapi = [ordered]@{
                    name = 'jaws-browser'
                    description = 'Private Playwright browser for operator-approved sites.'
                    auth = [ordered]@{
                        type = 'managed_identity'
                        security_scheme = [ordered]@{ audience = 'api://jaws-browser' }
                    }
                    spec = [ordered]@{
                        openapi = '3.1.0'
                        info = [ordered]@{ title = 'JAWS browser'; version = '1' }
                        servers = @([ordered]@{ url = $Endpoint })
                        paths = [ordered]@{
                            '/sessions' = (& $operation 'browser_open' '/sessions' 'Open one browser session.' $objectSchema)
                            '/sessions/{id}/navigate' = (& $operation 'browser_navigate' '/sessions/{id}/navigate' 'Load an allow-listed URL.' $objectSchema)
                            '/sessions/{id}/snapshot' = (& $operation 'browser_snapshot' '/sessions/{id}/snapshot' 'Return the current page text.' $objectSchema)
                            '/sessions/{id}/click' = (& $operation 'browser_click' '/sessions/{id}/click' 'Click an element from the snapshot.' $objectSchema)
                            '/sessions/{id}/type' = (& $operation 'browser_type' '/sessions/{id}/type' 'Type into a non-credential field. Password fields are filled from Key Vault.' $objectSchema)
                            '/sessions/{id}/screenshot' = (& $operation 'browser_screenshot' '/sessions/{id}/screenshot' 'Store a screenshot and return its evidence reference.' $objectSchema)
                            '/sessions/{id}/close' = (& $operation 'browser_close' '/sessions/{id}/close' 'Close the session and drop cookies and storage.' $objectSchema)
                        }
                    }
                }
            }
        )
    }
}

function Install-JawsStepDBrowser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string]$InstallerRoot
    )
    if ([string]$Context.EnvironmentName -eq 'dev') {
        throw 'JAWS-STEP-D-030: Browser control is not provisioned on the accepted dev project.'
    }
    foreach ($name in @('SubscriptionId','ResourceGroupName','Location','RegistryName','KeyVaultName','FoundryAccountName','ProjectName','SupervisorAgent','AgentName','Endpoint')) {
        $value = [string]$Context.$name
        if ([string]::IsNullOrWhiteSpace($value)) {
            throw "JAWS-STEP-D-030: Step B receipt is missing $name, so browser control was not provisioned."
        }
    }
    $names = Get-JawsBrowserNames -EnvironmentName $Context.EnvironmentName
    $writes = 0
    $sub = [string]$Context.SubscriptionId
    $rg = [string]$Context.ResourceGroupName
    $location = [string]$Context.Location
    foreach ($namespace in @('Microsoft.App','Microsoft.Network')) {
        $provider = Invoke-JawsBrowserAz -Arguments @('provider','show','--namespace',$namespace,'--subscription',$sub,'--output','json','--only-show-errors')
        if ([string]$provider.registrationState -ne 'Registered') {
            throw "JAWS-STEP-D-030: $namespace is not registered. Run az provider register --namespace $namespace and wait until it is Registered. Browser control was not provisioned."
        }
    }
    $account = Invoke-JawsBrowserAz -Arguments @('account','show','--output','json','--only-show-errors')
    $tenant = [string](Get-JawsBrowserProperty $account @('tenantId'))
    $vnet = Invoke-JawsBrowserAz -AllowMissing -Arguments @('network','vnet','show','--subscription',$sub,'--resource-group',$rg,'--name',$names.VnetName,'--output','json','--only-show-errors')
    if ($null -eq $vnet) {
        $vnet = Invoke-JawsBrowserAz -Arguments @('network','vnet','create','--subscription',$sub,'--resource-group',$rg,'--name',$names.VnetName,'--location',$location,'--address-prefix','10.42.0.0/16','--output','json','--only-show-errors')
        $writes++
    }
    $subnet = Invoke-JawsBrowserAz -AllowMissing -Arguments @('network','vnet','subnet','show','--subscription',$sub,'--resource-group',$rg,'--vnet-name',$names.VnetName,'--name',$names.SubnetName,'--output','json','--only-show-errors')
    if ($null -eq $subnet) {
        $subnet = Invoke-JawsBrowserAz -Arguments @('network','vnet','subnet','create','--subscription',$sub,'--resource-group',$rg,'--vnet-name',$names.VnetName,'--name',$names.SubnetName,'--address-prefixes','10.42.0.0/23','--delegations','Microsoft.App/environments','--output','json','--only-show-errors')
        $writes++
    }
    $subnetId = [string](Get-JawsBrowserProperty $subnet @('id'))
    if ([string]::IsNullOrWhiteSpace($subnetId)) { $subnetId = "/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Network/virtualNetworks/$($names.VnetName)/subnets/$($names.SubnetName)" }
    $environment = Invoke-JawsBrowserAz -AllowMissing -Arguments @('containerapp','env','show','--subscription',$sub,'--resource-group',$rg,'--name',$names.EnvironmentName,'--output','json','--only-show-errors')
    if ($null -eq $environment) {
        $environment = Invoke-JawsBrowserAz -Arguments @('containerapp','env','create','--subscription',$sub,'--resource-group',$rg,'--name',$names.EnvironmentName,'--location',$location,'--internal-only','true','--infrastructure-subnet-resource-id',$subnetId,'--output','json','--only-show-errors')
        $writes++
    }
    $packageRoot = Split-Path -Parent $InstallerRoot
    $dockerFile = Join-Path $packageRoot 'src/Jaws.Browser.Host/Dockerfile'
    $buildContext = Split-Path -Parent $dockerFile
    if (-not (Test-Path -LiteralPath $dockerFile -PathType Leaf)) {
        throw "JAWS-STEP-D-030: Browser Dockerfile was not found at $dockerFile."
    }
    $imageRef = "$($Context.RegistryName).azurecr.io/$($names.ImageRepository)"
    $existingImage = Invoke-JawsBrowserAz -AllowMissing -Arguments @('acr','repository','show','--name',[string]$Context.RegistryName,'--image',$names.ImageRepository,'--output','json','--only-show-errors')
    if ($null -eq $existingImage) {
        $null = Invoke-JawsBrowserAz -Arguments @('acr','build','--registry',[string]$Context.RegistryName,'--subscription',$sub,'--image',$names.ImageRepository,'--file',$dockerFile,'--platform','linux/amd64','--output','none',$buildContext)
        $writes++
        $existingImage = Invoke-JawsBrowserAz -Arguments @('acr','repository','show','--name',[string]$Context.RegistryName,'--image',$names.ImageRepository,'--output','json','--only-show-errors')
    }
    $digest = [string](Get-JawsBrowserProperty $existingImage @('digest'))
    if ($digest -notmatch '^sha256:[a-f0-9]{64}$') {
        throw 'JAWS-STEP-D-030: The browser image digest was not returned. The Container App was not created.'
    }
    $pinnedImage = "$($Context.RegistryName).azurecr.io/jaws/browser@$digest"
    $app = Invoke-JawsBrowserAz -AllowMissing -Arguments @('containerapp','show','--subscription',$sub,'--resource-group',$rg,'--name',$names.AppName,'--output','json','--only-show-errors')
    $allowPath = Get-JawsBrowserAllowListPath -InstallerRoot $InstallerRoot -EnvironmentName $Context.EnvironmentName
    if (-not (Test-Path -LiteralPath $allowPath -PathType Leaf)) {
        Save-JawsBrowserAllowList -Path $allowPath -Urls @()
    }
    $allowUri = "https://$($Context.KeyVaultName).vault.azure.net/secrets/$($names.AllowListSecret)"
    $credentialUri = "https://$($Context.KeyVaultName).vault.azure.net/secrets/$($names.CredentialSecret)"
    $envVars = @(
        "JAWS_BROWSER_AUDIENCE=$($names.Audience)",
        "JAWS_BROWSER_ALLOW_LIST_SECRET_URI=$allowUri",
        "JAWS_BROWSER_CREDENTIAL_SECRET_URI=$credentialUri",
        'JAWS_BROWSER_TIMEOUT_MINUTES=10',
        'JAWS_BROWSER_STEP_LIMIT=50',
        'JAWS_BROWSER_MAX_SESSIONS=3',
        "AZURE_TENANT_ID=$tenant",
        "JAWS_BROWSER_TENANT_ID=$tenant"
    )
    if ($null -eq $app) {
        $app = Invoke-JawsBrowserAz -Arguments (@(
            'containerapp','create','--subscription',$sub,'--resource-group',$rg,'--name',$names.AppName,
            '--environment',$names.EnvironmentName,'--image',$pinnedImage,'--ingress','internal','--target-port','8089',
            '--system-assigned','--min-replicas','0','--max-replicas','3','--cpu','1.0','--memory','2.0Gi',
            '--registry-server',"$($Context.RegistryName).azurecr.io",'--registry-identity','system','--output','json','--only-show-errors',
            '--env-vars') + $envVars)
        $writes++
    } else {
        $external = Get-JawsBrowserProperty $app @('properties','configuration','ingress','external')
        if ($external -eq $true) {
            throw 'JAWS-STEP-D-030: The browser Container App has public ingress. It was not changed.'
        }
    }
    $principal = [string](Get-JawsBrowserProperty $app @('identity','principalId'))
    if ([string]::IsNullOrWhiteSpace($principal)) {
        throw 'JAWS-STEP-D-030: The browser Container App has no managed identity.'
    }
    $vaultId = "/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.KeyVault/vaults/$($Context.KeyVaultName)"
    foreach ($secretName in @($names.AllowListSecret, $names.CredentialSecret)) {
        $shown = Invoke-JawsBrowserAz -AllowMissing -Arguments @('keyvault','secret','show','--subscription',$sub,'--vault-name',[string]$Context.KeyVaultName,'--name',$secretName,'--output','json','--only-show-errors')
        if ($null -eq $shown) {
            $seed = if ($secretName -eq $names.AllowListSecret) { Get-Content -LiteralPath $allowPath -Raw } else { '{}' }
            $seedFile = Join-Path $InstallerRoot ".local/jaws-browser-secret-$secretName.$($Context.EnvironmentName).json"
            Set-Content -LiteralPath $seedFile -Value $seed -Encoding utf8
            $null = Invoke-JawsBrowserAz -Arguments @('keyvault','secret','set','--subscription',$sub,'--vault-name',[string]$Context.KeyVaultName,'--name',$secretName,'--file',$seedFile,'--output','json','--only-show-errors')
            $writes++
        }
        $scope = "$vaultId/secrets/$secretName"
        $existingRole = @(Invoke-JawsBrowserAz -Arguments @('role','assignment','list','--subscription',$sub,'--assignee-object-id',$principal,'--scope',$scope,'--output','json','--only-show-errors'))
        $hasSecrets = @($existingRole | Where-Object { $_ -and [string]$_.roleDefinitionName -eq 'Key Vault Secrets User' }).Count -gt 0
        if (-not $hasSecrets) {
            $null = Invoke-JawsBrowserAz -Arguments @('role','assignment','create','--subscription',$sub,'--assignee-object-id',$principal,'--assignee-principal-type','ServicePrincipal','--role','Key Vault Secrets User','--scope',$scope,'--output','json','--only-show-errors')
            $writes++
        }
    }
    $registryId = "/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.ContainerRegistry/registries/$($Context.RegistryName)"
    $pullRoles = @(Invoke-JawsBrowserAz -Arguments @('role','assignment','list','--subscription',$sub,'--assignee-object-id',$principal,'--scope',$registryId,'--output','json','--only-show-errors'))
    $hasPull = @($pullRoles | Where-Object { $_ -and [string]$_.roleDefinitionName -eq 'AcrPull' }).Count -gt 0
    if (-not $hasPull) {
        $null = Invoke-JawsBrowserAz -Arguments @('role','assignment','create','--subscription',$sub,'--assignee-object-id',$principal,'--assignee-principal-type','ServicePrincipal','--role','AcrPull','--scope',$registryId,'--output','json','--only-show-errors')
        $writes++
    }
    $fqdn = [string](Get-JawsBrowserProperty $app @('properties','configuration','ingress','fqdn'))
    if ([string]::IsNullOrWhiteSpace($fqdn)) { throw 'JAWS-STEP-D-030: The browser Container App did not return an internal endpoint.' }
    $endpoint = "https://$fqdn"
    $toolboxUrl = "$($Context.Endpoint)/toolboxes/$($names.ToolboxName)/versions?api-version=v1"
    $toolbox = Invoke-JawsBrowserAz -AllowMissing -Arguments @('rest','--method','GET','--url',"$($Context.Endpoint)/toolboxes/$($names.ToolboxName)?api-version=v1",'--resource','https://ai.azure.com','--output','json','--only-show-errors')
    $toolsetVersion = [string](Get-JawsBrowserProperty $toolbox @('default_version'))
    if ([string]::IsNullOrWhiteSpace($toolsetVersion)) {
        $body = New-JawsBrowserOpenApiBody -Endpoint $endpoint
        $bodyFile = Join-Path $InstallerRoot ".local/jaws-browser-toolbox.$($Context.EnvironmentName).json"
        $body | ConvertTo-Json -Depth 20 -Compress | Set-Content -LiteralPath $bodyFile -Encoding utf8
        $created = Invoke-JawsBrowserAz -Arguments @('rest','--method','POST','--url',$toolboxUrl,'--resource','https://ai.azure.com','--body',"@$bodyFile",'--output','json','--only-show-errors')
        $writes++
        $toolsetVersion = [string](Get-JawsBrowserProperty $created @('version'))
        if ([string]::IsNullOrWhiteSpace($toolsetVersion)) { $toolsetVersion = '1' }
    }
    $supervisor = Publish-JawsBrowserSupervisorVersion -Context $Context -ToolboxName $names.ToolboxName
    $writes += $supervisor.AzureWrites
    return [pscustomobject]@{
        AzureWrites = $writes
        ToolboxName = $names.ToolboxName
        ToolsetVersion = $toolsetVersion
        PlaywrightServiceEndpoint = $endpoint
        CredentialScopeId = "$vaultId/secrets/$($names.CredentialSecret)"
        AllowListPath = $allowPath
        BrowserImage = $pinnedImage
        Agents = @([string]$Context.SupervisorAgent, [string]$Context.AgentName)
        SupervisorVersion = $supervisor.Version
        SupervisorV1Unchanged = $true
    }
}

function Publish-JawsBrowserSupervisorVersion {
    param($Context,[Parameter(Mandatory)][string]$ToolboxName)
    $v1Url = "$($Context.Endpoint)/agents/$($Context.SupervisorAgent)/versions/1?api-version=v1"
    $v1 = Invoke-JawsBrowserAz -Arguments @('rest','--method','GET','--url',$v1Url,'--resource','https://ai.azure.com','--output','json','--only-show-errors')
    $v1Image = [string](Get-JawsBrowserProperty $v1 @('definition','container_configuration','image'))
    $v1Browser = [string](Get-JawsBrowserProperty $v1 @('definition','environment_variables','JAWS_BROWSER_TOOLBOX_NAME'))
    $v1Investigation = [string](Get-JawsBrowserProperty $v1 @('definition','environment_variables','JAWS_INVESTIGATION_TOOLBOX_NAME'))
    if ([string]$v1.status -ne 'active' -or $v1.draft -eq $true -or $v1Image -notmatch '@sha256:[a-f0-9]{64}$' -or -not [string]::IsNullOrWhiteSpace($v1Browser) -or -not [string]::IsNullOrWhiteSpace($v1Investigation)) {
        throw 'JAWS-STEP-D-031: Supervisor version 1 is not an active digest-pinned image without a toolbox variable. It was not modified.'
    }
    $summary = Invoke-JawsBrowserAz -Arguments @('rest','--method','GET','--url',"$($Context.Endpoint)/agents/$($Context.SupervisorAgent)?api-version=v1",'--resource','https://ai.azure.com','--output','json','--only-show-errors')
    $latest = [string](Get-JawsBrowserProperty $summary @('versions','latest'))
    if ($latest -match '^[0-9]+$' -and $latest -ne '1') {
        $source = Invoke-JawsBrowserAz -Arguments @('rest','--method','GET','--url',"$($Context.Endpoint)/agents/$($Context.SupervisorAgent)/versions/${latest}?api-version=v1",'--resource','https://ai.azure.com','--output','json','--only-show-errors')
    } else {
        $source = $v1
        $latest = '1'
    }
    $sourceBrowser = [string](Get-JawsBrowserProperty $source @('definition','environment_variables','JAWS_BROWSER_TOOLBOX_NAME'))
    if ($sourceBrowser -eq $ToolboxName -and [string]$source.status -eq 'active' -and $source.draft -ne $true) {
        return [pscustomobject]@{ AzureWrites = 0; Version = $latest }
    }
    $variables = [ordered]@{}
    $current = Get-JawsBrowserProperty $source @('definition','environment_variables')
    if ($null -ne $current) {
        foreach ($prop in $current.PSObject.Properties) { $variables[$prop.Name] = [string]$prop.Value }
    }
    $variables['JAWS_BROWSER_TOOLBOX_NAME'] = $ToolboxName
    $image = [string](Get-JawsBrowserProperty $source @('definition','container_configuration','image'))
    if ($image -cne $v1Image) {
        throw 'JAWS-STEP-D-031: The latest Supervisor image differs from version 1. Browser control does not publish a new Supervisor image.'
    }
    $body = [ordered]@{
        draft = $false
        definition = [ordered]@{
            kind = 'hosted'
            container_configuration = [ordered]@{ image = $image }
            cpu = [string](Get-JawsBrowserProperty $source @('definition','cpu'))
            memory = [string](Get-JawsBrowserProperty $source @('definition','memory'))
            protocol_versions = @([ordered]@{ protocol = 'responses'; version = '2.0.0' })
            environment_variables = $variables
        }
    }
    $bodyFile = [IO.Path]::GetTempFileName()
    try {
        $body | ConvertTo-Json -Depth 12 -Compress | Set-Content -LiteralPath $bodyFile -Encoding utf8
        $created = Invoke-JawsBrowserAz -Arguments @('rest','--method','POST','--url',"$($Context.Endpoint)/agents/$($Context.SupervisorAgent)/versions?api-version=v1",'--resource','https://ai.azure.com','--body',"@$bodyFile",'--output','json','--only-show-errors')
    } finally {
        Remove-Item -LiteralPath $bodyFile -Force -ErrorAction SilentlyContinue
    }
    $createdVersion = [string](Get-JawsBrowserProperty $created @('version'))
    if ($createdVersion -notmatch '^[0-9]+$' -or $createdVersion -eq '1') {
        throw 'JAWS-STEP-D-031: Foundry did not return a Supervisor version after version 1.'
    }
    $v1After = Invoke-JawsBrowserAz -Arguments @('rest','--method','GET','--url',$v1Url,'--resource','https://ai.azure.com','--output','json','--only-show-errors')
    $v1AfterImage = [string](Get-JawsBrowserProperty $v1After @('definition','container_configuration','image'))
    $v1AfterBrowser = [string](Get-JawsBrowserProperty $v1After @('definition','environment_variables','JAWS_BROWSER_TOOLBOX_NAME'))
    if ([string]$v1After.status -ne 'active' -or $v1AfterImage -cne $v1Image -or -not [string]::IsNullOrWhiteSpace($v1AfterBrowser)) {
        throw 'JAWS-STEP-D-031: Supervisor version 1 changed while the browser toolbox was registered.'
    }
    return [pscustomobject]@{ AzureWrites = 1; Version = $createdVersion }
}

function Update-JawsBrowserAllowList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$EnvironmentName,
        [Parameter(Mandatory)][ValidateSet('Add','Remove')][string]$Action,
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$InstallerRoot,
        [switch]$AcknowledgeBrowserAllowList
    )
    if (-not $AcknowledgeBrowserAllowList) {
        throw 'JAWS-STEP-D-033: Updating the browser allow-list requires -AcknowledgeBrowserAllowList. No secret was written.'
    }
    if ($EnvironmentName -eq 'dev') {
        throw 'JAWS-STEP-D-033: The accepted dev project does not receive browser control.'
    }
    $parsed = $null
    if (-not [Uri]::TryCreate($Url, [UriKind]::Absolute, [ref]$parsed) -or $parsed.Scheme -notin @('https','http') -or -not [string]::IsNullOrEmpty($parsed.UserInfo)) {
        throw 'JAWS-STEP-D-033: The allow-list entry must be an absolute http or https URL without user info.'
    }
    $receiptPath = Join-Path $InstallerRoot ".local/jaws-step-b-install.$EnvironmentName.generated.json"
    if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) {
        throw "JAWS-STEP-D-033: Step B receipt was not found: $receiptPath"
    }
    $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
    $names = Get-JawsBrowserNames -EnvironmentName $EnvironmentName
    $path = Get-JawsBrowserAllowListPath -InstallerRoot $InstallerRoot -EnvironmentName $EnvironmentName
    $urls = @(Read-JawsBrowserAllowList -Path $path)
    if ($Action -eq 'Add') {
        if ($urls -notcontains $Url) { $urls += $Url }
    } else {
        $urls = @($urls | Where-Object { $_ -cne $Url })
    }
    Save-JawsBrowserAllowList -Path $path -Urls $urls
    $null = Invoke-JawsBrowserAz -Arguments @('keyvault','secret','set','--subscription',[string]$receipt.SubscriptionId,'--vault-name',[string]$receipt.KeyVaultName,'--name',$names.AllowListSecret,'--file',$path,'--output','json','--only-show-errors')
    return [pscustomobject]@{ Path = $path; Urls = @($urls); AzureWrites = 1 }
}

function Confirm-JawsStepDBrowser {
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)]$InstallReceipt)
    $names = Get-JawsBrowserNames -EnvironmentName $Context.EnvironmentName
    $reasons = @()
    $app = Invoke-JawsBrowserAz -AllowMissing -Arguments @('containerapp','show','--subscription',[string]$Context.SubscriptionId,'--resource-group',[string]$Context.ResourceGroupName,'--name',$names.AppName,'--output','json','--only-show-errors')
    $external = Get-JawsBrowserProperty $app @('properties','configuration','ingress','external')
    $fqdn = [string](Get-JawsBrowserProperty $app @('properties','configuration','ingress','fqdn'))
    if ($null -eq $app) { $reasons += 'browser Container App is missing' }
    elseif ($external -eq $true) { $reasons += 'browser Container App has public ingress' }
    elseif ("https://$fqdn" -cne [string]$InstallReceipt.PlaywrightServiceEndpoint) { $reasons += 'browser endpoint differs from the install receipt' }
    $toolbox = Invoke-JawsBrowserAz -AllowMissing -Arguments @('rest','--method','GET','--url',"$($Context.Endpoint)/toolboxes/$($names.ToolboxName)?api-version=v1",'--resource','https://ai.azure.com','--output','json','--only-show-errors')
    $version = [string](Get-JawsBrowserProperty $toolbox @('default_version'))
    if ([string]::IsNullOrWhiteSpace($version)) { $reasons += 'browser toolbox is missing' }
    elseif ($version -cne [string]$InstallReceipt.BrowserToolsetVersion) { $reasons += 'browser toolset version differs from the install receipt' }
    $summary = Invoke-JawsBrowserAz -Arguments @('rest','--method','GET','--url',"$($Context.Endpoint)/agents/$($Context.SupervisorAgent)?api-version=v1",'--resource','https://ai.azure.com','--output','json','--only-show-errors')
    $latest = [string](Get-JawsBrowserProperty $summary @('versions','latest'))
    $routed = Invoke-JawsBrowserAz -Arguments @('rest','--method','GET','--url',"$($Context.Endpoint)/agents/$($Context.SupervisorAgent)/versions/${latest}?api-version=v1",'--resource','https://ai.azure.com','--output','json','--only-show-errors')
    $routedBrowser = [string](Get-JawsBrowserProperty $routed @('definition','environment_variables','JAWS_BROWSER_TOOLBOX_NAME'))
    if ($routedBrowser -cne $names.ToolboxName) { $reasons += 'the latest Supervisor version does not name the browser toolbox' }
    $v1 = Invoke-JawsBrowserAz -Arguments @('rest','--method','GET','--url',"$($Context.Endpoint)/agents/$($Context.SupervisorAgent)/versions/1?api-version=v1",'--resource','https://ai.azure.com','--output','json','--only-show-errors')
    $v1Browser = [string](Get-JawsBrowserProperty $v1 @('definition','environment_variables','JAWS_BROWSER_TOOLBOX_NAME'))
    if (-not [string]::IsNullOrWhiteSpace($v1Browser)) { $reasons += 'Supervisor version 1 names the browser toolbox' }
    return $reasons
}

function Get-JawsBrowserImageReceiptPath {
    param([Parameter(Mandatory)][string]$InstallerRoot,[Parameter(Mandatory)][string]$EnvironmentName)
    Join-Path $InstallerRoot ".local/jaws-step-d-browser-image.$EnvironmentName.generated.json"
}

function Get-JawsBrowserPrivatePathReceiptPath {
    param([Parameter(Mandatory)][string]$InstallerRoot,[Parameter(Mandatory)][string]$EnvironmentName)
    Join-Path $InstallerRoot ".local/jaws-step-d-browser-private-path.$EnvironmentName.generated.json"
}

function Get-JawsBrowserCapabilityReceiptPath {
    param([Parameter(Mandatory)][string]$InstallerRoot,[Parameter(Mandatory)][string]$EnvironmentName)
    Join-Path $InstallerRoot ".local/jaws-step-d-browser-capability.$EnvironmentName.generated.json"
}

function Save-JawsBrowserReceipt {
    param([Parameter(Mandatory)][string]$Path,$Payload)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    $Payload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding utf8
}

function Read-JawsBrowserReceipt {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
}

function Get-JawsBrowserStepBReceipt {
    param([Parameter(Mandatory)][string]$InstallerRoot,[Parameter(Mandatory)][string]$EnvironmentName)
    $path = Join-Path $InstallerRoot ".local/jaws-step-b-install.$EnvironmentName.generated.json"
    $receipt = Read-JawsBrowserReceipt -Path $path
    if ($null -eq $receipt -or [string]$receipt.Status -ne 'STEP_B_INSTALLED') {
        throw "JAWS-STEP-D-035: Step B receipt was not found for $EnvironmentName."
    }
    return $receipt
}

function Test-JawsPublishedSupervisorBrowserImage {
    param([string]$Image,[string]$VersionOneImage,[string]$RegistryName)
    $login = "$RegistryName.azurecr.io"
    $pattern = '^' + [regex]::Escape($login) + '/jaws/supervisor@sha256:[a-f0-9]{64}$'
    return ($Image -cmatch $pattern -and $Image -cne $VersionOneImage)
}

function Get-JawsBrowserResponseCalls {
    param($Response)
    $items = @()
    if ($null -ne $Response -and $Response.PSObject.Properties['output'] -and $null -ne $Response.output) {
        $items = @($Response.output)
    }
    $calls = @($items | Where-Object { $_ -and $_.PSObject.Properties['type'] -and [string]$_.type -eq 'function_call' })
    $records = @()
    foreach ($call in $calls) {
        $id = if ($call.PSObject.Properties['call_id']) { [string]$call.call_id } else { '' }
        $name = if ($call.PSObject.Properties['name']) { [string]$call.name } else { '' }
        $raw = if ($call.PSObject.Properties['output'] -and $null -ne $call.output) { [string]$call.output } else { '' }
        $match = @($items | Where-Object {
            $_ -and $_.PSObject.Properties['type'] -and [string]$_.type -eq 'function_call_output' -and
            $_.PSObject.Properties['call_id'] -and [string]$_.call_id -ceq $id
        })
        if ($match.Count -eq 1 -and $match[0].PSObject.Properties['output'] -and $null -ne $match[0].output) {
            $raw = [string]$match[0].output
        }
        $records += [pscustomobject]@{ Name = $name; Output = $raw }
    }
    return @($records)
}

function Invoke-JawsBrowserSupervisorResponse {
    param([Parameter(Mandatory)][string]$Url,[Parameter(Mandatory)][string]$Body,[Parameter(Mandatory)][string]$FailureCode)
    $tmp = [IO.Path]::GetTempFileName()
    try {
        [IO.File]::WriteAllText($tmp, $Body, [Text.UTF8Encoding]::new($false))
        $raw = & az rest --method post --url $Url --resource https://ai.azure.com --headers 'Content-Type=application/json' --body "@$tmp" --output json --only-show-errors 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "${FailureCode}: Supervisor invocation failed. $($raw | Out-String)"
        }
        return (($raw | Out-String) | ConvertFrom-Json)
    } finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}

function Publish-JawsSupervisorBrowserImage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$EnvironmentName,
        [Parameter(Mandatory)][string]$InstallerRoot,
        [switch]$AcknowledgeSupervisorBrowserImage
    )
    if (-not $AcknowledgeSupervisorBrowserImage) {
        throw 'JAWS-STEP-D-035: Publishing the Supervisor browser image requires -AcknowledgeSupervisorBrowserImage. No image was built.'
    }
    if ($EnvironmentName -eq 'dev') {
        throw 'JAWS-STEP-D-035: The accepted dev project does not receive a Supervisor browser image.'
    }
    $install = Read-JawsBrowserReceipt -Path (Join-Path $InstallerRoot ".local/jaws-step-d-install.$EnvironmentName.generated.json")
    $toolbox = if ($null -ne $install -and $install.PSObject.Properties['BrowserToolboxName']) { [string]$install.BrowserToolboxName } else { '' }
    if ([string]::IsNullOrWhiteSpace($toolbox)) {
        throw 'JAWS-STEP-D-035: Step D Install has not recorded a browser toolbox. The Supervisor image was not built.'
    }
    $stepB = Get-JawsBrowserStepBReceipt -InstallerRoot $InstallerRoot -EnvironmentName $EnvironmentName
    $endpoint = "https://$([string]$stepB.FoundryAccountName).services.ai.azure.com/api/projects/$([string]$stepB.ProjectName)"
    $supervisor = [string]$stepB.AgentName
    $registry = [string]$stepB.RegistryName
    $subscription = [string]$stepB.SubscriptionId
    $v1Url = "$endpoint/agents/$supervisor/versions/1?api-version=v1"
    $v1 = Invoke-JawsBrowserAz -Arguments @('rest','--method','GET','--url',$v1Url,'--resource','https://ai.azure.com','--output','json','--only-show-errors')
    $v1Image = [string](Get-JawsBrowserProperty $v1 @('definition','container_configuration','image'))
    $v1Browser = [string](Get-JawsBrowserProperty $v1 @('definition','environment_variables','JAWS_BROWSER_TOOLBOX_NAME'))
    if ([string]$v1.status -ne 'active' -or $v1.draft -eq $true -or $v1Image -notmatch '@sha256:[a-f0-9]{64}$' -or -not [string]::IsNullOrWhiteSpace($v1Browser)) {
        throw 'JAWS-STEP-D-035: Supervisor version 1 is not an active digest-pinned image without the browser variable. It was not modified.'
    }
    $summary = Invoke-JawsBrowserAz -Arguments @('rest','--method','GET','--url',"$endpoint/agents/${supervisor}?api-version=v1",'--resource','https://ai.azure.com','--output','json','--only-show-errors')
    $latest = [string](Get-JawsBrowserProperty $summary @('versions','latest'))
    $source = if ($latest -match '^[0-9]+$' -and $latest -ne '1') {
        Invoke-JawsBrowserAz -Arguments @('rest','--method','GET','--url',"$endpoint/agents/$supervisor/versions/${latest}?api-version=v1",'--resource','https://ai.azure.com','--output','json','--only-show-errors')
    } else { $v1 }
    $sourceImage = [string](Get-JawsBrowserProperty $source @('definition','container_configuration','image'))
    $sourceBrowser = [string](Get-JawsBrowserProperty $source @('definition','environment_variables','JAWS_BROWSER_TOOLBOX_NAME'))
    $alreadyPublished = ($sourceBrowser -eq $toolbox -and (Test-JawsPublishedSupervisorBrowserImage -Image $sourceImage -VersionOneImage $v1Image -RegistryName $registry))
    $writes = 0
    $builtThisRun = $false
    $image = $sourceImage
    if ($alreadyPublished) {
        $image = $sourceImage
    } else {
        if ($sourceImage -cne $v1Image) {
            throw 'JAWS-STEP-D-035: The latest Supervisor image differs from version 1 and is not a digest-pinned browser image from this registry. No image was built.'
        }
        Import-Module (Join-Path $PSScriptRoot 'SupervisorPackage.psm1') -Force
        $package = Get-JawsSupervisorPackagePlan -InstallerRoot $InstallerRoot
        $tag = 'browser-' + [guid]::NewGuid().ToString('N').Substring(0, 16)
        $imageName = "jaws/supervisor:$tag"
        $buildOutput = & az @(
            'acr','build',
            '--registry',$registry,
            '--subscription',$subscription,
            '--image',$imageName,
            '--file',$package.DockerfilePath,
            '--platform','linux/amd64',
            '--output','none',
            $package.BuildContext
        ) 2>&1
        $buildCode = $LASTEXITCODE
        if ($buildCode -ne 0) {
            throw "JAWS-STEP-D-035: Azure Container Registry build failed ($buildCode). Docker was not used. $($buildOutput | Out-String)"
        }
        $writes++
        $builtThisRun = $true
        $shown = Invoke-JawsBrowserAz -Arguments @('acr','repository','show','--name',$registry,'--image',$imageName,'--output','json','--only-show-errors')
        $digest = [string](Get-JawsBrowserProperty $shown @('digest'))
        if ($digest -notmatch '^sha256:[a-f0-9]{64}$') {
            throw 'JAWS-STEP-D-035: Registry did not return a valid immutable digest. No Supervisor version was posted.'
        }
        $image = "$registry.azurecr.io/jaws/supervisor@$digest"
        $variables = [ordered]@{}
        $current = Get-JawsBrowserProperty $source @('definition','environment_variables')
        if ($null -ne $current) {
            foreach ($prop in $current.PSObject.Properties) { $variables[$prop.Name] = [string]$prop.Value }
        }
        $variables['JAWS_BROWSER_TOOLBOX_NAME'] = $toolbox
        $body = [ordered]@{
            draft = $false
            definition = [ordered]@{
                kind = 'hosted'
                container_configuration = [ordered]@{ image = $image }
                cpu = [string](Get-JawsBrowserProperty $source @('definition','cpu'))
                memory = [string](Get-JawsBrowserProperty $source @('definition','memory'))
                protocol_versions = @([ordered]@{ protocol = 'responses'; version = '2.0.0' })
                environment_variables = $variables
            }
        }
        $bodyFile = [IO.Path]::GetTempFileName() + '.json'
        try {
            $body | ConvertTo-Json -Depth 12 -Compress | Set-Content -LiteralPath $bodyFile -Encoding utf8
            $created = Invoke-JawsBrowserAz -Arguments @('rest','--method','POST','--url',"$endpoint/agents/$supervisor/versions?api-version=v1",'--resource','https://ai.azure.com','--body',"@$bodyFile",'--output','json','--only-show-errors')
        } finally {
            Remove-Item -LiteralPath $bodyFile -Force -ErrorAction SilentlyContinue
        }
        $writes++
        $createdVersion = [string](Get-JawsBrowserProperty $created @('version'))
        if ($createdVersion -notmatch '^[0-9]+$' -or $createdVersion -eq '1') {
            throw 'JAWS-STEP-D-035: Foundry did not return a Supervisor version after version 1.'
        }
        $latest = $createdVersion
    }
    $v1After = Invoke-JawsBrowserAz -Arguments @('rest','--method','GET','--url',$v1Url,'--resource','https://ai.azure.com','--output','json','--only-show-errors')
    $v1AfterImage = [string](Get-JawsBrowserProperty $v1After @('definition','container_configuration','image'))
    $v1AfterBrowser = [string](Get-JawsBrowserProperty $v1After @('definition','environment_variables','JAWS_BROWSER_TOOLBOX_NAME'))
    if ([string]$v1After.status -ne 'active' -or $v1AfterImage -cne $v1Image -or -not [string]::IsNullOrWhiteSpace($v1AfterBrowser)) {
        throw 'JAWS-STEP-D-035: Supervisor version 1 changed while the browser image was published.'
    }
    $path = Get-JawsBrowserImageReceiptPath -InstallerRoot $InstallerRoot -EnvironmentName $EnvironmentName
    Save-JawsBrowserReceipt -Path $path -Payload ([pscustomobject]@{
        Result = 'PASS'
        EnvironmentName = $EnvironmentName
        SupervisorImageRebuilt = $true
        ImageBuiltThisRun = $builtThisRun
        PreviousImage = $v1Image
        Image = $image
        SupervisorVersion = $latest
        BrowserToolboxName = $toolbox
        SupervisorV1Unchanged = $true
        AzureWrites = $writes
        CustomerInstallationAccepted = $false
        FreshSubscriptionReceiptArchived = $false
        EvidenceLimitations = 'This receipt records an image publish. It is not a fresh-subscription browser capability receipt.'
        CompletedAtUtc = [DateTime]::UtcNow.ToString('o')
    })
    return [pscustomobject]@{
        Passed = $true
        EvidencePath = $path
        ReadyForNextStep = $true
        NextStep = 'Test-JawsBrowserPrivatePath.ps1'
        AzureWrites = $writes
        Image = $image
        PreviousImage = $v1Image
        ImageBuiltThisRun = $builtThisRun
        SupervisorV1Unchanged = $true
    }
}

function Invoke-JawsBrowserPrivatePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$EnvironmentName,
        [Parameter(Mandatory)][string]$InstallerRoot,
        [switch]$AcknowledgeBrowserPrivatePath
    )
    if (-not $AcknowledgeBrowserPrivatePath) {
        throw 'JAWS-STEP-D-037: The private-path check requires -AcknowledgeBrowserPrivatePath. No Supervisor call was made.'
    }
    if ($EnvironmentName -eq 'dev') {
        throw 'JAWS-STEP-D-037: The accepted dev project does not receive a browser private-path check.'
    }
    $imageReceipt = Read-JawsBrowserReceipt -Path (Get-JawsBrowserImageReceiptPath -InstallerRoot $InstallerRoot -EnvironmentName $EnvironmentName)
    $rebuilt = ($null -ne $imageReceipt -and $imageReceipt.PSObject.Properties['SupervisorImageRebuilt'] -and $imageReceipt.SupervisorImageRebuilt -eq $true)
    $previous = if ($null -ne $imageReceipt -and $imageReceipt.PSObject.Properties['PreviousImage']) { [string]$imageReceipt.PreviousImage } else { '' }
    $image = if ($null -ne $imageReceipt -and $imageReceipt.PSObject.Properties['Image']) { [string]$imageReceipt.Image } else { '' }
    if (-not $rebuilt -or [string]::IsNullOrWhiteSpace($image) -or $image -ceq $previous) {
        throw 'JAWS-STEP-D-036: Publish the Supervisor browser image before the private-path check. No Supervisor call was made.'
    }
    $stepB = Get-JawsBrowserStepBReceipt -InstallerRoot $InstallerRoot -EnvironmentName $EnvironmentName
    $endpoint = "https://$([string]$stepB.FoundryAccountName).services.ai.azure.com/api/projects/$([string]$stepB.ProjectName)"
    $supervisor = [string]$stepB.AgentName
    $model = [string]$stepB.ModelDeploymentName
    $url = "$endpoint/agents/$supervisor/endpoint/protocols/openai/responses?api-version=v1"
    $body = @{
        model = $model
        input = 'Call browser_open once, then browser_close. Do not open a page. This proves the Foundry tool path can reach the private browser.'
        stream = $false
        store = $false
    } | ConvertTo-Json -Depth 6 -Compress
    $response = Invoke-JawsBrowserSupervisorResponse -Url $url -Body $body -FailureCode 'JAWS-STEP-D-040'
    $calls = @(Get-JawsBrowserResponseCalls -Response $response)
    $opens = @($calls | Where-Object { $_.Name -eq 'browser_open' })
    $navigates = @($calls | Where-Object { $_.Name -eq 'browser_navigate' })
    $openText = ((@($opens | ForEach-Object { $_.Output })) -join "`n")
    $proven = ($opens.Count -ge 1 -and $navigates.Count -eq 0 -and $openText -match 'sessionId' -and $openText -notmatch 'browser_unreachable')
    $path = Get-JawsBrowserPrivatePathReceiptPath -InstallerRoot $InstallerRoot -EnvironmentName $EnvironmentName
    Save-JawsBrowserReceipt -Path $path -Payload ([pscustomobject]@{
        Result = $(if ($proven) { 'PASS' } else { 'FAIL' })
        PrivatePathProven = $proven
        EnvironmentName = $EnvironmentName
        SupervisorImage = $image
        BrowserOpenCalls = $opens.Count
        BrowserNavigateCalls = $navigates.Count
        ObservedOutput = $openText
        AzureWrites = 0
        InferencePerformed = $true
        LiveAzureRead = $true
        CustomerInstallationAccepted = $false
        FreshSubscriptionReceiptArchived = $false
        EvidenceLimitations = 'A CLI stand-in is not a live Foundry receipt. This command does not navigate.'
        CompletedAtUtc = [DateTime]::UtcNow.ToString('o')
    })
    if (-not $proven) {
        return [pscustomobject]@{
            Passed = $false
            EvidencePath = $path
            ReadyForNextStep = $false
            NextStep = 'Test-JawsBrowserPrivatePath.ps1'
            AzureWrites = 0
            Error = 'JAWS-STEP-D-040: The Foundry tool path did not open a browser session. Navigation was not attempted.'
        }
    }
    return [pscustomobject]@{
        Passed = $true
        EvidencePath = $path
        ReadyForNextStep = $true
        NextStep = 'Set-JawsBrowserAllowList.ps1, then Test-JawsBrowserCapability.ps1'
        AzureWrites = 0
    }
}

function Invoke-JawsBrowserCapability {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$EnvironmentName,
        [Parameter(Mandatory)][string]$InstallerRoot,
        [Parameter(Mandatory)][string]$Url,
        [switch]$AcknowledgeBrowserCapability
    )
    if (-not $AcknowledgeBrowserCapability) {
        throw 'JAWS-STEP-D-038: Browser capability acceptance requires -AcknowledgeBrowserCapability. No Supervisor call was made.'
    }
    if ($EnvironmentName -eq 'dev') {
        throw 'JAWS-STEP-D-038: The accepted dev project does not receive browser capability acceptance.'
    }
    $privatePath = Read-JawsBrowserReceipt -Path (Get-JawsBrowserPrivatePathReceiptPath -InstallerRoot $InstallerRoot -EnvironmentName $EnvironmentName)
    $proven = ($null -ne $privatePath -and $privatePath.PSObject.Properties['PrivatePathProven'] -and $privatePath.PrivatePathProven -eq $true)
    if (-not $proven) {
        throw 'JAWS-STEP-D-041: The private-path check has not passed. Navigation was not attempted.'
    }
    $allowPath = Get-JawsBrowserAllowListPath -InstallerRoot $InstallerRoot -EnvironmentName $EnvironmentName
    $allowed = @(Read-JawsBrowserAllowList -Path $allowPath)
    if ($allowed -notcontains $Url) {
        throw 'JAWS-STEP-D-039: Add that URL with Set-JawsBrowserAllowList.ps1 before capability acceptance. No Supervisor call was made.'
    }
    $stepB = Get-JawsBrowserStepBReceipt -InstallerRoot $InstallerRoot -EnvironmentName $EnvironmentName
    $endpoint = "https://$([string]$stepB.FoundryAccountName).services.ai.azure.com/api/projects/$([string]$stepB.ProjectName)"
    $supervisor = [string]$stepB.AgentName
    $model = [string]$stepB.ModelDeploymentName
    $invokeUrl = "$endpoint/agents/$supervisor/endpoint/protocols/openai/responses?api-version=v1"
    $prompt = "Navigate to $Url with browser_navigate, extract one value, and include the marker EXTRACTED_VALUE. Then try https://blocked.invalid/not-allowed, which is not on the allow-list, and include allow_list_rejected. Do not log a password."
    $body = @{ model = $model; input = $prompt; stream = $false; store = $false } | ConvertTo-Json -Depth 6 -Compress
    $response = Invoke-JawsBrowserSupervisorResponse -Url $invokeUrl -Body $body -FailureCode 'JAWS-STEP-D-042'
    $calls = @(Get-JawsBrowserResponseCalls -Response $response)
    $text = ((@($calls | ForEach-Object { $_.Output })) -join "`n")
    $extracted = $text.Contains('EXTRACTED_VALUE')
    $rejected = $text.Contains('allow_list_rejected')
    $passed = $extracted -and $rejected
    $path = Get-JawsBrowserCapabilityReceiptPath -InstallerRoot $InstallerRoot -EnvironmentName $EnvironmentName
    Save-JawsBrowserReceipt -Path $path -Payload ([pscustomobject]@{
        Result = $(if ($passed) { 'PASS' } else { 'FAIL' })
        CapabilityProven = $passed
        ExtractedValueObserved = $extracted
        AllowListRejectionObserved = $rejected
        Url = $Url
        EnvironmentName = $EnvironmentName
        AzureWrites = 0
        InferencePerformed = $true
        LiveAzureRead = $true
        LiveNavigationClaimed = $false
        VaultLoginClaimed = $false
        SignatureValidationClaimed = $false
        CustomerInstallationAccepted = $false
        FreshSubscriptionReceiptArchived = $false
        EvidenceLimitations = 'A CLI stand-in is not a live page load, a vault login, or a tenant signature check. Customer installation accepted stays false.'
        CompletedAtUtc = [DateTime]::UtcNow.ToString('o')
    })
    if (-not $passed) {
        return [pscustomobject]@{
            Passed = $false
            EvidencePath = $path
            ReadyForNextStep = $false
            NextStep = 'Test-JawsBrowserCapability.ps1'
            AzureWrites = 0
            Error = 'JAWS-STEP-D-042: The browser response did not contain both EXTRACTED_VALUE and allow_list_rejected.'
        }
    }
    return [pscustomobject]@{
        Passed = $true
        EvidencePath = $path
        ReadyForNextStep = $false
        NextStep = 'Step E is not installable'
        AzureWrites = 0
    }
}

Export-ModuleMember -Function Get-JawsBrowserToolNames,Get-JawsBrowserNames,Install-JawsStepDBrowser,Update-JawsBrowserAllowList,Get-JawsBrowserAllowListPath,Confirm-JawsStepDBrowser,Publish-JawsSupervisorBrowserImage,Invoke-JawsBrowserPrivatePath,Invoke-JawsBrowserCapability
