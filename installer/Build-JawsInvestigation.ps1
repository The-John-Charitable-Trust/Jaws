# Step C: local-only .NET build and optional Linux container build. No Azure calls.
[CmdletBinding()]
param([switch]$BuildContainer)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=[System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$project=Join-Path $root 'src/Jaws.Investigation.Host/Jaws.Investigation.Host.csproj'
$dockerfile=Join-Path $root 'src/Jaws.Investigation.Host/Dockerfile'
$out=Join-Path $PSScriptRoot '.local/investigation/publish'
if (-not (Test-Path -LiteralPath $project -PathType Leaf) -or
    -not (Test-Path -LiteralPath $dockerfile -PathType Leaf)) {
    throw 'JAWS-INV-BUILD-001: Investigation host project or Dockerfile missing.'
}
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw 'JAWS-INV-BUILD-002: .NET 10 SDK not available.'
}
& dotnet publish $project '-c' 'Release' '--output' $out
if ($LASTEXITCODE -ne 0) { throw 'JAWS-INV-BUILD-003: Investigation .NET publish failed.' }
if ($BuildContainer) {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw 'JAWS-INV-BUILD-004: Docker is not installed.'
    }
    & docker build '--platform' 'linux/amd64' '--file' $dockerfile '--tag' 'jaws-investigation:local' $root
    if ($LASTEXITCODE -ne 0) { throw 'JAWS-INV-BUILD-005: Linux container build failed.' }
}
[pscustomobject]@{
    Status='LOCAL_BUILD_COMPLETE'
    ProjectPath=$project
    OutputPath=$out
    ContainerBuilt=[bool]$BuildContainer
    ImageTag=if ($BuildContainer) {'jaws-investigation:local'} else {$null}
    AzureWrites=0
    FoundryDeploymentPerformed=$false
} | Format-List | Out-Host
