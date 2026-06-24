namespace Jaws.AgentFramework.Step1;

public interface IStep1Agent
{
    Task<Step1AgentResponse> RunAsync(Step1AgentRequest request, CancellationToken cancellationToken = default);
}
