# JAWS Stage A - Azure sign-in, tenant inventory, target selection
# Read-only Azure management API calls, except optional interactive az login.
Set-StrictMode -Version Latest

function Invoke-JawsPreflightRead {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Arguments,[Parameter(Mandatory)][string]$Operation)
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        throw 'JAWS-PREREQ-001: Azure CLI is not installed or not on PATH.'
    }
    $allowed = @('account show','account list','group list','group show','resource list')
    $joined = $Arguments -join ' '
    if (-not @($allowed | Where-Object { $joined.StartsWith($_ + ' ',[StringComparison]::OrdinalIgnoreCase) -or $joined -eq $_ }).Count) {
        throw "JAWS-SEC-001: Unsupported preflight operation: $Operation"
    }
    $raw = & az @Arguments 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "JAWS-AUTH-003: Cannot complete '$Operation'. Check login, subscription access, Azure RBAC, and network connectivity. Azure CLI exit code: $LASTEXITCODE."
    }
    $value = ($raw | Out-String).Trim()
    if (-not $value) { throw "JAWS-AUTH-004: Empty Azure response during $Operation." }
    try { return (ConvertFrom-Json -InputObject $value) }
    catch { throw "JAWS-AUTH-005: Invalid Azure JSON during $Operation." }
}

function Get-JawsAuthorizedSubscriptions {
    [CmdletBinding()]
    param([switch]$NonInteractive)
    try {
        $account=Invoke-JawsPreflightRead -Arguments @('account','show','--output','json','--only-show-errors') -Operation 'authentication check'
    } catch {
        if ($NonInteractive) { throw "JAWS-AUTH-001: Azure sign-in required. Sign in with Azure CLI before noninteractive execution. $($_.Exception.Message)" }
        Write-Host 'Azure authentication required. The installer can launch the Azure sign-in flow.' -ForegroundColor Yellow
        $answer=Read-Host 'Launch Microsoft Entra sign-in now? [Y/N]'
        if ($answer -notin @('Y','y')) { throw 'JAWS-AUTH-001: User declined Azure sign-in.' }
        & az login --only-show-errors --output none
        if ($LASTEXITCODE -ne 0) { throw 'JAWS-AUTH-002: Azure sign-in failed.' }
        $account=Invoke-JawsPreflightRead -Arguments @('account','show','--output','json','--only-show-errors') -Operation 'authentication recheck'
    }
    $subscriptions=@(Invoke-JawsPreflightRead -Arguments @('account','list','--all','--output','json','--only-show-errors') -Operation 'authorized subscription enumeration')
    $enabled=@($subscriptions | Where-Object { $_ -and $_.state -eq 'Enabled' -and $_.id -and $_.tenantId })
    if ($enabled.Count -eq 0) { throw 'JAWS-AUTH-006: No enabled Azure subscriptions are visible to this identity.' }
    [pscustomobject]@{Account=$account;Subscriptions=$enabled}
}

function Select-JawsSubscription {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$Subscriptions,[string]$SubscriptionId,[switch]$NonInteractive)
    if ($SubscriptionId) {
        $found=@($Subscriptions | Where-Object { $_.id -ieq $SubscriptionId })
        if ($found.Count -ne 1) { throw "JAWS-AUTH-007: Target subscription '$SubscriptionId' is not enabled or is not visible to the signed-in identity." }
        return $found[0]
    }
    if ($NonInteractive) { throw 'JAWS-CONFIG-001: -SubscriptionId required for noninteractive discovery.' }
    Write-Host 'Select an accessible subscription:' -ForegroundColor Cyan
    for($i=0;$i -lt $Subscriptions.Count;$i++) { Write-Host "[$($i+1)] $($Subscriptions[$i].name) ($($Subscriptions[$i].id))" }
    $choice=Read-Host 'Subscription number'
    $number=0
    if (-not [int]::TryParse($choice,[ref]$number) -or $number -lt 1 -or $number -gt $Subscriptions.Count) {
        throw 'JAWS-CONFIG-002: Invalid subscription selection.'
    }
    return $Subscriptions[$number-1]
}

function Select-JawsResourceGroup {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$SubscriptionId,[string]$ResourceGroupName,[switch]$NonInteractive)
    if (-not $ResourceGroupName) {
        if ($NonInteractive) { throw 'JAWS-CONFIG-003: -ResourceGroupName required for noninteractive discovery.' }
        $groups=@(Invoke-JawsPreflightRead -Arguments @('group','list','--subscription',$SubscriptionId,'--output','json','--only-show-errors') -Operation 'resource group selection')
        if ($groups.Count -eq 0) { throw 'JAWS-CONFIG-004: No visible resource groups. Stage A does not create resource groups.' }
        for($i=0;$i -lt $groups.Count;$i++) { Write-Host "[$($i+1)] $($groups[$i].name)" }
        $choice=Read-Host 'Resource group number'
        $number=0
        if (-not [int]::TryParse($choice,[ref]$number) -or $number -lt 1 -or $number -gt $groups.Count) { throw 'JAWS-CONFIG-005: Invalid resource group selection.' }
        $ResourceGroupName=[string]$groups[$number-1].name
    }
    # Test actual data-plane management read; role names alone are insufficient.
    $rg=Invoke-JawsPreflightRead -Arguments @('group','show','--subscription',$SubscriptionId,'--name',$ResourceGroupName,'--output','json','--only-show-errors') -Operation "resource group read authorization: $ResourceGroupName"
    if (-not $rg.id -or $rg.name -ine $ResourceGroupName) { throw 'JAWS-AUTH-008: Resource group response identity mismatch.' }
    return [string]$rg.name
}

function Get-JawsTenantInstallationScan {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$Subscriptions,[Parameter(Mandatory)][string]$TenantId)
    $targets=@($Subscriptions | Where-Object { $_.tenantId -ieq $TenantId -and $_.state -eq 'Enabled' })
    if (-not $targets.Count) { throw 'JAWS-SCAN-001: No enabled subscriptions found for selected tenant.' }
    $results=@()
    $candidates=@()
    foreach($sub in $targets) {
        try {
            $resources=@(Invoke-JawsPreflightRead -Arguments @('resource','list','--subscription',[string]$sub.id,'--output','json','--only-show-errors') -Operation "tenant resource scan: $($sub.id)")
            $results+= [pscustomobject]@{SubscriptionId=$sub.id;Status='Scanned';ResourceCount=$resources.Count;Error=$null}
            foreach($resource in $resources) {
                if (-not $resource) { continue }
                $name=[string]$resource.name
                $rg=[string]$resource.resourceGroup
                $tags=$resource.tags
                $tagMatches=$false
                if ($tags) {
                    foreach($key in @($tags.PSObject.Properties.Name)) {
                        if ($key -match '(?i)^(application|solution|product|project|managedby|jaws)$' -and
                            [string]$tags.$key -match '(?i)jaws|tight.?fang|tfang') { $tagMatches=$true; break }
                    }
                }
                if ($name -match '(?i)jaws|tight.?fang|tfang' -or $rg -match '(?i)jaws|tight.?fang|tfang' -or $tagMatches) {
                    $candidates+=[pscustomobject]@{
                        SubscriptionId=$sub.id;ResourceGroup=$rg;Name=$name
                        Type=$resource.type;ResourceId=$resource.id
                        Reason=if ($tagMatches) {'MatchingTags'} elseif ($name -match '(?i)jaws|tight.?fang|tfang') {'MatchingName'} else {'MatchingResourceGroup'}
                    }
                }
            }
        } catch {
            $results+= [pscustomobject]@{SubscriptionId=$sub.id;Status='Failed';ResourceCount=$null;Error=$_.Exception.Message}
        }
    }
    [pscustomobject]@{
        SchemaVersion='1.0';TenantId=$TenantId;GeneratedAtUtc=(Get-Date).ToUniversalTime().ToString('o')
        SubscriptionCount=$targets.Count;Completed=(@($results | Where-Object Status -eq 'Failed').Count -eq 0)
        Subscriptions=@($results);Candidates=@($candidates)
        Disclaimer='Heuristic inventory of readable subscriptions. Candidates do not prove an installation. No candidates does not prove absence of JAWS.'
    }
}

Export-ModuleMember -Function Invoke-JawsPreflightRead,Get-JawsAuthorizedSubscriptions,Select-JawsSubscription,Select-JawsResourceGroup,Get-JawsTenantInstallationScan
