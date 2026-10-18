# Prints the same three facts for every key milestone: PASS or FAIL, whether the next step can be run, and the evidence file.
Set-StrictMode -Version Latest

function Resolve-JawsEvidencePath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    if (Test-Path -LiteralPath $Path) {
        return (Resolve-Path -LiteralPath $Path).Path
    }
    return $Path
}

function Save-JawsMilestoneFailure {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Message,
        [Parameter(Mandatory)][datetime]$Started
    )
    $replace = $true
    if (Test-Path -LiteralPath $Path) {
        $written = (Get-Item -LiteralPath $Path).LastWriteTime
        if ($written -ge $Started.AddSeconds(-1)) { $replace = $false }
    }
    if (-not $replace) { return }
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    [pscustomobject]@{
        SchemaVersion = '1.0'
        Result = 'FAIL'
        Message = $Message
        AzureWrites = 0
        CustomerInstallationAccepted = $false
        CompletedAtUtc = [DateTime]::UtcNow.ToString('o')
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $Path -Encoding utf8
}

function Write-JawsMilestoneResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('PASS','FAIL')][string]$Result,
        [Parameter(Mandatory)][bool]$ReadyForNextStep,
        [Parameter(Mandatory)][string]$NextStep,
        [Parameter(Mandatory)][string]$EvidencePath
    )
    $ready = if ($ReadyForNextStep) { 'true' } else { 'false' }
    Write-Host "Result: $Result"
    Write-Host "Ready for next step: $ready"
    Write-Host "Next step: $NextStep"
    Write-Host "Evidence: $(Resolve-JawsEvidencePath $EvidencePath)"
}

Export-ModuleMember -Function Resolve-JawsEvidencePath,Save-JawsMilestoneFailure,Write-JawsMilestoneResult
