# Build the Supervisor image from this host and post one later version that names the browser toolbox.
# Install does not run this command. Supervisor version 1 is not modified. The dev project is refused.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$EnvironmentName,
    [switch]$AcknowledgeSupervisorBrowserImage
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$started = Get-Date
Import-Module (Join-Path $root 'modules/StepDBrowser.psm1') -Force
Import-Module (Join-Path $root 'modules/MilestoneResult.psm1') -Force
$local = Join-Path $root '.local'
if (-not (Test-Path -LiteralPath $local)) { New-Item -ItemType Directory -Path $local | Out-Null }
$evidencePath = Join-Path $local "jaws-step-d-browser-image.$EnvironmentName.generated.json"
try {
    $result = Publish-JawsSupervisorBrowserImage -EnvironmentName $EnvironmentName -InstallerRoot $root -AcknowledgeSupervisorBrowserImage:$AcknowledgeSupervisorBrowserImage
    $evidencePath = $result.EvidencePath
    Write-Host 'STEP-D BROWSER IMAGE PASS'
    Write-Host 'Customer installation accepted: false'
    Write-Host "Azure writes: $($result.AzureWrites)"
    Write-Host 'Supervisor image rebuilt: true'
    Write-Host "Supervisor image built this run: $($result.ImageBuiltThisRun)"
    Write-Host "Previous image: $($result.PreviousImage)"
    Write-Host "Image: $($result.Image)"
    Write-Host 'Supervisor version 1 unchanged: true'
    Write-JawsMilestoneResult -Result PASS -ReadyForNextStep $result.ReadyForNextStep -NextStep $result.NextStep -EvidencePath $evidencePath
} catch {
    Save-JawsMilestoneFailure -Path $evidencePath -Message $_.Exception.Message -Started $started
    Write-Host 'STEP-D BROWSER IMAGE FAIL'
    Write-Host 'Customer installation accepted: false'
    Write-JawsMilestoneResult -Result FAIL -ReadyForNextStep $false -NextStep 'Publish-JawsSupervisorBrowserImage.ps1' -EvidencePath $evidencePath
    throw
}
