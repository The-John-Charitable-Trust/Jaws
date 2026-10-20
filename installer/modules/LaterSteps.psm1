# Steps F, G, H, and I.
# F creates the observability prompt agent and grants Azure Monitor and Microsoft Defender on Azure MCP.
# G records the custom MCP manifest for Datadog and ServiceNow on that same agent.
# H grants the virtual-machine specialist one write tool behind approve-vm-change and does not run it.
# I checks the receipt chain. It does not run an incident.
# None of these functions modify Supervisor version 1 or the dev installation state.
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'StepRoadmap.psm1') -Force

function Get-JawsLaterContext {
    param([Parameter(Mandatory)][string]$EnvironmentName,[Parameter(Mandatory)][string]$InstallerRoot,[Parameter(Mandatory)][string]$Code)
    Assert-JawsRoadmapEnvironment -EnvironmentName $EnvironmentName -Code $Code
    $receiptPath = Join-Path $InstallerRoot ".local/jaws-step-b-install.$EnvironmentName.generated.json"
    if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) { throw "${Code}: Step B install receipt was not found." }
    $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
    $devState = Join-Path $InstallerRoot 'config/jaws-installation-state.dev.json'
    $account = [string]$receipt.FoundryAccountName
    $project = [string]$receipt.ProjectName
    return [pscustomobject]@{
        EnvironmentName = $EnvironmentName
        ModelDeploymentName = [string]$receipt.ModelDeploymentName
        VmAgent = "jaws-vm-specialist-$EnvironmentName"
        ObservabilityAgent = "jaws-observability-$EnvironmentName"
        SupervisorAgent = [string]$receipt.AgentName
        Endpoint = "https://$account.services.ai.azure.com/api/projects/$project"
        InstallerRoot = $InstallerRoot
        DevStatePath = $devState
        DevStateBefore = $(if (Test-Path -LiteralPath $devState) { Get-Content -LiteralPath $devState -Raw } else { '' })
    }
}

function Assert-JawsLaterDevState {
    param($Context,[Parameter(Mandatory)][string]$Code)
    if (-not (Test-Path -LiteralPath $Context.DevStatePath)) { return }
    $current = Get-Content -LiteralPath $Context.DevStatePath -Raw
    if ($current -ne $Context.DevStateBefore) { throw "${Code}: This step changed the dev installation state." }
}

function Assert-JawsLaterPrior {
    param([Parameter(Mandatory)][string]$InstallerRoot,[Parameter(Mandatory)][string]$EnvironmentName,[Parameter(Mandatory)][string]$File,[Parameter(Mandatory)][string]$Code,[Parameter(Mandatory)][string]$Label)
    $path = Join-Path $InstallerRoot ".local/$File"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "${Code}: $Label evidence was not found: $path" }
    $receipt = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    if ([string]$receipt.Result -ne 'PASS') { throw "${Code}: $Label is not PASS." }
}

function Get-JawsLaterBrowserTools {
    param($InstallerRoot,$EnvironmentName)
    $path = Join-Path $InstallerRoot ".local/jaws-specialist-catalog.$EnvironmentName.generated.json"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return @() }
    $catalog = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    $vm = @($catalog.Specialists | Where-Object { [string]$_.Id -eq 'virtual-machine' })
    if ($vm.Count -lt 1) { return @() }
    return @($vm[0].AllowedTools | ForEach-Object { [string]$_ } | Where-Object { $_ -like 'browser_*' })
}

function New-JawsLaterCatalog {
    param($Context,[string]$Stage,[string[]]$BrowserTools)
    $vmTools = @(Get-JawsVmReadTools) + @($BrowserTools)
    if ($Stage -in @('H','I')) { $vmTools += @(Get-JawsVmWriteTools) }
    $obsTools = @(Get-JawsObservabilityAzureTools)
    $obsServers = @('azure-mcp')
    if ($Stage -in @('G','H','I')) {
        $obsTools += @(Get-JawsObservabilityCustomTools)
        $obsServers += 'jaws-observability'
    }
    [pscustomobject]@{
        SchemaVersion = '1.1'
        EnvironmentName = $Context.EnvironmentName
        Specialists = @(
            [pscustomobject]@{
                Id = 'virtual-machine'
                FoundryAgentName = $Context.VmAgent
                Kind = 'hosted'
                Skills = @('investigate-vm-security-incident','deliberate-remediation')
                McpServers = @('azure-mcp')
                AllowedTools = $vmTools
                WritesRequireApproval = $true
                ApprovalWorkflow = 'approve-vm-change'
                ComputeEnvironmentId = $Context.VmAgent
            }
            [pscustomobject]@{
                Id = 'observability'
                FoundryAgentName = $Context.ObservabilityAgent
                Kind = 'prompt'
                Skills = @('correlate-incident-signals')
                McpServers = $obsServers
                AllowedTools = $obsTools
                WritesRequireApproval = $false
                ComputeEnvironmentId = $Context.VmAgent
            }
        )
    }
}

function Save-JawsLaterCatalog {
    param($InstallerRoot,$EnvironmentName,$Catalog,$Stage)
    $null = Test-JawsTargetCatalog -Catalog $Catalog -Stage $Stage
    $path = Join-Path $InstallerRoot ".local/jaws-specialist-catalog.$EnvironmentName.generated.json"
    Save-JawsRoadmapEvidence -Path $path -Payload $Catalog | Out-Null
    return $path
}

function Invoke-JawsStepFValidate {
    param([Parameter(Mandatory)][string]$EnvironmentName,[Parameter(Mandatory)][string]$InstallerRoot)
    Assert-JawsLaterPrior -InstallerRoot $InstallerRoot -EnvironmentName $EnvironmentName -File "jaws-step-e-acceptance.$EnvironmentName.generated.json" -Code 'JAWS-STEP-F-002' -Label 'Step E acceptance'
    $context = Get-JawsLaterContext -EnvironmentName $EnvironmentName -InstallerRoot $InstallerRoot -Code 'JAWS-STEP-F-014'
    $path = Join-Path $InstallerRoot ".local/jaws-step-f-validate.$EnvironmentName.generated.json"
    Save-JawsRoadmapEvidence -Path $path -Payload ([pscustomobject]@{
        SchemaVersion = '1.0'; Result = 'PASS'; Status = 'STEP_F_VALIDATED'; EnvironmentName = $EnvironmentName
        ObservabilityAgent = $context.ObservabilityAgent; McpServers = @('azure-mcp'); AzureMcpConnectionWritten = $false
        LiveToolCall = $false; AzureWrites = 0; CustomerInstallationAccepted = $false; FedRAMPModerate = $false
        CompletedAtUtc = [DateTime]::UtcNow.ToString('o')
    }) | Out-Null
    Assert-JawsLaterDevState $context 'JAWS-STEP-F-022'
    return [pscustomobject]@{ EvidencePath = $path; ReadyForNextStep = $true; NextStep = 'Step F Install'; AzureWrites = 0 }
}

function Invoke-JawsStepFInstall {
    param([Parameter(Mandatory)][string]$EnvironmentName,[Parameter(Mandatory)][string]$InstallerRoot,[switch]$AcknowledgeStepFInstall)
    if (-not $AcknowledgeStepFInstall) { throw 'JAWS-STEP-F-001: Install requires -AcknowledgeStepFInstall.' }
    Assert-JawsLaterPrior -InstallerRoot $InstallerRoot -EnvironmentName $EnvironmentName -File "jaws-step-e-acceptance.$EnvironmentName.generated.json" -Code 'JAWS-STEP-F-002' -Label 'Step E acceptance'
    $context = Get-JawsLaterContext -EnvironmentName $EnvironmentName -InstallerRoot $InstallerRoot -Code 'JAWS-STEP-F-014'
    $versionUrl = "$($context.Endpoint)/agents/$($context.ObservabilityAgent)/versions/1?api-version=v1"
    $existing = Invoke-JawsRoadmapAz -AllowMissing -Arguments @('rest','--method','GET','--url',$versionUrl,'--resource','https://ai.azure.com','--output','json','--only-show-errors')
    $writes = 0
    if ($null -eq $existing) {
        $instructions = 'You are the JAWS observability agent. Use Azure MCP for AZURE MONITOR AND MICROSOFT DEFENDER only. Return cited read-only evidence. Do not call Datadog or ServiceNow. Do not change a resource.'
        $body = @{ name = $context.ObservabilityAgent; definition = @{ kind = 'prompt'; model = $context.ModelDeploymentName; instructions = $instructions } } | ConvertTo-Json -Depth 6 -Compress
        $bodyFile = Join-Path $InstallerRoot ".local/jaws-step-f-agent.$EnvironmentName.json"
        [System.IO.File]::WriteAllText($bodyFile, $body)
        $null = Invoke-JawsRoadmapAz -Arguments @('rest','--method','POST','--url',"$($context.Endpoint)/agents?api-version=v1",'--resource','https://ai.azure.com','--body',"@$bodyFile",'--output','json','--only-show-errors')
        $writes++
        $existing = Invoke-JawsRoadmapAz -Arguments @('rest','--method','GET','--url',$versionUrl,'--resource','https://ai.azure.com','--output','json','--only-show-errors')
    }
    if ($null -eq $existing -or [string]$existing.definition.kind -ne 'prompt' -or [string]$existing.definition.instructions -notmatch 'AZURE MONITOR AND MICROSOFT DEFENDER') {
        throw 'JAWS-STEP-F-018: The observability agent is missing or is not the read-only Monitor and Defender prompt. It was not overwritten.'
    }
    $browser = @(Get-JawsLaterBrowserTools $InstallerRoot $EnvironmentName)
    $catalog = New-JawsLaterCatalog -Context $context -Stage 'F' -BrowserTools $browser
    $catalogPath = Save-JawsLaterCatalog $InstallerRoot $EnvironmentName $catalog 'F'
    $path = Join-Path $InstallerRoot ".local/jaws-step-f-install.$EnvironmentName.generated.json"
    Save-JawsRoadmapEvidence -Path $path -Payload ([pscustomobject]@{
        SchemaVersion = '1.0'; Result = 'PASS'; Status = 'STEP_F_INSTALLED'; EnvironmentName = $EnvironmentName
        ObservabilityAgent = $context.ObservabilityAgent; CatalogPath = $catalogPath; McpServers = @('azure-mcp')
        AzureMcpConnectionWritten = $false; LiveToolCall = $false; AzureWrites = $writes
        CustomerInstallationAccepted = $false; FedRAMPModerate = $false; CompletedAtUtc = [DateTime]::UtcNow.ToString('o')
    }) | Out-Null
    Assert-JawsLaterDevState $context 'JAWS-STEP-F-022'
    return [pscustomobject]@{ EvidencePath = $path; ReadyForNextStep = $true; NextStep = 'Step F Accept'; AzureWrites = $writes }
}

function Invoke-JawsStepFAccept {
    param([Parameter(Mandatory)][string]$EnvironmentName,[Parameter(Mandatory)][string]$InstallerRoot)
    $context = Get-JawsLaterContext -EnvironmentName $EnvironmentName -InstallerRoot $InstallerRoot -Code 'JAWS-STEP-F-014'
    $catalogPath = Join-Path $InstallerRoot ".local/jaws-specialist-catalog.$EnvironmentName.generated.json"
    if (-not (Test-Path -LiteralPath $catalogPath)) { throw 'JAWS-STEP-F-024: The Step F catalog was not found.' }
    $catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json
    $null = Test-JawsTargetCatalog -Catalog $catalog -Stage 'F'
    $version = Invoke-JawsRoadmapAz -Arguments @('rest','--method','GET','--url',"$($context.Endpoint)/agents/$($context.ObservabilityAgent)/versions/1?api-version=v1",'--resource','https://ai.azure.com','--output','json','--only-show-errors')
    $ok = $null -ne $version -and [string]$version.definition.kind -eq 'prompt' -and [string]$version.status -eq 'active'
    $path = Join-Path $InstallerRoot ".local/jaws-step-f-acceptance.$EnvironmentName.generated.json"
    Save-JawsRoadmapEvidence -Path $path -Payload ([pscustomobject]@{
        SchemaVersion = '1.0'; Result = $(if ($ok) {'PASS'} else {'FAIL'}); EnvironmentName = $EnvironmentName
        LiveAzureRead = $true; LiveToolCall = $false; AzureMcpConnectionWritten = $false; AzureWrites = 0
        CustomerInstallationAccepted = $false; FreshSubscriptionReceiptArchived = $false; FedRAMPModerate = $false
        CompletedAtUtc = [DateTime]::UtcNow.ToString('o')
    }) | Out-Null
    Assert-JawsLaterDevState $context 'JAWS-STEP-F-022'
    if (-not $ok) { throw "JAWS-STEP-F-024: The live observability agent does not match. Evidence: $path" }
    return [pscustomobject]@{ EvidencePath = $path; ReadyForNextStep = $true; NextStep = 'Step G Validate'; AzureWrites = 0 }
}

function Invoke-JawsStepGValidate {
    param([Parameter(Mandatory)][string]$EnvironmentName,[Parameter(Mandatory)][string]$InstallerRoot)
    Assert-JawsLaterPrior -InstallerRoot $InstallerRoot -EnvironmentName $EnvironmentName -File "jaws-step-f-acceptance.$EnvironmentName.generated.json" -Code 'JAWS-STEP-G-002' -Label 'Step F acceptance'
    $path = Join-Path $InstallerRoot ".local/jaws-step-g-validate.$EnvironmentName.generated.json"
    Save-JawsRoadmapEvidence -Path $path -Payload ([pscustomobject]@{
        SchemaVersion = '1.0'; Result = 'PASS'; EnvironmentName = $EnvironmentName; McpServerDeployed = $false
        AzureWrites = 0; CustomerInstallationAccepted = $false; CompletedAtUtc = [DateTime]::UtcNow.ToString('o')
    }) | Out-Null
    return [pscustomobject]@{ EvidencePath = $path; ReadyForNextStep = $true; NextStep = 'Step G Install'; AzureWrites = 0 }
}

function Invoke-JawsStepGInstall {
    param([Parameter(Mandatory)][string]$EnvironmentName,[Parameter(Mandatory)][string]$InstallerRoot,[switch]$AcknowledgeStepGInstall)
    if (-not $AcknowledgeStepGInstall) { throw 'JAWS-STEP-G-001: Install requires -AcknowledgeStepGInstall. No MCP server is deployed.' }
    Assert-JawsLaterPrior -InstallerRoot $InstallerRoot -EnvironmentName $EnvironmentName -File "jaws-step-f-acceptance.$EnvironmentName.generated.json" -Code 'JAWS-STEP-G-002' -Label 'Step F acceptance'
    $context = Get-JawsLaterContext -EnvironmentName $EnvironmentName -InstallerRoot $InstallerRoot -Code 'JAWS-STEP-G-014'
    $manifest = @(New-JawsObservabilityManifest)
    $null = Test-JawsObservabilityManifest $manifest
    $manifestPath = Join-Path $InstallerRoot ".local/jaws-observability-manifest.$EnvironmentName.generated.json"
    Save-JawsRoadmapEvidence -Path $manifestPath -Payload $manifest | Out-Null
    $browser = @(Get-JawsLaterBrowserTools $InstallerRoot $EnvironmentName)
    $catalog = New-JawsLaterCatalog -Context $context -Stage 'G' -BrowserTools $browser
    $null = Save-JawsLaterCatalog $InstallerRoot $EnvironmentName $catalog 'G'
    $path = Join-Path $InstallerRoot ".local/jaws-step-g-install.$EnvironmentName.generated.json"
    Save-JawsRoadmapEvidence -Path $path -Payload ([pscustomobject]@{
        SchemaVersion = '1.0'; Result = 'PASS'; Status = 'STEP_G_INSTALLED'; EnvironmentName = $EnvironmentName
        ManifestPath = $manifestPath; McpServer = 'jaws-observability'; McpServerDeployed = $false; LiveToolCall = $false
        Modules = @('Datadog','ServiceNow'); AzureWrites = 0; CustomerInstallationAccepted = $false; FedRAMPModerate = $false
        CompletedAtUtc = [DateTime]::UtcNow.ToString('o')
    }) | Out-Null
    Assert-JawsLaterDevState $context 'JAWS-STEP-G-022'
    return [pscustomobject]@{ EvidencePath = $path; ReadyForNextStep = $true; NextStep = 'Step G Accept'; AzureWrites = 0 }
}

function Invoke-JawsStepGAccept {
    param([Parameter(Mandatory)][string]$EnvironmentName,[Parameter(Mandatory)][string]$InstallerRoot)
    $manifestPath = Join-Path $InstallerRoot ".local/jaws-observability-manifest.$EnvironmentName.generated.json"
    $catalogPath = Join-Path $InstallerRoot ".local/jaws-specialist-catalog.$EnvironmentName.generated.json"
    if (-not (Test-Path -LiteralPath $manifestPath) -or -not (Test-Path -LiteralPath $catalogPath)) {
        throw 'JAWS-STEP-G-024: Step G manifest or catalog was not found.'
    }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $null = Test-JawsObservabilityManifest $manifest
    $catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json
    $null = Test-JawsTargetCatalog -Catalog $catalog -Stage 'G'
    $path = Join-Path $InstallerRoot ".local/jaws-step-g-acceptance.$EnvironmentName.generated.json"
    Save-JawsRoadmapEvidence -Path $path -Payload ([pscustomobject]@{
        SchemaVersion = '1.0'; Result = 'PASS'; EnvironmentName = $EnvironmentName; McpServerDeployed = $false
        LiveToolCall = $false; AzureWrites = 0; CustomerInstallationAccepted = $false; FreshSubscriptionReceiptArchived = $false
        CompletedAtUtc = [DateTime]::UtcNow.ToString('o')
    }) | Out-Null
    return [pscustomobject]@{ EvidencePath = $path; ReadyForNextStep = $true; NextStep = 'Step H Validate'; AzureWrites = 0 }
}

function Invoke-JawsStepHValidate {
    param([Parameter(Mandatory)][string]$EnvironmentName,[Parameter(Mandatory)][string]$InstallerRoot)
    Assert-JawsLaterPrior -InstallerRoot $InstallerRoot -EnvironmentName $EnvironmentName -File "jaws-step-g-acceptance.$EnvironmentName.generated.json" -Code 'JAWS-STEP-H-002' -Label 'Step G acceptance'
    $path = Join-Path $InstallerRoot ".local/jaws-step-h-validate.$EnvironmentName.generated.json"
    Save-JawsRoadmapEvidence -Path $path -Payload ([pscustomobject]@{
        SchemaVersion = '1.0'; Result = 'PASS'; EnvironmentName = $EnvironmentName; ChangeExecuted = $false
        AzureWrites = 0; CustomerInstallationAccepted = $false; CompletedAtUtc = [DateTime]::UtcNow.ToString('o')
    }) | Out-Null
    return [pscustomobject]@{ EvidencePath = $path; ReadyForNextStep = $true; NextStep = 'Step H Install'; AzureWrites = 0 }
}

function Invoke-JawsStepHInstall {
    param([Parameter(Mandatory)][string]$EnvironmentName,[Parameter(Mandatory)][string]$InstallerRoot,[switch]$AcknowledgeStepHInstall)
    if (-not $AcknowledgeStepHInstall) { throw 'JAWS-STEP-H-001: Install requires -AcknowledgeStepHInstall. No change is executed.' }
    Assert-JawsLaterPrior -InstallerRoot $InstallerRoot -EnvironmentName $EnvironmentName -File "jaws-step-g-acceptance.$EnvironmentName.generated.json" -Code 'JAWS-STEP-H-002' -Label 'Step G acceptance'
    $context = Get-JawsLaterContext -EnvironmentName $EnvironmentName -InstallerRoot $InstallerRoot -Code 'JAWS-STEP-H-014'
    $browser = @(Get-JawsLaterBrowserTools $InstallerRoot $EnvironmentName)
    $catalog = New-JawsLaterCatalog -Context $context -Stage 'H' -BrowserTools $browser
    $null = Save-JawsLaterCatalog $InstallerRoot $EnvironmentName $catalog 'H'
    $path = Join-Path $InstallerRoot ".local/jaws-step-h-install.$EnvironmentName.generated.json"
    Save-JawsRoadmapEvidence -Path $path -Payload ([pscustomobject]@{
        SchemaVersion = '1.0'; Result = 'PASS'; Status = 'STEP_H_INSTALLED'; EnvironmentName = $EnvironmentName
        ApprovalWorkflow = 'approve-vm-change'; ChangeExecuted = $false; AzureWrites = 0
        CustomerInstallationAccepted = $false; CompletedAtUtc = [DateTime]::UtcNow.ToString('o')
    }) | Out-Null
    Assert-JawsLaterDevState $context 'JAWS-STEP-H-022'
    return [pscustomobject]@{ EvidencePath = $path; ReadyForNextStep = $true; NextStep = 'Step H Accept'; AzureWrites = 0 }
}

function Invoke-JawsStepHAccept {
    param([Parameter(Mandatory)][string]$EnvironmentName,[Parameter(Mandatory)][string]$InstallerRoot)
    $catalogPath = Join-Path $InstallerRoot ".local/jaws-specialist-catalog.$EnvironmentName.generated.json"
    if (-not (Test-Path -LiteralPath $catalogPath)) { throw 'JAWS-STEP-H-024: The Step H catalog was not found.' }
    $catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json
    $null = Test-JawsTargetCatalog -Catalog $catalog -Stage 'H'
    $vm = @($catalog.Specialists | Where-Object { [string]$_.Id -eq 'virtual-machine' })[0]
    $tools = @($vm.AllowedTools | ForEach-Object { [string]$_ })
    if ('vm.run-command' -notin $tools) { throw 'JAWS-STEP-H-024: vm.run-command is not granted.' }
    $path = Join-Path $InstallerRoot ".local/jaws-step-h-acceptance.$EnvironmentName.generated.json"
    Save-JawsRoadmapEvidence -Path $path -Payload ([pscustomobject]@{
        SchemaVersion = '1.0'; Result = 'PASS'; EnvironmentName = $EnvironmentName; ChangeExecuted = $false
        LiveAzureRead = $false; AzureWrites = 0; CustomerInstallationAccepted = $false; FreshSubscriptionReceiptArchived = $false
        CompletedAtUtc = [DateTime]::UtcNow.ToString('o')
    }) | Out-Null
    return [pscustomobject]@{ EvidencePath = $path; ReadyForNextStep = $true; NextStep = 'Step I Validate'; AzureWrites = 0 }
}

function Invoke-JawsStepIValidate {
    param([Parameter(Mandatory)][string]$EnvironmentName,[Parameter(Mandatory)][string]$InstallerRoot)
    Assert-JawsLaterPrior -InstallerRoot $InstallerRoot -EnvironmentName $EnvironmentName -File "jaws-step-h-acceptance.$EnvironmentName.generated.json" -Code 'JAWS-STEP-I-002' -Label 'Step H acceptance'
    $path = Join-Path $InstallerRoot ".local/jaws-step-i-validate.$EnvironmentName.generated.json"
    Save-JawsRoadmapEvidence -Path $path -Payload ([pscustomobject]@{
        SchemaVersion = '1.0'; Result = 'PASS'; EnvironmentName = $EnvironmentName; LiveIncident = $false
        AzureWrites = 0; CustomerInstallationAccepted = $false; CompletedAtUtc = [DateTime]::UtcNow.ToString('o')
    }) | Out-Null
    return [pscustomobject]@{ EvidencePath = $path; ReadyForNextStep = $true; NextStep = 'Step I Accept'; AzureWrites = 0 }
}

function Invoke-JawsStepIAccept {
    param([Parameter(Mandatory)][string]$EnvironmentName,[Parameter(Mandatory)][string]$InstallerRoot)
    foreach ($pair in @(
        @("jaws-step-e-acceptance.$EnvironmentName.generated.json",'Step E'),
        @("jaws-step-f-acceptance.$EnvironmentName.generated.json",'Step F'),
        @("jaws-step-g-acceptance.$EnvironmentName.generated.json",'Step G'),
        @("jaws-step-h-acceptance.$EnvironmentName.generated.json",'Step H')
    )) {
        Assert-JawsLaterPrior -InstallerRoot $InstallerRoot -EnvironmentName $EnvironmentName -File $pair[0] -Code 'JAWS-STEP-I-002' -Label $pair[1]
    }
    $catalog = Get-Content -LiteralPath (Join-Path $InstallerRoot ".local/jaws-specialist-catalog.$EnvironmentName.generated.json") -Raw | ConvertFrom-Json
    $null = Test-JawsTargetCatalog -Catalog $catalog -Stage 'I'
    $path = Join-Path $InstallerRoot ".local/jaws-step-i-acceptance.$EnvironmentName.generated.json"
    Save-JawsRoadmapEvidence -Path $path -Payload ([pscustomobject]@{
        SchemaVersion = '1.0'; Result = 'PASS'; EnvironmentName = $EnvironmentName; LiveIncident = $false
        SecondConversationRecorded = $false; AzureWrites = 0; CustomerInstallationAccepted = $false
        FreshSubscriptionReceiptArchived = $false; FedRAMPModerate = $false; CompletedAtUtc = [DateTime]::UtcNow.ToString('o')
    }) | Out-Null
    return [pscustomobject]@{ EvidencePath = $path; ReadyForNextStep = $false; NextStep = 'none'; AzureWrites = 0 }
}

Export-ModuleMember -Function Invoke-JawsStepFValidate,Invoke-JawsStepFInstall,Invoke-JawsStepFAccept,Invoke-JawsStepGValidate,Invoke-JawsStepGInstall,Invoke-JawsStepGAccept,Invoke-JawsStepHValidate,Invoke-JawsStepHInstall,Invoke-JawsStepHAccept,Invoke-JawsStepIValidate,Invoke-JawsStepIAccept,New-JawsLaterCatalog
