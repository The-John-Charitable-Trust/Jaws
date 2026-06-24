namespace Jaws.AgentFramework.FirstAgent;

public interface IFirstAgent
{
    Task<FirstAgentResponse> RunAsync(FirstAgentRequest request, CancellationToken cancellationToken = default);
}
