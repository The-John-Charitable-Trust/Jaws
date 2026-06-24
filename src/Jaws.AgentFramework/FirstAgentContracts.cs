namespace Jaws.AgentFramework.FirstAgent;

public sealed record FirstAgentRequest(string Message);

public sealed record FirstAgentResponse(
    string Answer,
    string AgentName,
    string Release);
