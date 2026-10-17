# Read-only status verification for installer-managed JAWS Supervisor.
[CmdletBinding()]
param(
    [string]$ReceiptFile=(Join-Path $PSScriptRoot '.local/jaws-foundry-supervisor-deploy-receipt.dev.generated.json')
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if (-not (Test-Path -LiteralPath $ReceiptFile -PathType Leaf)) {
    throw 'JAWS-FOUNDRY-STATUS-001: Deployment receipt missing.'
}
$r=Get-Content -LiteralPath $ReceiptFile -Raw | ConvertFrom-Json -ErrorAction Stop
if ($r.Status -ne 'PROVISIONING_STARTED' -or $r.AgentName -cnotmatch '^jaws-supervisor-dev$' -or
    $r.Version -notmatch '^[0-9]+$' -or
    [string]$r.AgentVersionUri -cnotmatch '^https://jaws-foundry-dev\.services\.ai\.azure\.com/api/projects/jaws-dev/agents/jaws-supervisor-dev/versions/[0-9]+$') {
    throw 'JAWS-FOUNDRY-STATUS-002: Unexpected deployment receipt; refusing cross-project query.'
}
$version=& az rest --method get --url "$($r.AgentVersionUri)?api-version=v1" --resource https://ai.azure.com --output json --only-show-errors 2>$null
if ($LASTEXITCODE -ne 0) {throw 'JAWS-FOUNDRY-STATUS-003: Unable to read hosted agent version status.'}
$v=$version | Out-String | ConvertFrom-Json
$state=[string]$v.status
$report=[pscustomobject]@{
    AgentName=$r.AgentName;Version=$r.Version;Status=$state
    Image=$r.Image;AzureWrites=0;ActiveVerified=($state -ieq 'active')
    InvocationVerified=$false
}
$report | Format-List | Out-Host
if ($state -ieq 'failed') {throw 'JAWS-FOUNDRY-STATUS-004: Hosted agent failed provisioning; inspect Foundry errors.'}
if ($state -ieq 'active') {Write-Host 'Hosted agent Active. Inference acceptance not yet executed.' -ForegroundColor Green}
