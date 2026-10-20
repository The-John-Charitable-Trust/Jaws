# Step D: one hosted virtual-machine specialist, one compute environment, and the JSON catalog.
# Validate is read-only. Install creates the specialist only after -AcknowledgeStepDInstall.
# Accept re-reads Azure. A passing run is not a fresh-subscription acceptance receipt.
[CmdletBinding()]
param(
    [ValidateSet('Validate','Install','Accept')][string]$Mode='Validate',
    [string]$EnvironmentName='dev',
    [switch]$AcknowledgeStepDInstall
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$started=Get-Date
Import-Module (Join-Path $root 'modules/StepDInstall.psm1') -Force
Import-Module (Join-Path $root 'modules/MilestoneResult.psm1') -Force
$local=Join-Path $root '.local'
if(-not (Test-Path -LiteralPath $local)){ New-Item -ItemType Directory -Path $local | Out-Null }
$evidenceName=switch($Mode){
    'Validate'{"jaws-step-d-validate.$EnvironmentName.generated.json"}
    'Install'{"jaws-step-d-install.$EnvironmentName.generated.json"}
    'Accept'{"jaws-step-d-acceptance.$EnvironmentName.generated.json"}
}
$evidencePath=Join-Path $local $evidenceName
$label=if($Mode -eq 'Accept'){'ACCEPTANCE'}else{$Mode.ToUpperInvariant()}
$next=switch($Mode){
    'Validate'{'Step D Install'}
    'Install'{'Step D Accept'}
    'Accept'{'Step E Validate'}
}
try {
    $result=switch($Mode){
        'Validate'{ Invoke-JawsStepDValidate -EnvironmentName $EnvironmentName -InstallerRoot $root }
        'Install'{ Invoke-JawsStepDInstall -EnvironmentName $EnvironmentName -InstallerRoot $root -AcknowledgeStepDInstall:$AcknowledgeStepDInstall }
        'Accept'{ Invoke-JawsStepDAccept -EnvironmentName $EnvironmentName -InstallerRoot $root }
    }
    $evidencePath=$result.EvidencePath
    Write-Host "STEP-D $label PASS"
    Write-Host 'Customer installation accepted: false'
    Write-Host "Azure writes: $($result.AzureWrites)"
    if ($Mode -eq 'Install' -and (Test-Path -LiteralPath $evidencePath -PathType Leaf)) {
        $receipt = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json
        $toolbox = if ($receipt.PSObject.Properties['BrowserToolboxName']) { [string]$receipt.BrowserToolboxName } else { '' }
        if ([string]::IsNullOrWhiteSpace($toolbox)) {
            Write-Host 'Browser toolbox: not provisioned'
        } else {
            Write-Host "Browser toolbox: $toolbox"
            Write-Host "Browser endpoint: $($receipt.PlaywrightServiceEndpoint)"
            Write-Host 'Browser network: private. The hostname is published on the VNet internal load balancer.'
            Write-Host "Browser toolset version: $($receipt.BrowserToolsetVersion)"
            Write-Host 'Supervisor image rebuilt: false'
            Write-Host 'Browser tools on this image: pending a Supervisor image built from this host'
            $allowPath = Join-Path $root ".local/jaws-browser-allow-list.$EnvironmentName.json"
            $allowCount = 0
            if (Test-Path -LiteralPath $allowPath -PathType Leaf) {
                $allowFile = Get-Content -LiteralPath $allowPath -Raw | ConvertFrom-Json
                if ($allowFile.PSObject.Properties['Urls'] -and $null -ne $allowFile.Urls) { $allowCount = @($allowFile.Urls).Count }
            }
            if ($allowCount -eq 0) {
                Write-Host 'Browser allow-list: empty. No navigation will succeed until an operator adds a URL.'
            } else {
                Write-Host "Browser allow-list entries: $allowCount"
            }
        }
        if ($receipt.PSObject.Properties['SupervisorV1Unchanged'] -and $receipt.SupervisorV1Unchanged -eq $true) {
            Write-Host 'Supervisor version 1 unchanged: true'
        }
    }
    Write-JawsMilestoneResult -Result PASS -ReadyForNextStep $result.ReadyForNextStep -NextStep $result.NextStep -EvidencePath $evidencePath
} catch {
    Save-JawsMilestoneFailure -Path $evidencePath -Message $_.Exception.Message -Started $started
    Write-Host "STEP-D $label FAIL"
    Write-Host 'Customer installation accepted: false'
    Write-JawsMilestoneResult -Result FAIL -ReadyForNextStep $false -NextStep $next -EvidencePath $evidencePath
    throw
}
