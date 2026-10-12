BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../installer/modules/DeploymentPlan.psm1') -Force
    $script:templatePath = Join-Path $PSScriptRoot '../../installer/config/jaws-stage-b-plan.example.json'
    $script:sampleId = '11111111-1111-1111-1111-111111111111'
    function New-TestBlueprintFile {
        param([scriptblock]$Mutate)
        $json = Get-Content $script:templatePath -Raw | ConvertFrom-Json
        $json.Scope.SubscriptionId = $script:sampleId
        if ($Mutate) { & $Mutate $json }
        $path = Join-Path ([IO.Path]::GetTempPath()) ("jaws-plan-" + [guid]::NewGuid().ToString('N') + '.json')
        $json | ConvertTo-Json -Depth 40 | Set-Content -Path $path -Encoding utf8
        return $path
    }
}
Describe 'Stage B2 offline blueprint planning' {
    It 'rejects the unconfigured example rather than assuming a subscription' {
        { New-JawsOfflineDeploymentPlan -BlueprintPath $script:templatePath } | Should -Throw '*JAWS-PLAN-004*'
    }
    It 'returns a blocked plan with no Azure writes or discovery' {
        $path = New-TestBlueprintFile
        try {
            $p = New-JawsOfflineDeploymentPlan -BlueprintPath $path
            $p.CanExecute | Should -BeFalse
            $p.AzureWrites | Should -Be 0
            $p.AzureDiscoveryPerformed | Should -BeFalse
            $p.CostsVerified | Should -BeFalse
            $p.UserAuthorizationVerified | Should -BeFalse
            $p.Status | Should -Be 'BLOCKED_PENDING_AZURE_DISCOVERY_AND_APPROVAL'
            @($p.Components).Count | Should -Be 16
        } finally { Remove-Item $path -Force -ErrorAction SilentlyContinue }
    }
    It 'orders dependencies before dependents' {
        $path = New-TestBlueprintFile
        try {
            $p = New-JawsOfflineDeploymentPlan -BlueprintPath $path
            $ids = @($p.Components | ForEach-Object Id)
            foreach ($c in $p.Components) {
                foreach ($dep in $c.DependsOn) {
                    [array]::IndexOf($ids, $dep) | Should -BeLessThan ([array]::IndexOf($ids, $c.Id))
                }
            }
        } finally { Remove-Item $path -Force -ErrorAction SilentlyContinue }
    }
    It 'rejects a blueprint that permits Azure writes' {
        $path = New-TestBlueprintFile -Mutate { param($b) $b.Constraints.AzureWritesAllowed = $true }
        try { { New-JawsOfflineDeploymentPlan -BlueprintPath $path } | Should -Throw '*JAWS-PLAN-005*' }
        finally { Remove-Item $path -Force -ErrorAction SilentlyContinue }
    }
    It 'rejects components missing approval' {
        $path = New-TestBlueprintFile -Mutate { param($b) $b.Components[0].ApprovalRequired = $false }
        try { { New-JawsOfflineDeploymentPlan -BlueprintPath $path } | Should -Throw '*JAWS-PLAN-006*' }
        finally { Remove-Item $path -Force -ErrorAction SilentlyContinue }
    }
    It 'rejects dependency cycles' {
        $path = New-TestBlueprintFile -Mutate { param($b) $b.Components[0].DependsOn = @('validation') }
        try { { New-JawsOfflineDeploymentPlan -BlueprintPath $path } | Should -Throw '*JAWS-PLAN-008*' }
        finally { Remove-Item $path -Force -ErrorAction SilentlyContinue }
    }
    It 'rejects unknown dependencies' {
        $path = New-TestBlueprintFile -Mutate { param($b) $b.Components[0].DependsOn = @('unknown-resource') }
        try { { New-JawsOfflineDeploymentPlan -BlueprintPath $path } | Should -Throw '*JAWS-PLAN-007*' }
        finally { Remove-Item $path -Force -ErrorAction SilentlyContinue }
    }
    It 'does not change Stage A Discover path or add Install mode' {
        $scriptPath = Join-Path $PSScriptRoot '../../installer/Install-Jaws.ps1'
        $body = Get-Content -LiteralPath $scriptPath -Raw
        $body | Should -Match "ValidateSet\('Discover','Plan'\)"
        $body | Should -Match 'if \(\$Mode -eq ''Plan''\)'
        $body | Should -Not -Match "ValidateSet\('Discover','Plan','Install'\)"
    }
}
