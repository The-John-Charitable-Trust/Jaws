BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../installer/modules/SupervisorInstall.psm1') -Force
    $script:goodImage='jawsregistry.azurecr.io/jaws/supervisor@sha256:' + ('a' * 64)
    $script:components=@('foundry','project','model','vault' | ForEach-Object { $_ })
    $script:plan=[pscustomobject]@{
        PlanKind='AzureAwareReadOnly';CanExecute=$false;AzureWrites=0;AzureDiscoveryPerformed=$true
        Status='BLOCKED_PENDING_CONFIG_COST_RBAC_AND_APPROVAL'
        SubscriptionId='11111111-1111-1111-1111-111111111111'
        ResourceGroupName='rg-jaws-test';TenantId='tenant-example'
        Components=@(('foundry','project','model','vault') | ForEach-Object {
            [pscustomobject]@{Id=$_;Ownership='External';ProposedAction='CandidateForReuseRequiresConfigValidation'}
        })
    }
}
Describe 'B2.1 hosted Supervisor deployment approval preparation — no cloud writes' {
    It 'produces a blocked, digest-bound deployment proposal' {
        $p=New-JawsSupervisorInstallProposal -AzurePlan $script:plan -FoundryName 'jaws-foundry-dev' -ProjectName 'jaws-dev' -Image $script:goodImage
        $p.CanExecute | Should -BeFalse
        $p.AzureWrites | Should -Be 0
        $p.Readiness | Should -Be 'BLOCKED_PENDING_IMAGE_RBAC_COST_AND_OPERATOR_APPROVAL'
        $p.ProposalSha256 | Should -Match '^[0-9a-f]{64}$'
        $p.Deployment.ContainerImage | Should -Be $script:goodImage
    }
    It 'creates reproducible fingerprint for the same inputs' {
        $a=New-JawsSupervisorInstallProposal -AzurePlan $script:plan -FoundryName 'jaws-foundry-dev' -ProjectName 'jaws-dev' -Image $script:goodImage
        $b=New-JawsSupervisorInstallProposal -AzurePlan $script:plan -FoundryName 'jaws-foundry-dev' -ProjectName 'jaws-dev' -Image $script:goodImage
        $a.ProposalSha256 | Should -Be $b.ProposalSha256
    }
    It 'rejects an unpinned container image' {
        { New-JawsSupervisorInstallProposal -AzurePlan $script:plan -FoundryName 'jaws-foundry-dev' -ProjectName 'jaws-dev' -Image 'registry.azurecr.io/jaws/supervisor:latest' } | Should -Throw '*JAWS-INSTALL-004*'
    }
    It 'requires a completed read-only Azure plan' {
        $bad=$script:plan.PSObject.Copy()
        $bad.AzureDiscoveryPerformed=$false
        { New-JawsSupervisorInstallProposal -AzurePlan $bad -FoundryName 'jaws-foundry-dev' -ProjectName 'jaws-dev' -Image $script:goodImage } | Should -Throw '*JAWS-INSTALL-001*'
    }
    It 'blocks drift/ownership statuses' {
        $bad=$script:plan.PSObject.Copy()
        $bad.Status='BLOCKED_RESOURCE_DRIFT_OR_OWNERSHIP'
        { New-JawsSupervisorInstallProposal -AzurePlan $bad -FoundryName 'jaws-foundry-dev' -ProjectName 'jaws-dev' -Image $script:goodImage } | Should -Throw '*JAWS-INSTALL-002*'
    }
    It 'blocks missing externally-owned reusable resources' {
        $bad=$script:plan.PSObject.Copy()
        $bad.Components=@($script:plan.Components | Where-Object Id -ne 'vault')
        { New-JawsSupervisorInstallProposal -AzurePlan $bad -FoundryName 'jaws-foundry-dev' -ProjectName 'jaws-dev' -Image $script:goodImage } | Should -Throw '*JAWS-INSTALL-005*'
    }
    It 'does not add active Install mode before permissions and image are validated' {
        $entry=Get-Content (Join-Path $PSScriptRoot '../../installer/Install-Jaws.ps1') -Raw
        $entry | Should -Match "ValidateSet\('Discover','Plan'\)"
        $entry | Should -Not -Match "ValidateSet\('Discover','Plan','Install'\)"
    }
}
