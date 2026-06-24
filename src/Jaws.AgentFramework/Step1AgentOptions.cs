namespace Jaws.AgentFramework.Step1;

/// <summary>
/// Configuration required by release 0.1, which maps to Microsoft Agent Framework
/// Step 1: Your First Agent. Later releases add tools, memory, workflows, and Teams
/// behavior, so this options type intentionally contains only the first-agent inputs.
/// </summary>
public sealed class Step1AgentOptions
{
    public const string SectionName = "Jaws:Agent:Step1";

    public string Endpoint { get; init; } = string.Empty;

    public string DeploymentName { get; init; } = string.Empty;

    public string AgentName { get; init; } = "JawsStep1Agent";

    public string Instructions { get; init; } =
        "You are JAWS, a concise agentic operations assistant. For Step 1, answer without tools.";

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
            errors.Add("Jaws:Agent:Step1:Endpoint must be an absolute URI.");
        }

        if (string.IsNullOrWhiteSpace(DeploymentName))
        {
            errors.Add("Jaws:Agent:Step1:DeploymentName is required.");
        }

        if (string.IsNullOrWhiteSpace(AgentName))
        {
            errors.Add("Jaws:Agent:Step1:AgentName is required.");
        }

        if (string.IsNullOrWhiteSpace(Instructions))
        {
            errors.Add("Jaws:Agent:Step1:Instructions is required.");
        }

        return errors;
    }
}
