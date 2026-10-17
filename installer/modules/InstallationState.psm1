# JAWS 0.4.6 - authoritative, operator-maintained desired installation state.
Set-StrictMode -Version Latest
function Read-JawsInstallationState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $state=Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -ErrorAction Stop
    if ($state.SchemaVersion -notin @('1.1') -or $state.Platform -ne 'JAWS' -or $null -eq $state.Resources) {
        throw 'JAWS-STATE-001: Unsupported or malformed JAWS installation state (expected 1.1).'
    }
    $subscriptionGuid=[guid]::Empty
    if (-not [guid]::TryParse([string]$state.SubscriptionId,[ref]$subscriptionGuid)) {
        throw 'JAWS-STATE-001: Installation state contains an invalid Azure subscription ID.'
    }
    if (-not [string]$state.ResourceGroupName -or -not [string]$state.EnvironmentName) {
        throw 'JAWS-STATE-001: Installation state must identify its environment and resource group.'
    }
    $supported=@('Microsoft.CognitiveServices/accounts','Microsoft.CognitiveServices/accounts/projects',
        'Microsoft.CognitiveServices/accounts/deployments','Microsoft.KeyVault/vaults')
    $keys=@{}
    foreach($r in @($state.Resources)) {
        if (-not $r.Name -or $r.Type -notin $supported -or [string]$r.Name -match '(?i)tight.?fang|tfang') {
            throw 'JAWS-STATE-004: Invalid or non-JAWS resource in installation state.'
        }
        $key=([string]$r.Type + '|' + [string]$r.Name).ToLowerInvariant()
        if ($keys.ContainsKey($key)) { throw "JAWS-STATE-005: Duplicate state resource $key" }
        $keys[$key]=$true
    }
    return $state
}
function Compare-JawsTenantScanToState {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$State,[Parameter(Mandatory)]$Scan)
    $comparisons=@()
    foreach($r in @($State.Resources)) {
        $matching=@($Scan.Candidates | Where-Object {
            $_.Platform -eq 'JAWS' -and $_.SubscriptionId -ieq $State.SubscriptionId -and
            $_.ResourceGroup -ieq $State.ResourceGroupName -and $_.Type -ieq $r.Type -and
            ($_.Name -ieq $r.Name -or $_.Name -like "*/$($r.Name)")
        })
        # Tenant heuristics may miss resources without a JAWS name/tag.
        # A missing match is NOT proof of absence; targeted discovery follows.
        $classification=if ($matching.Count -eq 1) { 'CandidateLocated' } elseif ($matching.Count -gt 1) {'Ambiguous'} else {'NotInTenantCandidateScan'}
        $observedId=if ($matching.Count -eq 1) { [string]$matching[0].ResourceId } else { $null }
        $idMatch=if ($r.ResourceId -and $observedId) { $r.ResourceId -ieq $observedId } else { $null }
        if ($idMatch -eq $false) { $classification='IdentityDrift' }
        $comparisons += [pscustomobject]@{Name=$r.Name;Type=$r.Type;Status=$classification;ExpectedResourceId=$r.ResourceId;ObservedResourceId=$observedId}
    }
    return @($comparisons)
}
function Compare-JawsTargetDiscoveryToState {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$State,[Parameter(Mandatory)][object[]]$Results)
    $comparisons=@()
    foreach($expected in @($State.Resources)) {
        $matching=@($Results | Where-Object { $_.Name -ieq $expected.Name -and $_.Type -ieq $expected.Type })
        if ($matching.Count -ne 1) { throw "JAWS-STATE-006: Expected exactly one targeted discovery result for $($expected.Name)." }
        $actual=$matching[0]
        $status=if ($actual.Status -eq 'Missing') {'Missing'} else {'Match'}
        if ($actual.Status -eq 'Discovered' -and $expected.ResourceId -and $actual.ResourceId -ine $expected.ResourceId) { $status='IdentityDrift' }
        if ($actual.Status -eq 'Discovered' -and $expected.Type -eq 'Microsoft.CognitiveServices/accounts/deployments') {
            $ec=$expected.ExpectedConfiguration
            $oc=$actual.ObservedConfiguration
            if ($ec.ModelVersion -and [string]$oc.ModelVersion -cne [string]$ec.ModelVersion) { $status='ConfigurationDrift' }
            if ($ec.ModelName -and [string]$oc.ModelName -cne [string]$ec.ModelName) { $status='ConfigurationDrift' }
        }
        $comparisons += [pscustomobject]@{Name=$expected.Name;Type=$expected.Type;Status=$status;ExpectedResourceId=$expected.ResourceId;ObservedResourceId=$actual.ResourceId}
    }
    return @($comparisons)
}
Export-ModuleMember -Function Read-JawsInstallationState,Compare-JawsTenantScanToState,Compare-JawsTargetDiscoveryToState
