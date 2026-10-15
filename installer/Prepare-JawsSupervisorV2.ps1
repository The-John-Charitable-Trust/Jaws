# Prepare and verify versioned Supervisor candidate without changing Supervisor v1.
[CmdletBinding()]
param([ValidateSet('Build','Plan','Verify')][string]$Mode='Build')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$project=Join-Path $root 'src/Jaws.Supervisor.Host/Jaws.Supervisor.Host.csproj'
$docker=Join-Path $root 'src/Jaws.Supervisor.Host/Dockerfile'
$toolbox='jaws-investigation-a2a-tools'
$receipt=Join-Path $PSScriptRoot '.local/jaws-step-c-a2a-receipt.dev.generated.json'
$connectionReceipt=Join-Path $PSScriptRoot '.local/jaws-step-c-delegation-connection-receipt.dev.generated.json'
if(-not(Test-Path $receipt) -or -not(Test-Path $connectionReceipt)){
 throw 'JAWS-SUP-V2-001: Verified Investigation A2A and connection receipts required.'
}
if($Mode -eq 'Verify'){
 & (Join-Path $PSScriptRoot 'Install-JawsStepC.ps1') -Mode DelegationVerify
 return
}
if($Mode -eq 'Build'){
 & dotnet build $project -c Release
 if($LASTEXITCODE -ne 0){throw 'JAWS-SUP-V2-002: .NET build failed.'}
 # Buildx emits an OCI index with OCI layers. The legacy builder's docker layer
 # media type failed Foundry provisioning for this registry.
 & docker buildx build --platform linux/amd64 --file $docker --tag jaws-supervisor:local --load (Split-Path -Parent $docker)
 if($LASTEXITCODE -ne 0){throw 'JAWS-SUP-V2-003: Container build failed.'}
 $arch=(& docker image inspect jaws-supervisor:local --format '{{.Os}}/{{.Architecture}}' | Out-String).Trim()
 if($arch -ne 'linux/amd64'){throw "JAWS-SUP-V2-004: Expected linux/amd64, got $arch"}
 Write-Host "Supervisor v2 candidate image prepared: jaws-supervisor:local ($arch). Supervisor v1 unchanged."
 Write-Host 'Next: publish via installer/Publish-JawsSupervisor.ps1 Plan/Publish with exact approval.'
 return
}
# Planning requires previously published immutable candidate image receipt.
$published=Join-Path $PSScriptRoot '.local/jaws-supervisor-publish-receipt.dev.generated.json'
if(-not(Test-Path $published)){throw 'JAWS-SUP-V2-005: Supervisor image publish receipt missing.'}
$p=Get-Content $published -Raw | ConvertFrom-Json
if($p.RegistryPushPerformed -ne $true -or $p.Status -ne 'PUBLISHED_AND_DIGEST_VERIFIED'){throw 'JAWS-SUP-V2-006: Valid publish receipt required.'}
& (Join-Path $PSScriptRoot 'Deploy-JawsSupervisor.ps1') -Mode Plan -AgentName 'jaws-supervisor-dev' -ToolboxName $toolbox -PublishReceiptFile $published
Write-Host 'Review the candidate draft version plan on existing jaws-supervisor-dev; v1 remains the routing target.'
