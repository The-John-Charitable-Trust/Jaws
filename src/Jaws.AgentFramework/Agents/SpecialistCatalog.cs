namespace Jaws.AgentFramework.Agents;

/// <summary>
/// Product specialist registry. The Supervisor is the Teams proxy and is not a
/// specialist. Each specialization is one agent that investigates, deliberates,
/// and remediates. A new product inside an existing job is a tool, not an agent.
/// </summary>
public static class SpecialistCatalog
{
    public static IReadOnlyList<SpecialistPhase> Phases { get; } =
    [
        SpecialistPhase.Investigate,
        SpecialistPhase.Deliberate,
        SpecialistPhase.Remediate
    ];

    public const string SupervisorDuty =
        "The Supervisor is the Teams proxy. It delegates to one specialist for the operator's project conversation and does not call Azure or observability products itself.";

    public const string ComputeRule =
        "The virtual-machine specialist owns the one compute environment. Every other specialist uses that same environment through its MCP server.";

    public static IReadOnlyList<string> ObservabilityTools { get; } =
    [
        "Datadog",
        "Azure Monitor",
        "Azure Sentinel",
        "ServiceNow incident"
    ];

    public static IReadOnlyList<string> LaterSpecializations { get; } =
    [
        "ServiceNow change and request fulfillment"
    ];

    public static IReadOnlyList<SpecialistDefinition> All { get; } =
    [
        new(
            Name: "Virtual machine",
            Job: "Investigate, deliberate, and remediate virtual-machine security incidents.",
            ToolServer: "Azure MCP",
            Tools: ["Azure MCP"],
            Acceptance: SpecialistAcceptance.CurrentEndState),
        new(
            Name: "Observability",
            Job: "Investigate, deliberate, and remediate from operational signals and incident records.",
            ToolServer: "Custom MCP",
            Tools: ObservabilityTools,
            Acceptance: SpecialistAcceptance.CurrentEndState),
        new(
            Name: "Azure network",
            Job: "Investigate, deliberate, and remediate Azure network resources.",
            ToolServer: "Azure MCP",
            Tools: ["Azure MCP"],
            Acceptance: SpecialistAcceptance.LaterSpecialization),
        new(
            Name: "Azure storage",
            Job: "Investigate, deliberate, and remediate Azure storage accounts.",
            ToolServer: "Azure MCP",
            Tools: ["Azure MCP"],
            Acceptance: SpecialistAcceptance.LaterSpecialization)
    ];

    public static IReadOnlyList<SpecialistDefinition> CurrentEndState { get; } =
        All.Where(specialist => specialist.Acceptance == SpecialistAcceptance.CurrentEndState).ToArray();
}

public enum SpecialistPhase
{
    Investigate,
    Deliberate,
    Remediate
}

public enum SpecialistAcceptance
{
    CurrentEndState,
    LaterSpecialization
}

public sealed record SpecialistDefinition(
    string Name,
    string Job,
    string ToolServer,
    IReadOnlyList<string> Tools,
    SpecialistAcceptance Acceptance);
