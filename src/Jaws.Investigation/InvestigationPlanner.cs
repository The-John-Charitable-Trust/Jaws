namespace Jaws.Investigation;

/// <summary>
/// Offline deterministic investigation-planning stub.
/// No model calls, MCP access, Azure queries, or remediation execution.
/// Replace with a separately authenticated specialist only after authorization
/// and hosted-agent A2A transport have been implemented and accepted.
/// </summary>
public sealed class InvestigationPlanner : IInvestigationAgent
{
    private static readonly string[] Requirements =
    [
        "Resolve the exact target resource identity and authorized subscription scope.",
        "Obtain Azure Policy compliance state and matching policy assignment from an authorized provider.",
        "Obtain relevant Defender for Cloud recommendations from an authorized provider.",
        "Correlate observations with their timestamps, resource IDs and provider source URLs."
    ];

    public Task<InvestigationResult> InvestigateAsync(
        InvestigationTask task, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(task);
        cancellationToken.ThrowIfCancellationRequested();

        string? rejection = Validate(task);
        var status = rejection is null ? InvestigationStatus.Planned : InvestigationStatus.Denied;

        // No provider call has occurred, so Evidence and VerifiedClaims stay EMPTY.
        return Task.FromResult(new InvestigationResult(
            SchemaVersion: "1.0",
            TaskId: task.TaskId,
            CorrelationId: task.CorrelationId,
            AgentName: "jaws-investigation",
            AgentVersion: "offline-step-c-0",
            Status: status,
            EvidenceRequirements: rejection is null ? Requirements : Array.Empty<string>(),
            Evidence: Array.Empty<EvidenceReference>(),
            VerifiedClaims: Array.Empty<string>(),
            ProposedActions: Array.Empty<string>(),
            Diagnostics: rejection is null
                ? ["PLAN_ONLY: No Azure Policy/Defender/Datadog evidence has been retrieved."]
                : [rejection]));
    }

    public static string? Validate(InvestigationTask? task)
    {
        if (task is null || task.Scope is null)
            return "DENIED: Missing task or broker-issued scope.";
        if (task.SchemaVersion != "1.0")
            return "DENIED: Unsupported task schema.";
        if (string.IsNullOrWhiteSpace(task.TaskId) ||
            string.IsNullOrWhiteSpace(task.CorrelationId) ||
            !Guid.TryParse(task.CorrelationId, out _) ||
            !Guid.TryParse(task.TaskId, out _))
            return "DENIED: Task and correlation IDs must be valid UUIDs.";
        var s = task.Scope;
        if (!s.IsVerifiedByBroker)
            return "DENIED: Scope was not verified by the authorization broker.";
        if (!Guid.TryParse(s.TenantId, out _) || !Guid.TryParse(s.UserObjectId, out _) ||
            string.IsNullOrWhiteSpace(s.ProjectId) ||
            string.IsNullOrWhiteSpace(s.ConversationId) ||
            string.IsNullOrWhiteSpace(s.AuthorizationContextRef))
            return "DENIED: Incomplete bound tenant, principal, project or conversation identity.";
        if (s.DeadlineUtc <= DateTimeOffset.UtcNow)
            return "DENIED: Investigation deadline has expired.";
        if (s.DeadlineUtc > DateTimeOffset.UtcNow.AddMinutes(30))
            return "DENIED: Investigation deadline exceeds the 30-minute budget.";
        if (string.IsNullOrWhiteSpace(s.TargetResourceScope) ||
            !s.TargetResourceScope.StartsWith("/subscriptions/", StringComparison.OrdinalIgnoreCase) ||
            s.TargetResourceScope.Contains("..", StringComparison.Ordinal) ||
            s.TargetResourceScope.Contains('*') ||
            s.TargetResourceScope.Contains('?'))
            return "DENIED: Target scope must be an exact Azure subscription or child-resource ID.";
        if (task.RequestedOperation != "PlanReadOnlyAzureVmComplianceInvestigation")
            return "DENIED: Only read-only investigation planning is allowed.";
        if (s.AllowedToolNames is null ||
            s.AllowedToolNames.Any(name => name is not ("AzurePolicy.Read" or "Defender.Read")) ||
            s.AllowedToolNames.Count != s.AllowedToolNames.Distinct(StringComparer.Ordinal).Count())
            return "DENIED: Tool allowlist is invalid or includes unauthorized tools.";
        return null;
    }
}
