namespace Jaws.AgentFramework.FirstAgent;

public sealed record FirstAgentRequest(
    string Message,
    string? ConversationId = null,
    bool ResetConversation = false);

public sealed record FirstAgentResponse(
    string Answer,
    string AgentName,
    string Release,
    string ConversationId,
    int TurnNumber,
    bool ConversationReset,
    string ConversationRelease);
