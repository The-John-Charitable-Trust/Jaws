# JAWS Stage A - persistent, ownership-aware resource inventory
Set-StrictMode -Version Latest

function New-JawsResourceManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SubscriptionId,
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$EnvironmentName,
        [string]$ExistingPath
    )
    if ($ExistingPath -and (Test-Path -LiteralPath $ExistingPath)) {
        $m = Get-Content -LiteralPath $ExistingPath -Raw | ConvertFrom-Json -ErrorAction Stop
        if ($m.SchemaVersion -ne '1.0' -or
            $m.SubscriptionId -ine $SubscriptionId -or
            $m.ResourceGroupName -ine $ResourceGroupName -or
            $m.EnvironmentName -ine $EnvironmentName) {
            throw "Manifest schema or environment identity mismatch. Use a distinct environment name or correct the target."
        }
        if ($null -eq $m.Resources) { throw 'Manifest lacks Resources.' }
        return $m
    }
    return [pscustomobject]@{
        SchemaVersion='1.0'
        InstallerVersion='0.3.0-stage-a'
        EnvironmentName=$EnvironmentName
        SubscriptionId=$SubscriptionId
        ResourceGroupName=$ResourceGroupName
        GeneratedAtUtc=$null
        Resources=@()
    }
}

function Add-JawsManifestResource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Manifest,
        [Parameter(Mandatory)][psobject]$DiscoveryResult,
        [psobject]$ExpectedConfiguration
    )
    if ($DiscoveryResult.Status -notin @('Discovered','Missing')) {
        throw "Unsupported discovery state: $($DiscoveryResult.Status)"
    }
    $prior = @($Manifest.Resources | Where-Object {
        $_.Name -ieq $DiscoveryResult.Name -and $_.Type -ieq $DiscoveryResult.Type
    })
    if ($prior.Count -gt 1) { throw "Duplicate manifest entries: $($DiscoveryResult.Name)" }
    $previous = if ($prior.Count) { $prior[0] } else { $null }
    $id = [string]$DiscoveryResult.ResourceId
    $oldId = if ($previous) { [string]$previous.ResourceId } else { '' }
    $same = $previous -and $id -and ($id -ieq $oldId)
    $replacement = $previous -and $id -and $oldId -and -not $same
    $created = if ($same) { [bool]$previous.CreatedByInstaller } else { $false }
    $owner = if ($created) { 'Installer' } else { 'External' }
    $observed = if ($DiscoveryResult.PSObject.Properties.Name -contains 'ObservedConfiguration') {
        $DiscoveryResult.ObservedConfiguration
    } else { [pscustomobject]@{} }
    $action = if ($DiscoveryResult.Status -eq 'Missing') { 'ReviewForCreation' }
              elseif ($replacement) { 'ReviewResourceIdentityChange' }
              else { 'ValidateForReuse' }
    $validation = 'NotEvaluated'
    if ($ExpectedConfiguration -and $DiscoveryResult.Status -eq 'Discovered') {
        $validation = 'Compliant'
        foreach ($prop in $ExpectedConfiguration.PSObject.Properties) {
            $observedValue = $observed.PSObject.Properties[$prop.Name]
            if (-not $observedValue -or [string]$observedValue.Value -cne [string]$prop.Value) {
                $validation='Drift'
                $action='ReviewConfigurationDrift'
                break
            }
        }
    }
    # A missing installer-owned resource retains historical ID and ownership
    # but never becomes an active discovered resource.
    if ($DiscoveryResult.Status -eq 'Missing' -and $previous -and [bool]$previous.CreatedByInstaller) {
        $created = $true
        $owner = 'Installer'
        $id = $oldId
    }
    $entry = [pscustomobject]@{
        Name=$DiscoveryResult.Name
        Type=$DiscoveryResult.Type
        ResourceId=if ($id) { $id } else { $null }
        Location=$DiscoveryResult.Location
        Status=$DiscoveryResult.Status
        Ownership=$owner
        CreatedByInstaller=$created
        RecommendedAction=$action
        ExpectedConfiguration=if ($ExpectedConfiguration) { $ExpectedConfiguration } else { [pscustomobject]@{} }
        ObservedConfiguration=$observed
        ValidationResult=$validation
        LastDiscoveredUtc=(Get-Date).ToUniversalTime().ToString('o')
    }
    # Persist history for identity replacement instead of silently deleting it.
    if ($replacement) {
        $history = @()
        if ($previous.PSObject.Properties.Name -contains 'PriorResourceIds') {
            $history += @($previous.PriorResourceIds)
        }
        $history += $oldId
        $entry | Add-Member -NotePropertyName PriorResourceIds -NotePropertyValue @($history | Select-Object -Unique)
    } elseif ($previous -and $previous.PSObject.Properties.Name -contains 'PriorResourceIds') {
        $entry | Add-Member -NotePropertyName PriorResourceIds -NotePropertyValue @($previous.PriorResourceIds)
    }
    $Manifest.Resources = @(
        @($Manifest.Resources) | Where-Object {
            $_.Name -ine $entry.Name -or $_.Type -ine $entry.Type
        }
    ) + @($entry)
    return $Manifest
}

function Save-JawsResourceManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Manifest,
        [Parameter(Mandatory)][string]$Path
    )
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $Manifest.GeneratedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    $tmp = Join-Path $dir ("." + [System.IO.Path]::GetFileName($Path) + "." + [guid]::NewGuid().ToString("N") + ".tmp")
    $backup = Join-Path $dir ("." + [System.IO.Path]::GetFileName($Path) + "." + [guid]::NewGuid().ToString("N") + ".bak")
    try {
        $json = $Manifest | ConvertTo-Json -Depth 30
        [System.IO.File]::WriteAllText($tmp,$json,[System.Text.UTF8Encoding]::new($false))
        # On Windows replace an existing manifest atomically; first creation is a move.
        if (Test-Path -LiteralPath $Path) {
            [System.IO.File]::Replace($tmp,$Path,$backup)
        } else {
            [System.IO.File]::Move($tmp,$Path)
        }
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
        if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Force }
    }
    return $Path
}

Export-ModuleMember -Function New-JawsResourceManifest,Add-JawsManifestResource,Save-JawsResourceManifest
