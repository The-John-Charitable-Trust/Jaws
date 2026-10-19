# JAWS Installer 0.4.10 - greenfield discovery, plan, preflight, package, approved Step B install, and live acceptance
[CmdletBinding()]
param(
    [ValidateSet('Discover','Plan','Preflight','Package','Install','Accept')][string]$Mode='Discover',
    [string]$PlanFile,
    [switch]$AzureAware,
    [switch]$BuildContainer,
    [string]$SupervisorImage,
    [string]$RegistryName,
    [string]$SupervisorName='jaws-supervisor-dev',
    [string]$SubscriptionId,
    [string]$ResourceGroupName,
    [string]$EnvironmentName='dev',
    [string]$Location,
    [string]$ModelName='gpt-5-mini',
    [string]$ModelVersion='2025-08-07',
    [ValidateSet('Static','Dynamic')][string]$QuotaMode='Static',
    [switch]$AcknowledgeStepBInstall,
    [string]$ApprovedPlanSha256,
    [string]$StateFile,
    [switch]$NonInteractive
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$jawsMilestoneStarted = Get-Date
Import-Module (Join-Path $PSScriptRoot 'modules/MilestoneResult.psm1') -Force
# Package is an explicitly local build. It has no Azure login, push or deployment path.
if ($Mode -eq 'Package') {
    if ($AzureAware -or $SupervisorImage -or $RegistryName -or $PlanFile -or $StateFile) {
        throw 'JAWS-PACKAGE-007: Package mode is local-only; Azure-aware planning flags are not accepted.'
    }
    Import-Module (Join-Path $PSScriptRoot 'modules/SupervisorPackage.psm1') -Force
    $package=Get-JawsSupervisorPackagePlan -InstallerRoot $PSScriptRoot
    $result=Invoke-JawsSupervisorLocalBuild -PackagePlan $package -BuildContainer:$BuildContainer
    if ($result.Status -ne 'LOCAL_PACKAGE_CREATED' -or $result.AzureWrites -ne 0 -or
        $result.RegistryPushPerformed -or $result.FoundryDeploymentPerformed) {
        throw 'JAWS-STEP-B-005: Local package result is not a Step B pass.'
    }
    $outputDir = Join-Path $PSScriptRoot '.local'
    if (-not (Test-Path -LiteralPath $outputDir)) { New-Item -ItemType Directory -Path $outputDir -Force | Out-Null }
    $packageReport=[pscustomobject]@{
        SchemaVersion='1.0'
        Mode='Package'
        Status=[string]$result.Status
        OutputPath=[string]$result.OutputPath
        ProjectPath=[string]$package.ProjectPath
        ContainerBuilt=[bool]$result.ContainerBuilt
        ContainerTag=$(if ($result.ContainerTag) {[string]$result.ContainerTag} else {$null})
        AzureWrites=0
        RegistryPushPerformed=$false
        FoundryDeploymentPerformed=$false
    }
    $packageReportPath=Join-Path $outputDir 'jaws-step-b-package.generated.json'
    $packageReport | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $packageReportPath -Encoding utf8
    Write-Host 'JAWS SUPERVISOR LOCAL PACKAGE: NO AZURE WRITES OR DEPLOYMENT' -ForegroundColor Cyan
    Write-Host 'STEP-B PACKAGE PASS'
    Write-Host "Status: $($packageReport.Status)"
    Write-Host 'Azure writes: 0'
    Write-Host 'Registry push: false'
    Write-Host 'Foundry deployment: false'
    Write-Host ("Container built: " + $(if ($packageReport.ContainerBuilt) {'true'} else {'false'}))
    if ($packageReport.ContainerBuilt) { Write-Host "Container tag: $($packageReport.ContainerTag)" }
    Write-Host "Output: $($packageReport.OutputPath)"
    Write-Host "Report: $packageReportPath"
    Write-JawsMilestoneResult -Result PASS -ReadyForNextStep $false -NextStep 'Step B Plan' -EvidencePath $packageReportPath
    return
}
if ($BuildContainer) { throw 'JAWS-PACKAGE-008: -BuildContainer applies only to -Mode Package.' }
# Plan validates the blueprint offline. A placeholder subscription is captured from
# the subscription already selected in Azure CLI. The example blueprint is not edited.
if ($Mode -eq 'Plan') {
    Import-Module (Join-Path $PSScriptRoot 'modules/DeploymentPlan.psm1') -Force
    if (-not $PlanFile) { $PlanFile = Join-Path $PSScriptRoot 'config/jaws-stage-b-plan.example.json' }
    $examplePath = Join-Path $PSScriptRoot 'config/jaws-stage-b-plan.example.json'
    $exampleBefore = Get-Content -LiteralPath $examplePath -Raw
    $blueprint = Get-Content -LiteralPath $PlanFile -Raw | ConvertFrom-Json
    $resolvedSubscription = $null
    $subscriptionSource = 'Blueprint'
    if ($SubscriptionId) {
        $resolvedSubscription = $SubscriptionId
        $subscriptionSource = 'Parameter'
    } elseif (Test-JawsPlaceholderSubscriptionId ([string]$blueprint.Scope.SubscriptionId)) {
        Import-Module (Join-Path $PSScriptRoot 'modules/AzurePreflight.psm1') -Force
        $selectedAccount = Get-JawsAuthorizedSubscriptions -NonInteractive:$NonInteractive
        $resolvedSubscription = [string]$selectedAccount.Account.id
        $subscriptionSource = 'AzureCli'
        if (Test-JawsPlaceholderSubscriptionId $resolvedSubscription) {
            throw 'JAWS-PLAN-011: Azure CLI has no selected subscription. Run az login and az account set. The example blueprint is not edited.'
        }
    }
    $planArgs=@{ BlueprintPath = $PlanFile }
    if ($resolvedSubscription) {
        $planArgs.SubscriptionId = $resolvedSubscription
        $planArgs.SubscriptionSource = $subscriptionSource
    }
    $offlinePlan = New-JawsOfflineDeploymentPlan @planArgs
    $exampleAfter = Get-Content -LiteralPath $examplePath -Raw
    if ($exampleAfter -ne $exampleBefore) { throw 'JAWS-PLAN-012: Plan mode rewrote the example blueprint.' }
    if ($PSBoundParameters.ContainsKey('EnvironmentName') -and $PSBoundParameters.ContainsKey('ResourceGroupName') -and $PSBoundParameters.ContainsKey('Location')) {
        Import-Module (Join-Path $PSScriptRoot 'modules/StepBInstall.psm1') -Force
        $installScope = New-JawsStepBInstallScope -SubscriptionId $offlinePlan.SubscriptionId -ResourceGroupName $ResourceGroupName -Location $Location -EnvironmentName $EnvironmentName -ModelName $ModelName -ModelVersion $ModelVersion
        $offlinePlan | Add-Member -NotePropertyName InstallScope -NotePropertyValue $installScope -Force
        $offlinePlan | Add-Member -NotePropertyName PlanSha256 -NotePropertyValue $installScope.PlanSha256 -Force
        $offlinePlan.ResourceGroupName = $installScope.ResourceGroupName
        $offlinePlan.Location = $installScope.Location
        $offlinePlan.EnvironmentName = $installScope.EnvironmentName
    }
    $planResult = $offlinePlan
    if ($AzureAware) {
        Import-Module (Join-Path $PSScriptRoot 'modules/AzurePreflight.psm1') -Force
        Import-Module (Join-Path $PSScriptRoot 'modules/ResourceDiscovery.psm1') -Force
        Import-Module (Join-Path $PSScriptRoot 'modules/InstallationState.psm1') -Force
        Import-Module (Join-Path $PSScriptRoot 'modules/AzureDeploymentPlan.psm1') -Force
        if (-not $StateFile) { $StateFile=Join-Path $PSScriptRoot "config/jaws-installation-state.$($offlinePlan.EnvironmentName).json" }
        $planState=Read-JawsInstallationState -Path $StateFile
        if (-not $planState) { throw "JAWS-PLAN-009: Azure-aware Plan requires authoritative installation state at '$StateFile'." }
        if ($offlinePlan.SubscriptionId -ine $planState.SubscriptionId -or
            $offlinePlan.ResourceGroupName -ine $planState.ResourceGroupName -or
            $offlinePlan.EnvironmentName -ine $planState.EnvironmentName) {
            throw 'JAWS-PLAN-010: Blueprint target differs from authoritative state.'
        }
        $planResult=New-JawsAzureReadOnlyDeploymentPlan -OfflinePlan $offlinePlan -State $planState -NonInteractive:$NonInteractive
    }
    if ($RegistryName) {
        if (-not $AzureAware) { throw 'JAWS-ACR-007: Registry assessment requires Azure-aware Plan.' }
        Import-Module (Join-Path $PSScriptRoot 'modules/RegistryReadiness.psm1') -Force
        $registryAssessment=Get-JawsRegistryReadOnlyAssessment -RegistryName $RegistryName -SubscriptionId $planResult.SubscriptionId -ResourceGroupName $planResult.ResourceGroupName
        Write-Host "Registry: $($registryAssessment.RegistryName) | $($registryAssessment.Status)" -ForegroundColor Yellow
    }
    if ($SupervisorImage) {
        if (-not $AzureAware) { throw 'JAWS-INSTALL-006: Supervisor install proposal requires -AzureAware discovery.' }
        Import-Module (Join-Path $PSScriptRoot 'modules/SupervisorInstall.psm1') -Force
        $foundryNames=@($planState.Resources | Where-Object Type -eq 'Microsoft.CognitiveServices/accounts')
        $projectNames=@($planState.Resources | Where-Object Type -eq 'Microsoft.CognitiveServices/accounts/projects')
        $supervisorProposal=New-JawsSupervisorInstallProposal -AzurePlan $planResult -FoundryName $foundryNames[0].Name -ProjectName $projectNames[0].Name -Image $SupervisorImage -AgentName $SupervisorName
        Write-Host 'SUPERVISOR PROPOSAL ONLY: no installation, no approval, no Azure writes.' -ForegroundColor Yellow
        Write-Host "Approval fingerprint: $($supervisorProposal.ProposalSha256)"
    }
    $outputDir = Join-Path $PSScriptRoot '.local'
    if (-not (Test-Path -LiteralPath $outputDir)) { New-Item -ItemType Directory -Path $outputDir -Force | Out-Null }
    $flavor=if ($AzureAware) { "azure-readonly" } else { "offline" }
    $outputPath = Join-Path $outputDir "jaws-stage-b-plan.$($planResult.EnvironmentName).$flavor.generated.json"
    $planResult | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $outputPath -Encoding utf8
    if ($RegistryName) {
        $registryReportPath=Join-Path $outputDir "jaws-acr-readiness.$($planResult.EnvironmentName).generated.json"
        $registryAssessment | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $registryReportPath -Encoding utf8
        Write-Host "Registry readiness: $registryReportPath"
    }
    if ($SupervisorImage) {
        $proposalPath=Join-Path $outputDir "jaws-supervisor-proposal.$($planResult.EnvironmentName).generated.json"
        $supervisorProposal | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $proposalPath -Encoding utf8
        Write-Host "Supervisor proposal: $proposalPath"
    }
    Write-Host "JAWS Stage B2 $($planResult.PlanKind) - NO AZURE WRITES" -ForegroundColor Cyan
    Write-Host "Target: $($planResult.SubscriptionId) | $($planResult.ResourceGroupName) | $($planResult.Location)"
    foreach ($component in $planResult.Components) {
        Write-Host ("  {0,-20} {1,-29} {2}" -f $component.Id, $component.ProposedAction, $component.EstimatedCost)
    }
    Write-Host "Status: $($planResult.Status)" -ForegroundColor Yellow
    Write-Host "Output: $outputPath"
    Write-Host 'Azure writes: 0 | Costs, deployment permissions, user authorization and approvals: not verified'
    if (-not $AzureAware) {
        if ($planResult.AzureWrites -ne 0 -or $planResult.CanExecute -or $planResult.AzureDiscoveryPerformed -or
            $planResult.Status -ne 'BLOCKED_PENDING_AZURE_DISCOVERY_AND_APPROVAL' -or
            (Test-JawsPlaceholderSubscriptionId ([string]$planResult.SubscriptionId))) {
            throw 'JAWS-STEP-B-002: Offline plan is not a Step B pass.'
        }
        Write-Host 'STEP-B PLAN PASS'
        Write-Host "Subscription: $($planResult.SubscriptionId)"
        Write-Host "Subscription source: $($planResult.SubscriptionSource)"
        Write-Host "Resource group: $($planResult.ResourceGroupName)"
        Write-Host "Location: $($planResult.Location)"
        Write-Host "Status: $($planResult.Status)"
        Write-Host 'Can execute: false'
        Write-Host 'Azure writes: 0'
        Write-Host 'Example blueprint: unchanged'
        if ($planResult.PSObject.Properties['PlanSha256']) {
            Write-Host "Plan SHA-256: $($planResult.PlanSha256)"
            Write-Host "Foundry account: $($planResult.InstallScope.FoundryAccountName)"
            Write-Host "Project: $($planResult.InstallScope.ProjectName)"
            Write-Host "Model: $($planResult.InstallScope.ModelName) $($planResult.InstallScope.ModelVersion)"
            Write-Host "Quota mode: $QuotaMode"
            Write-Host "Registry: $($planResult.InstallScope.RegistryName)"
            Write-Host "Agent: $($planResult.InstallScope.AgentName)"
            Write-Host 'Install authorized: false'
        }
        Write-JawsMilestoneResult -Result PASS -ReadyForNextStep $true -NextStep 'Step B Preflight' -EvidencePath $outputPath
    }
    return
}
if ($Mode -eq 'Preflight') {
    if (-not $PSBoundParameters.ContainsKey('EnvironmentName') -or -not $PSBoundParameters.ContainsKey('ResourceGroupName') -or -not $PSBoundParameters.ContainsKey('Location')) {
        throw 'JAWS-STEP-B-016: Preflight requires the same -EnvironmentName, -ResourceGroupName, and -Location used to create the plan.'
    }
    Import-Module (Join-Path $PSScriptRoot 'modules/StepBInstall.psm1') -Force
    $planPath = Join-Path $PSScriptRoot ".local/jaws-stage-b-plan.$EnvironmentName.offline.generated.json"
    if (-not (Test-Path -LiteralPath $planPath -PathType Leaf)) {
        throw "JAWS-STEP-B-016: Approved plan not found at $planPath. Run -Mode Plan with the same environment, resource group, and location first."
    }
    $saved = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
    if (-not $saved.PSObject.Properties['InstallScope']) {
        throw 'JAWS-STEP-B-016: The saved plan has no install scope. Re-run Plan with -EnvironmentName, -ResourceGroupName, and -Location.'
    }
    $checked = Invoke-JawsStepBPreflight -Scope $saved.InstallScope -InstallerRoot $PSScriptRoot
    if (-not $checked.Ready) {
        Write-JawsMilestoneResult -Result FAIL -ReadyForNextStep $false -NextStep 'Step B Install' -EvidencePath $checked.ReportPath
        throw "JAWS-STEP-B-026: Step B preflight is not ready. No Azure writes were attempted. $($checked.Report.Reasons -join ' ')"
    }
    Write-Host 'STEP-B PREFLIGHT PASS'
    Write-Host 'Azure writes: 0'
    Write-Host "Plan SHA-256: $($checked.Report.PlanSha256)"
    Write-Host 'Providers: Registered'
    Write-Host "Resource write: $($checked.Report.ResourceWrite.ToString().ToLowerInvariant())"
    Write-Host "Role assignment: $($checked.Report.RoleAssignment.ToString().ToLowerInvariant())"
    Write-Host "Location: $($checked.Report.Location)"
    Write-Host 'Model quota: deferred'
    Write-Host 'Policy simulation: not performed'
    Write-Host 'Authorized writes: bounded'
    Write-Host "Report: $($checked.ReportPath)"
    Write-JawsMilestoneResult -Result PASS -ReadyForNextStep $true -NextStep 'Step B Install' -EvidencePath $checked.ReportPath
    return
}
if ($Mode -eq 'Install') {
    if (-not $PSBoundParameters.ContainsKey('EnvironmentName') -or -not $PSBoundParameters.ContainsKey('ResourceGroupName') -or -not $PSBoundParameters.ContainsKey('Location')) {
        throw 'JAWS-STEP-B-016: Install requires the same -EnvironmentName, -ResourceGroupName, and -Location used to create the plan.'
    }
    Import-Module (Join-Path $PSScriptRoot 'modules/StepBInstall.psm1') -Force
    $planPath = Join-Path $PSScriptRoot ".local/jaws-stage-b-plan.$EnvironmentName.offline.generated.json"
    if (-not (Test-Path -LiteralPath $planPath -PathType Leaf)) {
        throw "JAWS-STEP-B-016: Approved plan not found at $planPath. Run -Mode Plan with the same environment, resource group, and location first."
    }
    $saved = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
    if (-not $saved.PSObject.Properties['InstallScope']) {
        throw 'JAWS-STEP-B-016: The saved plan has no install scope. Re-run Plan with -EnvironmentName, -ResourceGroupName, and -Location.'
    }
    $installEvidence = Join-Path $PSScriptRoot ".local/jaws-step-b-install.$EnvironmentName.generated.json"
    try {
        $installed = Invoke-JawsStepBInstall -Scope $saved.InstallScope -ApprovedPlanSha256 $ApprovedPlanSha256 -InstallerRoot $PSScriptRoot -QuotaMode $QuotaMode -AcknowledgeStepBInstall:$AcknowledgeStepBInstall
    } catch {
        Save-JawsMilestoneFailure -Path $installEvidence -Message $_.Exception.Message -Started $jawsMilestoneStarted
        Write-JawsMilestoneResult -Result FAIL -ReadyForNextStep $false -NextStep 'Step B Accept' -EvidencePath $installEvidence
        throw
    }
    $done = $installed.Receipt
    Write-Host 'STEP-B INSTALL PASS'
    Write-Host "Foundry account: $($done.FoundryAccountName)"
    Write-Host "Project: $($done.ProjectName)"
    Write-Host "Model: $($done.ModelName) $($done.ModelVersion)"
    Write-Host "Quota mode: $($done.QuotaMode)"
    Write-Host "Registry: $($done.RegistryLoginServer)"
    Write-Host "Image: $($done.Image)"
    Write-Host "Agent: $($done.AgentName)"
    Write-Host "Agent version: $($done.AgentVersion)"
    Write-Host "Agent status: $($done.AgentStatus)"
    Write-Host "Azure writes: $($done.AzureWrites)"
    Write-Host "State: $($installed.StatePath)"
    Write-Host "Receipt: $($installed.ReceiptPath)"
    Write-JawsMilestoneResult -Result PASS -ReadyForNextStep $true -NextStep 'Step B Accept' -EvidencePath $installed.ReceiptPath
    return
}
if ($Mode -eq 'Accept') {
    if (-not $PSBoundParameters.ContainsKey('EnvironmentName') -or -not $PSBoundParameters.ContainsKey('ResourceGroupName') -or -not $PSBoundParameters.ContainsKey('Location')) {
        throw 'JAWS-STEP-B-016: Accept requires the same -EnvironmentName, -ResourceGroupName, and -Location used to install.'
    }
    Import-Module (Join-Path $PSScriptRoot 'modules/StepBInstall.psm1') -Force
    $acceptEvidence = Join-Path $PSScriptRoot ".local/jaws-step-b-acceptance.$EnvironmentName.generated.json"
    try {
        $accepted = Invoke-JawsStepBAccept -EnvironmentName $EnvironmentName -ResourceGroupName $ResourceGroupName -Location $Location -ModelName $ModelName -ModelVersion $ModelVersion -InstallerRoot $PSScriptRoot
    } catch {
        Save-JawsMilestoneFailure -Path $acceptEvidence -Message $_.Exception.Message -Started $jawsMilestoneStarted
        Write-JawsMilestoneResult -Result FAIL -ReadyForNextStep $false -NextStep 'Step C Validate' -EvidencePath $acceptEvidence
        throw
    }
    $live = $accepted.Report
    Write-Host 'STEP-B ACCEPTANCE PASS'
    Write-Host 'Live Azure read: true'
    Write-Host 'Azure writes: 0'
    Write-Host "Foundry account: $($live.FoundryAccountName)"
    Write-Host "Foundry provisioning: $($live.FoundryProvisioningState)"
    Write-Host "Project: $($live.ProjectName)"
    Write-Host "Model: $($live.ModelName) $($live.ModelVersion)"
    Write-Host "Quota mode: $($live.QuotaMode)"
    Write-Host "Deployment: $($live.DeploymentProvisioningState)"
    Write-Host "Registry admin: false"
    Write-Host 'AcrPull: true'
    Write-Host "Image: $($live.Image)"
    Write-Host "Agent: $($live.AgentName)"
    Write-Host 'Agent version: 1'
    Write-Host 'Agent status: active'
    Write-Host 'Dev state: unchanged'
    Write-Host "Receipt: $($live.ReceiptPath)"
    Write-JawsMilestoneResult -Result PASS -ReadyForNextStep $true -NextStep 'Step C Validate' -EvidencePath $accepted.ReportPath
    return
}
Import-Module (Join-Path $PSScriptRoot 'modules/AzurePreflight.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'modules/ResourceDiscovery.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'modules/ResourceManifest.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'modules/InstallationState.psm1') -Force

# The operator-maintained state is the GOLD COPY. Never overwrite it in Discover.
Import-Module (Join-Path $PSScriptRoot 'modules/StepADiscovery.psm1') -Force
$stateFileWasExplicit = $PSBoundParameters.ContainsKey('StateFile')
if (-not $StateFile) { $StateFile=Join-Path $PSScriptRoot "config/jaws-installation-state.$EnvironmentName.json" }
if ($stateFileWasExplicit -and -not (Test-Path -LiteralPath $StateFile -PathType Leaf)) {
    throw "JAWS-STATE-003: No installation state at '$StateFile'. Discover does not create a JAWS state file."
}
if (-not (Test-Path -LiteralPath $StateFile -PathType Leaf)) {
    $discovered = Invoke-JawsStepAGreenfieldDiscovery -EnvironmentName $EnvironmentName -SubscriptionId $SubscriptionId -ResourceGroupName $(if ($PSBoundParameters.ContainsKey('ResourceGroupName')) { $ResourceGroupName } else { '' }) -Location $(if ($PSBoundParameters.ContainsKey('Location')) { $Location } else { '' }) -InstallerRoot $PSScriptRoot -NonInteractive:$NonInteractive
    $found = $discovered.Receipt
    Write-Host 'STEP-A DISCOVERY PASS'
    Write-Host 'Discovery: Greenfield'
    Write-Host "Subscription source: $($found.SubscriptionSource)"
    Write-Host "Subscription: $($found.SubscriptionId)"
    Write-Host "Tenant: $($found.TenantId)"
    Write-Host "Resource groups: $($found.ResourceGroupCount)"
    Write-Host "Resources: $($found.ResourceCount)"
    Write-Host "JAWS candidates: $($found.CandidateCount)"
    Write-Host 'State file required: false'
    Write-Host 'State file written: false'
    Write-Host 'Azure writes: 0'
    Write-Host "Prepared for Step B: $($found.PreparedForStepB.ToString().ToLowerInvariant())"
    if ($found.PreparedForStepBReason) { Write-Host "Prepared for Step B reason: $($found.PreparedForStepBReason)" }
    Write-Host "Next command: $($found.NextCommand)"
    Write-Host "Receipt: $($discovered.ReceiptPath)"
    Write-JawsMilestoneResult -Result PASS -ReadyForNextStep ([bool]$found.PreparedForStepB) -NextStep 'Step B Plan' -EvidencePath $discovered.ReceiptPath
    return
}
$state=Read-JawsInstallationState -Path $StateFile
if (-not $state) { throw "JAWS-STATE-003: Installation state at '$StateFile' could not be read. Discover does not replace it." }
if ($state.EnvironmentName -ine $EnvironmentName) { throw 'JAWS-STATE-002: Environment name does not match the JAWS state.' }
if ($SubscriptionId -and $SubscriptionId -ine $state.SubscriptionId) { throw 'JAWS-STATE-002: Subscription differs from the authoritative state.' }
if ($ResourceGroupName -and $ResourceGroupName -ine $state.ResourceGroupName) { throw 'JAWS-STATE-002: Resource group differs from the authoritative state.' }
$SubscriptionId=[string]$state.SubscriptionId
$ResourceGroupName=[string]$state.ResourceGroupName
Write-Host "JAWS Installer v0.4.10 | $Mode | State-first verification" -ForegroundColor Cyan
Write-Host "Authoritative state: $StateFile"
Write-Host "Target: $SubscriptionId | $ResourceGroupName"
$context=Get-JawsAuthorizedSubscriptions -NonInteractive:$NonInteractive
$selected=Select-JawsSubscription -Subscriptions $context.Subscriptions -SubscriptionId $SubscriptionId -NonInteractive:$NonInteractive
$tenantId=[string]$selected.tenantId
$null=Select-JawsResourceGroup -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -NonInteractive:$NonInteractive
$scan=Get-JawsTenantInstallationScan -Subscriptions $context.Subscriptions -TenantId $tenantId
$local=Join-Path $PSScriptRoot '.local'
if (-not (Test-Path $local)) { New-Item -ItemType Directory -Path $local -Force | Out-Null }
$scanPath=Join-Path $local "jaws-tenant-scan.$EnvironmentName.generated.json"
$scan | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $scanPath -Encoding utf8
Write-Host "TENANT SCAN: $(@($scan.Subscriptions | Where-Object Status -eq 'Scanned').Count)/$($scan.SubscriptionCount) subscriptions" -ForegroundColor Cyan
foreach($sub in @($scan.Subscriptions)) { Write-Host ("  {0,-38} {1,-8} Resources: {2}" -f $sub.SubscriptionId,$sub.Status,$sub.ResourceCount) }
if (-not $scan.Completed) { throw "JAWS-SCAN-002: Tenant scan incomplete. Report: $scanPath. Authoritative JAWS state unchanged." }
$scanMatches=Compare-JawsTenantScanToState -State $state -Scan $scan
Write-Host 'TENANT SCAN VS. JAWS STATE' -ForegroundColor Cyan
foreach($m in $scanMatches) { Write-Host ("  {0,-26} {1}" -f $m.Name,$m.Status) }
# Ignore legacy infrastructure entirely in the customer-facing JAWS reports.
# Targeted discovery is authoritative on actual presence; tenant naming heuristic is only informative.
$foundry=@($state.Resources | Where-Object Type -eq 'Microsoft.CognitiveServices/accounts')
$project=@($state.Resources | Where-Object Type -eq 'Microsoft.CognitiveServices/accounts/projects')
$model=@($state.Resources | Where-Object Type -eq 'Microsoft.CognitiveServices/accounts/deployments')
$vault=@($state.Resources | Where-Object Type -eq 'Microsoft.KeyVault/vaults')
if ($foundry.Count -ne 1 -or $project.Count -ne 1 -or $model.Count -ne 1 -or $vault.Count -ne 1) { throw 'JAWS-STATE-007: Stage A requires exactly one Foundry resource, project, deployment, and vault in the state JSON.' }
$items=@()
$items+=Get-JawsAzureResource -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -ResourceName $foundry[0].Name -ResourceType $foundry[0].Type
$items+=Get-JawsFoundryProject -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -FoundryResourceName $foundry[0].Name -ProjectName $project[0].Name
$items+=Get-JawsModelDeployment -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -FoundryResourceName $foundry[0].Name -DeploymentName $model[0].Name
$items+=Get-JawsAzureResource -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -ResourceName $vault[0].Name -ResourceType $vault[0].Type
$comparison=Compare-JawsTargetDiscoveryToState -State $state -Results $items
$manifestPath=Join-Path $local "jaws-resources.$EnvironmentName.generated.json"
$manifest=New-JawsResourceManifest -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -EnvironmentName $EnvironmentName -ExistingPath $manifestPath
foreach($item in $items) {
    $ex=@($state.Resources | Where-Object { $_.Name -ieq $item.Name -and $_.Type -ieq $item.Type })[0]
    $expected=$null
    if ($item.Type -eq 'Microsoft.CognitiveServices/accounts/deployments') {
        $expected=[pscustomobject]@{ModelName=$ex.ExpectedConfiguration.ModelName;ModelVersion=$ex.ExpectedConfiguration.ModelVersion;ProvisioningState=$ex.ExpectedConfiguration.ProvisioningState}
    }
    $manifest=Add-JawsManifestResource -Manifest $manifest -DiscoveryResult $item -ExpectedConfiguration $expected
}
# Refuse to persist a current-state manifest over an identity mismatch.
if (@($comparison | Where-Object Status -eq 'IdentityDrift').Count -gt 0) { throw 'JAWS-STATE-008: Resource identity mismatch. State unchanged and manifest not rewritten.' }
Save-JawsResourceManifest -Manifest $manifest -Path $manifestPath | Out-Null
$report=[pscustomobject]@{SchemaVersion='1.0';EnvironmentName=$EnvironmentName;StateFile=$StateFile;TenantScan=$scanMatches;TargetDiscovery=$comparison;CompletedAtUtc=(Get-Date).ToUniversalTime().ToString('o')}
$reportPath=Join-Path $local "jaws-state-comparison.$EnvironmentName.generated.json"
$report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $reportPath -Encoding utf8
Write-Host 'JAWS TARGET RESOURCE COMPARISON' -ForegroundColor Cyan
foreach($m in $comparison) { Write-Host ("  {0,-26} {1,-20} {2}" -f $m.Name,$m.Status,$m.ObservedResourceId) }
Write-Host "Manifest: $manifestPath"
Write-Host "Comparison report: $reportPath"
Write-Host 'JAWS golden state JSON: unchanged (Discover mode).' -ForegroundColor Green
Write-Host 'Azure writes: 0'
$readyForStepB = ($EnvironmentName -ne 'dev' -and $ResourceGroupName -ne 'rg-aiops-lab')
Write-Host 'STEP-A DISCOVERY PASS'
Write-JawsMilestoneResult -Result PASS -ReadyForNextStep $readyForStepB -NextStep 'Step B Plan' -EvidencePath $reportPath
