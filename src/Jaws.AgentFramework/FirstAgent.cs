using Azure;
using Azure.AI.OpenAI;
using Jaws.AgentFramework.Conversations;
using Microsoft.Agents.AI;
using Microsoft.Extensions.AI;
using System.Collections.Concurrent;

namespace Jaws.AgentFramework.FirstAgent;

/// <summary>
/// Minimal JAWS agent implementation. Release 0.5 adds multi-turn session
/// support while keeping tools, durable memory, Teams routing, and workflows
/// outside this step's scope.
/// </summary>
public sealed class FirstAgent : IFirstAgent
{
    private const string Release = "0.1";
    private readonly FirstAgentOptions _options;
    private readonly InMemoryConversationStore _conversationStore;
    private readonly ConcurrentDictionary<string, Task<AgentSession>> _agentSessions = new(StringComparer.Ordinal);
    private readonly Lazy<AIAgent> _agent;

    public FirstAgent(FirstAgentOptions options, InMemoryConversationStore? conversationStore = null)
    {
        var errors = options.Validate();
        if (errors.Count > 0)
        {
            throw new ArgumentException(string.Join(" ", errors), nameof(options));
        }

        _options = options;
        _conversationStore = conversationStore ?? new InMemoryConversationStore();
        _agent = new Lazy<AIAgent>(CreateAgent);
    }

    public async Task<FirstAgentResponse> RunAsync(
        FirstAgentRequest request,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(request.Message))
        {
            throw new ArgumentException("Message is required.", nameof(request));
        }

        var conversation = _conversationStore.BeginTurn(request.ConversationId, request.ResetConversation);
        var agent = _agent.Value;

        // Release 0.5 follows the Microsoft Agent Framework multi-turn pattern:
        // create an AgentSession once for a conversation, reuse it on later
        // calls, and pass that session into RunAsync so prior turns remain in
        // the agent's conversation context. This is process-local only; durable
        // storage and RAG memory arrive in later releases.
        var session = await _agentSessions
            .GetOrAdd(conversation.ConversationId, _ => agent.CreateSessionAsync(cancellationToken).AsTask())
            .WaitAsync(cancellationToken);

        var runResult = await agent.RunAsync(
            request.Message,
            session,
            cancellationToken: cancellationToken);

        return new FirstAgentResponse(
            Answer: runResult.ToString() ?? string.Empty,
            AgentName: _options.AgentName,
            Release: Release,
            ConversationId: conversation.ConversationId,
            TurnNumber: conversation.TurnNumber,
            ConversationReset: conversation.WasReset,
            ConversationRelease: InMemoryConversationStore.Release);
    }

    private AIAgent CreateAgent()
    {
        // The standalone tutorial uses an explicit endpoint API key so the
        // reader can validate agent construction without Azure RBAC, managed
        // identity, or a tenant-specific credential chain. Future hosted
        // deployment can move this secret into Key Vault-backed configuration.
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
        return chatClient.AsAIAgent(
            instructions: _options.Instructions,
            name: _options.AgentName);
    }
}
