# Step B | JAWS source-code implementation

Azure provisioning and readiness are implemented in PowerShell; the hosted Supervisor application is implemented in C#. The included JSON is the actual repository blueprint. No Python implementation was found for this step.

**Provenance:** All listings below are verbatim, contiguous excerpts retrieved from the `main` branch of [The-John-Charitable-Trust/Jaws](https://github.com/The-John-Charitable-Trust/Jaws). No code here is invented, pseudocode, or a Microsoft sample. The line numbers and blob identifiers identify the reviewed snapshot. Other lines are intentionally omitted; open each linked source file for its complete implementation. Executing an excerpt alone is not equivalent to running the full JAWS installer.

## installer/modules/StepBInstall.psm1

[View complete JAWS source](https://github.com/The-John-Charitable-Trust/Jaws/blob/main/installer/modules/StepBInstall.psm1) · Reviewed blob `9b005536f6c132285eedb76a4757355461f49543`

**Source lines 96–120:**

```powershell
function Get-JawsStepBScopeSha256 {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Scope)
    $canonical = @(
        'JAWS-STEP-B-SCOPE-1',
        [string]$Scope.SubscriptionId.ToLowerInvariant(),
        [string]$Scope.ResourceGroupName,
        [string]$Scope.Location.ToLowerInvariant(),
        [string]$Scope.EnvironmentName,
        [string]$Scope.FoundryAccountName,
        [string]$Scope.ProjectName,
        [string]$Scope.ModelDeploymentName,
        [string]$Scope.ModelName,
        [string]$Scope.ModelVersion,
        [string]$Scope.KeyVaultName,
        [string]$Scope.RegistryName,
        [string]$Scope.AgentName
    ) -join "`n"
    return (Get-JawsStepBSha256 -Text $canonical)
}

function Invoke-JawsStepBAz {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Arguments,[switch]$AllowMissing)
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
```

**Source lines 279–316:**

```powershell
function Invoke-JawsStepBPreflight {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Scope,
        [Parameter(Mandatory)][string]$InstallerRoot
    )
    $devState = Join-Path $InstallerRoot 'config/jaws-installation-state.dev.json'
    $devBefore = Get-Content -LiteralPath $devState -Raw
    $reasons = [System.Collections.Generic.List[string]]::new()
    $account = Invoke-JawsStepBAz -Arguments @('account','show','--output','json','--only-show-errors')
    if ([string]$account.id -ine [string]$Scope.SubscriptionId) {
        $reasons.Add('JAWS-STEP-B-019: Azure CLI subscription differs from the approved plan. Run az account set.')
    }
    $sub = [string]$Scope.SubscriptionId
    $rg = [string]$Scope.ResourceGroupName
    $user = [string](Get-JawsStepBProperty -Object $account -Names @('user','name'))
    if ([string]::IsNullOrWhiteSpace($user)) { $reasons.Add('The signed-in account has no user name, so role assignments cannot be checked.') }
    foreach ($namespace in @('Microsoft.CognitiveServices','Microsoft.KeyVault','Microsoft.ContainerRegistry')) {
        try {
            $provider = Invoke-JawsStepBAz -Arguments @('provider','show','--namespace',$namespace,'--subscription',$sub,'--output','json','--only-show-errors')
            if ([string]$provider.registrationState -ne 'Registered') {
                $reasons.Add("$namespace registration is '$([string]$provider.registrationState)'. Run az provider register --namespace $namespace --subscription $sub and wait until it is Registered. Preflight does not register providers.")
            }
        } catch {
            $reasons.Add("Could not read provider ${namespace}. $($_.Exception.Message)")
        }
    }
    $locations = @()
    $locationOk = $false
    if ([string]$account.id -ieq [string]$Scope.SubscriptionId) {
        try {
            $locations = @(Invoke-JawsStepBAz -Arguments @('account','list-locations','--output','json','--only-show-errors'))
        } catch {
            $reasons.Add("Could not list subscription locations. $($_.Exception.Message)")
        }
        $locationOk = @($locations | Where-Object { $_ -and [string]$_.name -eq [string]$Scope.Location }).Count -eq 1
        if (-not $locationOk) { $reasons.Add("Location '$([string]$Scope.Location)' is not enabled for this subscription.") }
    }
```

**Source lines 642–664:**

```powershell
function Invoke-JawsStepBAccept {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$EnvironmentName,
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$Location,
        [Parameter(Mandatory)][string]$ModelName,
        [Parameter(Mandatory)][string]$ModelVersion,
        [Parameter(Mandatory)][string]$InstallerRoot
    )
    $devState = Join-Path $InstallerRoot 'config/jaws-installation-state.dev.json'
    $devBefore = Get-Content -LiteralPath $devState -Raw
    $receiptPath = Join-Path $InstallerRoot ".local/jaws-step-b-install.$EnvironmentName.generated.json"
    if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) {
        throw "JAWS-STEP-B-006: Step B install receipt not found: $receiptPath"
    }
    $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
    $account = Invoke-JawsStepBAz -Arguments @('account','show','--output','json','--only-show-errors')
    if ([string]$account.id -ine [string]$receipt.SubscriptionId) {
        throw 'JAWS-STEP-B-019: Azure CLI subscription differs from the install receipt. No resources were changed.'
    }
    $scope = New-JawsStepBInstallScope -SubscriptionId ([string]$account.id) -ResourceGroupName $ResourceGroupName -Location $Location -EnvironmentName $EnvironmentName -ModelName $ModelName -ModelVersion $ModelVersion
    $mismatch = @()
```

## src/Jaws.Supervisor.Host/Program.cs

[View complete JAWS source](https://github.com/The-John-Charitable-Trust/Jaws/blob/main/src/Jaws.Supervisor.Host/Program.cs) · Excerpt matches the current file. The earlier reviewed blob `b9319105b2e30264fd78b9507323e7064943444d` predates the browser toolbox.

**Source lines 1–27:**

```csharp
using Azure.AI.Projects;
using Azure.Identity;
using Jaws.Supervisor.Host;
using Microsoft.Agents.AI;
using Microsoft.Agents.AI.Foundry.Hosting;

// Hosted Supervisor. Toolbox delegation is explicitly enabled only in a future
// approved Supervisor version; existing deployed Supervisor v1 stays unchanged.
// The platform, not an arbitrary caller header, supplies user/session context.
// Product specialists are declared in SpecialistCatalog: one agent per
// specialization, not one agent per phase. This host does not call them yet.
var endpointText = Environment.GetEnvironmentVariable("FOUNDRY_PROJECT_ENDPOINT");
var model = Environment.GetEnvironmentVariable("AZURE_AI_MODEL_DEPLOYMENT_NAME");
if (string.IsNullOrWhiteSpace(endpointText) ||
    !Uri.TryCreate(endpointText, UriKind.Absolute, out var endpoint) ||
    endpoint.Scheme != Uri.UriSchemeHttps)
{
    throw new InvalidOperationException("A valid HTTPS FOUNDRY_PROJECT_ENDPOINT is required.");
}
if (string.IsNullOrWhiteSpace(model))
{
    throw new InvalidOperationException("AZURE_AI_MODEL_DEPLOYMENT_NAME is required.");
}
var credential = new DefaultAzureCredential();
var toolboxNames = new List<string>();
AddToolbox(toolboxNames, "JAWS_INVESTIGATION_TOOLBOX_NAME");
AddToolbox(toolboxNames, "JAWS_BROWSER_TOOLBOX_NAME");
```

**Source lines 59–84:**

```csharp
AIAgent supervisor = new AIProjectClient(endpoint, credential)
    .AsAIAgent(
        model: model,
        instructions: instructions,
        name: "jaws-supervisor",
        description: "JAWS Supervisor hosted runtime: read-only initial deployment.");

// Only a toolbox-enabled candidate wraps the agent. Supervisor v1 leaves both names unset.
if (toolboxNames.Count > 0)
{
    FoundryToolboxCallMetadata.EnableDetailedFunctionErrors(supervisor);
    supervisor = supervisor.AsBuilder().Use(
        FoundryToolboxCallMetadata.ForwardBeforeRun,
        FoundryToolboxCallMetadata.ForwardBeforeStreamingRun).Build();
}

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
```

## installer/config/jaws-stage-b-plan.example.json

[View complete JAWS source](https://github.com/The-John-Charitable-Trust/Jaws/blob/main/installer/config/jaws-stage-b-plan.example.json) · Reviewed blob `ec8d41c88adf15085730215b83b4a1ae464b6889`

**Source lines 1–32:**

```json
{
  "SchemaVersion": "0.1",
  "Platform": "JAWS",
  "PlanKind": "StageBOfflineBlueprint",
  "EnvironmentName": "tester",
  "Scope": {
    "SubscriptionId": "00000000-0000-0000-0000-000000000000",
    "ResourceGroupName": "rg-jaws-test",
    "Location": "eastus",
    "TenantId": null
  },
  "Constraints": {
    "AzureWritesAllowed": false,
    "LiveInferenceAllowed": false,
    "UserPermissionCeiling": true,
    "HumanApprovalForWrites": true,
    "ExternalOwnershipMustBePreserved": true,
    "TeamsAdminConsentMayBeRequired": true,
    "CostEstimatesVerified": false
  },
  "Components": [
    {
      "Id": "foundry",
      "Name": "Microsoft Foundry resource",
      "ResourceType": "Microsoft.CognitiveServices/accounts",
      "DependsOn": [],
      "Cost": "Unknown",
      "ApprovalRequired": true
    },
    {
      "Id": "project",
      "Name": "Microsoft Foundry project",
```

## Scope and validation

The snippets above reflect the code on `main` at the time this documentation was authored. Do not use them as standalone scripts; use the documented installer commands and test/acceptance gates. After source changes, re-extract excerpts from the changed files and update the listed ranges and blob identifiers.
