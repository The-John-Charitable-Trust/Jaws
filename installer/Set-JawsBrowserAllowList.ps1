# Add or remove one browser allow-list URL without rebuilding the browser image.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Add','Remove')][string]$Action,
    [Parameter(Mandatory)][string]$Url,
    [Parameter(Mandatory)][string]$EnvironmentName,
    [switch]$AcknowledgeBrowserAllowList
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'modules/StepDBrowser.psm1') -Force
$result = Update-JawsBrowserAllowList -EnvironmentName $EnvironmentName -Action $Action -Url $Url -InstallerRoot $PSScriptRoot -AcknowledgeBrowserAllowList:$AcknowledgeBrowserAllowList
Write-Host "Browser allow-list: $Action"
Write-Host "URL: $Url"
Write-Host "Entries: $($result.Urls.Count)"
Write-Host "Allow-list: $($result.Path)"
Write-Host 'Azure writes: 1'
Write-Host 'Customer installation accepted: false'
