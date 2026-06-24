namespace Jaws.AgentFramework.Agents;

/// <summary>
/// Release 0.1 catalog of role-oriented JAWS agents. Keeping the catalog in code
/// makes the end-state workflow visible from the start while later releases add
/// JSON loading so customers can define additional agents after installation.
/// </summary>
public static class RoleAgentCatalog
{
    public static IReadOnlyList<AgentJobDescription> All { get; } = new[]
    {
        SupportAgent.JobDescription,
        GovernanceAgent.JobDescription,
        DeployAgent.JobDescription,
        WorkflowAgent.JobDescription
    };
}
