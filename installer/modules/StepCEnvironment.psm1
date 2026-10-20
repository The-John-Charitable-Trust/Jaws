# Step C names for an environment created by Step B.
# The dev project is not resolved here. Install-JawsThroughStepC.ps1 keeps that path.
Set-StrictMode -Version Latest

function Get-JawsStepCA2AEndpoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectEndpoint,
        [Parameter(Mandatory)][string]$EnvironmentName
    )
    if ($EnvironmentName -ceq 'dev') { return $ProjectEndpoint }
    if ($ProjectEndpoint -notmatch '^https://(?<account>[a-z0-9-]+)\.services\.ai\.azure\.com/api/projects/(?<project>[a-z0-9-]+)$') {
        throw 'JAWS-DELEGATE-010: Project endpoint is not a Step B Foundry project URL.'
    }
    # Foundry-to-Foundry A2A uses this services.ai.azure.com project route for every environment.
    # On a private-from-create account the same name resolves to the private endpoint.
    return $ProjectEndpoint
}

function Get-JawsStepCReservedNames {
    [CmdletBinding()]
    param()
    return @(
        'dev',
        'rg-aiops-lab',
        'jaws-foundry-dev',
        'jaws-dev',
        'jawsregistrydev001',
        'jaws-supervisor-dev',
        'kv-jaws-dev-001',
        'jaws-investigation-dev',
        'jaws-investigation-planner-dev',
        'jaws-investigation-a2a-dev'
    )
}

function Resolve-JawsStepCStepBContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$EnvironmentName,
        [Parameter(Mandatory)][string]$InstallerRoot
    )
    if ($EnvironmentName -ceq 'dev') {
        throw 'JAWS-INSTALL-C-014: The Step B path refuses the accepted dev environment. Run Install-JawsThroughStepC.ps1 without -EnvironmentName for that project.'
    }
    if ($EnvironmentName -notmatch '^[a-z][a-z0-9-]{1,20}$') {
        throw 'JAWS-INSTALL-C-015: Environment name must be 2-21 characters, start with a letter, and use lowercase letters, digits, and hyphens.'
    }
    $local = Join-Path $InstallerRoot '.local'
    $receiptPath = Join-Path $local "jaws-step-b-install.$EnvironmentName.generated.json"
    $statePath = Join-Path $local "jaws-installation-state.$EnvironmentName.generated.json"
    if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf) -or -not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
        throw "JAWS-INSTALL-C-016: Step B receipt and generated state are required before Step C ($receiptPath)."
    }
    $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
    Import-Module (Join-Path $InstallerRoot 'modules/InstallationState.psm1') -Force
    $state = Read-JawsInstallationState -Path $statePath
    if ($null -eq $state) { throw 'JAWS-INSTALL-C-016: Step B installation state could not be read.' }
    if ([string]$receipt.Status -cne 'STEP_B_INSTALLED') {
        throw 'JAWS-INSTALL-C-016: Step B receipt is not STEP_B_INSTALLED. Step C does not create the foundation.'
    }
    if ([string]$state.StateAuthority -cne 'InstallerGenerated' -or [string]$state.EnvironmentName -cne $EnvironmentName -or [string]$receipt.EnvironmentName -cne $EnvironmentName) {
        throw 'JAWS-INSTALL-C-019: Step B state does not belong to this environment.'
    }
    foreach ($reserved in (Get-JawsStepCReservedNames)) {
        foreach ($value in @(
            [string]$receipt.EnvironmentName,
            [string]$receipt.ResourceGroupName,
            [string]$receipt.FoundryAccountName,
            [string]$receipt.ProjectName,
            [string]$receipt.RegistryName,
            [string]$receipt.AgentName,
            [string]$receipt.KeyVaultName
        )) {
            if ($value -ceq $reserved) {
                throw "JAWS-INSTALL-C-017: Refusing dev resource '$reserved' in the Step B environment."
            }
        }
    }
    if ([string]$receipt.Image -match 'jawsregistrydev001\.azurecr\.io' -or [string]$receipt.FoundryAccountName -ceq 'jaws-foundry-dev') {
        throw 'JAWS-INSTALL-C-017: Refusing the dev Foundry host or dev registry.'
    }
    Import-Module (Join-Path $InstallerRoot 'modules/StepBInstall.psm1') -Force
    $stepB = Get-Module StepBInstall
    $names = & $stepB {
        param($EnvironmentName, $ModelName)
        New-JawsStepBResourceNames -EnvironmentName $EnvironmentName -ModelName $ModelName
    } $EnvironmentName ([string]$receipt.ModelName)
    $endpoint = "https://$($names.FoundryAccountName).services.ai.azure.com/api/projects/$($names.ProjectName)"
    $a2aEndpoint = Get-JawsStepCA2AEndpoint -ProjectEndpoint $endpoint -EnvironmentName $EnvironmentName
    $login = "$($names.RegistryName).azurecr.io"
    $imagePattern = '^' + [regex]::Escape($login) + '/jaws/supervisor@sha256:[a-f0-9]{64}$'
    $checks = @(
        @{ Name = 'SubscriptionId'; Receipt = [string]$receipt.SubscriptionId; State = [string]$state.SubscriptionId },
        @{ Name = 'ResourceGroupName'; Receipt = [string]$receipt.ResourceGroupName; State = [string]$state.ResourceGroupName },
        @{ Name = 'FoundryAccountName'; Receipt = [string]$receipt.FoundryAccountName; State = [string]$names.FoundryAccountName },
        @{ Name = 'ProjectName'; Receipt = [string]$receipt.ProjectName; State = [string]$names.ProjectName },
        @{ Name = 'RegistryName'; Receipt = [string]$receipt.RegistryName; State = [string]$names.RegistryName },
        @{ Name = 'AgentName'; Receipt = [string]$receipt.AgentName; State = [string]$names.AgentName },
        @{ Name = 'KeyVaultName'; Receipt = [string]$receipt.KeyVaultName; State = [string]$names.KeyVaultName },
        @{ Name = 'ModelDeploymentName'; Receipt = [string]$receipt.ModelDeploymentName; State = [string]$names.ModelDeploymentName }
    )
    $mismatch = @($checks | Where-Object { $_.Receipt -cne $_.State } | ForEach-Object { $_.Name })
    if ([string]$state.SubscriptionId -ine [string]$receipt.SubscriptionId) { $mismatch += 'SubscriptionIdCase' }
    if ([string]$receipt.RegistryLoginServer -cne $login) { $mismatch += 'RegistryLoginServer' }
    if ([string]$receipt.Image -cnotmatch $imagePattern) { $mismatch += 'Image' }
    if ([string]$receipt.AgentVersion -cne '1') { $mismatch += 'AgentVersion' }
    if ($mismatch.Count -gt 0) {
        throw "JAWS-INSTALL-C-019: Step B receipt does not match this environment ($($mismatch -join ', '))."
    }
    if ($endpoint -match 'jaws-foundry-dev\.services\.ai\.azure\.com') {
        throw 'JAWS-INSTALL-C-017: Refusing the dev Foundry host or dev registry.'
    }
    $planner = "jaws-investigation-planner-$EnvironmentName"
    $connection = "jaws-investigation-a2a-$EnvironmentName"
    [pscustomobject]@{
        Profile = 'StepB'
        EnvironmentName = $EnvironmentName
        StateFile = $statePath
        ReceiptFile = $receiptPath
        SubscriptionId = [string]$receipt.SubscriptionId
        ResourceGroupName = [string]$receipt.ResourceGroupName
        Location = [string]$receipt.Location
        FoundryAccountName = [string]$names.FoundryAccountName
        ProjectName = [string]$names.ProjectName
        ProjectEndpoint = $endpoint
        A2AEndpoint = $a2aEndpoint
        SupervisorAgent = [string]$names.AgentName
        PlannerAgent = $planner
        ConnectionName = $connection
        ToolboxName = 'jaws-investigation-a2a-tools'
        ModelName = [string]$receipt.ModelName
        ModelDeploymentName = [string]$receipt.ModelDeploymentName
        ExpectedImage = [string]$receipt.Image
        RegistryName = [string]$names.RegistryName
        RegistryLoginServer = $login
        PlanSuffix = $EnvironmentName
        HostedInvestigationConfigured = $false
        CustomerInstallationAccepted = $false
    }
}

Export-ModuleMember -Function Get-JawsStepCA2AEndpoint, Get-JawsStepCReservedNames, Resolve-JawsStepCStepBContext
