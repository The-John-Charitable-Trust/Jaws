# B2.1 Supervisor deployment approval: no Azure write capability in this module.
Set-StrictMode -Version Latest
function New-JawsSupervisorInstallProposal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$AzurePlan,
        [Parameter(Mandatory)][string]$FoundryName,
        [Parameter(Mandatory)][string]$ProjectName,
        [Parameter(Mandatory)][string]$Image,
        [string]$AgentName='jaws-supervisor-dev'
    )
    if ($AzurePlan.PlanKind -ne 'AzureAwareReadOnly' -or $AzurePlan.CanExecute -ne $false -or
        $AzurePlan.AzureWrites -ne 0 -or $AzurePlan.AzureDiscoveryPerformed -ne $true) {
        throw 'JAWS-INSTALL-001: A completed read-only Azure assessment is required.'
    }
    if ($AzurePlan.Status -ne 'BLOCKED_PENDING_CONFIG_COST_RBAC_AND_APPROVAL') {
        throw 'JAWS-INSTALL-002: Existing resource drift/ownership or assessment issues block deployment.'
    }
    if ($AgentName -notmatch '^[a-zA-Z][a-zA-Z0-9-]{2,62}$' -or
        $FoundryName -notmatch '^[a-zA-Z0-9-]{2,64}$' -or
        $ProjectName -notmatch '^[a-zA-Z0-9-]{2,64}$') {
        throw 'JAWS-INSTALL-003: Invalid Supervisor, Foundry or project name.'
    }
    # Container image must be digest pinned to preclude tag substitution after approval.
    if ($Image -notmatch '^[a-zA-Z0-9-]+\\.azurecr\\.io(/[a-zA-Z0-9._-]+)+@sha256:[a-fA-F0-9]{64}$' -or
        $Image -match '(?i)(localhost|127\.0\.0\.1)') {
        throw 'JAWS-INSTALL-004: Hosted agent image must be a registry image pinned by sha256 digest.'
    }
    foreach ($id in @('foundry','project','model','vault')) {
        $matches=@($AzurePlan.Components | Where-Object Id -eq $id)
        if ($matches.Count -ne 1 -or $matches[0].ProposedAction -ne 'CandidateForReuseRequiresConfigValidation' -or
            $matches[0].Ownership -ne 'External') {
            throw "JAWS-INSTALL-005: Expected externally owned $id resource not available for reuse review."
        }
    }
    $payload=[ordered]@{
        SchemaVersion='0.1'
        Action='CreateHostedSupervisorAgent'
        SubscriptionId=[string]$AzurePlan.SubscriptionId
        ResourceGroupName=[string]$AzurePlan.ResourceGroupName
        TenantId=[string]$AzurePlan.TenantId
        FoundryResourceName=$FoundryName
        FoundryProjectName=$ProjectName
        SupervisorAgentName=$AgentName
        ContainerImage=$Image
        ApiVersion='v1'
        Cpu='1'
        Memory='2Gi'
        Protocol='responses'
        ProtocolVersion='2.0.0'
    }
    $proposalText=ConvertTo-Json -InputObject $payload -Depth 12 -Compress
    $sha=[System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($proposalText))
    $fingerprint=[Convert]::ToHexString($sha).ToLowerInvariant()
    [pscustomobject]@{
        SchemaVersion='0.1'
        ProposalType='SupervisorHostedAgentDeployment'
        ProposalSha256=$fingerprint
        ApprovalScope='Exact proposal only; fingerprint is NOT an authorization or a digital signature'
        Readiness='BLOCKED_PENDING_IMAGE_RBAC_COST_AND_OPERATOR_APPROVAL'
        CanExecute=$false
        AzureWrites=0
        Prerequisites=@(
            'Foundry Project Manager at project scope or other proven equivalent',
            'Hosted agents supported for project/region and selected model',
            'Trusted pre-built ACR image implementing Responses 2.0.0',
            'Project managed identity has ACR Repository Reader to selected image',
            'Approved budget/exposure and operator authorization',
            'No existing agent with the proposed name; no unrelated resources affected'
        )
        Deployment=$payload
    }
}
Export-ModuleMember -Function New-JawsSupervisorInstallProposal
