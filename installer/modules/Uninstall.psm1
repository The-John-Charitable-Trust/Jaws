# Removes one JAWS environment and every resource Steps B, C, and D create.
# Deleting the resource group is not enough. On 2026-10-20 that delete and the
# account purge both succeeded, and the Foundry data plane still returned the
# old agents when the same names were created again. Agents are force-deleted
# first. The resource group is then emptied explicitly: deployments, projects,
# role assignments, container apps, the virtual network, the registry, and
# every other resource in the group. Steps E-I create no Azure resources.
Set-StrictMode -Version Latest

function Test-JawsUninstallReservedName {
    param([string]$Value)
    $reserved = @(
        'dev',
        'rg-aiops-lab',
        'jaws-foundry-dev',
        'jaws-dev',
        'jawsregistrydev001',
        'jaws-supervisor-dev',
        'kv-jaws-dev-001'
    )
    return ($Value -and ($reserved -contains $Value))
}

function ConvertFrom-JawsUninstallJson {
    param([AllowNull()][string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $clean = $Text.Trim() -replace "$([char]27)\[[0-9;?]*[ -/]*[@-~]", ''
    if ($clean -match '^(?i:true|false)$') { return [System.Convert]::ToBoolean($clean) }
    $start = $clean.IndexOfAny(@('{', '['))
    if ($start -lt 0) { return $null }
    return ($clean.Substring($start) | ConvertFrom-Json)
}

function Invoke-JawsUninstallAz {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Arguments,[switch]$AllowMissing)
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        throw 'JAWS-PREREQ-001: Azure CLI is not installed or not on PATH.'
    }
    $output = & az @Arguments 2>&1
    $code = $LASTEXITCODE
    $text = (@($output) | ForEach-Object { "$_" }) -join "`n"
    if ($code -ne 0) {
        if ($AllowMissing -and $text -match 'MISSING|ResourceNotFound|ResourceGroupNotFound|ParentResourceNotFound|was not found|NotFound|not_found|Not Found|No deleted') {
            return $null
        }
        throw "JAWS-UNINSTALL-010: az $($Arguments -join ' ') failed ($code). $text"
    }
    return (ConvertFrom-JawsUninstallJson $text)
}

function Get-JawsUninstallNames {
    param($Payload)
    if ($null -eq $Payload) { return @() }
    $rows = @()
    if ($Payload -is [System.Array]) { $rows = @($Payload) }
    elseif ($Payload.PSObject.Properties['data'] -and $null -ne $Payload.data) { $rows = @($Payload.data) }
    elseif ($Payload.PSObject.Properties['value'] -and $null -ne $Payload.value) { $rows = @($Payload.value) }
    else { $rows = @($Payload) }
    $names = New-Object System.Collections.Generic.List[string]
    foreach ($row in $rows) {
        if ($null -eq $row) { continue }
        if ($row -is [string]) { $names.Add($row) | Out-Null; continue }
        if ($row.PSObject.Properties['name'] -and -not [string]::IsNullOrWhiteSpace([string]$row.name)) {
            $names.Add([string]$row.name) | Out-Null
        }
    }
    return @($names)
}

function Start-JawsUninstallPollSleep {
    $seconds = 10
    if ($env:JAWS_UNINSTALL_POLL_SECONDS -match '^\d+$') { $seconds = [int]$env:JAWS_UNINSTALL_POLL_SECONDS }
    if ($seconds -gt 0) { Start-Sleep -Seconds $seconds }
}

function Resolve-JawsUninstallTarget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$EnvironmentName,
        [Parameter(Mandatory)][string]$InstallerRoot,
        [string]$SubscriptionId,
        [string]$ResourceGroupName,
        [string]$Location,
        [string]$FoundryAccountName,
        [string]$ProjectName,
        [string]$KeyVaultName
    )
    if ($EnvironmentName -ceq 'dev' -or (Test-JawsUninstallReservedName $EnvironmentName)) {
        throw 'JAWS-UNINSTALL-006: Uninstall refuses the accepted dev environment.'
    }
    if ($EnvironmentName -notmatch '^[a-z][a-z0-9-]{1,20}$') {
        throw 'JAWS-UNINSTALL-002: Environment name must be 2-21 characters, start with a letter, and use lowercase letters, digits, and hyphens.'
    }
    $receiptPath = Join-Path $InstallerRoot ".local/jaws-step-b-install.$EnvironmentName.generated.json"
    $receipt = $null
    if (Test-Path -LiteralPath $receiptPath -PathType Leaf) {
        $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
    }
    $fields = @(
        @{ Name = 'SubscriptionId'; Parameter = $SubscriptionId },
        @{ Name = 'ResourceGroupName'; Parameter = $ResourceGroupName },
        @{ Name = 'Location'; Parameter = $Location },
        @{ Name = 'FoundryAccountName'; Parameter = $FoundryAccountName },
        @{ Name = 'ProjectName'; Parameter = $ProjectName },
        @{ Name = 'KeyVaultName'; Parameter = $KeyVaultName }
    )
    $values = @{}
    foreach ($field in $fields) {
        $fromReceipt = ''
        if ($null -ne $receipt -and $receipt.PSObject.Properties[$field.Name]) { $fromReceipt = [string]$receipt.$($field.Name) }
        $supplied = [string]$field.Parameter
        if (-not [string]::IsNullOrWhiteSpace($fromReceipt) -and -not [string]::IsNullOrWhiteSpace($supplied) -and $fromReceipt -ine $supplied.Trim()) {
            throw "JAWS-UNINSTALL-005: -$($field.Name) does not match the Step B receipt. Uninstall uses the receipt so it cannot delete a different resource group."
        }
        $values[$field.Name] = $(if (-not [string]::IsNullOrWhiteSpace($fromReceipt)) { $fromReceipt } else { $supplied.Trim() })
    }
    foreach ($name in @($values.Values)) {
        if (Test-JawsUninstallReservedName $name) {
            throw "JAWS-UNINSTALL-006: Uninstall refuses reserved dev resource '$name'."
        }
    }
    if ([string]::IsNullOrWhiteSpace($values.ResourceGroupName) -or [string]::IsNullOrWhiteSpace($values.SubscriptionId) -or [string]::IsNullOrWhiteSpace($values.Location)) {
        throw 'JAWS-UNINSTALL-002: Subscription, resource group, and location are required. Pass them, or keep the Step B receipt.'
    }
    [pscustomobject]@{
        EnvironmentName = $EnvironmentName
        ReceiptPath = $receiptPath
        SubscriptionId = $values.SubscriptionId
        ResourceGroupName = $values.ResourceGroupName
        Location = $values.Location
        FoundryAccountName = $values.FoundryAccountName
        ProjectName = $values.ProjectName
        KeyVaultName = $values.KeyVaultName
        Endpoint = $(if ($values.FoundryAccountName -and $values.ProjectName) { "https://$($values.FoundryAccountName).services.ai.azure.com/api/projects/$($values.ProjectName)" } else { '' })
    }
}

function Remove-JawsUninstallFoundryCollection {
    param(
        [Parameter(Mandatory)][string]$ListUrl,
        [Parameter(Mandatory)][string]$DeleteUrlPrefix,
        [string]$DeleteQuery = 'api-version=v1'
    )
    $removed = New-Object System.Collections.Generic.List[string]
    $listed = Invoke-JawsUninstallAz -AllowMissing -Arguments @('rest','--method','GET','--url',$ListUrl,'--resource','https://ai.azure.com','--output','json','--only-show-errors')
    foreach ($name in @(Get-JawsUninstallNames $listed)) {
        $deleteUrl = "$DeleteUrlPrefix/$([uri]::EscapeDataString($name))?$DeleteQuery"
        $null = Invoke-JawsUninstallAz -AllowMissing -Arguments @('rest','--method','DELETE','--url',$deleteUrl,'--resource','https://ai.azure.com','--output','json','--only-show-errors')
        $removed.Add($name) | Out-Null
    }
    return @($removed)
}

function Get-JawsUninstallField {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-JawsUninstallRows {
    param($Payload)
    if ($null -eq $Payload) { return @() }
    if ($Payload -is [System.Array]) { return @($Payload) }
    foreach ($name in @('data', 'value')) {
        $nested = Get-JawsUninstallField $Payload $name
        if ($null -ne $nested) { return @($nested) }
    }
    return @($Payload)
}

function Get-JawsUninstallResourceRank {
    param([string]$Type)
    switch -Regex ($Type) {
        '^Microsoft\.Authorization/locks$' { return 0 }
        '^Microsoft\.Insights/diagnosticSettings$' { return 5 }
        '^Microsoft\.App/containerApps$' { return 10 }
        '^Microsoft\.Compute/virtualMachines$' { return 20 }
        '^Microsoft\.App/managedEnvironments$' { return 30 }
        '^Microsoft\.Network/privateEndpoints$' { return 40 }
        '^Microsoft\.Network/networkInterfaces$' { return 50 }
        '^Microsoft\.CognitiveServices/accounts/.+' { return 60 }
        '^Microsoft\.CognitiveServices/accounts$' { return 70 }
        '^Microsoft\.KeyVault/vaults$' { return 80 }
        '^Microsoft\.Network/virtualNetworks/subnets$' { return 90 }
        '^Microsoft\.Network/virtualNetworks$' { return 100 }
        '^Microsoft\.ContainerRegistry/registries$' { return 110 }
        '^Microsoft\.ManagedIdentity/' { return 300 }
        default { return 200 }
    }
}

function Remove-JawsUninstallKeyVault {
    param(
        [Parameter(Mandatory)][string]$SubscriptionId,
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$Location,
        [Parameter(Mandatory)][string]$Name
    )
    $writes = 0
    $purge = 'absent'
    $notBefore = ''
    $vault = Invoke-JawsUninstallAz -AllowMissing -Arguments @('keyvault','show','--subscription',$SubscriptionId,'--resource-group',$ResourceGroupName,'--name',$Name,'--output','json','--only-show-errors')
    if ($null -ne $vault) {
        $null = Invoke-JawsUninstallAz -Arguments @('keyvault','delete','--subscription',$SubscriptionId,'--resource-group',$ResourceGroupName,'--name',$Name,'--output','json','--only-show-errors')
        $writes++
        $purge = 'deleted'
    }
    try {
        $null = Invoke-JawsUninstallAz -AllowMissing -Arguments @('keyvault','purge','--subscription',$SubscriptionId,'--name',$Name,'--location',$Location,'--output','json','--only-show-errors')
        if ($purge -eq 'deleted') { $purge = 'purged' }
        $writes++
    } catch {
        $message = $_.Exception.Message
        if ($message -notmatch 'purge protection|Purge Protection|MethodNotAllowed|still recoverable') { throw }
        $purge = 'blocked'
        $deletedVault = Invoke-JawsUninstallAz -AllowMissing -Arguments @('keyvault','show-deleted','--subscription',$SubscriptionId,'--name',$Name,'--location',$Location,'--output','json','--only-show-errors')
        $purgeDate = Get-JawsUninstallField (Get-JawsUninstallField $deletedVault 'properties') 'scheduledPurgeDate'
        if ($purgeDate -is [datetime]) { $notBefore = $purgeDate.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
        elseif ($null -ne $purgeDate) { $notBefore = [string]$purgeDate }
    }
    if ($purge -eq 'deleted') { $purge = 'purged' }
    [pscustomobject]@{ Writes = $writes; Purge = $purge; NotBefore = $notBefore }
}

function Merge-JawsUninstallVaultPurge {
    param($Current, $Incoming)
    if ($null -eq $Current) { return $Incoming }
    if ($Incoming.Purge -eq 'blocked' -or $Current.Purge -eq 'blocked') {
        $notBefore = [string]$Current.NotBefore
        if ([string]::IsNullOrWhiteSpace($notBefore)) { $notBefore = [string]$Incoming.NotBefore }
        return [pscustomobject]@{ Writes = ([int]$Current.Writes + [int]$Incoming.Writes); Purge = 'blocked'; NotBefore = $notBefore }
    }
    if ($Incoming.Purge -eq 'purged' -or $Current.Purge -eq 'purged') {
        return [pscustomobject]@{ Writes = ([int]$Current.Writes + [int]$Incoming.Writes); Purge = 'purged'; NotBefore = '' }
    }
    return [pscustomobject]@{ Writes = ([int]$Current.Writes + [int]$Incoming.Writes); Purge = 'absent'; NotBefore = '' }
}

function Get-JawsUninstallDatadogVmId {
    param([Parameter(Mandatory)][string]$InstallerRoot, [Parameter(Mandatory)][string]$EnvironmentName)
    $path = Join-Path $InstallerRoot ".local/jaws-observability-integration.$EnvironmentName.generated.json"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return '' }
    $doc = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    $id = Get-JawsUninstallField $doc 'DefaultVirtualMachineResourceId'
    if ([string]::IsNullOrWhiteSpace([string]$id)) { return '' }
    return [string]$id
}

function Remove-JawsUninstallLocalFiles {
    param([Parameter(Mandatory)][string]$InstallerRoot,[Parameter(Mandatory)][string]$EnvironmentName)
    $local = Join-Path $InstallerRoot '.local'
    if (-not (Test-Path -LiteralPath $local)) { return @() }
    $pattern = '\.' + [regex]::Escape($EnvironmentName) + '(\.|$)'
    $removed = New-Object System.Collections.Generic.List[string]
    Get-ChildItem -LiteralPath $local -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Name -match $pattern -and $_.Name -notlike "jaws-uninstall.$EnvironmentName.*") {
            Remove-Item -LiteralPath $_.FullName -Force
            $removed.Add($_.FullName) | Out-Null
        }
    }
    return @($removed)
}

function Invoke-JawsUninstall {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$EnvironmentName,
        [Parameter(Mandatory)][string]$InstallerRoot,
        [switch]$AcknowledgeJawsUninstall,
        [string]$SubscriptionId,
        [string]$ResourceGroupName,
        [string]$Location,
        [string]$FoundryAccountName,
        [string]$ProjectName,
        [string]$KeyVaultName
    )
    if (-not $AcknowledgeJawsUninstall) {
        throw 'JAWS-UNINSTALL-001: Uninstall requires -AcknowledgeJawsUninstall. No Azure resource is deleted.'
    }
    $target = Resolve-JawsUninstallTarget -EnvironmentName $EnvironmentName -InstallerRoot $InstallerRoot -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -Location $Location -FoundryAccountName $FoundryAccountName -ProjectName $ProjectName -KeyVaultName $KeyVaultName
    $devState = Join-Path $InstallerRoot 'config/jaws-installation-state.dev.json'
    $devBefore = ''
    if (Test-Path -LiteralPath $devState) { $devBefore = Get-Content -LiteralPath $devState -Raw }
    $writes = 0
    $agents = @()
    $toolboxes = @()
    $connections = @()
    if (-not [string]::IsNullOrWhiteSpace($target.Endpoint)) {
        $agents = @(Remove-JawsUninstallFoundryCollection -ListUrl "$($target.Endpoint)/agents?api-version=v1" -DeleteUrlPrefix "$($target.Endpoint)/agents" -DeleteQuery 'api-version=v1&force=true')
        $writes += $agents.Count
        $toolboxes = @(Remove-JawsUninstallFoundryCollection -ListUrl "$($target.Endpoint)/toolboxes?api-version=v1" -DeleteUrlPrefix "$($target.Endpoint)/toolboxes")
        $writes += $toolboxes.Count
        $connections = @(Remove-JawsUninstallFoundryCollection -ListUrl "$($target.Endpoint)/connections?api-version=v1" -DeleteUrlPrefix "$($target.Endpoint)/connections")
        $writes += $connections.Count
    }
    $sub = $target.SubscriptionId
    $rg = $target.ResourceGroupName
    $deployments = New-Object System.Collections.Generic.List[string]
    $projects = New-Object System.Collections.Generic.List[string]
    $foundryPurged = $false
    if (-not [string]::IsNullOrWhiteSpace($target.FoundryAccountName)) {
        foreach ($deployment in @(Get-JawsUninstallNames (Invoke-JawsUninstallAz -AllowMissing -Arguments @('cognitiveservices','account','deployment','list','--subscription',$sub,'--resource-group',$rg,'--name',$target.FoundryAccountName,'--output','json','--only-show-errors')))) {
            $null = Invoke-JawsUninstallAz -AllowMissing -Arguments @('cognitiveservices','account','deployment','delete','--subscription',$sub,'--resource-group',$rg,'--name',$target.FoundryAccountName,'--deployment-name',$deployment,'--yes','--output','json','--only-show-errors')
            $deployments.Add($deployment) | Out-Null
            $writes++
        }
        $projectNames = New-Object System.Collections.Generic.List[string]
        foreach ($projectName in @(Get-JawsUninstallNames (Invoke-JawsUninstallAz -AllowMissing -Arguments @('cognitiveservices','account','project','list','--subscription',$sub,'--resource-group',$rg,'--name',$target.FoundryAccountName,'--output','json','--only-show-errors')))) {
            $projectNames.Add($projectName) | Out-Null
        }
        if (-not [string]::IsNullOrWhiteSpace($target.ProjectName) -and -not $projectNames.Contains($target.ProjectName)) {
            $projectNames.Add($target.ProjectName) | Out-Null
        }
        foreach ($projectName in @($projectNames)) {
            $project = Invoke-JawsUninstallAz -AllowMissing -Arguments @('cognitiveservices','account','project','show','--subscription',$sub,'--resource-group',$rg,'--name',$target.FoundryAccountName,'--project-name',$projectName,'--output','json','--only-show-errors')
            if ($null -eq $project) { continue }
            $null = Invoke-JawsUninstallAz -Arguments @('cognitiveservices','account','project','delete','--subscription',$sub,'--resource-group',$rg,'--name',$target.FoundryAccountName,'--project-name',$projectName,'--yes','--output','json','--only-show-errors')
            $projects.Add($projectName) | Out-Null
            $writes++
        }
        $account = Invoke-JawsUninstallAz -AllowMissing -Arguments @('cognitiveservices','account','show','--subscription',$sub,'--resource-group',$rg,'--name',$target.FoundryAccountName,'--output','json','--only-show-errors')
        if ($null -ne $account) {
            $null = Invoke-JawsUninstallAz -Arguments @('cognitiveservices','account','delete','--subscription',$sub,'--resource-group',$rg,'--name',$target.FoundryAccountName,'--yes','--output','json','--only-show-errors')
            $writes++
        }
        $null = Invoke-JawsUninstallAz -AllowMissing -Arguments @('cognitiveservices','account','purge','--subscription',$sub,'--resource-group',$rg,'--name',$target.FoundryAccountName,'--location',$target.Location,'--output','json','--only-show-errors')
        $foundryPurged = $true
        $writes++
    }
    $apps = @(Get-JawsUninstallNames (Invoke-JawsUninstallAz -AllowMissing -Arguments @('containerapp','list','--subscription',$sub,'--resource-group',$rg,'--output','json','--only-show-errors')))
    foreach ($app in $apps) {
        $null = Invoke-JawsUninstallAz -AllowMissing -Arguments @('containerapp','delete','--subscription',$sub,'--resource-group',$rg,'--name',$app,'--yes','--output','json','--only-show-errors')
        $writes++
    }
    $environments = @(Get-JawsUninstallNames (Invoke-JawsUninstallAz -AllowMissing -Arguments @('containerapp','env','list','--subscription',$sub,'--resource-group',$rg,'--output','json','--only-show-errors')))
    foreach ($environment in $environments) {
        $null = Invoke-JawsUninstallAz -AllowMissing -Arguments @('containerapp','env','delete','--subscription',$sub,'--resource-group',$rg,'--name',$environment,'--yes','--output','json','--only-show-errors')
        $writes++
    }
    $vaultState = $null
    $vaultNames = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($target.KeyVaultName)) { $vaultNames.Add($target.KeyVaultName) | Out-Null }
    $locks = New-Object System.Collections.Generic.List[string]
    foreach ($lock in @(Get-JawsUninstallRows (Invoke-JawsUninstallAz -AllowMissing -Arguments @('lock','list','--subscription',$sub,'--resource-group',$rg,'--output','json','--only-show-errors')))) {
        $lockId = [string](Get-JawsUninstallField $lock 'id')
        if ([string]::IsNullOrWhiteSpace($lockId)) { continue }
        $null = Invoke-JawsUninstallAz -AllowMissing -Arguments @('lock','delete','--ids',$lockId,'--output','json','--only-show-errors')
        $locks.Add($lockId) | Out-Null
        $writes++
    }
    $rgScope = "/subscriptions/$sub/resourceGroups/$rg"
    $roles = New-Object System.Collections.Generic.List[string]
    foreach ($role in @(Get-JawsUninstallRows (Invoke-JawsUninstallAz -AllowMissing -Arguments @('role','assignment','list','--subscription',$sub,'--resource-group',$rg,'--include-inherited','false','--output','json','--only-show-errors')))) {
        $roleId = [string](Get-JawsUninstallField $role 'id')
        $roleScope = [string](Get-JawsUninstallField $role 'scope')
        if ([string]::IsNullOrWhiteSpace($roleId) -or -not $roleScope.StartsWith($rgScope, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        $null = Invoke-JawsUninstallAz -AllowMissing -Arguments @('role','assignment','delete','--ids',$roleId,'--output','json','--only-show-errors')
        $roles.Add($roleId) | Out-Null
        $writes++
    }
    $resourcesDeleted = New-Object System.Collections.Generic.List[string]
    $resourceRows = @(Get-JawsUninstallRows (Invoke-JawsUninstallAz -AllowMissing -Arguments @('resource','list','--subscription',$sub,'--resource-group',$rg,'--output','json','--only-show-errors')))
    $orderedResources = @($resourceRows | Sort-Object { '{0:D4}/{1}' -f (Get-JawsUninstallResourceRank ([string](Get-JawsUninstallField $_ 'type'))), [string](Get-JawsUninstallField $_ 'name') })
    foreach ($resource in $orderedResources) {
        $type = [string](Get-JawsUninstallField $resource 'type')
        $name = [string](Get-JawsUninstallField $resource 'name')
        $id = [string](Get-JawsUninstallField $resource 'id')
        if ([string]::IsNullOrWhiteSpace($type) -or [string]::IsNullOrWhiteSpace($id)) { continue }
        if ($type -eq 'Microsoft.KeyVault/vaults') {
            if (-not [string]::IsNullOrWhiteSpace($name) -and -not $vaultNames.Contains($name)) { $vaultNames.Add($name) | Out-Null }
            $resourcesDeleted.Add("$type/$name") | Out-Null
            continue
        }
        if ($type -eq 'Microsoft.CognitiveServices/accounts' -and -not [string]::IsNullOrWhiteSpace($name) -and $name -ine $target.FoundryAccountName) {
            foreach ($deployment in @(Get-JawsUninstallNames (Invoke-JawsUninstallAz -AllowMissing -Arguments @('cognitiveservices','account','deployment','list','--subscription',$sub,'--resource-group',$rg,'--name',$name,'--output','json','--only-show-errors')))) {
                $null = Invoke-JawsUninstallAz -AllowMissing -Arguments @('cognitiveservices','account','deployment','delete','--subscription',$sub,'--resource-group',$rg,'--name',$name,'--deployment-name',$deployment,'--yes','--output','json','--only-show-errors')
                $deployments.Add($deployment) | Out-Null
                $writes++
            }
            $null = Invoke-JawsUninstallAz -AllowMissing -Arguments @('cognitiveservices','account','delete','--subscription',$sub,'--resource-group',$rg,'--name',$name,'--yes','--output','json','--only-show-errors')
            $null = Invoke-JawsUninstallAz -AllowMissing -Arguments @('cognitiveservices','account','purge','--subscription',$sub,'--resource-group',$rg,'--name',$name,'--location',$target.Location,'--output','json','--only-show-errors')
            $writes += 2
        }
        $null = Invoke-JawsUninstallAz -AllowMissing -Arguments @('resource','delete','--ids',$id,'--output','json','--only-show-errors')
        $resourcesDeleted.Add("$type/$name") | Out-Null
        $writes++
    }
    foreach ($vaultName in @($vaultNames)) {
        $vaultResult = Remove-JawsUninstallKeyVault -SubscriptionId $sub -ResourceGroupName $rg -Location $target.Location -Name $vaultName
        $vaultState = Merge-JawsUninstallVaultPurge -Current $vaultState -Incoming $vaultResult
        $writes += [int]$vaultResult.Writes
    }
    if ($null -eq $vaultState) { $vaultState = [pscustomobject]@{ Purge = 'absent'; NotBefore = '' } }
    $datadogVm = Get-JawsUninstallDatadogVmId -InstallerRoot $InstallerRoot -EnvironmentName $EnvironmentName
    $datadogTagRemoved = $false
    if (-not [string]::IsNullOrWhiteSpace($datadogVm)) {
        $vmIdentity = [regex]::Match($datadogVm, '^/subscriptions/[^/]+/resourceGroups/(?<rg>[^/]+)/providers/Microsoft\.Compute/virtualMachines/[^/]+$')
        if ($vmIdentity.Success -and $vmIdentity.Groups['rg'].Value -ine $rg) {
            $null = Invoke-JawsUninstallAz -AllowMissing -Arguments @('tag','update','--resource-id',$datadogVm,'--operation','Delete','--tags','jaws-datadog-default','--output','json','--only-show-errors')
            $datadogTagRemoved = $true
            $writes++
        }
    }
    $groupExists = Invoke-JawsUninstallAz -Arguments @('group','exists','--subscription',$sub,'--name',$rg,'--output','tsv','--only-show-errors')
    $groupDeleted = ($groupExists -eq $false)
    if (-not $groupDeleted) {
        $null = Invoke-JawsUninstallAz -Arguments @('group','delete','--subscription',$sub,'--name',$rg,'--yes','--output','json','--only-show-errors')
        $writes++
        for ($attempt = 0; $attempt -lt 60; $attempt++) {
            $groupExists = Invoke-JawsUninstallAz -Arguments @('group','exists','--subscription',$sub,'--name',$rg,'--output','tsv','--only-show-errors')
            if ($groupExists -eq $false) { $groupDeleted = $true; break }
            Start-JawsUninstallPollSleep
        }
    }
    if (-not $groupDeleted) {
        throw "JAWS-UNINSTALL-011: Resource group $rg is still present. Foundry agents were already deleted. Inspect the group before retrying."
    }
    if (-not [string]::IsNullOrWhiteSpace($devBefore) -and (Get-Content -LiteralPath $devState -Raw) -ne $devBefore) {
        throw 'JAWS-UNINSTALL-012: Uninstall changed the dev installation state.'
    }
    $localRemoved = @(Remove-JawsUninstallLocalFiles -InstallerRoot $InstallerRoot -EnvironmentName $EnvironmentName)
    $local = Join-Path $InstallerRoot '.local'
    if (-not (Test-Path -LiteralPath $local)) { New-Item -ItemType Directory -Path $local | Out-Null }
    $evidence = Join-Path $local "jaws-uninstall.$EnvironmentName.generated.json"
    $payload = [pscustomobject]@{
        SchemaVersion = '1.0'
        Status = 'UNINSTALLED'
        EnvironmentName = $EnvironmentName
        SubscriptionId = $sub
        ResourceGroupName = $rg
        Location = $target.Location
        FoundryAccountName = $target.FoundryAccountName
        ProjectName = $target.ProjectName
        KeyVaultName = $target.KeyVaultName
        AgentsDeleted = @($agents)
        ToolboxesDeleted = @($toolboxes)
        ConnectionsDeleted = @($connections)
        DeploymentsDeleted = @($deployments)
        ProjectsDeleted = @($projects)
        ResourcesDeleted = @($resourcesDeleted)
        RoleAssignmentsDeleted = @($roles)
        LocksDeleted = @($locks)
        FoundryPurged = $foundryPurged
        KeyVaultPurge = [string]$vaultState.Purge
        KeyVaultPurgeNotBefore = [string]$vaultState.NotBefore
        DatadogTagRemoved = $datadogTagRemoved
        ResourceGroupDeleted = $true
        LocalFilesRemoved = $localRemoved.Count
        AzureWrites = $writes
        CustomerInstallationAccepted = $false
        CompletedAtUtc = [DateTime]::UtcNow.ToString('o')
    }
    $payload | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $evidence -Encoding utf8
    return [pscustomobject]@{ EvidencePath = $evidence; Receipt = $payload; AzureWrites = $writes }
}

Export-ModuleMember -Function Resolve-JawsUninstallTarget, Invoke-JawsUninstall
