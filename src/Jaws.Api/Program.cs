using Jaws.AgentFramework.Conversations;
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
// supplies the API key. Future hosted deployments should source secrets from
// Key Vault or Key Vault-backed application settings.
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
builder.Services.AddSingleton<InMemoryConversationStore>();
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
        surface = "first-agent",
        // The health endpoint validates the first-agent surface introduced in
        // release 0.1. MCP endpoints report their own MCP release value so each
        // tutorial validation block checks the surface it is exercising.
        release = "0.1",
        mcpRelease = JawsMcpToolRegistry.Release,
        conversationRelease = InMemoryConversationStore.Release,
        configurationErrors = errors
    });
});

app.MapPost("/api/agent/run", async (
    FirstAgentRequest request,
    IFirstAgent agent,
    CancellationToken cancellationToken) =>
{
    // Expose one narrow execution endpoint. Release 0.5 adds conversationId and
    // resetConversation support while leaving Teams, durable memory, and
    // workflow endpoints for later releases.
    var response = await agent.RunAsync(request, cancellationToken);
    return Results.Ok(response);
});

app.MapPost("/api/conversations/reset", (ConversationResetRequest request, InMemoryConversationStore conversations) =>
{
    // This reset endpoint mirrors the user-facing /reset behavior that will
    // later be available through Teams. It resets local in-memory conversation
    // state only; durable history and memory are introduced later.
    var reset = conversations.Reset(request.ConversationId);
    return Results.Ok(new ConversationResetResponse(
        ConversationId: reset.ConversationId,
        TurnNumber: reset.TurnNumber,
        ConversationReset: reset.WasReset,
        ConversationRelease: InMemoryConversationStore.Release));
});
app.MapPost("/mcp", (JsonElement request, JawsMcpServer mcpServer) =>
{
    // The release 0.2 MCP endpoint exposes initialize, tools/list, and
    // read-only tools/call. Release 0.3 hardens local request handling before
    // operational provider tools are exposed.
    return Results.Json(mcpServer.Handle(request));
});

app.Run();

static string FirstConfiguredValue(params string?[] values) =>
    values.FirstOrDefault(value => !string.IsNullOrWhiteSpace(value)) ?? string.Empty;

public sealed record ConversationResetRequest(string? ConversationId = null);

public sealed record ConversationResetResponse(
    string ConversationId,
    int TurnNumber,
    bool ConversationReset,
    string ConversationRelease);
