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

static void AddToolbox(List<string> names, string variable)
{
    var value = Environment.GetEnvironmentVariable(variable);
    if (string.IsNullOrWhiteSpace(value))
    {
        return;
    }
    if (!System.Text.RegularExpressions.Regex.IsMatch(value, "^[a-z][a-z0-9-]{2,62}$"))
    {
        throw new InvalidOperationException($"{variable} is invalid.");
    }
    names.Add(value);
}
