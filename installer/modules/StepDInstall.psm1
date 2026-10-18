# Step D catalog and one hosted virtual-machine specialist.
# A prompt specialist may share that compute environment. A second sandbox, a phase agent,
# an unknown tool, or a write without the approval workflow is refused.
# This module does not modify Supervisor version 1 or the dev installation state.
Set-StrictMode -Version Latest

function Get-JawsStepDReadTools {
    @(
        'vm.get',
        'vm.identity.get',
        'vm.network.get',
        'policy.state.get',
        'defender.alert.get',
        'monitor.metrics.query',
        'monitor.logs.query'
    )
}

function Get-JawsStepDWriteTools {
    @('vm.run-command')
}

function ConvertFrom-JawsStepDJson {
    [CmdletBinding()]
    param([AllowNull()][string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $objectAt = $Text.IndexOf('{')
    $arrayAt = $Text.IndexOf('[')
    $start = $objectAt
    if ($start -lt 0 -or ($arrayAt -ge 0 -and $arrayAt -lt $start)) { $start = $arrayAt }
    if ($start -lt 0) { return $null }
    return ($Text.Substring($start) | ConvertFrom-Json)
}

function Invoke-JawsStepDAz {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Arguments,[switch]$AllowMissing)
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        throw 'JAWS-PREREQ-001: Azure CLI is not installed or not on PATH.'
    }
    $output = & az @Arguments 2>&1
    $code = $LASTEXITCODE
    $text = (@($output) | ForEach-Object { "$_" }) -join "`n"
    if ($code -ne 0) {
        if ($AllowMissing -and $text -match 'MISSING|ResourceNotFound|ResourceGroupNotFound|was not found|NotFound') {
            return $null
        }
        throw "JAWS-STEP-D-AZ-001: az $($Arguments -join ' ') failed ($code). $text"
    }
    return (ConvertFrom-JawsStepDJson $text)
}

function Start-JawsStepDPollSleep {
    $seconds = 10
    if ($env:JAWS_STEPD_POLL_SECONDS) { $seconds = [int]$env:JAWS_STEPD_POLL_SECONDS }
    if ($seconds -gt 0) { Start-Sleep -Seconds $seconds }
}

function Test-JawsStepDCatalog {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Catalog)
    $reasons = [System.Collections.Generic.List[string]]::new()
    $specialists = @($Catalog.Specialists)
    if ($specialists.Count -lt 1) { throw 'JAWS-STEP-D-003: The catalog has no specialists.' }
    $hosted = @($specialists | Where-Object { [string]$_.Kind -eq 'hosted' -and [string]$_.Id -eq 'virtual-machine' })
    if ($hosted.Count -ne 1) { throw 'JAWS-STEP-D-004: The catalog must contain exactly one hosted virtual-machine specialist.' }
    $compute = [string]$hosted[0].ComputeEnvironmentId
    if ([string]::IsNullOrWhiteSpace($compute) -or $compute -ne [string]$hosted[0].FoundryAgentName) {
        throw 'JAWS-STEP-D-006: The virtual-machine specialist compute environment must be that hosted agent and no other sandbox.'
    }
    $known = @(Get-JawsStepDReadTools) + @(Get-JawsStepDWriteTools)
    $phase = @('investigation','deliberation','remediation')
    foreach ($item in $specialists) {
        $id = [string]$item.Id
        if ($id -in $phase) { throw "JAWS-STEP-D-004: '$id' is a skill or a workflow, not a separate agent." }
        if ([string]$item.ComputeEnvironmentId -ne $compute) {
            throw "JAWS-STEP-D-006: Specialist '$id' names a second compute environment."
        }
        foreach ($tool in @($item.AllowedTools)) {
            if ([string]$tool -notin $known) { throw "JAWS-STEP-D-003: Unknown tool '$tool'." }
            if ([string]$tool -in @(Get-JawsStepDWriteTools)) {
                if ($item.WritesRequireApproval -ne $true -or [string]$item.ApprovalWorkflow -ne 'approve-vm-change') {
                    throw "JAWS-STEP-D-005: Write tool '$tool' requires the approve-vm-change workflow."
                }
            }
        }
        if ([string]$item.Kind -eq 'hosted' -and $id -ne 'virtual-machine') {
            throw "JAWS-STEP-D-006: Hosted specialist '$id' would create another sandbox."
        }
    }
    return $reasons
}

function New-JawsStepDCatalog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$EnvironmentName,
        [Parameter(Mandatory)][string]$AgentName,
        [string]$Image
    )
    [pscustomobject]@{
        SchemaVersion = '1.0'
        EnvironmentName = $EnvironmentName
        Specialists = @(
            [pscustomobject]@{
                Id = 'virtual-machine'
                FoundryAgentName = $AgentName
                Kind = 'hosted'
                Skills = @('investigate-vm-security-incident','deliberate-remediation')
                McpServer = 'azure-mcp'
                AllowedTools = @(Get-JawsStepDReadTools)
                WritesRequireApproval = $true
                ApprovalWorkflow = 'approve-vm-change'
                ComputeEnvironmentId = $AgentName
                Image = $Image
            }
        )
    }
}

function Resolve-JawsStepDContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$EnvironmentName,
        [Parameter(Mandatory)][string]$InstallerRoot
    )
    if ($EnvironmentName -notmatch '^[a-z][a-z0-9-]{1,20}$' -and $EnvironmentName -ne 'dev') {
        throw 'JAWS-STEP-D-014: Environment name must be 2-21 characters, start with a letter, and use lowercase letters, digits, and hyphens.'
    }
    $acceptancePath = Join-Path $InstallerRoot ".local/jaws-step-c-final-acceptance.$EnvironmentName.generated.json"
    if (-not (Test-Path -LiteralPath $acceptancePath -PathType Leaf)) {
        throw "JAWS-STEP-D-002: Step C acceptance evidence was not found: $acceptancePath"
    }
    $acceptance = Get-Content -LiteralPath $acceptancePath -Raw | ConvertFrom-Json
    if ([string]$acceptance.Status -ne 'PASS' -or [string]$acceptance.TaskState -ne 'TASK_STATE_COMPLETED') {
        throw "JAWS-STEP-D-002: Step C is not complete for $EnvironmentName. Status='$([string]$acceptance.Status)' TaskState='$([string]$acceptance.TaskState)'."
    }
    if ($EnvironmentName -eq 'dev') {
        $statePath = Join-Path $InstallerRoot 'config/jaws-installation-state.dev.json'
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        return [pscustomobject]@{
            EnvironmentName = 'dev'
            Profile = 'Dev'
            FoundryAccountName = 'jaws-foundry-dev'
            ProjectName = 'jaws-dev'
            AgentName = 'jaws-investigation-dev'
            SupervisorAgent = 'jaws-supervisor-dev'
            Image = $null
            ModelDeploymentName = 'gpt-5-mini'
            Endpoint = 'https://jaws-foundry-dev.services.ai.azure.com/api/projects/jaws-dev'
            StepCAcceptancePath = $acceptancePath
            DevStatePath = $statePath
            DevStateBefore = Get-Content -LiteralPath $statePath -Raw
            SubscriptionId = [string]$state.SubscriptionId
        }
    }
    $receiptPath = Join-Path $InstallerRoot ".local/jaws-step-b-install.$EnvironmentName.generated.json"
    if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) {
        throw "JAWS-STEP-D-016: Step B install receipt was not found: $receiptPath"
    }
    $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
    if ([string]$receipt.Status -ne 'STEP_B_INSTALLED') {
        throw 'JAWS-STEP-D-016: Step B receipt is not STEP_B_INSTALLED.'
    }
    foreach ($reserved in @('jaws-foundry-dev','jaws-dev','jaws-investigation-dev','jaws-supervisor-dev','jawsregistrydev001')) {
        foreach ($field in @('EnvironmentName','ResourceGroupName','FoundryAccountName','ProjectName','RegistryName','AgentName','KeyVaultName')) {
            $prop = $receipt.PSObject.Properties[$field]
            $value = if ($null -eq $prop) { '' } else { [string]$prop.Value }
            if ($value -ceq $reserved) { throw "JAWS-STEP-D-017: Refusing reserved dev name $reserved." }
        }
    }
    $imageProp = $receipt.PSObject.Properties['Image']
    $imageValue = if ($null -eq $imageProp) { '' } else { [string]$imageProp.Value }
    if ($imageValue -match 'jawsregistrydev001\.azurecr\.io') {
        throw 'JAWS-STEP-D-017: Refusing the dev registry image.'
    }
    $agent = "jaws-vm-specialist-$EnvironmentName"
    return [pscustomobject]@{
        EnvironmentName = $EnvironmentName
        Profile = 'StepB'
        FoundryAccountName = [string]$receipt.FoundryAccountName
        ProjectName = [string]$receipt.ProjectName
        AgentName = $agent
        SupervisorAgent = [string]$receipt.AgentName
        Image = [string]$receipt.Image
        ModelDeploymentName = [string]$receipt.ModelDeploymentName
        Endpoint = "https://$([string]$receipt.FoundryAccountName).services.ai.azure.com/api/projects/$([string]$receipt.ProjectName)"
        StepCAcceptancePath = $acceptancePath
        StepBReceiptPath = $receiptPath
        DevStatePath = Join-Path $InstallerRoot 'config/jaws-installation-state.dev.json'
        DevStateBefore = Get-Content -LiteralPath (Join-Path $InstallerRoot 'config/jaws-installation-state.dev.json') -Raw
        SubscriptionId = [string]$receipt.SubscriptionId
    }
}

function Get-JawsStepDAgentVersion {
    param($Context)
    $url = "$($Context.Endpoint)/agents/$($Context.AgentName)/versions/1?api-version=v1"
    return Invoke-JawsStepDAz -AllowMissing -Arguments @('rest','--method','GET','--url',$url,'--resource','https://ai.azure.com','--output','json','--only-show-errors')
}

function Get-JawsStepDSupervisorVersion {
    param($Context)
    $url = "$($Context.Endpoint)/agents/$($Context.SupervisorAgent)?api-version=v1"
    return Invoke-JawsStepDAz -AllowMissing -Arguments @('rest','--method','GET','--url',$url,'--resource','https://ai.azure.com','--output','json','--only-show-errors')
}

function Assert-JawsStepDDevState {
    param($Context)
    $current = Get-Content -LiteralPath $Context.DevStatePath -Raw
    if ($current -ne $Context.DevStateBefore) {
        throw 'JAWS-STEP-D-022: Step D changed the dev installation state.'
    }
}

function Save-JawsStepDEvidence {
    param([string]$Path,$Payload)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    $Payload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding utf8
    return $Path
}

function Invoke-JawsStepDValidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$EnvironmentName,
        [Parameter(Mandatory)][string]$InstallerRoot
    )
    $context = Resolve-JawsStepDContext -EnvironmentName $EnvironmentName -InstallerRoot $InstallerRoot
    $agent = Get-JawsStepDAgentVersion -Context $context
    $image = [string]$context.Image
    if ($null -ne $agent) {
        $image = [string]$agent.definition.container_configuration.image
    }
    $catalog = New-JawsStepDCatalog -EnvironmentName $EnvironmentName -AgentName $context.AgentName -Image $image
    $null = Test-JawsStepDCatalog -Catalog $catalog
    $local = Join-Path $InstallerRoot '.local'
    $catalogPath = Join-Path $local "jaws-specialist-catalog.$EnvironmentName.generated.json"
    Save-JawsStepDEvidence -Path $catalogPath -Payload $catalog | Out-Null
    $ready = ($EnvironmentName -ne 'dev') -or ($null -ne $agent -and [string]$agent.status -eq 'active')
    $evidencePath = Join-Path $local "jaws-step-d-validate.$EnvironmentName.generated.json"
    $payload = [pscustomobject]@{
        SchemaVersion = '1.0'
        Result = $(if ($ready) { 'PASS' } else { 'FAIL' })
        Status = $(if ($ready) { 'READY_FOR_STEP_D_INSTALL' } else { 'NOT_READY' })
        EnvironmentName = $EnvironmentName
        Profile = $context.Profile
        AgentName = $context.AgentName
        AgentPresent = ($null -ne $agent)
        CatalogPath = $catalogPath
        AzureWrites = 0
        CustomerInstallationAccepted = $false
        Reasons = @($(if (-not $ready) { 'The dev virtual-machine specialist was not readable as an active hosted agent.' }))
        CompletedAtUtc = [DateTime]::UtcNow.ToString('o')
    }
    Save-JawsStepDEvidence -Path $evidencePath -Payload $payload | Out-Null
    Assert-JawsStepDDevState -Context $context
    if (-not $ready) { throw "JAWS-STEP-D-018: The dev virtual-machine specialist is not an active hosted agent. Evidence: $evidencePath" }
    return [pscustomobject]@{
        EvidencePath = $evidencePath
        ReadyForNextStep = $true
        NextStep = 'Step D Install'
        AzureWrites = 0
    }
}

function Invoke-JawsStepDInstall {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$EnvironmentName,
        [Parameter(Mandatory)][string]$InstallerRoot,
        [switch]$AcknowledgeStepDInstall
    )
    if (-not $AcknowledgeStepDInstall) {
        throw 'JAWS-STEP-D-001: Install requires -AcknowledgeStepDInstall. -Mode Validate performs no specialist creation.'
    }
    $context = Resolve-JawsStepDContext -EnvironmentName $EnvironmentName -InstallerRoot $InstallerRoot
    $supervisorBefore = Get-JawsStepDSupervisorVersion -Context $context
    $existing = Get-JawsStepDAgentVersion -Context $context
    $writes = 0
    if ($null -eq $existing) {
        if ($EnvironmentName -eq 'dev') {
            throw 'JAWS-STEP-D-018: Step D does not create a second agent in the dev project. jaws-investigation-dev must already be active.'
        }
        if ([string]$context.Image -notmatch '@sha256:[a-f0-9]{64}$') {
            throw 'JAWS-STEP-D-018: Step B receipt has no digest-pinned image for the virtual-machine specialist.'
        }
        $body = @{
            name = $context.AgentName
            definition = @{
                kind = 'hosted'
                container_configuration = @{ image = [string]$context.Image }
                cpu = '1'
                memory = '2Gi'
                protocol_versions = @(@{ protocol = 'responses'; version = '2.0.0' })
                environment_variables = @{ AZURE_AI_MODEL_DEPLOYMENT_NAME = [string]$context.ModelDeploymentName }
            }
        } | ConvertTo-Json -Depth 8 -Compress
        $bodyFile = Join-Path $InstallerRoot ".local/jaws-step-d-agent-body.$EnvironmentName.json"
        $dir = Split-Path -Parent $bodyFile
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
        Set-Content -LiteralPath $bodyFile -Value $body -Encoding ascii
        $null = Invoke-JawsStepDAz -Arguments @('rest','--method','POST','--url',"$($context.Endpoint)/agents?api-version=v1",'--resource','https://ai.azure.com','--body',"@$bodyFile",'--output','json','--only-show-errors')
        $writes++
        $existing = $null
        for ($attempt = 0; $attempt -lt 60; $attempt++) {
            $existing = Get-JawsStepDAgentVersion -Context $context
            if ($null -ne $existing -and [string]$existing.status -eq 'failed') { throw 'JAWS-STEP-D-018: Hosted virtual-machine specialist provisioning failed.' }
            if ($null -ne $existing -and [string]$existing.status -eq 'active') { break }
            Start-JawsStepDPollSleep
        }
    }
    if ($null -eq $existing -or [string]$existing.status -ne 'active' -or $existing.draft -eq $true) {
        throw 'JAWS-STEP-D-018: Hosted virtual-machine specialist version 1 is not active.'
    }
    $image = [string]$existing.definition.container_configuration.image
    if ($image -notmatch '@sha256:[a-f0-9]{64}$') { throw 'JAWS-STEP-D-018: Virtual-machine specialist image is not digest-pinned.' }
    if ($EnvironmentName -ne 'dev' -and $image -cne [string]$context.Image) {
        throw 'JAWS-STEP-D-018: Virtual-machine specialist image differs from the Step B receipt. It was not overwritten.'
    }
    $catalog = New-JawsStepDCatalog -EnvironmentName $EnvironmentName -AgentName $context.AgentName -Image $image
    $null = Test-JawsStepDCatalog -Catalog $catalog
    $local = Join-Path $InstallerRoot '.local'
    $catalogPath = Join-Path $local "jaws-specialist-catalog.$EnvironmentName.generated.json"
    Save-JawsStepDEvidence -Path $catalogPath -Payload $catalog | Out-Null
    $supervisorAfter = Get-JawsStepDSupervisorVersion -Context $context
    if ($null -eq $supervisorBefore -or $null -eq $supervisorAfter) {
        throw 'JAWS-STEP-D-019: Supervisor inventory could not be read before and after Step D.'
    }
    $beforeJson = $supervisorBefore | ConvertTo-Json -Depth 8 -Compress
    $afterJson = $supervisorAfter | ConvertTo-Json -Depth 8 -Compress
    if ($beforeJson -ne $afterJson) { throw 'JAWS-STEP-D-019: Step D changed the Supervisor version inventory.' }
    $evidencePath = Join-Path $local "jaws-step-d-install.$EnvironmentName.generated.json"
    $payload = [pscustomobject]@{
        SchemaVersion = '1.0'
        Result = 'PASS'
        Status = 'STEP_D_INSTALLED'
        EnvironmentName = $EnvironmentName
        Profile = $context.Profile
        AgentName = $context.AgentName
        AgentStatus = [string]$existing.status
        Image = $image
        ComputeEnvironmentId = $context.AgentName
        CatalogPath = $catalogPath
        AzureWrites = $writes
        SupervisorUnchanged = $true
        CustomerInstallationAccepted = $false
        CompletedAtUtc = [DateTime]::UtcNow.ToString('o')
    }
    Save-JawsStepDEvidence -Path $evidencePath -Payload $payload | Out-Null
    Assert-JawsStepDDevState -Context $context
    return [pscustomobject]@{
        EvidencePath = $evidencePath
        ReadyForNextStep = $true
        NextStep = 'Step D Accept'
        AzureWrites = $writes
    }
}

function Invoke-JawsStepDAccept {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$EnvironmentName,
        [Parameter(Mandatory)][string]$InstallerRoot
    )
    $context = Resolve-JawsStepDContext -EnvironmentName $EnvironmentName -InstallerRoot $InstallerRoot
    $local = Join-Path $InstallerRoot '.local'
    $catalogPath = Join-Path $local "jaws-specialist-catalog.$EnvironmentName.generated.json"
    $installPath = Join-Path $local "jaws-step-d-install.$EnvironmentName.generated.json"
    if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf) -or -not (Test-Path -LiteralPath $installPath -PathType Leaf)) {
        throw 'JAWS-STEP-D-024: Step D install evidence was not found. A local catalog alone is not acceptance.'
    }
    $catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json
    $null = Test-JawsStepDCatalog -Catalog $catalog
    $vm = @($catalog.Specialists)[0]
    $agent = Get-JawsStepDAgentVersion -Context $context
    $image = if ($null -eq $agent) { '' } else { [string]$agent.definition.container_configuration.image }
    $expected = [string]$vm.Image
    $ok = $null -ne $agent -and [string]$agent.status -eq 'active' -and $agent.draft -ne $true -and $image -eq $expected -and [string]$vm.ComputeEnvironmentId -eq $context.AgentName
    $evidencePath = Join-Path $local "jaws-step-d-acceptance.$EnvironmentName.generated.json"
    $payload = [pscustomobject]@{
        SchemaVersion = '1.0'
        Result = $(if ($ok) { 'PASS' } else { 'FAIL' })
        Status = $(if ($ok) { 'STEP_D_ACCEPTED_FOR_THIS_RUN' } else { 'NOT_ACCEPTED' })
        EnvironmentName = $EnvironmentName
        AgentName = $context.AgentName
        AgentStatus = $(if ($null -eq $agent) { '' } else { [string]$agent.status })
        Image = $image
        ExpectedImage = $expected
        LiveAzureRead = $true
        AzureWrites = 0
        CustomerInstallationAccepted = $false
        FreshSubscriptionReceiptArchived = $false
        Reasons = @($(if (-not $ok) { 'The live hosted agent does not match the Step D catalog.' }))
        CompletedAtUtc = [DateTime]::UtcNow.ToString('o')
    }
    Save-JawsStepDEvidence -Path $evidencePath -Payload $payload | Out-Null
    Assert-JawsStepDDevState -Context $context
    if (-not $ok) { throw "JAWS-STEP-D-024: Live virtual-machine specialist does not match the catalog. Evidence: $evidencePath" }
    return [pscustomobject]@{
        EvidencePath = $evidencePath
        ReadyForNextStep = $false
        NextStep = 'Step E is not installable'
        AzureWrites = 0
    }
}

Export-ModuleMember -Function Get-JawsStepDReadTools,Get-JawsStepDWriteTools,Test-JawsStepDCatalog,New-JawsStepDCatalog,Resolve-JawsStepDContext,Invoke-JawsStepDValidate,Invoke-JawsStepDInstall,Invoke-JawsStepDAccept
