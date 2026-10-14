# JAWS workstation prerequisites. Local read-only checks; no installation or Azure writes.
[CmdletBinding()]
param([switch]$RequireContainerBuild)
$ErrorActionPreference='Continue'
$checks=New-Object System.Collections.Generic.List[object]
function Add-Check([string]$Name,[bool]$Passed,[string]$Details) {
  $checks.Add([pscustomobject]@{Name=$Name;Passed=$Passed;Details=$Details})
}
$win=($env:OS -eq 'Windows_NT')
Add-Check 'Windows host' $win 'Windows 11 recommended for JAWS development.'
$psVersion=$PSVersionTable.PSVersion
Add-Check 'PowerShell 7+' ($psVersion.Major -ge 7) "Running $psVersion. Install PowerShell 7 if needed."
$policy=Get-ExecutionPolicy
Add-Check 'PowerShell execution policy' ($policy -ne 'Restricted' -and $policy -ne 'AllSigned') "Effective policy: $policy. Check script signature / Mark-of-the-Web; do not change organization policies."
$git=Get-Command git -ErrorAction SilentlyContinue
Add-Check 'Git' ($null -ne $git) 'Git CLI must be available in PATH.'
$az=Get-Command az -ErrorAction SilentlyContinue
Add-Check 'Azure CLI' ($null -ne $az) 'Azure CLI must be available for Foundry/ACR deployment.'
$dotnet=Get-Command dotnet -ErrorAction SilentlyContinue
$sdks=if($dotnet){ @(& dotnet --list-sdks 2>$null) } else {@()}
Add-Check '.NET 10 SDK' (@($sdks | Where-Object {$_ -match '^10\.'}).Count -gt 0) (($sdks -join '; ') + ' | .NET 10 SDK required for Investigation host.')
$wsl=Get-Command wsl.exe -ErrorAction SilentlyContinue
Add-Check 'WSL CLI' ($null -ne $wsl) 'Install WSL 2 and a Linux distribution for Docker Desktop WSL backend.'
$wslText=if($wsl){ (& wsl.exe --list --verbose 2>&1 | Out-String) } else {''}
# WSL output formatting may vary by locale/encoding: report it for operator inspection.
$wsl2=($wslText -match '(?m)\b2\s*$')
Add-Check 'WSL 2 available' ($wsl2 -or $null -ne $wsl) 'Inspect wsl --status and wsl --list --verbose. Docker Desktop may use its own WSL distro; a separate Linux distro is optional.'
$docker=Get-Command docker -ErrorAction SilentlyContinue
Add-Check 'Docker CLI' ($null -ne $docker) 'Install Docker Desktop with Linux containers enabled.'
$dockerInfo=if($docker){ (& docker info --format '{{.OSType}}/{{.Architecture}}' 2>$null | Out-String).Trim() } else {''}
Add-Check 'Docker Linux engine' ($dockerInfo -match '^linux/') "Detected engine: $dockerInfo; Docker Desktop should be running in Linux containers mode."
if($RequireContainerBuild) {
  Add-Check 'Linux AMD64 target' ($dockerInfo -match '^linux/') 'Build using docker build --platform linux/amd64; validate resulting image architecture.'
}
$checks | Format-Table -AutoSize | Out-Host
if(@($checks | Where-Object { -not $_.Passed }).Count -gt 0) {
  Write-Warning 'JAWS prerequisites incomplete. Address failed checks before building/deploying.'
  exit 1
}
Write-Host 'JAWS prerequisites passed.'
