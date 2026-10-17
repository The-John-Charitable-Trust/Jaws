# Validate a Step A discovery report. This script does not call Azure.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ReportPath)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if (-not (Test-Path -LiteralPath $ReportPath)) {
    throw "JAWS-STEP-A-001: No Step A report at '$ReportPath'. Run Discover first. A missing report is not a pass."
}
Import-Module (Join-Path $PSScriptRoot 'modules/StepADiscovery.psm1') -Force
$report=Get-Content -LiteralPath $ReportPath -Raw -Encoding utf8 | ConvertFrom-Json
$result=Test-JawsStepADiscoveryReport -Report $report
if ($result.Result -eq 'PASS') {
    Write-Host 'STEP-A PASS'
    Write-Host "Outcome: $($result.Outcome)"
    Write-Host 'Azure writes: 0'
    return
}
$code=if ($result.Result -eq 'DRIFT') { 'JAWS-STEP-A-002' } else { 'JAWS-STEP-A-003' }
throw "$code`: STEP-A $($result.Result). $($result.Reasons -join ' ')"
