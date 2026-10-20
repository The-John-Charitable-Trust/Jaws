# Store ServiceNow and Datadog settings in the Step B Key Vault.
# Secret values stay out of receipts, console output, and git.
Set-StrictMode -Version Latest

function Get-JawsObservabilitySecretNames {
    [CmdletBinding()]
    param()
    [pscustomobject]@{
        ServiceNowUrl = 'jaws-servicenow-url'
        ServiceNowUsername = 'jaws-servicenow-username'
        ServiceNowPassword = 'jaws-servicenow-password'
        DatadogApiKey = 'jaws-datadog-api-key'
        DatadogAppKey = 'jaws-datadog-app-key'
        DatadogSite = 'jaws-datadog-site'
        DefaultVirtualMachine = 'jaws-datadog-default-vm'
    }
}

function Get-JawsObservabilityDatadogSites {
    [CmdletBinding()]
    param()
    return @(
        'datadoghq.com',
        'us3.datadoghq.com',
        'us5.datadoghq.com',
        'ap1.datadoghq.com',
        'datadoghq.eu',
        'ddog-gov.com'
    )
}

function Resolve-JawsObservabilityVault {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$EnvironmentName,
        [Parameter(Mandatory)][string]$InstallerRoot
    )
    if ($EnvironmentName -ceq 'dev') {
        throw 'JAWS-OBS-002: The accepted dev project does not receive ServiceNow or Datadog secrets.'
    }
    if ($EnvironmentName -notmatch '^[a-z][a-z0-9-]{1,20}$') {
        throw 'JAWS-OBS-002: Environment name must be 2-21 characters, start with a letter, and use lowercase letters, digits, and hyphens.'
    }
    $receiptPath = Join-Path $InstallerRoot ".local/jaws-step-b-install.$EnvironmentName.generated.json"
    if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) {
        throw "JAWS-OBS-005: Step B receipt is required before observability secrets can be stored ($receiptPath)."
    }
    $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
    if ([string]$receipt.Status -cne 'STEP_B_INSTALLED' -or [string]$receipt.EnvironmentName -cne $EnvironmentName) {
        throw 'JAWS-OBS-005: Step B receipt is not STEP_B_INSTALLED for this environment.'
    }
    foreach ($reserved in @('rg-aiops-lab', 'jaws-foundry-dev', 'kv-jaws-dev-001', 'jawsregistrydev001')) {
        foreach ($value in @([string]$receipt.ResourceGroupName, [string]$receipt.FoundryAccountName, [string]$receipt.KeyVaultName, [string]$receipt.RegistryName)) {
            if ($value -ceq $reserved) { throw "JAWS-OBS-002: Refusing dev resource '$reserved'." }
        }
    }
    [pscustomobject]@{
        ReceiptPath = $receiptPath
        SubscriptionId = [string]$receipt.SubscriptionId
        ResourceGroupName = [string]$receipt.ResourceGroupName
        Location = $(if ($receipt.PSObject.Properties['Location']) { [string]$receipt.Location } else { '' })
        KeyVaultName = [string]$receipt.KeyVaultName
        EnvironmentName = $EnvironmentName
    }
}

function Invoke-JawsObservabilityAz {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Arguments)
    $output = & az @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "JAWS-OBS-010: az $($Arguments -join ' ') failed. $($output | Out-String)"
    }
    $text = ($output | Out-String)
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    return ($text | ConvertFrom-Json)
}

function Set-JawsObservabilityIntegration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$EnvironmentName,
        [Parameter(Mandatory)][string]$InstallerRoot,
        [switch]$AcknowledgeObservabilitySecrets,
        [string]$ServiceNowUrl = '',
        [string]$ServiceNowUsername = '',
        [string]$ServiceNowPassword = '',
        [string]$DatadogApiKey = '',
        [string]$DatadogAppKey = '',
        [string]$DatadogSite = '',
        [string]$DefaultVirtualMachineResourceId = ''
    )
    if (-not $AcknowledgeObservabilitySecrets) {
        throw 'JAWS-OBS-001: Observability secrets require -AcknowledgeObservabilitySecrets. No Key Vault write was made.'
    }
    $names = Get-JawsObservabilitySecretNames
    $serviceNow = @(@($ServiceNowUrl, $ServiceNowUsername, $ServiceNowPassword) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($serviceNow.Count -gt 0 -and $serviceNow.Count -lt 3) {
        throw 'JAWS-OBS-003: ServiceNow login URL, username, and password are stored together.'
    }
    $serviceNowUrlValue = ''
    if ($serviceNow.Count -eq 3) {
        $trimmedUrl = $ServiceNowUrl.Trim()
        if ($trimmedUrl -notmatch '^https://(?<host>[a-z0-9-]+\.service-now\.com)(/.*)?$') {
            throw 'JAWS-OBS-004: ServiceNow login URL must be https://<instance>.service-now.com.'
        }
        $serviceNowUrlValue = "https://$($Matches.host)"
        if ($ServiceNowUsername -match '[\r\n]' -or $ServiceNowPassword -match '[\r\n]' -or [string]::IsNullOrWhiteSpace($ServiceNowUsername) -or [string]::IsNullOrWhiteSpace($ServiceNowPassword)) {
            throw 'JAWS-OBS-003: ServiceNow username and password are required with the login URL.'
        }
    }
    $datadog = @(@($DatadogApiKey, $DatadogAppKey, $DatadogSite) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($datadog.Count -gt 0 -and [string]::IsNullOrWhiteSpace($DatadogApiKey)) {
        throw 'JAWS-OBS-006: A Datadog application key or site requires the API key.'
    }
    if (-not [string]::IsNullOrWhiteSpace($DatadogApiKey) -and [string]::IsNullOrWhiteSpace($DatadogSite)) {
        throw 'JAWS-OBS-006: Datadog API key requires the Datadog site.'
    }
    if (-not [string]::IsNullOrWhiteSpace($DatadogSite)) {
        $site = $DatadogSite.Trim().TrimEnd('/')
        if ((Get-JawsObservabilityDatadogSites) -notcontains $site) {
            throw 'JAWS-OBS-006: Datadog site must be one of the Datadog public sites.'
        }
        $DatadogSite = $site
    }
    $vmId = $DefaultVirtualMachineResourceId.Trim()
    if (-not [string]::IsNullOrWhiteSpace($vmId) -and $vmId -notmatch '^/subscriptions/[0-9a-fA-F-]{36}/resourceGroups/[^/]+/providers/Microsoft\.Compute/virtualMachines/[A-Za-z0-9._-]+$') {
        throw 'JAWS-OBS-007: Default virtual machine must be a Microsoft.Compute/virtualMachines resource id.'
    }
    if ($serviceNow.Count -eq 0 -and [string]::IsNullOrWhiteSpace($DatadogApiKey) -and [string]::IsNullOrWhiteSpace($vmId)) {
        throw 'JAWS-OBS-008: Supply the ServiceNow login, the Datadog parameters, or the default virtual machine.'
    }
    $vault = Resolve-JawsObservabilityVault -EnvironmentName $EnvironmentName -InstallerRoot $InstallerRoot
    if (-not [string]::IsNullOrWhiteSpace($vmId)) {
        $vmIdentity = [regex]::Match($vmId, '^/subscriptions/(?<sub>[0-9a-fA-F-]{36})/resourceGroups/(?<rg>[^/]+)/providers/Microsoft\.Compute/virtualMachines/(?<name>[A-Za-z0-9._-]+)$')
        if ($vmIdentity.Groups['sub'].Value -ine $vault.SubscriptionId -or $vmIdentity.Groups['rg'].Value -ine $vault.ResourceGroupName) {
            throw "JAWS-OBS-009: The Datadog Agent host must already exist in subscription $($vault.SubscriptionId) and resource group $($vault.ResourceGroupName), in this environment's location. A virtual machine in another resource group is not this environment."
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$vault.Location)) {
            $machine = Invoke-JawsObservabilityAz -Arguments @('vm','show','--subscription',$vault.SubscriptionId,'--resource-group',$vault.ResourceGroupName,'--name',$vmIdentity.Groups['name'].Value,'--output','json','--only-show-errors')
            $machineLocation = [string]$machine.location
            if ([string]::IsNullOrWhiteSpace($machineLocation) -or $machineLocation -ine [string]$vault.Location) {
                throw "JAWS-OBS-009: The Datadog Agent host is in '$machineLocation'. This environment is in '$($vault.Location)'."
            }
        }
    }
    $values = [ordered]@{}
    if ($serviceNow.Count -eq 3) {
        $values[$names.ServiceNowUrl] = $serviceNowUrlValue
        $values[$names.ServiceNowUsername] = $ServiceNowUsername
        $values[$names.ServiceNowPassword] = $ServiceNowPassword
    }
    if (-not [string]::IsNullOrWhiteSpace($DatadogApiKey)) {
        $values[$names.DatadogApiKey] = $DatadogApiKey
        $values[$names.DatadogSite] = $DatadogSite
        if (-not [string]::IsNullOrWhiteSpace($DatadogAppKey)) { $values[$names.DatadogAppKey] = $DatadogAppKey }
    }
    if (-not [string]::IsNullOrWhiteSpace($vmId)) { $values[$names.DefaultVirtualMachine] = $vmId }
    $vaultId = "/subscriptions/$($vault.SubscriptionId)/resourceGroups/$($vault.ResourceGroupName)/providers/Microsoft.KeyVault/vaults/$($vault.KeyVaultName)"
    $signedIn = Invoke-JawsObservabilityAz -Arguments @('ad','signed-in-user','show','--output','json','--only-show-errors')
    $installerId = [string]$signedIn.id
    if ([string]::IsNullOrWhiteSpace($installerId)) {
        throw 'JAWS-OBS-010: The signed-in account has no object id, so Key Vault secrets were not written.'
    }
    $roles = @(Invoke-JawsObservabilityAz -Arguments @('role','assignment','list','--subscription',$vault.SubscriptionId,'--assignee-object-id',$installerId,'--scope',$vaultId,'--output','json','--only-show-errors'))
    $writes = 0
    $hasOfficer = @($roles | Where-Object { $_ -and [string]$_.roleDefinitionName -eq 'Key Vault Secrets Officer' }).Count -gt 0
    if (-not $hasOfficer) {
        $null = Invoke-JawsObservabilityAz -Arguments @('role','assignment','create','--subscription',$vault.SubscriptionId,'--assignee-object-id',$installerId,'--assignee-principal-type','User','--role','Key Vault Secrets Officer','--scope',$vaultId,'--output','json','--only-show-errors')
        $writes++
    }
    $written = New-Object System.Collections.Generic.List[string]
    foreach ($name in @($values.Keys)) {
        $file = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
        try {
            [IO.File]::WriteAllText($file, [string]$values[$name], [Text.UTF8Encoding]::new($false))
            $null = Invoke-JawsObservabilityAz -Arguments @('keyvault','secret','set','--subscription',$vault.SubscriptionId,'--vault-name',$vault.KeyVaultName,'--name',$name,'--file',$file,'--output','json','--only-show-errors')
            $writes++
            $written.Add($name) | Out-Null
        } finally {
            Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($vmId)) {
        $null = Invoke-JawsObservabilityAz -Arguments @('tag','update','--resource-id',$vmId,'--operation','Merge','--tags','jaws-datadog-default=true','--output','json','--only-show-errors')
        $writes++
    }
    $local = Join-Path $InstallerRoot '.local'
    if (-not (Test-Path -LiteralPath $local)) { $null = New-Item -ItemType Directory -Path $local -Force }
    $evidence = Join-Path $local "jaws-observability-integration.$EnvironmentName.generated.json"
    $payload = [pscustomobject]@{
        Status = 'OBSERVABILITY_INTEGRATION_RECORDED'
        EnvironmentName = $EnvironmentName
        KeyVaultName = $vault.KeyVaultName
        SecretNames = @($written)
        ServiceNowConfigured = ($serviceNow.Count -eq 3)
        DatadogConfigured = (-not [string]::IsNullOrWhiteSpace($DatadogApiKey))
        DefaultVirtualMachineResourceId = $vmId
        DefaultVirtualMachineTag = $(if ([string]::IsNullOrWhiteSpace($vmId)) { '' } else { 'jaws-datadog-default=true' })
        DatadogAgentInstalled = $false
        CustomerInstallationAccepted = $false
        AzureWrites = $writes
    }
    $payload | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $evidence -Encoding utf8
    [pscustomobject]@{
        Evidence = $evidence
        SecretNames = @($written)
        ServiceNowConfigured = ($serviceNow.Count -eq 3)
        DatadogConfigured = (-not [string]::IsNullOrWhiteSpace($DatadogApiKey))
        DefaultVirtualMachineResourceId = $vmId
        AzureWrites = $writes
    }
}

Export-ModuleMember -Function Get-JawsObservabilitySecretNames, Get-JawsObservabilityDatadogSites, Resolve-JawsObservabilityVault, Set-JawsObservabilityIntegration
