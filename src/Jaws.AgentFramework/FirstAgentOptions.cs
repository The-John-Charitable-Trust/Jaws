namespace Jaws.AgentFramework.FirstAgent;

/// <summary>
/// Configuration required to create the first JAWS agent. Later releases add
/// tools, memory, workflows, and Teams behavior, so this options type
/// intentionally contains only the first-agent inputs.
/// </summary>
public sealed class FirstAgentOptions
{
    public const string SectionName = "Jaws:Agent";

    public string Endpoint { get; init; } = string.Empty;

    public string DeploymentName { get; init; } = string.Empty;

    public string AgentName { get; init; } = "JawsFirstAgent";

    public string Instructions { get; init; } =
        "You are JAWS, a concise agentic operations assistant. Answer directly and do not use tools unless tools are explicitly configured.";

    public bool IsConfigured =>
        Uri.TryCreate(Endpoint, UriKind.Absolute, out _) &&
        !string.IsNullOrWhiteSpace(DeploymentName) &&
        !string.IsNullOrWhiteSpace(AgentName) &&
        !string.IsNullOrWhiteSpace(Instructions);

    public IReadOnlyList<string> Validate()
    {
        var errors = new List<string>();

        if (!Uri.TryCreate(Endpoint, UriKind.Absolute, out _))
        {
            errors.Add("Jaws:Agent:Endpoint must be an absolute URI.");
        }

        if (string.IsNullOrWhiteSpace(DeploymentName))
        {
            errors.Add("Jaws:Agent:DeploymentName is required.");
        }

        if (string.IsNullOrWhiteSpace(AgentName))
        {
            errors.Add("Jaws:Agent:AgentName is required.");
        }

        if (string.IsNullOrWhiteSpace(Instructions))
        {
            errors.Add("Jaws:Agent:Instructions is required.");
        }

        return errors;
    }
}
