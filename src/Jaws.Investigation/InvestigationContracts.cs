using System.Text.Json.Serialization;

namespace Jaws.Investigation;

/// <summary>Validated, broker-supplied scope. Never populate from untrusted model/user text.</summary>
public sealed record VerifiedInvestigationScope(
    string TenantId,
    string UserObjectId,
    string ProjectId,
    string ConversationId,
    string AuthorizationContextRef,
    string TargetResourceScope,
    IReadOnlyList<string> AllowedToolNames,
    DateTimeOffset DeadlineUtc,
    bool IsVerifiedByBroker);

public sealed record InvestigationTask(
    string SchemaVersion,
    string TaskId,
    string CorrelationId,
    string OriginatingTeamsMessageId,
    string RequestedOperation,
    VerifiedInvestigationScope Scope);

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum InvestigationStatus { Planned, Partial, Denied, Failed, Succeeded }

public sealed record EvidenceReference(
    string Provider,
    Uri SourceUri,
    string ResourceScope,
    string ClaimId,
    DateTimeOffset ObservedAtUtc);

public sealed record InvestigationResult(
    string SchemaVersion,
    string TaskId,
    string CorrelationId,
    string AgentName,
    string AgentVersion,
    InvestigationStatus Status,
    IReadOnlyList<string> EvidenceRequirements,
    IReadOnlyList<EvidenceReference> Evidence,
    IReadOnlyList<string> VerifiedClaims,
    IReadOnlyList<string> ProposedActions,
    IReadOnlyList<string> Diagnostics);

public interface IInvestigationAgent
{
    Task<InvestigationResult> InvestigateAsync(
        InvestigationTask task,
        CancellationToken cancellationToken = default);
}
