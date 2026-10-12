using Azure.AI.Projects;
using Azure.Identity;
using Microsoft.Agents.AI;
using Microsoft.Agents.AI.Foundry.Hosting;

// Dedicated Foundry-hosted Supervisor. No Azure writes, MCP tools or delegated
// worker permissions are attached until the security broker is implemented.
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
AIAgent supervisor = new AIProjectClient(endpoint, new DefaultAzureCredential())
    .AsAIAgent(
        model: model,
        instructions: """
            You are JAWS Supervisor, an operational investigation coordinator.
            Respond concisely and accurately. Do not claim access to Azure Policy,
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
var app = builder.Build();
app.MapGet("/healthz", () => Results.Ok(new {
    status = "ready",
    component = "jaws-supervisor-host",
    agentIntegration = "not-yet-connected",
    deployment = model
}));
// Foundry hosting library provides the Responses protocol implementation.
app.MapFoundryResponses();
app.Run();
