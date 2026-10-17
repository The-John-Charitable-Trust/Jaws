# B2.1 installer-controlled local Supervisor build. Never calls Azure APIs.
Set-StrictMode -Version Latest

function Get-JawsSupervisorPackagePlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$InstallerRoot)
    $repo=[System.IO.Path]::GetFullPath((Join-Path $InstallerRoot '..'))
    $project=Join-Path $repo 'src/Jaws.Supervisor.Host/Jaws.Supervisor.Host.csproj'
    $dockerfile=Join-Path $repo 'src/Jaws.Supervisor.Host/Dockerfile'
    if (-not (Test-Path -LiteralPath $project -PathType Leaf) -or
        -not (Test-Path -LiteralPath $dockerfile -PathType Leaf)) {
        throw 'JAWS-PACKAGE-001: Supervisor host project or Dockerfile missing.'
    }
    [pscustomobject]@{
        Mode='LocalPackage'
        ProjectPath=$project
        DockerfilePath=$dockerfile
        BuildContext=(Split-Path -Parent $project)
        OutputPath=(Join-Path $InstallerRoot '.local/supervisor/publish')
        DockerTag='jaws-supervisor:local'
        CanPushToRegistry=$false
        AzureWrites=0
        CloudDeployment='NOT_PERFORMED'
    }
}

function Invoke-JawsSupervisorLocalBuild {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$PackagePlan,[switch]$BuildContainer)
    if ($PackagePlan.Mode -ne 'LocalPackage' -or $PackagePlan.AzureWrites -ne 0 -or
        $PackagePlan.CanPushToRegistry -ne $false) {
        throw 'JAWS-PACKAGE-002: Unsafe or unsupported package plan.'
    }
    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
        throw 'JAWS-PACKAGE-003: .NET SDK not found. Install .NET 10 before packaging.'
    }
    # Only the fixed repository Supervisor project is built, no operator-supplied commands.
    & dotnet publish $PackagePlan.ProjectPath '-c' 'Release' '--output' $PackagePlan.OutputPath
    if ($LASTEXITCODE -ne 0) { throw "JAWS-PACKAGE-004: dotnet publish failed ($LASTEXITCODE)." }
    if ($BuildContainer) {
        if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
            throw 'JAWS-PACKAGE-005: Docker not available; published binaries remain local.'
        }
        # Buildx keeps the image as an OCI index with OCI layers, which Foundry can provision.
        & docker buildx build '--platform' 'linux/amd64' '--tag' $PackagePlan.DockerTag '--file' $PackagePlan.DockerfilePath '--load' $PackagePlan.BuildContext
        if ($LASTEXITCODE -ne 0) { throw "JAWS-PACKAGE-006: Docker build failed ($LASTEXITCODE)." }
    }
    return [pscustomobject]@{
        Status='LOCAL_PACKAGE_CREATED'
        OutputPath=$PackagePlan.OutputPath
        ContainerBuilt=[bool]$BuildContainer
        ContainerTag=if ($BuildContainer) {$PackagePlan.DockerTag} else {$null}
        AzureWrites=0
        RegistryPushPerformed=$false
        FoundryDeploymentPerformed=$false
    }
}
Export-ModuleMember -Function Get-JawsSupervisorPackagePlan,Invoke-JawsSupervisorLocalBuild
