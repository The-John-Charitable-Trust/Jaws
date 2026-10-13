namespace Jaws.Investigation;

/// <summary>
/// Supervisor-side delegation coordinator. An in-process offline boundary only;
/// this does NOT provide remote Foundry A2A transport or grant MCP access.
/// </summary>
public sealed class SupervisorInvestigationDelegator(IInvestigationAgent investigation)
{
    public async Task<InvestigationResult> DelegateAsync(
        InvestigationTask task,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(task);
        // Validate the broker-issued task before calling a worker, fail closed.
        var rejection = InvestigationPlanner.Validate(task);
        if (rejection is not null)
        {
            return new InvestigationResult("1.0", task.TaskId, task.CorrelationId,
                "jaws-supervisor", "offline-step-c-0", InvestigationStatus.Denied,
                [], [], [], [], [rejection]);
        }

        var response = await investigation.InvestigateAsync(task, cancellationToken);
        if (response is null ||
            response.TaskId != task.TaskId ||
            response.CorrelationId != task.CorrelationId ||
            response.SchemaVersion != "1.0" ||
            string.IsNullOrWhiteSpace(response.AgentName) ||
            response.Status == InvestigationStatus.Succeeded &&
                response.Evidence.Count == 0)
        {
            return new InvestigationResult("1.0", task.TaskId, task.CorrelationId,
                "jaws-supervisor", "offline-step-c-0", InvestigationStatus.Failed,
                [], [], [], [], ["WORKER_RESULT_REJECTED: Task/correlation/schema identity or evidence integrity failed."]);
        }
        return response;
    }
}
