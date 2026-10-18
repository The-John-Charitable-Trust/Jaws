# Step C | JAWS source-code implementation

RemoteA2A and toolbox configuration are implemented in PowerShell; the hosted Supervisor runtime is implemented in C#. The Investigation Planner is a Foundry prompt agent, not a Python program. No Python implementation was found in the current Step C source.

**Provenance:** All listings below are verbatim, contiguous excerpts retrieved from the `main` branch of [The-John-Charitable-Trust/Jaws](https://github.com/The-John-Charitable-Trust/Jaws). No code here is invented, pseudocode, or a Microsoft sample. The line numbers and blob identifiers identify the reviewed snapshot. Other lines are intentionally omitted; open each linked source file for its complete implementation. Executing an excerpt alone is not equivalent to running the full JAWS installer.

## installer/Configure-JawsDelegationConnection.ps1

[View complete JAWS source](https://github.com/The-John-Charitable-Trust/Jaws/blob/main/installer/Configure-JawsDelegationConnection.ps1) · Reviewed blob `2957e311caf3af710bf4b321c7926647e1c185a0`

**Source lines 18–43:**

```powershell
# Foundry rejects A2A operations on hosted agents (HOSTED_AGENT_NOT_SUPPORTED / -32099).
# The prompt planner is the A2A target. Hosted Investigation v1 stays in place.
$hostedTarget="$endpoint/agents/jaws-investigation-dev/endpoint/protocols/a2a"
$target="$endpoint/agents/jaws-investigation-planner-dev/endpoint/protocols/a2a"
$id="/subscriptions/$($state.SubscriptionId)/resourceGroups/$($state.ResourceGroupName)/providers/Microsoft.CognitiveServices/accounts/$foundry/projects/$project/connections/$name"
# Correct PowerShell interpolation: a question mark immediately after a variable needs $().
$url="https://management.azure.com/$($id.TrimStart('/'))?api-version=2025-04-01-preview"
$payload=[ordered]@{
 name=$name
 properties=[ordered]@{
  authType='AgenticIdentityToken'
  group='ServicesAndApps'
  category='RemoteA2A'
  target=$target
  isSharedToAll=$true
  sharedUserList=@()
  audience='https://ai.azure.com'
  Credentials=[ordered]@{}
  metadata=[ordered]@{ApiType='Azure'}
 }
}
$json=ConvertTo-Json -InputObject $payload -Depth 12 -Compress
$sha=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($json))).ToLowerInvariant()
$dir=Join-Path $PSScriptRoot '.local'
if(-not(Test-Path $dir)){ $null=New-Item -ItemType Directory -Path $dir -Force }
$planFile=Join-Path $dir 'jaws-step-c-delegation-connection-plan.dev.generated.json'
```

**Source lines 119–136:**

```powershell
 throw 'JAWS-DELEGATE-004: Existing connection differs; refusing to overwrite.'
}
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
$receipt=Join-Path $dir 'jaws-step-c-delegation-connection-receipt.dev.generated.json'
[pscustomobject]@{Status='REMOTE_A2A_CONNECTION_VERIFIED';ResourceId=$id;Target=$target;AuthType='AgenticIdentityToken';PlanSha256=$sha;SupervisorDelegationVerified=$false;VerifiedAtUtc=[DateTime]::UtcNow.ToString('o')} |
 ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receipt -Encoding utf8
Write-Host "Verified RemoteA2A connection: $name; Receipt: $receipt"
```

## installer/Configure-JawsDelegationToolbox.ps1

[View complete JAWS source](https://github.com/The-John-Charitable-Trust/Jaws/blob/main/installer/Configure-JawsDelegationToolbox.ps1) · Reviewed blob `8b7e3aae3a8500bce52d4b51ea18dbd6249f6a89`

**Source lines 1–27:**

```powershell
# Step C: Foundry A2A v1.0 toolbox. No Supervisor modification.
[CmdletBinding()]
param(
 [ValidateSet('Plan','Install','Verify')][string]$Mode='Plan',
 [string]$ApprovedPlanSha256,
 [switch]$AcknowledgeToolboxChargesAndAccess
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$project='https://jaws-foundry-dev.services.ai.azure.com/api/projects/jaws-dev'
$name='jaws-investigation-a2a-tools'
$connName='jaws-investigation-a2a-dev'
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
$target="https://jaws-foundry-dev.services.ai.azure.com/api/projects/jaws-dev/agents/jaws-investigation-planner-dev/endpoint/protocols/a2a"
$directTarget=if($conn.PSObject.Properties['target']){[string]$conn.target}else{''}
$nestedTarget=if($conn.PSObject.Properties['properties'] -and $conn.properties -and $conn.properties.PSObject.Properties['target']){[string]$conn.properties.target}else{''}
```

## src/Jaws.Supervisor.Host/Program.cs

[View complete JAWS source](https://github.com/The-John-Charitable-Trust/Jaws/blob/main/src/Jaws.Supervisor.Host/Program.cs) · Reviewed blob `b9319105b2e30264fd78b9507323e7064943444d`

**Source lines 28–42:**

```csharp
{
    throw new InvalidOperationException("JAWS_INVESTIGATION_TOOLBOX_NAME is invalid.");
}
AIAgent supervisor = new AIProjectClient(endpoint, credential)
    .AsAIAgent(
        model: model,
        instructions: """
            You are JAWS Supervisor, an operational investigation coordinator.
            Respond concisely and accurately. If a verified Investigation toolbox is available,
            delegate read-only investigation planning when it is useful, and report its result
            with attribution. Never claim a delegation happened unless a real tool call succeeds.
            Do not claim access to Azure Policy,
            Defender, Datadog, ServiceNow, scripts, or specialist workers until
            authenticated tool integrations have been configured and verified.
            Never assert that a remediation was executed, an approval was granted,
```

**Source lines 57–79:**

```csharp

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddFoundryResponses(supervisor);
// Supported Foundry hosted-toolbox integration (Microsoft Agent Framework).
// Installer must verify toolbox version, identity, RBAC and operator approval
// before it deploys a new Supervisor container with this setting.
if (!string.IsNullOrWhiteSpace(toolboxName))
{
    builder.Services.AddFoundryToolboxes(credential, toolboxName);
    // AddFoundryToolboxes lists tools but does not echo tools/list _meta on tools/call.
    // The Foundry proxy rejects that call. This startup pass forwards the listed metadata.
    builder.Services.AddHostedService<FoundryToolboxMetadataStartup>();
}
var app = builder.Build();
app.MapGet("/healthz", () => Results.Ok(new {
    status = "ready",
    component = "jaws-supervisor-host",
    agentIntegration = string.IsNullOrWhiteSpace(toolboxName) ? "not-configured" : "toolbox-registered-unverified",
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
