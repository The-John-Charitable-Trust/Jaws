# Removes one JAWS environment, including Foundry agent records.
# Deleting the resource group and purging the soft-deleted account is not enough:
# on 2026-10-20 those two operations succeeded and the old agents returned
# when the same account name was created again. Agents are force-deleted first.
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
    if (-not [string]::IsNullOrWhiteSpace($target.ProjectName) -and -not [string]::IsNullOrWhiteSpace($target.FoundryAccountName)) {
        $project = Invoke-JawsUninstallAz -AllowMissing -Arguments @('cognitiveservices','account','project','show','--subscription',$sub,'--resource-group',$rg,'--name',$target.FoundryAccountName,'--project-name',$target.ProjectName,'--output','json','--only-show-errors')
        if ($null -ne $project) {
            $null = Invoke-JawsUninstallAz -Arguments @('cognitiveservices','account','project','delete','--subscription',$sub,'--resource-group',$rg,'--name',$target.FoundryAccountName,'--project-name',$target.ProjectName,'--yes','--output','json','--only-show-errors')
            $writes++
        }
    }
    $foundryPurged = $false
    if (-not [string]::IsNullOrWhiteSpace($target.FoundryAccountName)) {
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
    $vaultPurge = 'absent'
    $vaultPurgeNotBefore = ''
    if (-not [string]::IsNullOrWhiteSpace($target.KeyVaultName)) {
        $vault = Invoke-JawsUninstallAz -AllowMissing -Arguments @('keyvault','show','--subscription',$sub,'--resource-group',$rg,'--name',$target.KeyVaultName,'--output','json','--only-show-errors')
        if ($null -ne $vault) {
            $null = Invoke-JawsUninstallAz -Arguments @('keyvault','delete','--subscription',$sub,'--resource-group',$rg,'--name',$target.KeyVaultName,'--output','json','--only-show-errors')
            $writes++
        }
        try {
            $null = Invoke-JawsUninstallAz -AllowMissing -Arguments @('keyvault','purge','--subscription',$sub,'--name',$target.KeyVaultName,'--location',$target.Location,'--output','json','--only-show-errors')
            $vaultPurge = 'purged'
            $writes++
        } catch {
            $message = $_.Exception.Message
            if ($message -notmatch 'purge protection|Purge Protection|MethodNotAllowed|still recoverable') { throw }
            $vaultPurge = 'blocked'
            $deletedVault = Invoke-JawsUninstallAz -AllowMissing -Arguments @('keyvault','show-deleted','--subscription',$sub,'--name',$target.KeyVaultName,'--location',$target.Location,'--output','json','--only-show-errors')
            if ($null -ne $deletedVault -and $deletedVault.PSObject.Properties['properties'] -and $deletedVault.properties.PSObject.Properties['scheduledPurgeDate']) {
                $purgeDate = $deletedVault.properties.scheduledPurgeDate
                if ($purgeDate -is [datetime]) {
                    $vaultPurgeNotBefore = $purgeDate.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                } else {
                    $vaultPurgeNotBefore = [string]$purgeDate
                }
            }
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
        FoundryPurged = $foundryPurged
        KeyVaultPurge = $vaultPurge
        KeyVaultPurgeNotBefore = $vaultPurgeNotBefore
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
