using Azure.AI.Projects;
using Azure.Identity;
using Microsoft.Agents.AI;

namespace Jaws.AgentFramework.Step1;

/// <summary>
/// Release 0.1 implementation of Microsoft Agent Framework Step 1: Your First Agent.
/// This class deliberately does only one thing: create an Agent Framework AIAgent and
/// call RunAsync. Tools, sessions, memory, MCP, Teams, and workflows are introduced in
/// later releases so the reader can see the platform grow one concept at a time.
/// </summary>
public sealed class Step1Agent : IStep1Agent
{
    private const string Release = "0.1";
    private const string DocumentationStep = "Step 1: Your First Agent";

    private readonly Step1AgentOptions _options;

    public Step1Agent(Step1AgentOptions options)
    {
        var errors = options.Validate();
        if (errors.Count > 0)
        {
            throw new ArgumentException(string.Join(" ", errors), nameof(options));
        }

        _options = options;
    }

    public async Task<Step1AgentResponse> RunAsync(
        Step1AgentRequest request,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(request.Message))
        {
            throw new ArgumentException("Message is required.", nameof(request));
        }

        // Step 1 follows the Microsoft tutorial pattern exactly:
        // create AIProjectClient with a project endpoint and Azure credential,
        // convert it into an AIAgent, then call RunAsync with a user message.
        // DefaultAzureCredential supports Azure CLI during local development and
        // managed identity once the API is deployed to Azure.
        AIAgent agent = new AIProjectClient(
                new Uri(_options.Endpoint),
                new DefaultAzureCredential())
            .AsAIAgent(
                model: _options.DeploymentName,
                instructions: _options.Instructions,
                name: _options.AgentName);

        var runResult = await agent.RunAsync(request.Message, cancellationToken: cancellationToken);

        return new Step1AgentResponse(
            Answer: runResult.ToString() ?? string.Empty,
            AgentName: _options.AgentName,
            Release: Release,
            DocumentationStep: DocumentationStep);
    }
}
