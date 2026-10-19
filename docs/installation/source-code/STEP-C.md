# Step C | JAWS source-code implementation

RemoteA2A and toolbox configuration are implemented in PowerShell; the hosted Supervisor runtime is implemented in C#. The Investigation Planner is a Foundry prompt agent, not a Python program. No Python implementation was found in the current Step C source.

**Provenance:** All listings below are verbatim, contiguous excerpts retrieved from the `main` branch of [The-John-Charitable-Trust/Jaws](https://github.com/The-John-Charitable-Trust/Jaws). No code here is invented, pseudocode, or a Microsoft sample. The line numbers and blob identifiers identify the reviewed snapshot. Other lines are intentionally omitted; open each linked source file for its complete implementation. Executing an excerpt alone is not equivalent to running the full JAWS installer.

## installer/Configure-JawsDelegationConnection.ps1

[View complete JAWS source](https://github.com/The-John-Charitable-Trust/Jaws/blob/main/installer/Configure-JawsDelegationConnection.ps1) · Reviewed blob `484831a52a4252e110bea9b0a7c3f960d4e1820d`

**Source lines 15–36:**

```powershell
if([string]$state.EnvironmentName -ceq 'dev'){
 if($state.ResourceGroupName -cne 'rg-aiops-lab'){throw 'JAWS-DELEGATE-001: Unauthorized installation state.'}
 $foundry='jaws-foundry-dev'; $project='jaws-dev'; $name='jaws-investigation-a2a-dev'
 $hostedAgent='jaws-investigation-dev'; $plannerAgent='jaws-investigation-planner-dev'
 $sharedToAll=$true
 $planSuffix='dev'
}else{
 Import-Module (Join-Path $PSScriptRoot 'modules/StepCEnvironment.psm1') -Force
 $connectionContext=Resolve-JawsStepCStepBContext -EnvironmentName ([string]$state.EnvironmentName) -InstallerRoot $PSScriptRoot
 if($state.ResourceGroupName -cne $connectionContext.ResourceGroupName -or [string]$state.SubscriptionId -ine $connectionContext.SubscriptionId){
  throw 'JAWS-DELEGATE-001: Installation state does not match the Step B receipt.'
 }
 $foundry=$connectionContext.FoundryAccountName; $project=$connectionContext.ProjectName; $name=$connectionContext.ConnectionName
 $hostedAgent="jaws-investigation-$($connectionContext.EnvironmentName)"; $plannerAgent=$connectionContext.PlannerAgent
 $sharedToAll=$false
 $planSuffix=$connectionContext.PlanSuffix
}
$endpoint="https://$foundry.services.ai.azure.com/api/projects/$project"
# Foundry rejects A2A operations on hosted agents (HOSTED_AGENT_NOT_SUPPORTED / -32099).
# The prompt planner is the A2A target. A hosted Investigation agent is not created for a Step B environment.
$hostedTarget="$endpoint/agents/$hostedAgent/endpoint/protocols/a2a"
$target="$endpoint/agents/$plannerAgent/endpoint/protocols/a2a"
```

**Source lines 136–151:**

```powershell
if($Mode -eq 'Install' -and $null -eq $current){
 if(-not $AcknowledgeA2AConnection -or $ApprovedPlanSha256 -cne $sha){
  throw 'JAWS-DELEGATE-005: Exact plan approval and acknowledgment required.'
 }
 $tmp=[IO.Path]::GetTempFileName()
 try{
  [IO.File]::WriteAllText($tmp,$json,[Text.UTF8Encoding]::new($false))
  $result=& az rest --method put --url $url --resource https://management.azure.com/ --headers 'Content-Type=application/json' --body "@$tmp" --output json --only-show-errors 2>&1
  if($LASTEXITCODE -ne 0){throw "JAWS-DELEGATE-006: Connection PUT outcome uncertain; inspect live state: $($result | Out-String)"}
 }finally{Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue}
}
Assert-Connection (Read-Connection)
$receipt=Join-Path $dir "jaws-step-c-delegation-connection-receipt.$planSuffix.generated.json"
[pscustomobject]@{Status='REMOTE_A2A_CONNECTION_VERIFIED';ResourceId=$id;Target=$target;AuthType='AgenticIdentityToken';PlanSha256=$sha;SupervisorDelegationVerified=$false;VerifiedAtUtc=[DateTime]::UtcNow.ToString('o')} |
 ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receipt -Encoding utf8
Write-Host "Verified RemoteA2A connection: $name; Receipt: $receipt"
```

## installer/Configure-JawsDelegationToolbox.ps1

[View complete JAWS source](https://github.com/The-John-Charitable-Trust/Jaws/blob/main/installer/Configure-JawsDelegationToolbox.ps1) · Reviewed blob `81a95337406e11ce14454214096575aaf07c5215`

**Source lines 1–47:**

```powershell
# Step C: Foundry A2A v1.0 toolbox. No Supervisor modification.
[CmdletBinding()]
param(
 [ValidateSet('Plan','Install','Verify')][string]$Mode='Plan',
 [string]$ApprovedPlanSha256,
 [switch]$AcknowledgeToolboxChargesAndAccess,
 [string]$EnvironmentName='dev',
 [string]$ProjectEndpoint='https://jaws-foundry-dev.services.ai.azure.com/api/projects/jaws-dev',
 [string]$ToolboxName='jaws-investigation-a2a-tools',
 [string]$ConnectionName='jaws-investigation-a2a-dev',
 [string]$PlannerAgent='jaws-investigation-planner-dev'
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($EnvironmentName -ceq 'dev'){
 if($ProjectEndpoint -cne 'https://jaws-foundry-dev.services.ai.azure.com/api/projects/jaws-dev' -or
    $ToolboxName -cne 'jaws-investigation-a2a-tools' -or
    $ConnectionName -cne 'jaws-investigation-a2a-dev' -or
    $PlannerAgent -cne 'jaws-investigation-planner-dev'){
  throw 'JAWS-TOOLBOX-010: Unexpected toolbox scope.'
 }
 $planSuffix='dev'
}else{
 Import-Module (Join-Path $PSScriptRoot 'modules/StepCEnvironment.psm1') -Force
 $toolboxContext=Resolve-JawsStepCStepBContext -EnvironmentName $EnvironmentName -InstallerRoot $PSScriptRoot
 if($ProjectEndpoint -cne $toolboxContext.ProjectEndpoint -or $ToolboxName -cne $toolboxContext.ToolboxName -or
    $ConnectionName -cne $toolboxContext.ConnectionName -or $PlannerAgent -cne $toolboxContext.PlannerAgent){
  throw 'JAWS-TOOLBOX-010: Toolbox scope does not match the Step B installation.'
 }
 $planSuffix=$toolboxContext.PlanSuffix
}
$project=$ProjectEndpoint
$name=$ToolboxName
$connName=$ConnectionName
$connectionUrl="$project/connections/$($connName)?api-version=v1"
function Get-Api([string]$Url,[switch]$AllowNotFound) {
 $result=& az rest --method get --url $Url --resource https://ai.azure.com --output json --only-show-errors 2>&1
 if($LASTEXITCODE -eq 0){return ($result | Out-String | ConvertFrom-Json)}
 $err=$result | Out-String
 if($AllowNotFound -and $err -match '(?i)(404|not found)'){return $null}
 throw "JAWS-TOOLBOX-001: Unable to read Foundry state: $err"
}
$conn=Get-Api -Url $connectionUrl
if($null -eq $conn -or -not $conn.id -or $conn.name -cne $connName) {
 throw 'JAWS-TOOLBOX-002: Authenticated Investigation RemoteA2A project connection not verified.'
}
$target="$project/agents/$PlannerAgent/endpoint/protocols/a2a"
```

## src/Jaws.Supervisor.Host/Program.cs

[View complete JAWS source](https://github.com/The-John-Charitable-Trust/Jaws/blob/main/src/Jaws.Supervisor.Host/Program.cs) · Excerpt matches the current file. The earlier reviewed blob `b9319105b2e30264fd78b9507323e7064943444d` predates the browser toolbox.

**Source lines 25–58:**

```csharp
var toolboxNames = new List<string>();
AddToolbox(toolboxNames, "JAWS_INVESTIGATION_TOOLBOX_NAME");
AddToolbox(toolboxNames, "JAWS_BROWSER_TOOLBOX_NAME");
var browserToolbox = Environment.GetEnvironmentVariable("JAWS_BROWSER_TOOLBOX_NAME");
var instructions = """
    You are JAWS Supervisor, an operational investigation coordinator.
    Respond concisely and accurately. If a verified Investigation toolbox is available,
    delegate read-only investigation planning when it is useful, and report its result
    with attribution. Never claim a delegation happened unless a real tool call succeeds.
    Do not claim access to Azure Policy,
    Defender, Datadog, ServiceNow, scripts, or specialist workers until
    authenticated tool integrations have been configured and verified.
    Never assert that a remediation was executed, an approval was granted,
    or compliance was verified without genuine external evidence.
    Refuse requests to elevate permissions or bypass human approval.
    """;
var investigationToolbox = Environment.GetEnvironmentVariable("JAWS_INVESTIGATION_TOOLBOX_NAME");
if (!string.IsNullOrWhiteSpace(investigationToolbox))
{
    instructions += """

        The Investigation toolbox is configured. When the user asks for it, call that
        toolbox before you answer. Do not invent the Investigation agent's result.
        """;
}
if (!string.IsNullOrWhiteSpace(browserToolbox))
{
    instructions += """

        A browser toolbox is available for operator-approved sites only.
        Use it when the task has no API. Never supply a password or token.
        A navigation outside the allow-list is a tool error. Do not retry that URL.
        """;
}
```

**Source lines 75–96:**

```csharp
var builder = WebApplication.CreateBuilder(args);
builder.Services.AddFoundryResponses(supervisor);
// Supported Foundry hosted-toolbox integration (Microsoft Agent Framework).
// Installer must verify toolbox version, identity, RBAC and operator approval
// before it deploys a new Supervisor container with this setting.
if (toolboxNames.Count > 0)
{
    builder.Services.AddFoundryToolboxes(credential, toolboxNames.ToArray());
    // AddFoundryToolboxes lists tools but does not echo tools/list _meta on tools/call.
    // The Foundry proxy rejects that call. This startup pass forwards the listed metadata.
    builder.Services.AddHostedService<FoundryToolboxMetadataStartup>();
}
var app = builder.Build();
app.MapGet("/healthz", () => Results.Ok(new {
    status = "ready",
    component = "jaws-supervisor-host",
    agentIntegration = toolboxNames.Count == 0 ? "not-configured" : "toolbox-registered-unverified",
    deployment = model
}));
// Foundry hosting library provides the Responses protocol implementation.
app.MapFoundryResponses();
app.Run();
```

## src/Jaws.Supervisor.Host/FoundryToolboxMetadataStartup.cs

[View complete JAWS source](https://github.com/The-John-Charitable-Trust/Jaws/blob/main/src/Jaws.Supervisor.Host/FoundryToolboxMetadataStartup.cs) · Reviewed blob `17401d0129c3541bda29a0dd3a80f3b777e38c3f`

**Source lines 1–28:**

```csharp
using Microsoft.Agents.AI.Foundry.Hosting;
using Microsoft.Extensions.AI;
#pragma warning disable MAAI001

namespace Jaws.Supervisor.Host;

/// <summary>
/// Patches toolbox tools after <see cref="FoundryToolboxService"/> has enumerated them.
/// Tools created later, during a deferred per-request retry, are patched by
/// <see cref="FoundryToolboxCallMetadata.ForwardBeforeInvocation"/> before that run.
/// </summary>
internal sealed class FoundryToolboxMetadataStartup : IHostedService
{
    private readonly FoundryToolboxService _toolboxes;
    private readonly ILogger<FoundryToolboxMetadataStartup> _logger;

    public FoundryToolboxMetadataStartup(
        FoundryToolboxService toolboxes,
        ILogger<FoundryToolboxMetadataStartup> logger)
    {
        _toolboxes = toolboxes;
        _logger = logger;
    }

    public Task StartAsync(CancellationToken cancellationToken)
    {
        var tools = _toolboxes.Tools;
        if (tools.Count == 0)
```

## Scope and validation

The snippets above reflect the code on `main` at the time this documentation was authored. Do not use them as standalone scripts; use the documented installer commands and test/acceptance gates. After source changes, re-extract excerpts from the changed files and update the listed ranges and blob identifiers.
