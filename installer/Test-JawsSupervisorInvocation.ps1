# Stage B2 runtime acceptance for an existing, immutable Foundry-hosted JAWS Supervisor.
# No Azure infrastructure writes. One explicit, charge-acknowledged inference request.
[CmdletBinding()]
param(
    [switch]$AcknowledgeInferenceCharges,
    [string]$ReceiptFile=(Join-Path $PSScriptRoot '.local/jaws-foundry-supervisor-deploy-receipt.dev.generated.json'),
    [string]$StateFile=(Join-Path $PSScriptRoot 'config/jaws-installation-state.dev.json'),
    [string]$PublishReceiptFile=(Join-Path $PSScriptRoot '.local/jaws-supervisor-publish-receipt.dev.generated.json')
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if (-not $AcknowledgeInferenceCharges) {
    throw 'JAWS-INVOKE-001: Explicit -AcknowledgeInferenceCharges is required. Invocation may incur Azure model/hosting charges.'
}
Import-Module (Join-Path $PSScriptRoot 'modules/InstallationState.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'modules/FoundrySupervisorDeployment.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'modules/FoundrySupervisorReconciliation.psm1') -Force
if (-not (Test-Path -LiteralPath $ReceiptFile -PathType Leaf)) {
    throw 'JAWS-INVOKE-002: Missing verified deployment receipt.'
}
$r=Get-Content -LiteralPath $ReceiptFile -Raw | ConvertFrom-Json -ErrorAction Stop
$state=Read-JawsInstallationState -Path $StateFile
$publishReceipt=Get-Content -LiteralPath $PublishReceiptFile -Raw | ConvertFrom-Json -ErrorAction Stop
$plan=New-JawsFoundrySupervisorPlan -State $state -PublishReceipt $publishReceipt -AgentName 'jaws-supervisor-dev'
Test-JawsFoundryDeploymentPlan -DeploymentPlan $plan
$endpoint=[string]$plan.Plan.ProjectEndpoint
$versionUri="$endpoint/agents/jaws-supervisor-dev/versions/1"
if ($endpoint -cne 'https://jaws-foundry-dev.services.ai.azure.com/api/projects/jaws-dev' -or
    [string]$r.AgentName -cne 'jaws-supervisor-dev' -or [string]$r.Version -cne '1' -or
    [string]$r.AgentVersionUri -cne $versionUri -or
    [string]$r.Image -cne [string]$plan.Plan.Image -or
    $r.ActiveVerified -ne $true -or $r.FoundryDeploymentPerformed -ne $true) {
    throw 'JAWS-INVOKE-003: Receipt/plan identity, image or active status mismatch.'
}
# Re-read the actual immutable version before making a potentially billable request.
$versionJson=& az rest --method get --url "$versionUri?api-version=v1" --resource https://ai.azure.com --output json --only-show-errors 2>$null
if ($LASTEXITCODE -ne 0) { throw 'JAWS-INVOKE-004: Cannot verify active Foundry agent version.' }
$versionObj=$versionJson | Out-String | ConvertFrom-Json -ErrorAction Stop
$comparison=Compare-JawsFoundrySupervisorState -DeploymentPlan $plan -ActualAgent $versionObj
if ($comparison.OverallStatus -ne 'MATCH') {
    throw "JAWS-INVOKE-005: Live agent configuration drift: $($comparison.FailedFields -join ', '). No inference was requested."
}
$path=Join-Path $PSScriptRoot '.local/jaws-supervisor-invocation-acceptance.dev.generated.json'
if (Test-Path -LiteralPath $path -PathType Leaf) {
    throw 'JAWS-INVOKE-006: Acceptance evidence already exists; refusing to overwrite. Inspect it first.'
}
$bodyFile=Join-Path $PSScriptRoot '.local/jaws-supervisor-invocation-request.dev.generated.json'
# Keep the prompt non-sensitive, and do not store token credentials or conversation content in the receipt.
$prompt='Identify yourself and explain your operational role in JAWS. Do not claim access to tools or data sources that have not been configured.'
$body=[ordered]@{model='gpt-5-mini';input=$prompt;stream=$false;store=$false}
$bodyJson=ConvertTo-Json -InputObject $body -Depth 8 -Compress
[System.IO.File]::WriteAllText($bodyFile,$bodyJson,[System.Text.UTF8Encoding]::new($false))
$url="$endpoint/agents/jaws-supervisor-dev/endpoint/protocols/openai/responses?api-version=v1"
$started=[datetime]::UtcNow
try {
    # The POST invokes an existing agent. It does NOT create or change Azure infrastructure.
    # --body @file preserves JSON quoting on Windows/PowerShell.
    $responseRaw=& az rest --method post --url $url --resource https://ai.azure.com `
        --headers 'Content-Type=application/json' --body "@$bodyFile" --output json --only-show-errors 2>&1
    $exitCode=$LASTEXITCODE
} finally {
    if (Test-Path -LiteralPath $bodyFile) { Remove-Item -LiteralPath $bodyFile -Force }
}
$elapsed=[math]::Round(([datetime]::UtcNow - $started).TotalMilliseconds)
if ($exitCode -ne 0) {
    # Do not persist response/error payloads that may contain sensitive service diagnostics.
    Write-Host ($responseRaw | Out-String)
    throw 'JAWS-INVOKE-007: Foundry Responses invocation failed. No acceptance receipt created.'
}
$response=$responseRaw | Out-String | ConvertFrom-Json -ErrorAction Stop
$status=if ($response.PSObject.Properties['status']) {[string]$response.status} else {'<missing>'}
$id=if ($response.PSObject.Properties['id']) {[string]$response.id} else {''}
$textParts=[System.Collections.Generic.List[string]]::new()
if ($response.PSObject.Properties['output']) {
    foreach ($output in @($response.output)) {
        if ($null -eq $output -or -not $output.PSObject.Properties['content']) {continue}
        foreach ($item in @($output.content)) {
            if ($null -ne $item -and $item.PSObject.Properties['type'] -and
                [string]$item.type -eq 'output_text' -and $item.PSObject.Properties['text'] -and
                -not [string]::IsNullOrWhiteSpace([string]$item.text)) {
                $textParts.Add([string]$item.text)
            }
        }
    }
}
$message=($textParts -join [Environment]::NewLine).Trim()
if ($status -cne 'completed' -or [string]::IsNullOrWhiteSpace($id) -or
    [string]::IsNullOrWhiteSpace($message)) {
    throw 'JAWS-INVOKE-008: HTTP success did not contain a completed Responses result with an id and nonempty assistant output.'
}
$report=[ordered]@{
    SchemaVersion='1.0'
    AgentName='jaws-supervisor-dev'
    Version='1'
    ProjectEndpoint=$endpoint
    Image=[string]$plan.Plan.Image
    PlanSha256=[string]$plan.PlanSha256
    ResponseId=$id
    ResponseStatus=$status
    OutputCharacters=$message.Length
    DurationMilliseconds=$elapsed
    ActiveVerified=$true
    InvocationVerified=$true
    AzureInfrastructureWrites=0
    InferenceRequestPerformed=$true
    RecordedAtUtc=[datetime]::UtcNow.ToString('o')
}
$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path -Encoding utf8
Write-Host "JAWS runtime acceptance PASSED: agent v1; response $id; latency $elapsed ms" -ForegroundColor Green
Write-Host "Supervisor response:`n$message"
Write-Host "Acceptance evidence: $path"
