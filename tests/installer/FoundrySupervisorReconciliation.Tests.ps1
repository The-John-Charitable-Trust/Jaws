BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../../installer/modules/FoundrySupervisorReconciliation.psm1') -Force
    $script:live=Get-Content (Join-Path $PSScriptRoot 'fixtures/foundry-supervisor-v1-actual.json') -Raw | ConvertFrom-Json
    $script:endpoint='https://jaws-foundry-dev.services.ai.azure.com/api/projects/jaws-dev'
    $script:image=$script:live.definition.container_configuration.image
    $script:plan=[pscustomobject]@{
        PlanSha256='test-plan'
        Plan=[pscustomobject]@{
            AgentName='jaws-supervisor-dev';ProjectEndpoint=$script:endpoint;Image=$script:image
            Request=[pscustomobject]@{definition=[pscustomobject]@{
                cpu='1';memory='2Gi';environment_variables=[pscustomobject]@{
                    AZURE_AI_MODEL_DEPLOYMENT_NAME='gpt-5-mini'
                    FOUNDRY_PROJECT_ENDPOINT=$script:endpoint
                }
            }}
        }
    }
}
Describe 'Foundry actual-state comparison against Azure response' {
    It 'reports the missing FOUNDRY_PROJECT_ENDPOINT explicitly rather than issuing a receipt' {
        $result=Compare-JawsFoundrySupervisorState -DeploymentPlan $script:plan -ActualAgent $script:live
        $result.OverallStatus | Should -Be 'DRIFT'
        $result.FailedFields | Should -Contain 'definition.environment_variables.FOUNDRY_PROJECT_ENDPOINT'
        $result.AzureWrites | Should -Be 0
    }
    It 'recognizes an exact match when the required variable is present' {
        $actual=$script:live | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $actual.definition.environment_variables | Add-Member -NotePropertyName FOUNDRY_PROJECT_ENDPOINT -NotePropertyValue $script:endpoint
        $result=Compare-JawsFoundrySupervisorState -DeploymentPlan $script:plan -ActualAgent $actual
        $result.OverallStatus | Should -Be 'MATCH'
        $result.FailedFields.Count | Should -Be 0
    }
    It 'detects immutable image drift even when the agent is active' {
        $actual=$script:live | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $actual.definition.environment_variables | Add-Member -NotePropertyName FOUNDRY_PROJECT_ENDPOINT -NotePropertyValue $script:endpoint
        $actual.definition.container_configuration.image='jawsregistrydev001.azurecr.io/jaws/supervisor@sha256:' + ('0'*64)
        $result=Compare-JawsFoundrySupervisorState -DeploymentPlan $script:plan -ActualAgent $actual
        $result.FailedFields | Should -Contain 'definition.container_configuration.image'
    }
    It 'accepts agent version in top-level version or nested versions.latest' {
        Get-JawsFoundryAgentVersion -Agent $script:live | Should -Be '1'
        Get-JawsFoundryAgentVersion -Agent ([pscustomobject]@{versions=[pscustomobject]@{latest='2'}}) | Should -Be '2'
        Get-JawsFoundryAgentVersion -Agent ([pscustomobject]@{versions=[pscustomobject]@{latest=[pscustomobject]@{version='3'}}}) | Should -Be '3'
    }
    It 'reports identity drift and empty fields without StrictMode exceptions' {
        $actual=[pscustomobject]@{name='wrong';status='active'}
        $result=Compare-JawsFoundrySupervisorState -DeploymentPlan $script:plan -ActualAgent $actual
        $result.OverallStatus | Should -Be 'DRIFT'
        $result.FailedFields | Should -Contain 'definition.container_configuration.image'
        $result.FailedFields | Should -Contain 'name'
    }
    It 'parses all changed installer modules without errors' {
        foreach($path in @('../../installer/modules/FoundrySupervisorReconciliation.psm1','../../installer/Recover-JawsSupervisorDeployment.ps1','../../installer/modules/FoundrySupervisorDeployment.psm1')) {
            $full=Join-Path $PSScriptRoot $path
            $tokens=$null;$errors=$null
            $null=[System.Management.Automation.Language.Parser]::ParseFile($full,[ref]$tokens,[ref]$errors)
            @($errors).Count | Should -Be 0
        }
    }
}
