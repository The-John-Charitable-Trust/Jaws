BeforeAll {
    $root=[System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $rbacPath=Join-Path $root 'installer/Configure-JawsDelegationConsumerRbac.ps1'
    $acceptancePath=Join-Path $root 'installer/Test-JawsStepCDelegation.ps1'
    $installerPath=Join-Path $root 'installer/Install-JawsStepC.ps1'
    $rbac=Get-Content -LiteralPath $rbacPath -Raw
    $acceptance=Get-Content -LiteralPath $acceptancePath -Raw
    $installer=Get-Content -LiteralPath $installerPath -Raw
}

Describe 'Step C Supervisor delegation RBAC gate' {
    It 'targets the released Supervisor instance identity' {
        $rbac | Should -Match "instance_identity"
        $rbac | Should -Match "principal_id"
        $rbac | Should -Match 'versions\.latest'
        $rbac | Should -Match 'versions/\$\(\$version\)'
        $rbac | Should -Not -Match '\$version\s*=\s*''2'''
    }

    It 'uses the least-privilege Foundry Agent Consumer role at project scope' {
        $rbac | Should -Match 'eed3b665-ab3a-47b6-8f48-c9382fb1dad6'
        $rbac | Should -Match 'Microsoft\.CognitiveServices/accounts/\$account/projects/\$project'
        $rbac | Should -Not -Match '(?i)--role\s+[''"]?(Owner|Contributor)[''"]?'
    }

    It 'permits mutation only in explicitly approved Assign mode' {
        @([regex]::Matches($rbac,'& az role assignment create')).Count | Should -Be 1
        $rbac | Should -Match 'ApprovedPlanSha256'
        $rbac | Should -Match 'AcknowledgeSecurityRoleAssignment'
    }

    It 'verifies delegation RBAC before final inference' {
        $verifyIndex=$acceptance.IndexOf("Configure-JawsDelegationConsumerRbac.ps1")
        $postIndex=$acceptance.IndexOf('& az rest --method post')
        $verifyIndex | Should -BeGreaterThan -1
        $postIndex | Should -BeGreaterThan $verifyIndex
    }

    It 'derives the approved hash inside the consolidated installer' {
        $installer | Should -Match "DelegationRbacInstall"
        $installer | Should -Match "jaws-step-c-delegation-consumer-rbac-plan\.dev\.generated\.json"
        $installer | Should -Match '-ApprovedPlanSha256 \$plan\.PlanSha256'
        $installer | Should -Match "Read-Host 'Approve this least-privilege security role assignment\? \[y/N\]'"
        $installer | Should -Not -Match '\[string\]\$ApprovedDelegationRbacSha256'
    }
}
