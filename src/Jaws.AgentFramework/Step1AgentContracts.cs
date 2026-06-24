namespace Jaws.AgentFramework.Step1;

public sealed record Step1AgentRequest(string Message);

public sealed record Step1AgentResponse(
    string Answer,
    string AgentName,
    string Release,
    string DocumentationStep);
