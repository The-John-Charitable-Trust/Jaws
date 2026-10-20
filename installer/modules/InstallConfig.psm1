# Install-time ServiceNow and Datadog parameters, and the FedRAMP Moderate inventory.
# Secret values are stored in Key Vault. The generated JSON config records names and posture only.
Set-StrictMode -Version Latest

function Get-JawsInstallConfigFields {
    [CmdletBinding()]
    param()
    return @(
        'ServiceNowUrl',
        'ServiceNowUsername',
        'ServiceNowPassword',
        'DatadogSite',
        'DatadogApiKey',
        'DatadogAppKey',
        'DefaultVirtualMachineResourceId'
    )
}

function Read-JawsInstallConfigFile {
    [CmdletBinding()]
    param([string]$Path)
    $values = @{}
    foreach ($field in (Get-JawsInstallConfigFields)) { $values[$field] = '' }
    if ([string]::IsNullOrWhiteSpace($Path)) { return $values }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "JAWS-INSTALL-CONFIG-001: Install config was not found at $Path."
    }
    $config = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    foreach ($field in (Get-JawsInstallConfigFields)) {
        $property = $config.PSObject.Properties[$field]
        if ($null -ne $property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
            $values[$field] = [string]$property.Value
        }
    }
    return $values
}

function ConvertTo-JawsInstallSkipFlag {
    [CmdletBinding()]
    param([string]$Name, $Value)
    if ($null -eq $Value) { return $false }
    if ($Value -is [bool]) { return [bool]$Value }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $false }
    if ($text -match '^(?i:true|yes|skip)$') { return $true }
    if ($text -match '^(?i:false|no)$') { return $false }
    throw "JAWS-INSTALL-CONFIG-004: $Name must be true or false."
}

function Read-JawsInstallSkipFlags {
    [CmdletBinding()]
    param([string]$Path)
    $flags = @{ SkipServiceNow = $false; SkipDatadog = $false }
    if ([string]::IsNullOrWhiteSpace($Path)) { return $flags }
    $config = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    foreach ($name in @($flags.Keys)) {
        $property = $config.PSObject.Properties[$name]
        if ($null -ne $property) { $flags[$name] = ConvertTo-JawsInstallSkipFlag -Name $name -Value $property.Value }
    }
    return $flags
}

function Read-JawsInstallPrompt {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Label, [switch]$Secret)
    if ($Secret) {
        $secure = Read-Host -Prompt $Label -AsSecureString
        return [System.Net.NetworkCredential]::new('', $secure).Password
    }
    return [string](Read-Host -Prompt $Label)
}

function Resolve-JawsInstallChoice {
    [CmdletBinding()]
    param([string]$Answer)
    $text = [string]$Answer
    if ($text -match '^(?i:yes|y)$') { return 'configure' }
    if ($text -match '^(?i:skip|no|n)$') { return 'skip' }
    throw 'JAWS-INSTALL-CONFIG-004: Answer yes to configure, or skip to leave it unset.'
}

function Resolve-JawsInstallObservability {
    [CmdletBinding()]
    param(
        [string]$InstallConfig,
        [hashtable]$Parameters,
        [switch]$NonInteractive,
        [switch]$SkipServiceNow,
        [switch]$SkipDatadog,
        [scriptblock]$Prompter
    )
    $values = Read-JawsInstallConfigFile -Path $InstallConfig
    if ($null -ne $Parameters) {
        foreach ($field in (Get-JawsInstallConfigFields)) {
            if ($Parameters.ContainsKey($field) -and -not [string]::IsNullOrWhiteSpace([string]$Parameters[$field])) {
                $values[$field] = [string]$Parameters[$field]
            }
        }
    }
    $flags = Read-JawsInstallSkipFlags -Path $InstallConfig
    $skipServiceNow = [bool]$flags.SkipServiceNow -or [bool]$SkipServiceNow
    $skipDatadog = [bool]$flags.SkipDatadog -or [bool]$SkipDatadog
    $serviceNowFields = @('ServiceNowUrl', 'ServiceNowUsername', 'ServiceNowPassword')
    $datadogFields = @('DatadogSite', 'DatadogApiKey', 'DatadogAppKey', 'DefaultVirtualMachineResourceId')
    $prompt = -not $NonInteractive
    if ($prompt -and $null -eq $Prompter) {
        $prompt = -not [Console]::IsInputRedirected
        if ($prompt) {
            foreach ($frame in @(Get-PSCallStack)) {
                if ($frame.Command -in @('Invoke-Pester', 'Describe', 'Context', 'It')) {
                    $prompt = $false
                    break
                }
            }
        }
    }
    $serviceNowChoice = ''
    $datadogChoice = ''
    if ($prompt) {
        $labels = @{
            ServiceNowUrl = 'ServiceNow login URL (https://<instance>.service-now.com)'
            ServiceNowUsername = 'ServiceNow username'
            ServiceNowPassword = 'ServiceNow password'
            DatadogSite = 'Datadog site (for example us5.datadoghq.com)'
            DatadogApiKey = 'Datadog API key'
            DatadogAppKey = 'Datadog application key (optional)'
            DefaultVirtualMachineResourceId = 'Virtual machine resource id for the Datadog Agent'
        }
        $serviceNowSet = @($serviceNowFields | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$values[$_]) }).Count -gt 0
        if (-not $skipServiceNow -and -not $serviceNowSet) {
            $answer = if ($null -ne $Prompter) { [string](& $Prompter 'Configure ServiceNow during this install? (yes/skip)' $false) } else { Read-JawsInstallPrompt -Label 'Configure ServiceNow during this install? (yes/skip)' }
            $serviceNowChoice = Resolve-JawsInstallChoice -Answer $answer
            if ($serviceNowChoice -eq 'skip') { $skipServiceNow = $true }
        }
        $datadogSet = @($datadogFields | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$values[$_]) }).Count -gt 0
        if (-not $skipDatadog -and -not $datadogSet) {
            $answer = if ($null -ne $Prompter) { [string](& $Prompter 'Configure Datadog during this install? (yes/skip). Skip requires no Datadog Agent host.' $false) } else { Read-JawsInstallPrompt -Label 'Configure Datadog during this install? (yes/skip). Skip requires no Datadog Agent host.' }
            $datadogChoice = Resolve-JawsInstallChoice -Answer $answer
            if ($datadogChoice -eq 'skip') { $skipDatadog = $true }
        }
        $pending = @()
        if (-not $skipServiceNow) { $pending += $serviceNowFields }
        if (-not $skipDatadog) { $pending += $datadogFields }
        foreach ($field in $pending) {
            if ([string]::IsNullOrWhiteSpace($values[$field])) {
                $secret = $field -in @('ServiceNowPassword', 'DatadogApiKey', 'DatadogAppKey')
                if ($null -ne $Prompter) {
                    $values[$field] = [string](& $Prompter $labels[$field] $secret)
                } else {
                    $values[$field] = Read-JawsInstallPrompt -Label $labels[$field] -Secret:$secret
                }
            }
        }
    }
    if ($skipServiceNow -and @($serviceNowFields | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$values[$_]) }).Count -gt 0) {
        throw 'JAWS-INSTALL-CONFIG-002: Skip ServiceNow leaves the ServiceNow login unset. Remove the ServiceNow values, or configure ServiceNow.'
    }
    if ($skipDatadog -and @($datadogFields | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$values[$_]) }).Count -gt 0) {
        throw 'JAWS-INSTALL-CONFIG-003: Skip Datadog leaves Datadog unset and requires no Datadog Agent host. Remove the Datadog values and the virtual machine resource id, or configure Datadog.'
    }
    if ($serviceNowChoice -eq 'configure') {
        $missing = @($serviceNowFields | Where-Object { [string]::IsNullOrWhiteSpace([string]$values[$_]) }).Count -gt 0
        if ($missing) { throw 'JAWS-INSTALL-CONFIG-006: ServiceNow configuration requires the login URL, username, and password. Answer skip to leave ServiceNow unset.' }
    }
    $datadogRequested = ($datadogChoice -eq 'configure') -or (-not $skipDatadog -and @($datadogFields | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$values[$_]) }).Count -gt 0)
    if ($datadogRequested -and ([string]::IsNullOrWhiteSpace([string]$values['DatadogSite']) -or [string]::IsNullOrWhiteSpace([string]$values['DatadogApiKey']) -or [string]::IsNullOrWhiteSpace([string]$values['DefaultVirtualMachineResourceId']))) {
        throw 'JAWS-INSTALL-CONFIG-005: Datadog configuration requires the site, the API key, and the virtual machine that hosts the Datadog Agent. Answer skip when no agent host is required.'
    }
    $values['SkipServiceNow'] = $skipServiceNow
    $values['SkipDatadog'] = $skipDatadog
    return $values
}

function Get-JawsFedRampResourceInventory {
    [CmdletBinding()]
    param($Receipt, [string]$DefaultVirtualMachineResourceId, [switch]$SkipDatadog)
    $foundry = [string]$Receipt.FoundryAccountName
    $project = [string]$Receipt.ProjectName
    $vault = [string]$Receipt.KeyVaultName
    $registry = [string]$Receipt.RegistryName
    $vm = [string]$DefaultVirtualMachineResourceId
    return @(
        [pscustomobject]@{ Name = [string]$Receipt.ResourceGroupName; Type = 'Microsoft.Resources/resourceGroups'; Step = 'B'; Requirement = 'Customer region only. No public service endpoint on the group itself.'; CurrentPosture = 'Created in the selected region.'; MeetsFedrampModerate = $true },
        [pscustomobject]@{ Name = $foundry; Type = 'Microsoft.CognitiveServices/accounts'; Step = 'B'; Requirement = 'Create private: public network access disabled, private endpoint, private DNS, and agent injection on a dedicated delegated subnet. Local authentication disabled.'; CurrentPosture = 'Public egress. No network injection.'; MeetsFedrampModerate = $false },
        [pscustomobject]@{ Name = $project; Type = 'Microsoft.CognitiveServices/accounts/projects'; Step = 'B'; Requirement = 'Same private boundary as the Foundry account. No public specialist endpoint.'; CurrentPosture = 'Inherits the public Foundry account.'; MeetsFedrampModerate = $false },
        [pscustomobject]@{ Name = [string]$Receipt.ModelDeploymentName; Type = 'Microsoft.CognitiveServices/accounts/deployments'; Step = 'B'; Requirement = 'Capacity 1 on the private account. No account key.'; CurrentPosture = 'Capacity 1 on the public account.'; MeetsFedrampModerate = $false },
        [pscustomobject]@{ Name = $vault; Type = 'Microsoft.KeyVault/vaults'; Step = 'B'; Requirement = 'RBAC authorization, purge protection, public network access disabled, and a private endpoint.'; CurrentPosture = 'RBAC and purge protection. Public network access remains enabled.'; MeetsFedrampModerate = $false },
        [pscustomobject]@{ Name = $registry; Type = 'Microsoft.ContainerRegistry/registries'; Step = 'B'; Requirement = 'Admin disabled, Premium SKU, and a private endpoint.'; CurrentPosture = 'Admin disabled. Basic SKU. Public network access remains enabled.'; MeetsFedrampModerate = $false },
        [pscustomobject]@{ Name = "$project-identity"; Type = 'SystemAssigned'; Step = 'B'; Requirement = 'System-assigned project identity. No shared account key.'; CurrentPosture = 'System-assigned project identity.'; MeetsFedrampModerate = $true },
        [pscustomobject]@{ Name = $(if ($Receipt.PSObject.Properties['AgentName'] -and -not [string]::IsNullOrWhiteSpace([string]$Receipt.AgentName)) { [string]$Receipt.AgentName } else { 'jaws-supervisor' }); Type = 'Microsoft.CognitiveServices/accounts/projects/agents'; Step = 'B'; Requirement = 'Hosted Supervisor on the private Foundry account. No public specialist endpoint.'; CurrentPosture = 'Hosted on the public-egress account.'; MeetsFedrampModerate = $false },
        [pscustomobject]@{ Name = "$foundry-diagnostics"; Type = 'Microsoft.Insights/diagnosticSettings'; Step = 'B'; Requirement = 'RequestResponse and Audit logs to a customer workspace.'; CurrentPosture = 'Not created.'; MeetsFedrampModerate = $false },
        [pscustomobject]@{ Name = 'jaws-br-vnet'; Type = 'Microsoft.Network/virtualNetworks'; Step = 'D'; Requirement = 'Delegated subnets, NSG, and private DNS for the internal browser and a private Foundry account.'; CurrentPosture = 'Not created by Step B.'; MeetsFedrampModerate = $false },
        [pscustomobject]@{ Name = 'jaws-browser'; Type = 'Microsoft.App/containerApps'; Step = 'D'; Requirement = 'Internal load balancer only. No public ingress.'; CurrentPosture = 'Not created by Step B.'; MeetsFedrampModerate = $false },
        $(if ($SkipDatadog) {
            [pscustomobject]@{ Name = 'datadog-agent-host'; Type = 'Microsoft.Compute/virtualMachines'; Step = 'G'; Requirement = 'A Datadog Agent host is required only when Datadog is configured.'; CurrentPosture = 'Datadog was skipped. No Datadog Agent host is required.'; MeetsFedrampModerate = $true }
        } else {
            [pscustomobject]@{ Name = $(if ([string]::IsNullOrWhiteSpace($vm)) { 'default-virtual-machine' } else { $vm }); Type = 'Microsoft.Compute/virtualMachines'; Step = 'G'; Requirement = 'The Datadog Agent runs on the named default virtual machine. Management stays on a private network path.'; CurrentPosture = $(if ([string]::IsNullOrWhiteSpace($vm)) { 'Default virtual machine was not supplied.' } else { 'Resource id recorded. Datadog Agent is not installed.' }); MeetsFedrampModerate = $false }
        })
    )
}

function New-JawsInstallConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Receipt,
        [Parameter(Mandatory)][hashtable]$Observability,
        [string[]]$StoredSecretNames,
        [switch]$SkipServiceNow,
        [switch]$SkipDatadog
    )
    $names = [pscustomobject]@{
        ServiceNowUrl = 'jaws-servicenow-url'
        ServiceNowUsername = 'jaws-servicenow-username'
        ServiceNowPassword = 'jaws-servicenow-password'
        DatadogApiKey = 'jaws-datadog-api-key'
        DatadogAppKey = 'jaws-datadog-app-key'
        DatadogSite = 'jaws-datadog-site'
        DefaultVirtualMachine = 'jaws-datadog-default-vm'
    }
    $stored = @($StoredSecretNames)
    $resources = @(Get-JawsFedRampResourceInventory -Receipt $Receipt -DefaultVirtualMachineResourceId ([string]$Observability['DefaultVirtualMachineResourceId']) -SkipDatadog:$SkipDatadog)
    $open = @($resources | Where-Object { -not $_.MeetsFedrampModerate })
    [pscustomobject]@{
        SchemaVersion = '1.0'
        EnvironmentName = [string]$Receipt.EnvironmentName
        KeyVaultName = [string]$Receipt.KeyVaultName
        Observability = [pscustomobject]@{
            ServiceNow = [pscustomobject]@{
                UrlSecret = $names.ServiceNowUrl
                UsernameSecret = $names.ServiceNowUsername
                PasswordSecret = $names.ServiceNowPassword
                Skipped = [bool]$SkipServiceNow
                Configured = (-not $SkipServiceNow -and ($stored -contains $names.ServiceNowUrl))
            }
            Datadog = [pscustomobject]@{
                ApiKeySecret = $names.DatadogApiKey
                AppKeySecret = $names.DatadogAppKey
                SiteSecret = $names.DatadogSite
                DefaultVirtualMachineSecret = $names.DefaultVirtualMachine
                Skipped = [bool]$SkipDatadog
                Configured = (-not $SkipDatadog -and ($stored -contains $names.DatadogApiKey))
                DefaultVirtualMachineConfigured = (-not $SkipDatadog -and ($stored -contains $names.DefaultVirtualMachine))
                AgentHostRequired = (-not $SkipDatadog -and ($stored -contains $names.DatadogApiKey))
            }
        }
        FedRampModerate = [pscustomobject]@{
            Profile = 'Moderate'
            Accepted = $false
            CustomerInstallationAccepted = $false
            Statement = 'Customer configuration record for the resources this install creates or depends on. This file is not a FedRAMP authorization of JAWS and is not an Azure platform authorization.'
            OpenResourceCount = $open.Count
            Resources = $resources
        }
    }
}

function Save-JawsInstallConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$EnvironmentName,
        [Parameter(Mandatory)][string]$InstallerRoot,
        [string]$InstallConfig,
        [hashtable]$Parameters,
        [switch]$NonInteractive,
        [switch]$SkipServiceNow,
        [switch]$SkipDatadog,
        [switch]$AcknowledgeStepBInstall,
        [scriptblock]$Prompter
    )
    $values = Resolve-JawsInstallObservability -InstallConfig $InstallConfig -Parameters $Parameters -NonInteractive:$NonInteractive -SkipServiceNow:$SkipServiceNow -SkipDatadog:$SkipDatadog -Prompter $Prompter
    $stored = @()
    $secretFields = @(Get-JawsInstallConfigFields)
    $hasValue = @($secretFields | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$values[$_]) }).Count -gt 0
    if ($hasValue) {
        Import-Module (Join-Path $InstallerRoot 'modules/ObservabilityIntegration.psm1') -Force
        $result = Set-JawsObservabilityIntegration -EnvironmentName $EnvironmentName -InstallerRoot $InstallerRoot -AcknowledgeObservabilitySecrets:$AcknowledgeStepBInstall -ServiceNowUrl $values['ServiceNowUrl'] -ServiceNowUsername $values['ServiceNowUsername'] -ServiceNowPassword $values['ServiceNowPassword'] -DatadogApiKey $values['DatadogApiKey'] -DatadogAppKey $values['DatadogAppKey'] -DatadogSite $values['DatadogSite'] -DefaultVirtualMachineResourceId $values['DefaultVirtualMachineResourceId']
        $stored = @($result.SecretNames)
    }
    $receiptPath = Join-Path $InstallerRoot ".local/jaws-step-b-install.$EnvironmentName.generated.json"
    $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
    $config = New-JawsInstallConfiguration -Receipt $receipt -Observability $values -StoredSecretNames $stored -SkipServiceNow:([bool]$values['SkipServiceNow']) -SkipDatadog:([bool]$values['SkipDatadog'])
    $local = Join-Path $InstallerRoot '.local'
    if (-not (Test-Path -LiteralPath $local)) { $null = New-Item -ItemType Directory -Path $local -Force }
    $path = Join-Path $local "jaws-install.$EnvironmentName.generated.json"
    $config | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding utf8
    [pscustomobject]@{
        Path = $path
        ServiceNowConfigured = [bool]$config.Observability.ServiceNow.Configured
        ServiceNowSkipped = [bool]$config.Observability.ServiceNow.Skipped
        DatadogConfigured = [bool]$config.Observability.Datadog.Configured
        DatadogSkipped = [bool]$config.Observability.Datadog.Skipped
        DefaultVirtualMachineConfigured = [bool]$config.Observability.Datadog.DefaultVirtualMachineConfigured
        DatadogAgentHostRequired = [bool]$config.Observability.Datadog.AgentHostRequired
        FedRampModerate = [bool]$config.FedRampModerate.Accepted
        OpenResourceCount = [int]$config.FedRampModerate.OpenResourceCount
    }
}

Export-ModuleMember -Function Get-JawsInstallConfigFields, Read-JawsInstallConfigFile, Read-JawsInstallSkipFlags, Resolve-JawsInstallObservability, Get-JawsFedRampResourceInventory, New-JawsInstallConfiguration, Save-JawsInstallConfiguration
