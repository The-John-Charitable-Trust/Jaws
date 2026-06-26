namespace Jaws.AgentFramework.Conversations;

/// <summary>
/// Release 0.5 conversation metadata returned with each agent response. This is
/// intentionally in-memory and process-local. Durable storage and RAG memory are
/// introduced later; this release proves only multi-turn session continuity.
/// </summary>
public sealed record ConversationTurn(
    string ConversationId,
    int TurnNumber,
    bool WasReset);
