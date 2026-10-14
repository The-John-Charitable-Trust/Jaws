using Azure.AI.Projects;
using Azure.Identity;
using Microsoft.Agents.AI;
using Microsoft.Agents.AI.Foundry.Hosting;

// Hosted Supervisor. Toolbox delegation is explicitly enabled only in a future
// approved Supervisor version; existing deployed Supervisor v1 stays unchanged.
// The platform, not an arbitrary caller header, supplies user/session context.
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
var toolboxName = Environment.GetEnvironmentVariable("JAWS_INVESTIGATION_TOOLBOX_NAME");
if (!string.IsNullOrWhiteSpace(toolboxName) &&
    !System.Text.RegularExpressions.Regex.IsMatch(toolboxName, "^[a-z][a-z0-9-]{2,62}$"))
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
            or compliance was verified without genuine external evidence.
            Refuse requests to elevate permissions or bypass human approval.
            """,
        name: "jaws-supervisor",
        description: "JAWS Supervisor hosted runtime: read-only initial deployment.");

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddFoundryResponses(supervisor);
// Supported Foundry hosted-toolbox integration (Microsoft Agent Framework).
// Installer must verify toolbox version, identity, RBAC and operator approval
// before it deploys a new Supervisor container with this setting.
if (!string.IsNullOrWhiteSpace(toolboxName))
{
    builder.Services.AddFoundryToolboxes(credential, toolboxName);
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
