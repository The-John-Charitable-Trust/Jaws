BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../installer/modules/SupervisorPublish.psm1') -Force
    $script:id='11111111-1111-1111-1111-111111111111'
    $script:state=[pscustomobject]@{Platform='JAWS';SubscriptionId=$script:id;ResourceGroupName='rg-aiops-lab'}
    $script:receipt=[pscustomobject]@{
        Status='CREATED_AND_VERIFIED';Ownership='InstallerCreated';CreatedByInstaller=$true
        AdminEnabled=$false;Sku='Basic';LoginServer='jawsregistrydev001.azurecr.io'
        RegistryResourceId="/subscriptions/$script:id/resourceGroups/rg-aiops-lab/providers/Microsoft.ContainerRegistry/registries/jawsregistrydev001"
    }
    $script:imageId='sha256:' + ('a'*64)
}
Describe 'JAWS Supervisor registry image publication preparation' {
    It 'produces stable plan hash and scoped immutable source image ID' {
        $p=Get-JawsSupervisorPublishPlan -State $script:state -RegistryReceipt $script:receipt -LocalImageId $script:imageId
        $p.PlanSha256 | Should -Match '^[0-9a-f]{64}$'
        $p.Plan.TargetTag | Should -Be 'jawsregistrydev001.azurecr.io/jaws/supervisor:build-aaaaaaaaaaaaaaaa'
        $p.CanPublishWithoutApproval | Should -BeFalse
        $p.AzureWrites | Should -Be 0
    }
    It 'computes same plan hash for same inputs' {
        $a=Get-JawsSupervisorPublishPlan -State $script:state -RegistryReceipt $script:receipt -LocalImageId $script:imageId
        $b=Get-JawsSupervisorPublishPlan -State $script:state -RegistryReceipt $script:receipt -LocalImageId $script:imageId
        $a.PlanSha256 | Should -Be $b.PlanSha256
    }
    It 'does not allow unrelated registries' {
        $bad=$script:receipt.PSObject.Copy()
        $bad.RegistryResourceId=$bad.RegistryResourceId.Replace('rg-aiops-lab','other-rg')
        { Get-JawsSupervisorPublishPlan -State $script:state -RegistryReceipt $bad -LocalImageId $script:imageId } | Should -Throw '*JAWS-PUSH-004*'
    }
    It 'rejects a registry with admin enabled' {
        $bad=$script:receipt.PSObject.Copy()
        $bad.AdminEnabled=$true
        { Get-JawsSupervisorPublishPlan -State $script:state -RegistryReceipt $bad -LocalImageId $script:imageId } | Should -Throw '*JAWS-PUSH-001*'
    }
    It 'rejects invalid local image IDs' {
        { Get-JawsSupervisorPublishPlan -State $script:state -RegistryReceipt $script:receipt -LocalImageId 'jaws-supervisor:latest' } | Should -Throw '*JAWS-PUSH-002*'
    }
    It 'protects against tampered publish plans before executing external commands' {
        $p=Get-JawsSupervisorPublishPlan -State $script:state -RegistryReceipt $script:receipt -LocalImageId $script:imageId
        $p.Plan.SourceImage='ubuntu:latest'
        { Invoke-JawsSupervisorPublish -Plan $p } | Should -Throw '*JAWS-PUSH-005*'
    }
    It 'requires exact approval hash and charge acknowledgment in entrypoint' {
        $body=Get-Content (Join-Path $PSScriptRoot '../../installer/Publish-JawsSupervisor.ps1') -Raw
        $body | Should -Match 'JAWS-PUSH-APPROVAL-001'
        $body | Should -Match 'AcknowledgeImageStorageAndTransferCharges'
        $body | Should -Match 'ApprovedPlanSha256'
    }
    It 'supports publishing only from the dedicated JAWS registry' {
        $body=Get-Content (Join-Path $PSScriptRoot '../../installer/modules/SupervisorPublish.psm1') -Raw
        $body | Should -Match 'az acr login'
        $body | Should -Match 'docker push'
        $body | Should -Match 'az acr manifest show-metadata'
        $body | Should -Match 'JAWS-PUSH-020'
        $body | Should -Not -Match 'az acr create'
        $body | Should -Not -Match 'az role assignment create'
    }
    It 'does not mix docker push progress with the structured publish result' {
        $body=Get-Content (Join-Path $PSScriptRoot '../../installer/modules/SupervisorPublish.psm1') -Raw
        $body | Should -Match '\& docker push \$Plan\.Plan\.TargetTag \| Out-Host'
    }
    It 'parses publishing module and entrypoint in PowerShell' {
        foreach($p in @('installer/Publish-JawsSupervisor.ps1','installer/modules/SupervisorPublish.psm1')) {
            $full=Join-Path (Join-Path $PSScriptRoot '../..') $p
            $tokens=$null;$errors=$null
            $null=[System.Management.Automation.Language.Parser]::ParseFile($full,[ref]$tokens,[ref]$errors)
            @($errors).Count | Should -Be 0
        }
    }
}
