using System.Collections.Concurrent;

namespace Jaws.AgentFramework.Conversations;

/// <summary>
/// In-memory conversation store for the release 0.5 code tutorial. The store gives
/// API callers a stable conversation ID, tracks the turn number, and supports a
/// reset operation. It does not persist data across process restarts and it does
/// not implement long-term memory or RAG.
/// </summary>
public sealed class InMemoryConversationStore
{
    public const string Release = "0.5";

    private readonly ConcurrentDictionary<string, int> _turns = new(StringComparer.Ordinal);

    public ConversationTurn BeginTurn(string? conversationId, bool resetConversation = false)
    {
        var normalizedConversationId = NormalizeConversationId(conversationId);

        if (resetConversation)
        {
            normalizedConversationId = CreateConversationId();
            _turns[normalizedConversationId] = 1;
            return new ConversationTurn(normalizedConversationId, TurnNumber: 1, WasReset: true);
        }

        var turnNumber = _turns.AddOrUpdate(
            normalizedConversationId,
            addValue: 1,
            updateValueFactory: (_, current) => current + 1);

        return new ConversationTurn(normalizedConversationId, turnNumber, WasReset: false);
    }

    public ConversationTurn Reset(string? conversationId = null)
    {
        var normalizedConversationId = string.IsNullOrWhiteSpace(conversationId)
            ? CreateConversationId()
            : NormalizeConversationId(conversationId);

        _turns[normalizedConversationId] = 0;
        return new ConversationTurn(normalizedConversationId, TurnNumber: 0, WasReset: true);
    }

    public bool Contains(string conversationId) => _turns.ContainsKey(conversationId);

    private static string NormalizeConversationId(string? conversationId) =>
        string.IsNullOrWhiteSpace(conversationId)
            ? CreateConversationId()
            : conversationId.Trim();

    private static string CreateConversationId() => $"JCN-{Guid.NewGuid():N}"[..20].ToUpperInvariant();
}
