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
        if ($AllowMissing -and $text -match 'MISSING|ResourceNotFound|ResourceGroupNotFound|was not found|NotFound|not_found|Not Found|does not exist') {
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

function Get-JawsBrowserToolboxServer {
    param($Version)
    $tools = @(Get-JawsBrowserProperty $Version @('tools')) | Where-Object { $_ }
    $tool = $tools | Select-Object -First 1
    $servers = @(Get-JawsBrowserProperty $tool @('openapi','spec','servers')) | Where-Object { $_ }
    $server = $servers | Select-Object -First 1
    return [string](Get-JawsBrowserProperty $server @('url'))
}

function Get-JawsBrowserLatestVersion {
    param($Summary)
    $latestObj = Get-JawsBrowserProperty $Summary @('versions','latest')
    if ($latestObj -is [string] -or $latestObj -is [ValueType]) { return [string]$latestObj }
    return [string](Get-JawsBrowserProperty $latestObj @('version'))
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
        FoundrySubnetName = 'jaws-foundry-agents'
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

function Publish-JawsBrowserToolboxVersion {
    param($Context,[Parameter(Mandatory)][string]$ToolboxName,[Parameter(Mandatory)][string]$ServerUrl,[Parameter(Mandatory)][string]$InstallerRoot)
    $base = "$($Context.Endpoint)/toolboxes/$ToolboxName"
    $toolbox = Invoke-JawsBrowserAz -AllowMissing -Arguments @('rest','--method','GET','--url',"$base`?api-version=v1",'--resource','https://ai.azure.com','--output','json','--only-show-errors')
    $current = [string](Get-JawsBrowserProperty $toolbox @('default_version'))
    if (-not [string]::IsNullOrWhiteSpace($current)) {
        $existing = Invoke-JawsBrowserAz -AllowMissing -Arguments @('rest','--method','GET','--url',"$base/versions/${current}?api-version=v1",'--resource','https://ai.azure.com','--output','json','--only-show-errors')
        if ((Get-JawsBrowserToolboxServer $existing) -ceq $ServerUrl) {
            return [pscustomobject]@{ Version = $current; AzureWrites = 0 }
        }
    }
    $body = New-JawsBrowserOpenApiBody -Endpoint $ServerUrl
    $local = Join-Path $InstallerRoot '.local'
    if (-not (Test-Path -LiteralPath $local)) { New-Item -ItemType Directory -Path $local | Out-Null }
    $bodyFile = Join-Path $local "jaws-browser-toolbox.$($Context.EnvironmentName).json"
    [IO.File]::WriteAllText($bodyFile, ($body | ConvertTo-Json -Depth 20 -Compress), [Text.UTF8Encoding]::new($false))
    $created = Invoke-JawsBrowserAz -Arguments @('rest','--method','POST','--url',"$base/versions?api-version=v1",'--resource','https://ai.azure.com','--body',"@$bodyFile",'--output','json','--only-show-errors')
    $writes = 1
    $createdVersion = [string](Get-JawsBrowserProperty $created @('version'))
    if ([string]::IsNullOrWhiteSpace($createdVersion)) { $createdVersion = '1' }
    $record = Invoke-JawsBrowserAz -Arguments @('rest','--method','GET','--url',"$base`?api-version=v1",'--resource','https://ai.azure.com','--output','json','--only-show-errors')
    $defaultNow = [string](Get-JawsBrowserProperty $record @('default_version'))
    if ($defaultNow -cne $createdVersion) {
        $patchFile = Join-Path $local "jaws-browser-toolbox-default.$($Context.EnvironmentName).json"
        [IO.File]::WriteAllText($patchFile, ('{"default_version":"' + $createdVersion + '"}'), [Text.UTF8Encoding]::new($false))
        $promoted = Invoke-JawsBrowserAz -Arguments @('rest','--method','PATCH','--url',"$base`?api-version=v1",'--resource','https://ai.azure.com','--body',"@$patchFile",'--output','json','--only-show-errors')
        $writes++
        $defaultNow = [string](Get-JawsBrowserProperty $promoted @('default_version'))
        if ($defaultNow -cne $createdVersion) {
            throw "JAWS-STEP-D-030: Browser toolbox default version is '$defaultNow' after promotion. Expected '$createdVersion'."
        }
    }
    return [pscustomobject]@{ Version = $createdVersion; AzureWrites = $writes }
}

function Test-JawsFoundryAgentInjection {
    param($Account)
    $injections = @(Get-JawsBrowserProperty $Account @('properties','networkInjections')) | Where-Object { $_ }
    foreach ($item in $injections) {
        $scenario = [string](Get-JawsBrowserProperty $item @('scenario'))
        $subnet = [string](Get-JawsBrowserProperty $item @('subnetArmId'))
        if ($scenario -eq 'agent' -and -not [string]::IsNullOrWhiteSpace($subnet)) {
            return $subnet
        }
    }
    return ''
}

function Enable-JawsBrowserPrivateNetwork {
    param($Context)
    $names = Get-JawsBrowserNames -EnvironmentName $Context.EnvironmentName
    $writes = 0
    $sub = [string]$Context.SubscriptionId
    $rg = [string]$Context.ResourceGroupName
    $location = [string]$Context.Location
    foreach ($namespace in @('Microsoft.App','Microsoft.Network')) {
        $provider = Invoke-JawsBrowserAz -Arguments @('provider','show','--namespace',$namespace,'--subscription',$sub,'--output','json','--only-show-errors')
        if ([string]$provider.registrationState -ne 'Registered') {
            throw "JAWS-STEP-D-030: $namespace is not registered. Run az provider register --namespace $namespace and wait until it is Registered."
        }
    }
    $vnet = Invoke-JawsBrowserAz -AllowMissing -Arguments @('network','vnet','show','--subscription',$sub,'--resource-group',$rg,'--name',$names.VnetName,'--output','json','--only-show-errors')
    if ($null -eq $vnet) {
        $null = Invoke-JawsBrowserAz -Arguments @('network','vnet','create','--subscription',$sub,'--resource-group',$rg,'--name',$names.VnetName,'--location',$location,'--address-prefix','10.42.0.0/16','--output','json','--only-show-errors')
        $writes++
    }
    $browserSubnet = Invoke-JawsBrowserAz -AllowMissing -Arguments @('network','vnet','subnet','show','--subscription',$sub,'--resource-group',$rg,'--vnet-name',$names.VnetName,'--name',$names.SubnetName,'--output','json','--only-show-errors')
    if ($null -eq $browserSubnet) {
        $browserSubnet = Invoke-JawsBrowserAz -Arguments @('network','vnet','subnet','create','--subscription',$sub,'--resource-group',$rg,'--vnet-name',$names.VnetName,'--name',$names.SubnetName,'--address-prefixes','10.42.0.0/23','--delegations','Microsoft.App/environments','--output','json','--only-show-errors')
        $writes++
    }
    $foundrySubnet = Invoke-JawsBrowserAz -AllowMissing -Arguments @('network','vnet','subnet','show','--subscription',$sub,'--resource-group',$rg,'--vnet-name',$names.VnetName,'--name',$names.FoundrySubnetName,'--output','json','--only-show-errors')
    if ($null -eq $foundrySubnet) {
        $foundrySubnet = Invoke-JawsBrowserAz -Arguments @('network','vnet','subnet','create','--subscription',$sub,'--resource-group',$rg,'--vnet-name',$names.VnetName,'--name',$names.FoundrySubnetName,'--address-prefixes','10.42.2.0/24','--delegations','Microsoft.App/environments','--output','json','--only-show-errors')
        $writes++
    }
    $browserSubnetId = [string](Get-JawsBrowserProperty $browserSubnet @('id'))
    $foundrySubnetId = [string](Get-JawsBrowserProperty $foundrySubnet @('id'))
    if ([string]::IsNullOrWhiteSpace($browserSubnetId)) { $browserSubnetId = "/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Network/virtualNetworks/$($names.VnetName)/subnets/$($names.SubnetName)" }
    if ([string]::IsNullOrWhiteSpace($foundrySubnetId)) { $foundrySubnetId = "/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Network/virtualNetworks/$($names.VnetName)/subnets/$($names.FoundrySubnetName)" }
    return [pscustomobject]@{ AzureWrites = $writes; BrowserSubnetId = $browserSubnetId; FoundrySubnetId = $foundrySubnetId }
}

function Install-JawsFoundryPrivateNetwork {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$EnvironmentName,
        [Parameter(Mandatory)][string]$InstallerRoot,
        [switch]$AcknowledgeFoundryReplacement
    )
    if (-not $AcknowledgeFoundryReplacement) {
        throw 'JAWS-STEP-D-044: Replacing Foundry with virtual-network injection requires -AcknowledgeFoundryReplacement. No Azure writes were attempted.'
    }
    if ($EnvironmentName -eq 'dev') {
        throw 'JAWS-STEP-D-044: The accepted dev project is not replaced.'
    }
    $receiptPath = Join-Path $InstallerRoot ".local/jaws-step-b-install.$EnvironmentName.generated.json"
    $receipt = Read-JawsBrowserReceipt -Path $receiptPath
    if ($null -eq $receipt -or [string]$receipt.Status -ne 'STEP_B_INSTALLED') {
        throw "JAWS-STEP-D-044: Step B receipt was not found for $EnvironmentName. No Foundry account was replaced."
    }
    foreach ($name in @('SubscriptionId','ResourceGroupName','Location','FoundryAccountName')) {
        if ([string]::IsNullOrWhiteSpace([string]$receipt.$name)) {
            throw "JAWS-STEP-D-044: Step B receipt is missing $name. No Foundry account was replaced."
        }
    }
    $context = [pscustomobject]@{
        EnvironmentName = $EnvironmentName
        SubscriptionId = [string]$receipt.SubscriptionId
        ResourceGroupName = [string]$receipt.ResourceGroupName
        Location = [string]$receipt.Location
    }
    $network = Enable-JawsBrowserPrivateNetwork -Context $context
    $writes = [int]$network.AzureWrites
    $sub = [string]$receipt.SubscriptionId
    $rg = [string]$receipt.ResourceGroupName
    $accountName = [string]$receipt.FoundryAccountName
    $show = @('cognitiveservices','account','show','--subscription',$sub,'--resource-group',$rg,'--name',$accountName,'--output','json','--only-show-errors')
    $foundry = Invoke-JawsBrowserAz -AllowMissing -Arguments $show
    $replaced = $false
    if ($null -ne $foundry) {
        $managedBy = [string](Get-JawsBrowserProperty $foundry @('tags','managedBy'))
        $environmentTag = [string](Get-JawsBrowserProperty $foundry @('tags','environment'))
        if ($managedBy -ne 'JAWS-Installer' -or $environmentTag -ne $EnvironmentName) {
            throw 'JAWS-STEP-D-044: Foundry account is not owned by this installer. It was not replaced.'
        }
        $injected = Test-JawsFoundryAgentInjection $foundry
        if (-not [string]::IsNullOrWhiteSpace($injected)) {
            if ($injected -cne [string]$network.FoundrySubnetId) {
                throw 'JAWS-STEP-D-044: Foundry is injected into a different subnet. It was not replaced.'
            }
        } else {
            $projectName = [string]$receipt.ProjectName
            if (-not [string]::IsNullOrWhiteSpace($projectName)) {
                $null = Invoke-JawsBrowserAz -AllowMissing -Arguments @('cognitiveservices','account','project','delete','--subscription',$sub,'--resource-group',$rg,'--name',$accountName,'--project-name',$projectName,'--output','json','--only-show-errors')
                $writes++
            }
            $null = Invoke-JawsBrowserAz -Arguments @('cognitiveservices','account','delete','--subscription',$sub,'--resource-group',$rg,'--name',$accountName,'--output','json','--only-show-errors')
            $writes++
            $null = Invoke-JawsBrowserAz -Arguments @('cognitiveservices','account','purge','--subscription',$sub,'--resource-group',$rg,'--name',$accountName,'--location',[string]$receipt.Location,'--output','json','--only-show-errors')
            $writes++
            $replaced = $true
        }
    } else {
        $replaced = $true
    }
    if ($replaced) {
        $body = [ordered]@{
            location = [string]$receipt.Location
            kind = 'AIServices'
            sku = [ordered]@{ name = 'S0' }
            identity = [ordered]@{ type = 'SystemAssigned' }
            tags = [ordered]@{ application = 'JAWS'; managedBy = 'JAWS-Installer'; environment = $EnvironmentName }
            properties = [ordered]@{
                allowProjectManagement = $true
                customSubDomainName = $accountName
                publicNetworkAccess = 'Enabled'
                disableLocalAuth = $false
                networkAcls = [ordered]@{ defaultAction = 'Allow'; virtualNetworkRules = @(); ipRules = @() }
                networkInjections = @(
                    [ordered]@{
                        scenario = 'agent'
                        subnetArmId = [string]$network.FoundrySubnetId
                        useMicrosoftManagedNetwork = $false
                    }
                )
            }
        }
        $local = Join-Path $InstallerRoot '.local'
        if (-not (Test-Path -LiteralPath $local)) { New-Item -ItemType Directory -Path $local | Out-Null }
        $bodyFile = Join-Path $local "jaws-foundry-network.$EnvironmentName.json"
        [IO.File]::WriteAllText($bodyFile, ($body | ConvertTo-Json -Depth 8 -Compress), [Text.UTF8Encoding]::new($false))
        $url = "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.CognitiveServices/accounts/${accountName}?api-version=2025-04-01-preview"
        $null = Invoke-JawsBrowserAz -Arguments @('rest','--method','PUT','--url',$url,'--body',"@$bodyFile",'--output','json','--only-show-errors')
        $writes++
        $created = Invoke-JawsBrowserAz -Arguments $show
        if ((Test-JawsFoundryAgentInjection $created) -cne [string]$network.FoundrySubnetId) {
            throw 'JAWS-STEP-D-044: Foundry was created without agent virtual-network injection.'
        }
    }
    return [pscustomobject]@{
        AzureWrites = $writes
        Replaced = $replaced
        FoundrySubnetId = [string]$network.FoundrySubnetId
        FoundryAccountName = $accountName
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
    $network = Enable-JawsBrowserPrivateNetwork -Context $Context
    $writes += [int]$network.AzureWrites
    $account = Invoke-JawsBrowserAz -Arguments @('account','show','--output','json','--only-show-errors')
    $tenant = [string](Get-JawsBrowserProperty $account @('tenantId'))
    $environment = Invoke-JawsBrowserAz -AllowMissing -Arguments @('containerapp','env','show','--subscription',$sub,'--resource-group',$rg,'--name',$names.EnvironmentName,'--output','json','--only-show-errors')
    $app = Invoke-JawsBrowserAz -AllowMissing -Arguments @('containerapp','show','--subscription',$sub,'--resource-group',$rg,'--name',$names.AppName,'--output','json','--only-show-errors')
    if ($null -ne $environment -and (Get-JawsBrowserProperty $environment @('properties','vnetConfiguration','internal')) -ne $true) {
        if ($null -ne $app) {
            $null = Invoke-JawsBrowserAz -Arguments @('containerapp','delete','--subscription',$sub,'--resource-group',$rg,'--name',$names.AppName,'--yes','--output','json','--only-show-errors')
            $writes++
            $app = $null
        }
        $null = Invoke-JawsBrowserAz -Arguments @('containerapp','env','delete','--subscription',$sub,'--resource-group',$rg,'--name',$names.EnvironmentName,'--yes','--output','json','--only-show-errors')
        $writes++
        $environment = $null
    }
    if ($null -eq $environment) {
        $environment = Invoke-JawsBrowserAz -Arguments @('containerapp','env','create','--subscription',$sub,'--resource-group',$rg,'--name',$names.EnvironmentName,'--location',$location,'--internal-only','true','--infrastructure-subnet-resource-id',[string]$network.BrowserSubnetId,'--output','json','--only-show-errors')
        $writes++
    }
    if ((Get-JawsBrowserProperty $environment @('properties','vnetConfiguration','internal')) -ne $true) {
        throw 'JAWS-STEP-D-030: The browser environment is not internal-only. It was not left on a public endpoint.'
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
        $null = Invoke-JawsBrowserAz -Arguments @('acr','build','--registry',[string]$Context.RegistryName,'--subscription',$sub,'--image',$names.ImageRepository,'--file',$dockerFile,'--platform','linux/amd64','--output','none','--no-logs',$buildContext)
        $writes++
        $existingImage = Invoke-JawsBrowserAz -Arguments @('acr','repository','show','--name',[string]$Context.RegistryName,'--image',$names.ImageRepository,'--output','json','--only-show-errors')
    }
    $digest = [string](Get-JawsBrowserProperty $existingImage @('digest'))
    if ($digest -notmatch '^sha256:[a-f0-9]{64}$') {
        throw 'JAWS-STEP-D-030: The browser image digest was not returned. The Container App was not created.'
    }
    $pinnedImage = "$($Context.RegistryName).azurecr.io/jaws/browser@$digest"
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
            '--environment',$names.EnvironmentName,'--image',$pinnedImage,'--ingress','external','--target-port','8089',
            '--system-assigned','--min-replicas','0','--max-replicas','3','--cpu','1.0','--memory','2.0Gi',
            '--registry-server',"$($Context.RegistryName).azurecr.io",'--registry-identity','system','--output','json','--only-show-errors',
            '--env-vars') + $envVars)
        $writes++
    } elseif ((Get-JawsBrowserProperty $app @('properties','configuration','ingress','external')) -ne $true) {
        $null = Invoke-JawsBrowserAz -Arguments @('containerapp','ingress','enable','--subscription',$sub,'--resource-group',$rg,'--name',$names.AppName,'--type','external','--target-port','8089','--output','json','--only-show-errors')
        $writes++
        $app = Invoke-JawsBrowserAz -Arguments @('containerapp','show','--subscription',$sub,'--resource-group',$rg,'--name',$names.AppName,'--output','json','--only-show-errors')
    }
    $principal = [string](Get-JawsBrowserProperty $app @('identity','principalId'))
    if ([string]::IsNullOrWhiteSpace($principal)) {
        throw 'JAWS-STEP-D-030: The browser Container App has no managed identity.'
    }
    $vaultId = "/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.KeyVault/vaults/$($Context.KeyVaultName)"
    $signedIn = Invoke-JawsBrowserAz -Arguments @('ad','signed-in-user','show','--output','json','--only-show-errors')
    $installerId = [string](Get-JawsBrowserProperty $signedIn @('id'))
    if ([string]::IsNullOrWhiteSpace($installerId)) {
        throw 'JAWS-STEP-D-030: The signed-in account has no object id, so Key Vault secrets were not written.'
    }
    $installerRoles = @(Invoke-JawsBrowserAz -Arguments @('role','assignment','list','--subscription',$sub,'--assignee-object-id',$installerId,'--scope',$vaultId,'--output','json','--only-show-errors'))
    $hasOfficer = @($installerRoles | Where-Object { $_ -and [string]$_.roleDefinitionName -eq 'Key Vault Secrets Officer' }).Count -gt 0
    if (-not $hasOfficer) {
        $null = Invoke-JawsBrowserAz -Arguments @('role','assignment','create','--subscription',$sub,'--assignee-object-id',$installerId,'--assignee-principal-type','User','--role','Key Vault Secrets Officer','--scope',$vaultId,'--output','json','--only-show-errors')
        $writes++
    }
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
    if ([string]::IsNullOrWhiteSpace($fqdn) -or $fqdn -match '\.internal\.') {
        throw 'JAWS-STEP-D-030: The browser Container App did not return a virtual-network endpoint. An .internal. name is hidden from the VNet, and a public environment is not used.'
    }
    $endpoint = "https://$fqdn"
    $toolbox = Publish-JawsBrowserToolboxVersion -Context $Context -ToolboxName $names.ToolboxName -ServerUrl $endpoint -InstallerRoot $InstallerRoot
    $writes += $toolbox.AzureWrites
    $toolsetVersion = $toolbox.Version
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
    $latest = Get-JawsBrowserLatestVersion $summary
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
    $environment = Invoke-JawsBrowserAz -AllowMissing -Arguments @('containerapp','env','show','--subscription',[string]$Context.SubscriptionId,'--resource-group',[string]$Context.ResourceGroupName,'--name',$names.EnvironmentName,'--output','json','--only-show-errors')
    $internal = Get-JawsBrowserProperty $environment @('properties','vnetConfiguration','internal')
    $external = Get-JawsBrowserProperty $app @('properties','configuration','ingress','external')
    $fqdn = [string](Get-JawsBrowserProperty $app @('properties','configuration','ingress','fqdn'))
    if ($null -eq $app) { $reasons += 'browser Container App is missing' }
    elseif ($internal -ne $true) { $reasons += 'browser environment has a public endpoint' }
    elseif ($external -ne $true) { $reasons += 'browser app is hidden from the virtual network' }
    elseif ($fqdn -match '\.internal\.') { $reasons += 'browser endpoint is hidden from the virtual network' }
    elseif ("https://$fqdn" -cne [string]$InstallReceipt.PlaywrightServiceEndpoint) { $reasons += 'browser endpoint differs from the install receipt' }
    $toolbox = Invoke-JawsBrowserAz -AllowMissing -Arguments @('rest','--method','GET','--url',"$($Context.Endpoint)/toolboxes/$($names.ToolboxName)?api-version=v1",'--resource','https://ai.azure.com','--output','json','--only-show-errors')
    $version = [string](Get-JawsBrowserProperty $toolbox @('default_version'))
    if ([string]::IsNullOrWhiteSpace($version)) { $reasons += 'browser toolbox is missing' }
    elseif ($version -cne [string]$InstallReceipt.BrowserToolsetVersion) { $reasons += 'browser toolset version differs from the install receipt' }
    else {
        $versionDoc = Invoke-JawsBrowserAz -AllowMissing -Arguments @('rest','--method','GET','--url',"$($Context.Endpoint)/toolboxes/$($names.ToolboxName)/versions/${version}?api-version=v1",'--resource','https://ai.azure.com','--output','json','--only-show-errors')
        $server = Get-JawsBrowserToolboxServer $versionDoc
        if ($server -cne [string]$InstallReceipt.PlaywrightServiceEndpoint) { $reasons += 'browser toolbox points at a different endpoint' }
    }
    $summary = Invoke-JawsBrowserAz -Arguments @('rest','--method','GET','--url',"$($Context.Endpoint)/agents/$($Context.SupervisorAgent)?api-version=v1",'--resource','https://ai.azure.com','--output','json','--only-show-errors')
    $latest = Get-JawsBrowserLatestVersion $summary
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

function Test-JawsBrowserToolName {
    param([string]$Name,[Parameter(Mandatory)][string]$Operation)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    if ($Name -ceq $Operation) { return $true }
    return ($Name.EndsWith(".$Operation") -or $Name.EndsWith("_$Operation"))
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
        $parsed = ConvertFrom-JawsBrowserJson (($raw | Out-String))
        if ($null -eq $parsed) {
            throw "${FailureCode}: Supervisor invocation returned no JSON. $($raw | Out-String)"
        }
        return $parsed
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
    $latest = Get-JawsBrowserLatestVersion $summary
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
            '--no-logs',
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
    $foundry = Invoke-JawsBrowserAz -AllowMissing -Arguments @('cognitiveservices','account','show','--subscription',[string]$stepB.SubscriptionId,'--resource-group',[string]$stepB.ResourceGroupName,'--name',[string]$stepB.FoundryAccountName,'--output','json','--only-show-errors')
    if ([string]::IsNullOrWhiteSpace((Test-JawsFoundryAgentInjection $foundry))) {
        throw 'JAWS-STEP-D-043: Foundry has no agent virtual-network injection, so it cannot reach the private browser. Run Install-JawsFoundryPrivateNetwork.ps1 -AcknowledgeFoundryReplacement. No Supervisor call was made.'
    }
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
    $opens = @($calls | Where-Object { Test-JawsBrowserToolName -Name $_.Name -Operation 'browser_open' })
    $navigates = @($calls | Where-Object { Test-JawsBrowserToolName -Name $_.Name -Operation 'browser_navigate' })
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
    $prompt = "Call browser_open once and use the session it returns. Navigate to $Url with browser_navigate, extract one value, and include the marker EXTRACTED_VALUE. Then navigate to https://blocked.invalid/not-allowed, which is not on the allow-list, and include allow_list_rejected. Then call browser_close. Do not log a password."
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
        ReadyForNextStep = $true
        NextStep = 'Step E Validate'
        AzureWrites = 0
    }
}

Export-ModuleMember -Function Get-JawsBrowserToolNames,Get-JawsBrowserNames,Install-JawsStepDBrowser,Install-JawsFoundryPrivateNetwork,Update-JawsBrowserAllowList,Get-JawsBrowserAllowListPath,Confirm-JawsStepDBrowser,Publish-JawsSupervisorBrowserImage,Invoke-JawsBrowserPrivatePath,Invoke-JawsBrowserCapability
