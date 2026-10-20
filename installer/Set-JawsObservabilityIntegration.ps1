# Store the observability integration in the Step B Key Vault.
# Values are written as secrets. This command does not install the Datadog Agent and does not install Step G.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$EnvironmentName,
    [switch]$AcknowledgeObservabilitySecrets,
    [string]$ServiceNowUrl = '',
    [string]$ServiceNowUsername = '',
    [string]$ServiceNowPassword = '',
    [string]$DatadogApiKey = '',
    [string]$DatadogAppKey = '',
    [string]$DatadogSite = '',
    [string]$DefaultVirtualMachineResourceId = ''
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'modules/ObservabilityIntegration.psm1') -Force
$result = Set-JawsObservabilityIntegration -EnvironmentName $EnvironmentName -InstallerRoot $PSScriptRoot -AcknowledgeObservabilitySecrets:$AcknowledgeObservabilitySecrets -ServiceNowUrl $ServiceNowUrl -ServiceNowUsername $ServiceNowUsername -ServiceNowPassword $ServiceNowPassword -DatadogApiKey $DatadogApiKey -DatadogAppKey $DatadogAppKey -DatadogSite $DatadogSite -DefaultVirtualMachineResourceId $DefaultVirtualMachineResourceId
Write-Host 'Observability integration: recorded'
Write-Host "ServiceNow configured: $($result.ServiceNowConfigured)"
Write-Host "Datadog configured: $($result.DatadogConfigured)"
Write-Host "Default virtual machine: $($result.DefaultVirtualMachineResourceId)"
Write-Host 'Datadog Agent installed: false'
Write-Host "Azure writes: $($result.AzureWrites)"
Write-Host 'Customer installation accepted: false'
Write-Host 'Result: PASS'
Write-Host 'Ready for next step: false'
Write-Host 'Next step: Step G is not installable'
Write-Host "Evidence: $($result.Evidence)"
