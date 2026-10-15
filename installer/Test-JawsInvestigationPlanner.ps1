# Read-only check that the A2A target is the prompt planner, not the hosted Investigation agent.
[CmdletBinding()]
param(
 [string]$ProjectEndpoint='https://jaws-foundry-dev.services.ai.azure.com/api/projects/jaws-dev',
 [string]$AgentName='jaws-investigation-planner-dev'
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'Configure-JawsInvestigationPlanner.ps1') -Mode Verify -ProjectEndpoint $ProjectEndpoint -AgentName $AgentName
if(-not $?){throw 'JAWS-PLANNER-003: Prompt planner is not the expected active A2A target.'}
