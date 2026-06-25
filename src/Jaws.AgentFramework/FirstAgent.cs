using Azure;
using Azure.AI.OpenAI;
using Microsoft.Agents.AI;
using Microsoft.Extensions.AI;

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

        // The standalone tutorial uses an explicit endpoint API key so the
        // reader can validate agent construction without Azure RBAC, managed
        // identity, or a tenant-specific credential chain. The hosted installer
        // can later move this secret into Key Vault-backed configuration.
        var azureOpenAiClient = new AzureOpenAIClient(
            new Uri(_options.Endpoint),
            new AzureKeyCredential(_options.ApiKey));

        // GetChatClient targets the configured model deployment. AsIChatClient
        // adapts the Azure OpenAI SDK client into the Microsoft.Extensions.AI
        // abstraction used by the Agent Framework ChatClientAgent.
        var chatClient = azureOpenAiClient
            .GetChatClient(_options.DeploymentName)
            .AsIChatClient();

        // AsAIAgent wraps the chat client as a Microsoft Agent Framework agent.
        // This keeps the first tutorial focused on agent construction and
        // execution while leaving tools, memory, Teams, and workflows for later.
        AIAgent agent = chatClient.AsAIAgent(
            instructions: _options.Instructions,
            name: _options.AgentName);

        // RunAsync sends the user's message to the configured agent and returns
        // the model response. Later releases add tools, memory, and workflows
        // around this same execution boundary.
        var runResult = await agent.RunAsync(request.Message, cancellationToken: cancellationToken);

        return new FirstAgentResponse(
            Answer: runResult.ToString() ?? string.Empty,
            AgentName: _options.AgentName,
            Release: Release);
    }
}
