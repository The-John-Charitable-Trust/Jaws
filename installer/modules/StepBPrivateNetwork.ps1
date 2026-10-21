# Step B private profile. Dot-sourced into StepBInstall so it can call Invoke-JawsStepBAz.
# The operator runs Azure CLI on their own computer. There is no jump VM.
# Control-plane work finishes from anywhere. The Supervisor create waits until
# this computer can reach services.ai.azure.com through the point-to-site VPN.

function Get-JawsStepBFoundryPreviewUrl {
    param([Parameter(Mandatory)]$Scope)
    $sub = [string]$Scope.SubscriptionId
    $rg = [string]$Scope.ResourceGroupName
    $name = [string]$Scope.FoundryAccountName
    "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.CognitiveServices/accounts/${name}?api-version=2025-04-01-preview"
}

function Get-JawsStepBFoundryPreview {
    param([Parameter(Mandatory)]$Scope)
    Invoke-JawsStepBAz -AllowMissing -Arguments @('rest','--method','GET','--url',(Get-JawsStepBFoundryPreviewUrl $Scope),'--output','json','--only-show-errors')
}

function Test-JawsStepBPrivateFoundryPosture {
    param($Account,[Parameter(Mandatory)][string]$SubnetId)
    if ($null -eq $Account) { return 'Foundry account preview read returned nothing' }
    $access = [string](Get-JawsStepBProperty -Object $Account -Names @('properties','publicNetworkAccess'))
    if ($access -ne 'Disabled') { return "publicNetworkAccess is '$access'" }
    Import-Module (Join-Path $PSScriptRoot 'StepDBrowser.psm1') -Force
    $injected = [string](StepDBrowser\Test-JawsFoundryAgentInjection $Account)
    if ($injected -cne $SubnetId) { return "agent injection subnet is '$injected'" }
    return ''
}

function Add-JawsStepBPrivateSubnet {
    param(
        [Parameter(Mandatory)][string]$SubscriptionId,
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$VnetName,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Prefix,
        [string]$Delegation
    )
    $shown = Invoke-JawsStepBAz -AllowMissing -Arguments @('network','vnet','subnet','show','--subscription',$SubscriptionId,'--resource-group',$ResourceGroupName,'--vnet-name',$VnetName,'--name',$Name,'--output','json','--only-show-errors')
    $writes = 0
    if ($null -eq $shown) {
        $create = @('network','vnet','subnet','create','--subscription',$SubscriptionId,'--resource-group',$ResourceGroupName,'--vnet-name',$VnetName,'--name',$Name,'--address-prefixes',$Prefix,'--output','json','--only-show-errors')
        if (-not [string]::IsNullOrWhiteSpace($Delegation)) { $create += @('--delegations',$Delegation) }
        $shown = Invoke-JawsStepBAz -Arguments $create
        $writes = 1
    }
    $id = [string](Get-JawsStepBProperty -Object $shown @('id'))
    if ([string]::IsNullOrWhiteSpace($id)) {
        $id = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Network/virtualNetworks/$VnetName/subnets/$Name"
    }
    [pscustomobject]@{ Id = $id; AzureWrites = $writes }
}

function Install-JawsStepBPrivateLayout {
    param([Parameter(Mandatory)]$Scope)
    Import-Module (Join-Path $PSScriptRoot 'StepDBrowser.psm1') -Force
    $plan = StepDBrowser\Get-JawsBrowserNetworkPlan -EnvironmentName ([string]$Scope.EnvironmentName)
    $context = [pscustomobject]@{
        EnvironmentName = [string]$Scope.EnvironmentName
        SubscriptionId = [string]$Scope.SubscriptionId
        ResourceGroupName = [string]$Scope.ResourceGroupName
        Location = [string]$Scope.Location
    }
    try {
        $network = StepDBrowser\Enable-JawsBrowserPrivateNetwork -Context $context
    } catch {
        if ($_.Exception.Message -match 'JAWS-STEP-D-030') {
            throw "JAWS-STEP-B-PROVIDER-001: $($_.Exception.Message)"
        }
        throw
    }
    $writes = [int]$network.AzureWrites
    $sub = [string]$Scope.SubscriptionId
    $rg = [string]$Scope.ResourceGroupName
    $endpoints = Add-JawsStepBPrivateSubnet -SubscriptionId $sub -ResourceGroupName $rg -VnetName $plan.VnetName -Name $plan.PrivateEndpointSubnet -Prefix $plan.PrivateEndpointPrefix
    $gateway = Add-JawsStepBPrivateSubnet -SubscriptionId $sub -ResourceGroupName $rg -VnetName $plan.VnetName -Name $plan.GatewaySubnet -Prefix $plan.GatewayPrefix
    $resolver = Add-JawsStepBPrivateSubnet -SubscriptionId $sub -ResourceGroupName $rg -VnetName $plan.VnetName -Name $plan.ResolverSubnet -Prefix $plan.ResolverPrefix -Delegation 'Microsoft.Network/dnsResolvers'
    $writes += [int]$endpoints.AzureWrites + [int]$gateway.AzureWrites + [int]$resolver.AzureWrites
    [pscustomobject]@{
        AzureWrites = $writes
        Plan = $plan
        AgentsSubnetId = [string]$network.FoundrySubnetId
        PrivateEndpointSubnetId = [string]$endpoints.Id
        GatewaySubnetId = [string]$gateway.Id
        ResolverSubnetId = [string]$resolver.Id
        VnetId = "/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Network/virtualNetworks/$($plan.VnetName)"
    }
}

function New-JawsStepBPrivateFoundryAccount {
    param([Parameter(Mandatory)]$Scope,[Parameter(Mandatory)][string]$InstallerRoot,[Parameter(Mandatory)][string]$SubnetId)
    $preview = Get-JawsStepBFoundryPreview -Scope $Scope
    if ($null -ne $preview) {
        if (-not (Test-JawsStepBOwned -Resource $preview -EnvironmentName ([string]$Scope.EnvironmentName))) {
            throw 'JAWS-STEP-B-012: Foundry account exists and is not owned by this installer. Refusing adoption.'
        }
        $problem = Test-JawsStepBPrivateFoundryPosture -Account $preview -SubnetId $SubnetId
        if (-not [string]::IsNullOrWhiteSpace($problem)) {
            throw "JAWS-STEP-B-028: The existing Foundry account does not match the private profile ($problem). It was not changed. No project, model, vault, registry, or agent was created."
        }
        return [pscustomobject]@{ AzureWrites = 0; Account = $preview }
    }
    $body = [ordered]@{
        location = [string]$Scope.Location
        kind = 'AIServices'
        sku = [ordered]@{ name = 'S0' }
        identity = [ordered]@{ type = 'SystemAssigned' }
        tags = [ordered]@{ application = 'JAWS'; managedBy = 'JAWS-Installer'; environment = [string]$Scope.EnvironmentName }
        properties = [ordered]@{
            allowProjectManagement = $true
            customSubDomainName = [string]$Scope.FoundryAccountName
            publicNetworkAccess = 'Disabled'
            networkInjections = @(
                [ordered]@{
                    scenario = 'agent'
                    subnetArmId = $SubnetId
                    useMicrosoftManagedNetwork = $false
                }
            )
        }
    }
    $local = Join-Path $InstallerRoot '.local'
    if (-not (Test-Path -LiteralPath $local)) { New-Item -ItemType Directory -Path $local | Out-Null }
    $bodyFile = Join-Path $local "jaws-step-b-foundry-private.$($Scope.EnvironmentName).json"
    [IO.File]::WriteAllText($bodyFile, ($body | ConvertTo-Json -Depth 8 -Compress), [Text.UTF8Encoding]::new($false))
    $null = Invoke-JawsStepBAz -Arguments @('rest','--method','PUT','--url',(Get-JawsStepBFoundryPreviewUrl $Scope),'--body',"@$bodyFile",'--output','json','--only-show-errors')
    $created = Get-JawsStepBFoundryPreview -Scope $Scope
    $problem = Test-JawsStepBPrivateFoundryPosture -Account $created -SubnetId $SubnetId
    if (-not [string]::IsNullOrWhiteSpace($problem)) {
        throw "JAWS-STEP-B-028: Foundry was created but the preview read does not match the private profile ($problem). No project, model, vault, registry, or agent was created."
    }
    [pscustomobject]@{ AzureWrites = 1; Account = $created }
}

function Add-JawsStepBPrivateDnsZone {
    param(
        [Parameter(Mandatory)][string]$SubscriptionId,
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$ZoneName,
        [Parameter(Mandatory)][string]$VnetId,
        [Parameter(Mandatory)][string]$LinkName
    )
    $writes = 0
    $zone = Invoke-JawsStepBAz -AllowMissing -Arguments @('network','private-dns','zone','show','--subscription',$SubscriptionId,'--resource-group',$ResourceGroupName,'--name',$ZoneName,'--output','json','--only-show-errors')
    if ($null -eq $zone) {
        $zone = Invoke-JawsStepBAz -Arguments @('network','private-dns','zone','create','--subscription',$SubscriptionId,'--resource-group',$ResourceGroupName,'--name',$ZoneName,'--output','json','--only-show-errors')
        $writes++
    }
    $link = Invoke-JawsStepBAz -AllowMissing -Arguments @('network','private-dns','link','vnet','show','--subscription',$SubscriptionId,'--resource-group',$ResourceGroupName,'--zone-name',$ZoneName,'--name',$LinkName,'--output','json','--only-show-errors')
    if ($null -eq $link) {
        $null = Invoke-JawsStepBAz -Arguments @('network','private-dns','link','vnet','create','--subscription',$SubscriptionId,'--resource-group',$ResourceGroupName,'--zone-name',$ZoneName,'--name',$LinkName,'--virtual-network',$VnetId,'--registration-enabled','false','--output','json','--only-show-errors')
        $writes++
    }
    $id = [string](Get-JawsStepBProperty -Object $zone @('id'))
    if ([string]::IsNullOrWhiteSpace($id)) {
        $id = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Network/privateDnsZones/$ZoneName"
    }
    [pscustomobject]@{ Id = $id; AzureWrites = $writes }
}

function Install-JawsStepBDnsResolverCli {
    $listed = @(Invoke-JawsStepBAz -Arguments @('extension','list','--output','json','--only-show-errors'))
    foreach ($item in $listed) {
        if ([string](Get-JawsStepBProperty -Object $item -Names @('name')) -eq 'dns-resolver') { return }
    }
    # Invoke-JawsStepBAz captures the CLI output, so a dynamic-install prompt would wait forever.
    $null = Invoke-JawsStepBAz -Arguments @('extension','add','--name','dns-resolver','--yes','--output','json','--only-show-errors')
}

function Install-JawsStepBPrivateAccess {
    param([Parameter(Mandatory)]$Scope,[Parameter(Mandatory)]$Layout)
    $writes = 0
    $sub = [string]$Scope.SubscriptionId
    $rg = [string]$Scope.ResourceGroupName
    $location = [string]$Scope.Location
    $plan = $Layout.Plan
    $accountName = [string]$Scope.FoundryAccountName
    $zoneIds = New-Object System.Collections.Generic.List[string]
    foreach ($zoneName in @($plan.DnsZones)) {
        $zone = Add-JawsStepBPrivateDnsZone -SubscriptionId $sub -ResourceGroupName $rg -ZoneName $zoneName -VnetId $Layout.VnetId -LinkName 'jaws-br-vnet'
        $writes += [int]$zone.AzureWrites
        $zoneIds.Add([string]$zone.Id) | Out-Null
    }
    $endpointName = "$accountName-pe"
    $accountId = "/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.CognitiveServices/accounts/$accountName"
    $endpoint = Invoke-JawsStepBAz -AllowMissing -Arguments @('network','private-endpoint','show','--subscription',$sub,'--resource-group',$rg,'--name',$endpointName,'--output','json','--only-show-errors')
    if ($null -eq $endpoint) {
        $endpoint = Invoke-JawsStepBAz -Arguments @(
            'network','private-endpoint','create','--subscription',$sub,'--resource-group',$rg,'--name',$endpointName,'--location',$location,
            '--vnet-name',$plan.VnetName,'--subnet',$plan.PrivateEndpointSubnet,
            '--private-connection-resource-id',$accountId,'--group-id','account','--connection-name',"$endpointName-conn",
            '--output','json','--only-show-errors'
        )
        $writes++
    }
    $groupShow = @('network','private-endpoint','dns-zone-group','show','--subscription',$sub,'--resource-group',$rg,'--endpoint-name',$endpointName,'--name','default','--output','json','--only-show-errors')
    $group = Invoke-JawsStepBAz -AllowMissing -Arguments $groupShow
    $aliases = @('cognitiveservices','openai','services')
    if ($null -eq $group) {
        $null = Invoke-JawsStepBAz -Arguments @(
            'network','private-endpoint','dns-zone-group','create','--subscription',$sub,'--resource-group',$rg,
            '--endpoint-name',$endpointName,'--name','default','--private-dns-zone',$zoneIds[0],'--zone-name',$aliases[0],'--output','json','--only-show-errors'
        )
        $writes++
        $group = Invoke-JawsStepBAz -AllowMissing -Arguments $groupShow
    }
    $attached = @(Get-JawsStepBPrivateDnsZoneIds $group)
    for ($i = 0; $i -lt $zoneIds.Count; $i++) {
        $zoneId = [string]$zoneIds[$i]
        if ($attached -contains $zoneId.ToLowerInvariant()) { continue }
        $null = Invoke-JawsStepBAz -Arguments @(
            'network','private-endpoint','dns-zone-group','add','--subscription',$sub,'--resource-group',$rg,
            '--endpoint-name',$endpointName,'--name','default','--private-dns-zone',$zoneId,'--zone-name',$aliases[$i],'--output','json','--only-show-errors'
        )
        $writes++
        $attached += $zoneId.ToLowerInvariant()
    }
    $compact = [string]$plan.Compact
    $pipName = "jaws-vpn-pip-$compact"
    $pip = Invoke-JawsStepBAz -AllowMissing -Arguments @('network','public-ip','show','--subscription',$sub,'--resource-group',$rg,'--name',$pipName,'--output','json','--only-show-errors')
    if ($null -eq $pip) {
        $null = Invoke-JawsStepBAz -Arguments @('network','public-ip','create','--subscription',$sub,'--resource-group',$rg,'--name',$pipName,'--location',$location,'--allocation-method','Static','--sku','Standard','--output','json','--only-show-errors')
        $writes++
    }
    $gatewayName = "jaws-vpn-$compact"
    $gateway = Invoke-JawsStepBAz -AllowMissing -Arguments @('network','vnet-gateway','show','--subscription',$sub,'--resource-group',$rg,'--name',$gatewayName,'--output','json','--only-show-errors')
    $tenant = [string](Get-JawsStepBProperty -Object (Invoke-JawsStepBAz -Arguments @('account','show','--output','json','--only-show-errors')) @('tenantId'))
    if ($null -eq $gateway) {
        $null = Invoke-JawsStepBAz -Arguments @(
            'network','vnet-gateway','create','--subscription',$sub,'--resource-group',$rg,'--name',$gatewayName,'--location',$location,
            '--public-ip-addresses',$pipName,'--vnet',$plan.VnetName,'--gateway-type','Vpn','--vpn-type','RouteBased','--sku','VpnGw1AZ',
            '--vpn-gateway-generation','Generation1','--vpn-auth-type','AAD','--client-protocol','OpenVPN','--address-prefixes',[string]$plan.VpnClientPrefix,
            '--aad-tenant',"https://login.microsoftonline.com/$tenant/",
            '--aad-audience','41b23e61-6c1e-4545-b367-cd054e0ed4b4',
            '--aad-issuer',"https://sts.windows.net/$tenant/",
            '--output','json','--only-show-errors'
        )
        $writes++
    }
    $resolverName = "jaws-dns-$compact"
    Install-JawsStepBDnsResolverCli
    $resolver = Invoke-JawsStepBAz -AllowMissing -Arguments @('dns-resolver','show','--subscription',$sub,'--resource-group',$rg,'--name',$resolverName,'--output','json','--only-show-errors')
    if ($null -eq $resolver) {
        $null = Invoke-JawsStepBAz -Arguments @('dns-resolver','create','--subscription',$sub,'--resource-group',$rg,'--name',$resolverName,'--location',$location,'--id',$Layout.VnetId,'--output','json','--only-show-errors')
        $writes++
    }
    $inbound = Invoke-JawsStepBAz -AllowMissing -Arguments @('dns-resolver','inbound-endpoint','show','--subscription',$sub,'--resource-group',$rg,'--dns-resolver-name',$resolverName,'--name','inbound','--output','json','--only-show-errors')
    if ($null -eq $inbound) {
        $config = '[{"private-ip-allocation-method":"Dynamic","id":"' + $Layout.ResolverSubnetId + '"}]'
        $inbound = Invoke-JawsStepBAz -Arguments @('dns-resolver','inbound-endpoint','create','--subscription',$sub,'--resource-group',$rg,'--dns-resolver-name',$resolverName,'--name','inbound','--ip-configurations',$config,'--output','json','--only-show-errors')
        $writes++
    }
    $inboundIp = ''
    $configs = @()
    if ($null -ne $inbound -and $inbound.PSObject.Properties['ipConfigurations']) { $configs = @($inbound.ipConfigurations) }
    elseif ($null -ne $inbound -and $inbound.PSObject.Properties['properties']) {
        $nested = $inbound.properties
        if ($null -ne $nested -and $nested.PSObject.Properties['ipConfigurations']) { $configs = @($nested.ipConfigurations) }
    }
    if ($configs.Count -gt 0 -and $configs[0].PSObject.Properties['privateIpAddress']) { $inboundIp = [string]$configs[0].privateIpAddress }
    if ([string]::IsNullOrWhiteSpace($inboundIp) -and $null -ne $inbound -and $inbound.PSObject.Properties['privateIpAddress']) {
        $inboundIp = [string]$inbound.privateIpAddress
    }
    [pscustomobject]@{
        AzureWrites = $writes
        VpnGatewayName = $gatewayName
        DnsResolverInboundIp = $inboundIp
        PrivateEndpointName = $endpointName
    }
}

function Get-JawsStepBPrivateDnsZoneIds {
    param($Group)
    if ($null -eq $Group) { return @() }
    $configs = @()
    if ($Group.PSObject.Properties['privateDnsZoneConfigs'] -and $null -ne $Group.privateDnsZoneConfigs) {
        $configs = @($Group.privateDnsZoneConfigs)
    } elseif ($Group.PSObject.Properties['properties'] -and $null -ne $Group.properties -and $Group.properties.PSObject.Properties['privateDnsZoneConfigs'] -and $null -ne $Group.properties.privateDnsZoneConfigs) {
        $configs = @($Group.properties.privateDnsZoneConfigs)
    }
    $ids = New-Object System.Collections.Generic.List[string]
    foreach ($config in $configs) {
        if ($null -eq $config) { continue }
        $id = ''
        if ($config.PSObject.Properties['privateDnsZoneId']) { $id = [string]$config.privateDnsZoneId }
        if ([string]::IsNullOrWhiteSpace($id) -and $config.PSObject.Properties['properties'] -and $null -ne $config.properties -and $config.properties.PSObject.Properties['privateDnsZoneId']) {
            $id = [string]$config.properties.privateDnsZoneId
        }
        if (-not [string]::IsNullOrWhiteSpace($id)) { $ids.Add($id.ToLowerInvariant()) | Out-Null }
    }
    return @($ids)
}

function Test-JawsStepBPrivateDataPlaneUnreachable {
    param([string]$Message)
    if ($Message -match 'JAWS-STEP-B-029') { return $true }
    # The public name still resolves. The account then refuses the call because public access is disabled.
    return $Message -match '(?i)public access is disabled|public network access is disabled|PublicNetworkAccess|Virtual Network/Firewall rules'
}

function Test-JawsStepBPrivateDataPlaneReachable {
    param([Parameter(Mandatory)]$Scope)
    $url = "https://$($Scope.FoundryAccountName).services.ai.azure.com/api/projects/$($Scope.ProjectName)/agents?api-version=v1"
    try {
        $null = Invoke-JawsStepBAz -Arguments @('rest','--method','GET','--url',$url,'--resource','https://ai.azure.com','--output','json','--only-show-errors')
        return $true
    } catch {
        if (Test-JawsStepBPrivateDataPlaneUnreachable $_.Exception.Message) { return $false }
        throw
    }
}

function New-JawsStepBPrivatePause {
    param(
        [Parameter(Mandatory)]$Scope,
        [Parameter(Mandatory)][string]$InstallerRoot,
        [Parameter(Mandatory)]$Layout,
        [Parameter(Mandatory)]$Access,
        [Parameter(Mandatory)][int]$AzureWrites,
        [Parameter(Mandatory)][string]$PlanSha256
    )
    $local = Join-Path $InstallerRoot '.local'
    if (-not (Test-Path -LiteralPath $local)) { New-Item -ItemType Directory -Path $local | Out-Null }
    $receipt = [pscustomobject]@{
        SchemaVersion = '1.0'
        Status = 'STEP_B_PRIVATE_PAUSED'
        Result = 'PAUSED'
        NetworkProfile = 'Private'
        PlanSha256 = $PlanSha256
        SubscriptionId = [string]$Scope.SubscriptionId
        ResourceGroupName = [string]$Scope.ResourceGroupName
        Location = [string]$Scope.Location
        EnvironmentName = [string]$Scope.EnvironmentName
        FoundryAccountName = [string]$Scope.FoundryAccountName
        ProjectName = [string]$Scope.ProjectName
        PrivatePostureVerified = $true
        SupervisorCreated = $false
        VpnGatewayName = [string]$Access.VpnGatewayName
        DnsResolverInboundIp = [string]$Access.DnsResolverInboundIp
        AgentsSubnetId = [string]$Layout.AgentsSubnetId
        AzureWrites = $AzureWrites
        OperatorAction = 'Connect the point-to-site VPN on this computer, set its DNS server to DnsResolverInboundIp, and run the same Install command again.'
        CustomerInstallationAccepted = $false
        FedRAMPModerate = $false
        CompletedAtUtc = [DateTime]::UtcNow.ToString('o')
    }
    $path = Join-Path $local "jaws-step-b-install.$($Scope.EnvironmentName).generated.json"
    $receipt | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $path -Encoding utf8
    [pscustomobject]@{ Paused = $true; Receipt = $receipt; ReceiptPath = $path; StatePath = $null }
}
