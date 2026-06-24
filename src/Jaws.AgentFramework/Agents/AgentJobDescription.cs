namespace Jaws.AgentFramework.Agents;

/// <summary>
/// Configuration contract for a JAWS agent job description. The contract is
/// intentionally small in release 0.1: it captures the role, instructions,
/// allowed tool names, approval requirement, and evidence behavior that later
/// releases will load from JSON and bind to concrete tools.
/// </summary>
public sealed record AgentJobDescription(
    string Id,
    string DisplayName,
    AgentRole Role,
    string Instructions,
    IReadOnlyList<string> AllowedTools,
    bool RequiresApproval,
    ApprovalPolicy ApprovalPolicy,
    EvidencePolicy EvidencePolicy)
{
    public IReadOnlyList<string> Validate()
    {
        var errors = new List<string>();

        if (string.IsNullOrWhiteSpace(Id))
        {
            errors.Add("Agent job description Id is required.");
        }

        if (string.IsNullOrWhiteSpace(DisplayName))
        {
            errors.Add("Agent job description DisplayName is required.");
        }

        if (string.IsNullOrWhiteSpace(Instructions))
        {
            errors.Add("Agent job description Instructions are required.");
        }

        return errors;
    }
}

public sealed record ApprovalPolicy(
    string? RequiredReferencePattern,
    IReadOnlyList<string> WriteActions);

public sealed record EvidencePolicy(
    bool IncludeToolCalls,
    bool IncludeExternalLinks,
    bool IncludePassFailTable);
