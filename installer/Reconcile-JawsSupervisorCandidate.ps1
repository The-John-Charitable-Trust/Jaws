# State-first read-only reconciliation of published Supervisor candidate.
[CmdletBinding()]
param([ValidateSet('Verify','Wait')][string]$Mode='Wait',[int]$MaxAttempts=20,[int]$DelaySeconds=15,[int]$StableReads=6)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
# Deployment imports reconciliation into its own scope and removes it from the caller.
# Import reconciliation afterward so Wait-JawsSupervisorCandidate stays visible here.
Import-Module (Join-Path $PSScriptRoot 'modules/FoundrySupervisorDeployment.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'modules/FoundrySupervisorReconciliation.psm1') -Force
$local=Join-Path $PSScriptRoot '.local'
$publishPath=Join-Path $local 'jaws-supervisor-publish-receipt.dev.generated.json'
if(-not(Test-Path -LiteralPath $publishPath)){throw 'JAWS-RECON-201: Verified publish receipt missing.'}
$publish=Resolve-JawsSupervisorPublishReceipt -ReceiptContent (Get-Content -LiteralPath $publishPath -Raw | ConvertFrom-Json)
$image=[string]$publish.Image
$endpoint='https://jaws-foundry-dev.services.ai.azure.com/api/projects/jaws-dev'
function Read-FoundryPage([string]$url) {
 $output=& az rest --method get --url $url --resource https://ai.azure.com --output json --only-show-errors 2>&1
 if($LASTEXITCODE -ne 0){throw "JAWS-RECON-202: Foundry read failed. $($output|Out-String)"}
 return ($output|Out-String|ConvertFrom-Json -ErrorAction Stop)
}
if($Mode -eq 'Verify'){$MaxAttempts=1; $StableReads=1}
$state=Wait-JawsSupervisorCandidate -ReadPage { param($url) Read-FoundryPage $url } -ProjectEndpoint $endpoint -Image $image -MaxAttempts $MaxAttempts -DelaySeconds $DelaySeconds -StableReads $StableReads
$report=[pscustomobject]@{
 SchemaVersion='1.0';AgentName='jaws-supervisor-dev';Status=$state.Status;ResolvedVersion=$state.Version
 ActiveVerified=$state.ActiveVerified;Attempts=$state.Attempts;Reason=$state.Reason
 Image=$image;AzureWrites=0;InvocationVerified=$false;VerifiedAtUtc=[datetime]::UtcNow.ToString('o')
}
$path=Join-Path $local 'jaws-step-c-supervisor-deployment-verified.dev.generated.json'
$report|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $path -Encoding utf8
Write-Host "Supervisor candidate reconciliation: $($state.Status) | Version: $($state.Version) | Attempts: $($state.Attempts)"
Write-Host "Report: $path"
if(-not $state.ActiveVerified){throw 'JAWS-RECON-203: No unique active Supervisor candidate. Release blocked; do not redeploy.'}
