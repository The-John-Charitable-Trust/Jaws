namespace Jaws.AgentFramework.Agents;

/// <summary>
/// Stable role names used by the JAWS role-oriented agents. Release 0.1 defines
/// the roles up front so later releases can add tools, memory, Teams routing,
/// and workflows without changing the core agent identity model.
/// </summary>
public enum AgentRole
{
    Support,
    Governance,
    Deploy,
    Workflow
}
