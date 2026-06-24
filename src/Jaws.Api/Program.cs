using Jaws.AgentFramework.Step1;

var builder = WebApplication.CreateBuilder(args);

// Step 1 reads configuration from normal ASP.NET Core providers such as app settings, environment variables, or local development settings.
var step1Options = new Step1AgentOptions
{
    Endpoint = FirstConfiguredValue(
        builder.Configuration["Jaws:Agent:Step1:Endpoint"],
        builder.Configuration["JAWS_AGENT_ENDPOINT"],
        Environment.GetEnvironmentVariable("JAWS_AGENT_ENDPOINT")),
    DeploymentName = FirstConfiguredValue(
        builder.Configuration["Jaws:Agent:Step1:DeploymentName"],
        builder.Configuration["JAWS_AGENT_DEPLOYMENT_NAME"],
        Environment.GetEnvironmentVariable("JAWS_AGENT_DEPLOYMENT_NAME")),
    AgentName = FirstConfiguredValue(
        builder.Configuration["Jaws:Agent:Step1:AgentName"],
        Environment.GetEnvironmentVariable("JAWS_AGENT_NAME"),
        "JawsStep1Agent"),
    Instructions = FirstConfiguredValue(
        builder.Configuration["Jaws:Agent:Step1:Instructions"],
        Environment.GetEnvironmentVariable("JAWS_AGENT_INSTRUCTIONS"),
        "You are JAWS, a concise agentic operations assistant. For Step 1, answer without tools.")
};

builder.Services.AddSingleton(step1Options);
builder.Services.AddSingleton<IStep1Agent, Step1Agent>();

var app = builder.Build();

app.MapGet("/health", () =>
{
    var errors = step1Options.Validate();
    return Results.Ok(new
    {
        status = errors.Count == 0 ? "healthy" : "configuration_incomplete",
        release = "0.1",
        documentationStep = "Step 1: Your First Agent",
        configurationErrors = errors
    });
});

app.MapPost("/api/agent/step1/run", async (
    Step1AgentRequest request,
    IStep1Agent agent,
    CancellationToken cancellationToken) =>
{
    // Step 1 exposes one narrow execution endpoint. Later releases add tools,
    // Teams routing, sessions, memory, and workflow endpoints.
    var response = await agent.RunAsync(request, cancellationToken);
    return Results.Ok(response);
});

app.Run();

static string FirstConfiguredValue(params string?[] values) =>
    values.FirstOrDefault(value => !string.IsNullOrWhiteSpace(value)) ?? string.Empty;

