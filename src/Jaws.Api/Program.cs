using Jaws.AgentFramework.FirstAgent;
using Jaws.AgentFramework.Mcp;
using System.Text.Json;

var builder = WebApplication.CreateBuilder(args);

if (builder.Environment.IsDevelopment())
{
    // Keep real local secrets out of the committed tutorial config.
    builder.Configuration.AddJsonFile("appsettings.Development.local.json", optional: true, reloadOnChange: true);
}

// Read first-agent runtime settings from ASP.NET Core configuration.
// For the standalone tutorial, appsettings.Development.local.json usually
// supplies the API key. Hosted deployments should source secrets from Key Vault
// or Key Vault-backed application settings.
var firstAgentOptions = new FirstAgentOptions
{
    Endpoint = FirstConfiguredValue(
        builder.Configuration["Jaws:Agent:Endpoint"],
        builder.Configuration["JAWS_AGENT_ENDPOINT"],
        Environment.GetEnvironmentVariable("JAWS_AGENT_ENDPOINT")),
    DeploymentName = FirstConfiguredValue(
        builder.Configuration["Jaws:Agent:DeploymentName"],
        builder.Configuration["JAWS_AGENT_DEPLOYMENT_NAME"],
        Environment.GetEnvironmentVariable("JAWS_AGENT_DEPLOYMENT_NAME")),
    ApiKey = FirstConfiguredValue(
        builder.Configuration["Jaws:Agent:ApiKey"],
        builder.Configuration["JAWS_AGENT_API_KEY"],
        Environment.GetEnvironmentVariable("JAWS_AGENT_API_KEY")),
    AgentName = FirstConfiguredValue(
        builder.Configuration["Jaws:Agent:AgentName"],
        Environment.GetEnvironmentVariable("JAWS_AGENT_NAME"),
        "JawsFirstAgent"),
    Instructions = FirstConfiguredValue(
        builder.Configuration["Jaws:Agent:Instructions"],
        Environment.GetEnvironmentVariable("JAWS_AGENT_INSTRUCTIONS"),
        "You are JAWS, a concise agentic operations assistant. Answer directly and do not use tools unless tools are explicitly configured.")
};

builder.Services.AddSingleton(firstAgentOptions);
builder.Services.AddSingleton<IFirstAgent, FirstAgent>();
builder.Services.AddSingleton<JawsMcpToolRegistry>();
builder.Services.AddSingleton<JawsMcpServer>();

var app = builder.Build();

app.MapGet("/health", () =>
{
    var errors = firstAgentOptions.Validate();
    return Results.Ok(new
    {
        status = errors.Count == 0 ? "healthy" : "configuration_incomplete",
        release = "0.1",
        configurationErrors = errors
    });
});

app.MapPost("/api/agent/run", async (
    FirstAgentRequest request,
    IFirstAgent agent,
    CancellationToken cancellationToken) =>
{
    // Expose one narrow execution endpoint. Later releases add tools, Teams
    // routing, sessions, memory, and workflow endpoints.
    var response = await agent.RunAsync(request, cancellationToken);
    return Results.Ok(response);
});

app.MapPost("/mcp", (JsonElement request, JawsMcpServer mcpServer) =>
{
    // Step 2 exposes the local MCP boundary. The initial endpoint supports
    // initialize, tools/list, and read-only tools/call. Step 3 hardens local
    // request handling before operational provider tools are exposed.
    return Results.Json(mcpServer.Handle(request));
});

app.Run();

static string FirstConfiguredValue(params string?[] values) =>
    values.FirstOrDefault(value => !string.IsNullOrWhiteSpace(value)) ?? string.Empty;
