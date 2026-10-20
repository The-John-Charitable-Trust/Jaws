# Target catalog for Steps E-I.
# One specialist may name more than one MCP server. The allow-list is the grant.
# This module does not call Azure and does not change the dev installation state.
Set-StrictMode -Version Latest

function Get-JawsVmReadTools {
    @('vm.get','vm.identity.get','vm.network.get','policy.state.get')
}

function Get-JawsVmWriteTools {
    @('vm.run-command')
}

function Get-JawsObservabilityAzureTools {
    @('monitor.metrics.query','monitor.logs.query','defender.alert.get')
}

function Get-JawsObservabilityCustomTools {
    @('datadog.metrics.query','servicenow.incident.get')
}

function Get-JawsCustomModuleNames {
    @('Datadog','ServiceNow')
}

function Get-JawsRoadmapJsonEnd {
    param([Parameter(Mandatory)][string]$Text,[Parameter(Mandatory)][int]$Start)
    $depth = 0
    $inString = $false
    $escaped = $false
    for ($i = $Start; $i -lt $Text.Length; $i++) {
        $ch = $Text[$i]
        if ($inString) {
            if ($escaped) { $escaped = $false; continue }
            if ($ch -eq '\') { $escaped = $true; continue }
            if ($ch -eq '"') { $inString = $false }
            continue
        }
        if ($ch -eq '"') { $inString = $true; continue }
        if ($ch -eq '{' -or $ch -eq '[') { $depth++ }
        elseif ($ch -eq '}' -or $ch -eq ']') {
            $depth--
            if ($depth -eq 0) { return $i }
        }
    }
    return -1
}

function ConvertFrom-JawsRoadmapJson {
    [CmdletBinding()]
    param([AllowNull()][string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $clean = $Text -replace "$([char]27)\[[0-9;?]*[ -/]*[@-~]", ''
    $objectAt = $clean.IndexOf('{')
    $arrayAt = $clean.IndexOf('[')
    $start = $objectAt
    if ($start -lt 0 -or ($arrayAt -ge 0 -and $arrayAt -lt $start)) { $start = $arrayAt }
    if ($start -lt 0) { return $null }
    $end = Get-JawsRoadmapJsonEnd -Text $clean -Start $start
    if ($end -lt $start) { return $null }
    return ($clean.Substring($start, ($end - $start) + 1) | ConvertFrom-Json)
}

function Invoke-JawsRoadmapAz {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Arguments,[switch]$AllowMissing)
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        throw 'JAWS-PREREQ-001: Azure CLI is not installed or not on PATH.'
    }
    $output = & az @Arguments 2>&1
    $code = $LASTEXITCODE
    $text = (@($output) | ForEach-Object { "$_" }) -join "`n"
    if ($code -ne 0) {
        if ($AllowMissing -and $text -match 'MISSING|ResourceNotFound|ResourceGroupNotFound|was not found|NotFound|not_found|Not Found') {
            return $null
        }
        throw "JAWS-ROADMAP-AZ-001: az $($Arguments -join ' ') failed ($code). $text"
    }
    return (ConvertFrom-JawsRoadmapJson $text)
}

function Invoke-JawsRoadmapAzText {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Arguments)
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        throw 'JAWS-PREREQ-001: Azure CLI is not installed or not on PATH.'
    }
    $output = & az @Arguments 2>&1
    $code = $LASTEXITCODE
    $text = (@($output) | ForEach-Object { "$_" }).Trim() -join "`n"
    if ($code -ne 0) {
        throw "JAWS-ROADMAP-AZ-001: az $($Arguments -join ' ') failed ($code). $text"
    }
    return $text.Trim()
}

function Save-JawsRoadmapEvidence {
    param([Parameter(Mandatory)][string]$Path,$Payload)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    $Payload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding utf8
    return $Path
}

function Assert-JawsRoadmapEnvironment {
    param([Parameter(Mandatory)][string]$EnvironmentName,[Parameter(Mandatory)][string]$Code)
    if ($EnvironmentName -eq 'dev') { throw "${Code}: This step refuses the dev project." }
    if ($EnvironmentName -notmatch '^[a-z][a-z0-9-]{1,20}$') {
        throw "${Code}: Environment name must be 2-21 characters, start with a letter, and use lowercase letters, digits, and hyphens."
    }
}

function Get-JawsRoadmapServers {
    param($Specialist)
    $names = @()
    if ($Specialist.PSObject.Properties['McpServers'] -and $null -ne $Specialist.McpServers) {
        $names = @($Specialist.McpServers | ForEach-Object { [string]$_ })
    } elseif ($Specialist.PSObject.Properties['McpServer']) {
        $names = @([string]$Specialist.McpServer)
    }
    return @($names | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Test-JawsTargetCatalog {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Catalog,[string]$Stage = 'F')
    $specialists = @($Catalog.Specialists)
    if ($specialists.Count -lt 1) { throw 'JAWS-CATALOG-003: The catalog has no specialists.' }
    $hosted = @($specialists | Where-Object { [string]$_.Kind -eq 'hosted' -and [string]$_.Id -eq 'virtual-machine' })
    if ($hosted.Count -ne 1) { throw 'JAWS-CATALOG-004: The catalog must contain exactly one hosted virtual-machine specialist.' }
    $compute = [string]$hosted[0].ComputeEnvironmentId
    if ([string]::IsNullOrWhiteSpace($compute)) { throw 'JAWS-CATALOG-006: The virtual-machine specialist has no compute environment.' }
    $phase = @('investigation','deliberation','remediation')
    $vmTools = @(Get-JawsVmReadTools)
    if ($Stage -eq 'H' -or $Stage -eq 'I') { $vmTools += @(Get-JawsVmWriteTools) }
    $obsTools = @()
    if ($Stage -in @('F','G','H','I')) { $obsTools += @(Get-JawsObservabilityAzureTools) }
    if ($Stage -in @('G','H','I')) { $obsTools += @(Get-JawsObservabilityCustomTools) }
    $browser = @()
    foreach ($tool in @($hosted[0].AllowedTools)) {
        if ([string]$tool -like 'browser_*') { $browser += [string]$tool }
    }
    $known = @($vmTools + $obsTools + $browser)
    foreach ($item in $specialists) {
        $id = [string]$item.Id
        if ($id -in $phase) { throw "JAWS-CATALOG-004: '$id' is a skill or a workflow, not a separate agent." }
        if ([string]$item.ComputeEnvironmentId -ne $compute) {
            throw "JAWS-CATALOG-006: Specialist '$id' names a second compute environment."
        }
        if ([string]$item.Kind -eq 'hosted' -and $id -ne 'virtual-machine') {
            throw "JAWS-CATALOG-006: Hosted specialist '$id' would create another sandbox."
        }
        $servers = @(Get-JawsRoadmapServers $item)
        if ($servers.Count -lt 1) { throw "JAWS-CATALOG-007: Specialist '$id' names no MCP server." }
        foreach ($tool in @($item.AllowedTools)) {
            $name = [string]$tool
            if ($name -notin $known -and $name -notlike 'browser_*') { throw "JAWS-CATALOG-003: Unknown tool '$name'." }
            if ($id -eq 'virtual-machine' -and $name -in @(Get-JawsObservabilityAzureTools) + @(Get-JawsObservabilityCustomTools)) {
                throw "JAWS-CATALOG-008: '$name' belongs to the observability agent."
            }
            if ($id -eq 'observability' -and $name -in @(Get-JawsVmReadTools) + @(Get-JawsVmWriteTools)) {
                throw "JAWS-CATALOG-008: '$name' belongs to the virtual-machine specialist."
            }
            if ($name -in @(Get-JawsVmWriteTools)) {
                if ($item.WritesRequireApproval -ne $true -or [string]$item.ApprovalWorkflow -ne 'approve-vm-change') {
                    throw "JAWS-CATALOG-005: Write tool '$name' requires the approve-vm-change workflow."
                }
            }
            if ($id -eq 'observability' -and $name -in @(Get-JawsObservabilityCustomTools) -and 'jaws-observability' -notin $servers) {
                throw "JAWS-CATALOG-007: '$name' requires the custom MCP server jaws-observability."
            }
            if ($id -eq 'observability' -and $name -in @(Get-JawsObservabilityAzureTools) -and 'azure-mcp' -notin $servers) {
                throw "JAWS-CATALOG-007: '$name' requires the Azure MCP server."
            }
        }
    }
    if ($Stage -in @('F','G','H','I')) {
        $obs = @($specialists | Where-Object { [string]$_.Id -eq 'observability' })
        if ($obs.Count -ne 1) { throw 'JAWS-CATALOG-004: The catalog must contain one observability specialist.' }
        if ([string]$obs[0].Kind -ne 'prompt') { throw 'JAWS-CATALOG-004: The observability specialist is a prompt agent.' }
    }
}

function New-JawsObservabilityManifest {
    @(
        [pscustomobject]@{ Name = 'datadog.metrics.query'; Module = 'Datadog'; ReadOnly = $true; Secret = 'jaws-datadog-api-key' }
        [pscustomobject]@{ Name = 'servicenow.incident.get'; Module = 'ServiceNow'; ReadOnly = $true; Secret = 'jaws-servicenow-password' }
    )
}

function Test-JawsObservabilityManifest {
    param([Parameter(Mandatory)]$Manifest)
    $rows = @($Manifest)
    $allowed = @(Get-JawsCustomModuleNames)
    $expected = @(Get-JawsObservabilityCustomTools)
    if ($rows.Count -ne $expected.Count) { throw 'JAWS-STEP-G-008: The manifest must name the Datadog and ServiceNow read tools.' }
    foreach ($row in $rows) {
        $module = [string]$row.Module
        $name = [string]$row.Name
        if ($module -notin $allowed) { throw "JAWS-STEP-G-008: Module '$module' is not in this build." }
        if ($name -notin $expected) { throw "JAWS-STEP-G-008: Tool '$name' is not a custom-server tool. Azure Monitor and Microsoft Defender stay on Azure MCP." }
        if ($row.ReadOnly -ne $true) { throw "JAWS-STEP-G-008: Tool '$name' must be read-only." }
    }
}

Export-ModuleMember -Function Get-JawsVmReadTools,Get-JawsVmWriteTools,Get-JawsObservabilityAzureTools,Get-JawsObservabilityCustomTools,Get-JawsCustomModuleNames,Invoke-JawsRoadmapAz,Invoke-JawsRoadmapAzText,Save-JawsRoadmapEvidence,Assert-JawsRoadmapEnvironment,Get-JawsRoadmapServers,Test-JawsTargetCatalog,New-JawsObservabilityManifest,Test-JawsObservabilityManifest
