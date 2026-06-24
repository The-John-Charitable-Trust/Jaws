using Azure.AI.Projects;
using Azure.Identity;
using Microsoft.Agents.AI;

namespace Jaws.AgentFramework.FirstAgent;

/// <summary>
/// Minimal JAWS agent implementation. This class deliberately does only one
/// thing: create an Agent Framework AIAgent and call RunAsync. Tools, sessions,
/// memory, MCP, Teams, and workflows are added in later releases.
/// </summary>
public sealed class FirstAgent : IFirstAgent
{
    private const string Release = "0.1";
    private readonly FirstAgentOptions _options;

    public FirstAgent(FirstAgentOptions options)
    {
        var errors = options.Validate();
        if (errors.Count > 0)
        {
            throw new ArgumentException(string.Join(" ", errors), nameof(options));
        }

        _options = options;
    }

    public async Task<FirstAgentResponse> RunAsync(
        FirstAgentRequest request,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(request.Message))
        {
            throw new ArgumentException("Message is required.", nameof(request));
        }

        // Create AIProjectClient with a project endpoint and Azure credential,
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

        return new FirstAgentResponse(
            Answer: runResult.ToString() ?? string.Empty,
            AgentName: _options.AgentName,
            Release: Release);
    }
}
