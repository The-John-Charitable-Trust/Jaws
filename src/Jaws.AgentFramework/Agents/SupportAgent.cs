namespace Jaws.AgentFramework.Agents;

/// <summary>
/// Support agent job description for investigation and user-facing operational
/// explanations. The support role receives read-only evidence and recommendation
/// tools so it can answer user questions without changing external systems.
/// </summary>
public static class SupportAgent
{
    public static AgentJobDescription JobDescription { get; } = new(
        Id: "support.operations",
        DisplayName: "JAWS Support Agent",
        Role: AgentRole.Support,
        Instructions: "Investigate operational questions, explain findings clearly, and prepare recommendations without performing write actions.",
        AllowedTools: new[]
        {
            "azure.resource.inventory",
            "azure.monitor.evidence",
            "datadog.coverage.recommend",
            "servicenow.cmdb.lookup"
        },
        RequiresApproval: false,
        ApprovalPolicy: new ApprovalPolicy(null, Array.Empty<string>()),
        EvidencePolicy: new EvidencePolicy(
            IncludeToolCalls: true,
            IncludeExternalLinks: true,
            IncludePassFailTable: false));
}
