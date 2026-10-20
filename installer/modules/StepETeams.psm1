# Step E publishes the Supervisor to Teams. Specialists are not published.
# Install creates one Azure Bot with public network access disabled and calls the
# Foundry Microsoft 365 publish API with publishScope Shared.
# Accept re-reads that bot. It does not record a Teams reply.
# This module does not modify Supervisor version 1 or the dev installation state.
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'StepRoadmap.psm1') -Force

function Get-JawsStepEContext {
    param([Parameter(Mandatory)][string]$EnvironmentName,[Parameter(Mandatory)][string]$InstallerRoot)
    Assert-JawsRoadmapEnvironment -EnvironmentName $EnvironmentName -Code 'JAWS-STEP-E-014'
    $acceptPath = Join-Path $InstallerRoot ".local/jaws-step-d-acceptance.$EnvironmentName.generated.json"
    if (-not (Test-Path -LiteralPath $acceptPath -PathType Leaf)) {
        throw "JAWS-STEP-E-002: Step D acceptance evidence was not found: $acceptPath"
    }
    $accept = Get-Content -LiteralPath $acceptPath -Raw | ConvertFrom-Json
    if ([string]$accept.Result -ne 'PASS') { throw 'JAWS-STEP-E-002: Step D acceptance is not PASS.' }
    $receiptPath = Join-Path $InstallerRoot ".local/jaws-step-b-install.$EnvironmentName.generated.json"
    if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) {
        throw "JAWS-STEP-E-016: Step B install receipt was not found: $receiptPath"
    }
    $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
    $devState = Join-Path $InstallerRoot 'config/jaws-installation-state.dev.json'
    $account = [string]$receipt.FoundryAccountName
    $project = [string]$receipt.ProjectName
    $supervisor = [string]$receipt.AgentName
    return [pscustomobject]@{
        EnvironmentName = $EnvironmentName
        FoundryAccountName = $account
        ProjectName = $project
        SupervisorAgent = $supervisor
        ResourceGroupName = [string]$receipt.ResourceGroupName
        SubscriptionId = [string]$receipt.SubscriptionId
        Endpoint = "https://$account.services.ai.azure.com/api/projects/$project"
        ActivityEndpoint = "https://$account.services.ai.azure.com/api/projects/$project/agents/$supervisor/endpoint/protocols/activityProtocol"
        BotName = "jaws-teams-$EnvironmentName"
        DevStatePath = $devState
        DevStateBefore = $(if (Test-Path -LiteralPath $devState) { Get-Content -LiteralPath $devState -Raw } else { '' })
    }
}

function Assert-JawsStepEDevState {
    param($Context)
    if (-not (Test-Path -LiteralPath $Context.DevStatePath)) { return }
    $current = Get-Content -LiteralPath $Context.DevStatePath -Raw
    if ($current -ne $Context.DevStateBefore) { throw 'JAWS-STEP-E-023: Step E changed the dev installation state.' }
}

function Get-JawsStepESupervisorImage {
    param($Context)
    $url = "$($Context.Endpoint)/agents/$($Context.SupervisorAgent)/versions/1?api-version=v1"
    $version = Invoke-JawsRoadmapAz -AllowMissing -Arguments @('rest','--method','GET','--url',$url,'--resource','https://ai.azure.com','--output','json','--only-show-errors')
    if ($null -eq $version) { return '' }
    return [string]$version.definition.container_configuration.image
}

function Invoke-JawsStepEValidate {
    param([Parameter(Mandatory)][string]$EnvironmentName,[Parameter(Mandatory)][string]$InstallerRoot)
    $context = Get-JawsStepEContext -EnvironmentName $EnvironmentName -InstallerRoot $InstallerRoot
    $agent = Invoke-JawsRoadmapAz -AllowMissing -Arguments @('rest','--method','GET','--url',"$($context.Endpoint)/agents/$($context.SupervisorAgent)?api-version=v1",'--resource','https://ai.azure.com','--output','json','--only-show-errors')
    if ($null -eq $agent) { throw "JAWS-STEP-E-020: Supervisor $($context.SupervisorAgent) was not found." }
    $path = Join-Path $InstallerRoot ".local/jaws-step-e-validate.$EnvironmentName.generated.json"
    Save-JawsRoadmapEvidence -Path $path -Payload ([pscustomobject]@{
        SchemaVersion = '1.0'
        Result = 'PASS'
        Status = 'STEP_E_VALIDATED'
        EnvironmentName = $EnvironmentName
        SupervisorAgent = $context.SupervisorAgent
        PublishScope = 'Shared'
        SpecialistsPublished = $false
        AzureWrites = 0
        CustomerInstallationAccepted = $false
        FedRAMPModerate = $false
        CompletedAtUtc = [DateTime]::UtcNow.ToString('o')
    }) | Out-Null
    Assert-JawsStepEDevState $context
    return [pscustomobject]@{ EvidencePath = $path; ReadyForNextStep = $true; NextStep = 'Step E Install'; AzureWrites = 0 }
}

function Invoke-JawsStepEInstall {
    param(
        [Parameter(Mandatory)][string]$EnvironmentName,
        [Parameter(Mandatory)][string]$InstallerRoot,
        [switch]$AcknowledgeStepEInstall
    )
    if (-not $AcknowledgeStepEInstall) {
        throw 'JAWS-STEP-E-001: Install requires -AcknowledgeStepEInstall. Validate creates no bot.'
    }
    $context = Get-JawsStepEContext -EnvironmentName $EnvironmentName -InstallerRoot $InstallerRoot
    $imageBefore = Get-JawsStepESupervisorImage $context
    $agent = Invoke-JawsRoadmapAz -Arguments @('rest','--method','GET','--url',"$($context.Endpoint)/agents/$($context.SupervisorAgent)?api-version=v1",'--resource','https://ai.azure.com','--output','json','--only-show-errors')
    $clientId = ''
    if ($agent.PSObject.Properties['instance_identity'] -and $agent.instance_identity.PSObject.Properties['client_id']) {
        $clientId = [string]$agent.instance_identity.client_id
    }
    if ([string]::IsNullOrWhiteSpace($clientId)) { throw 'JAWS-STEP-E-020: Supervisor instance_identity.client_id is missing. No bot was created.' }
    $tenant = Invoke-JawsRoadmapAzText -Arguments @('account','show','--query','tenantId','--output','tsv')
    $template = Join-Path $PSScriptRoot '../templates/jaws-teams-bot.bicep'
    $deployment = Invoke-JawsRoadmapAz -Arguments @(
        'deployment','group','create',
        '--resource-group',$context.ResourceGroupName,
        '--name',"jaws-teams-$EnvironmentName",
        '--template-file',$template,
        '--parameters',"botName=$($context.BotName)","displayName=JAWS Supervisor","msaAppId=$clientId","tenantId=$tenant","endpoint=$($context.ActivityEndpoint)",
        '--output','json','--only-show-errors'
    )
    $botId = [string]$deployment.properties.outputs.botId.value
    if ([string]::IsNullOrWhiteSpace($botId)) { throw 'JAWS-STEP-E-021: The bot deployment did not return a resource id.' }
    $body = @{
        agentDisplayName = 'JAWS Supervisor'
        botServiceArmId = $botId
        publishScope = 'Shared'
        publishAsAutopilot = $false
        appVersion = '1.0.0'
        shortDescription = 'JAWS Supervisor for this environment.'
        fullDescription = 'The operator talks to the JAWS Supervisor. Specialists stay on the virtual network.'
        developerName = 'JAWS'
        developerWebsiteUrl = 'https://github.com/The-John-Charitable-Trust/Jaws'
        privacyUrl = 'https://github.com/The-John-Charitable-Trust/Jaws'
        termsOfUseUrl = 'https://github.com/The-John-Charitable-Trust/Jaws'
    } | ConvertTo-Json -Depth 6 -Compress
    $bodyFile = Join-Path $InstallerRoot ".local/jaws-step-e-publish.$EnvironmentName.json"
    Save-JawsRoadmapEvidence -Path $bodyFile -Payload ($body | ConvertFrom-Json) | Out-Null
    $published = Invoke-JawsRoadmapAz -Arguments @('rest','--method','POST','--url',"$($context.Endpoint)/agents/$($context.SupervisorAgent)/microsoft365/publish?api-version=v1",'--resource','https://ai.azure.com','--body',"@$bodyFile",'--output','json','--only-show-errors')
    $imageAfter = Get-JawsStepESupervisorImage $context
    if ($imageBefore -ne $imageAfter) { throw 'JAWS-STEP-E-019: Step E changed the Supervisor version 1 image.' }
    $title = ''
    if ($published -and $published.PSObject.Properties['titleId']) { $title = [string]$published.titleId }
    $path = Join-Path $InstallerRoot ".local/jaws-step-e-install.$EnvironmentName.generated.json"
    Save-JawsRoadmapEvidence -Path $path -Payload ([pscustomobject]@{
        SchemaVersion = '1.0'
        Result = 'PASS'
        Status = 'STEP_E_INSTALLED'
        EnvironmentName = $EnvironmentName
        SupervisorAgent = $context.SupervisorAgent
        BotName = $context.BotName
        BotResourceId = $botId
        ActivityEndpoint = $context.ActivityEndpoint
        PublishScope = 'Shared'
        TitleId = $title
        SpecialistsPublished = $false
        EnableM365PublicEndpoint = $false
        SupervisorVersion1Unchanged = $true
        TeamsReplyRecorded = $false
        AzureWrites = 2
        CustomerInstallationAccepted = $false
        FedRAMPModerate = $false
        CompletedAtUtc = [DateTime]::UtcNow.ToString('o')
    }) | Out-Null
    Assert-JawsStepEDevState $context
    return [pscustomobject]@{ EvidencePath = $path; ReadyForNextStep = $true; NextStep = 'Step E Accept'; AzureWrites = 2; TeamsReplyRecorded = $false }
}

function Invoke-JawsStepEAccept {
    param([Parameter(Mandatory)][string]$EnvironmentName,[Parameter(Mandatory)][string]$InstallerRoot)
    $context = Get-JawsStepEContext -EnvironmentName $EnvironmentName -InstallerRoot $InstallerRoot
    $installPath = Join-Path $InstallerRoot ".local/jaws-step-e-install.$EnvironmentName.generated.json"
    if (-not (Test-Path -LiteralPath $installPath -PathType Leaf)) {
        throw 'JAWS-STEP-E-024: Step E install evidence was not found.'
    }
    $install = Get-Content -LiteralPath $installPath -Raw | ConvertFrom-Json
    $bot = Invoke-JawsRoadmapAz -Arguments @('resource','show','--ids',[string]$install.BotResourceId,'--output','json','--only-show-errors')
    $endpoint = [string]$bot.properties.endpoint
    $access = [string]$bot.properties.publicNetworkAccess
    $ok = [string]$bot.id -eq [string]$install.BotResourceId -and $access -eq 'Disabled' -and $endpoint -eq [string]$install.ActivityEndpoint -and $endpoint -match [regex]::Escape($context.SupervisorAgent)
    $path = Join-Path $InstallerRoot ".local/jaws-step-e-acceptance.$EnvironmentName.generated.json"
    Save-JawsRoadmapEvidence -Path $path -Payload ([pscustomobject]@{
        SchemaVersion = '1.0'
        Result = $(if ($ok) { 'PASS' } else { 'FAIL' })
        Status = $(if ($ok) { 'STEP_E_ACCEPTED_FOR_THIS_RUN' } else { 'NOT_ACCEPTED' })
        EnvironmentName = $EnvironmentName
        SupervisorAgent = $context.SupervisorAgent
        BotResourceId = [string]$install.BotResourceId
        PublishScope = 'Shared'
        LiveAzureRead = $true
        TeamsReplyRecorded = $false
        AzureWrites = 0
        CustomerInstallationAccepted = $false
        FreshSubscriptionReceiptArchived = $false
        FedRAMPModerate = $false
        CompletedAtUtc = [DateTime]::UtcNow.ToString('o')
    }) | Out-Null
    Assert-JawsStepEDevState $context
    if (-not $ok) { throw "JAWS-STEP-E-024: The live bot does not match the Step E receipt. Evidence: $path" }
    return [pscustomobject]@{ EvidencePath = $path; ReadyForNextStep = $true; NextStep = 'Step F Validate'; AzureWrites = 0; TeamsReplyRecorded = $false }
}

Export-ModuleMember -Function Invoke-JawsStepEValidate,Invoke-JawsStepEInstall,Invoke-JawsStepEAccept
