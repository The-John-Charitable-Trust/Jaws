namespace Jaws.AgentFramework.Agents;

/// <summary>
/// Support agent job description for investigation and user-facing operational
/// explanations. Tools are attached in later releases; release 0.1 defines the
/// role, intent, and evidence posture.
/// </summary>
public static class SupportAgent
{
    public static AgentJobDescription JobDescription { get; } = new(
        Id: "support.operations",
        DisplayName: "JAWS Support Agent",
        Role: AgentRole.Support,
        Instructions: "Investigate operational questions, explain findings clearly, and prepare recommendations without performing write actions.",
        AllowedTools: Array.Empty<string>(),
        RequiresApproval: false,
        ApprovalPolicy: new ApprovalPolicy(null, Array.Empty<string>()),
        EvidencePolicy: new EvidencePolicy(
            IncludeToolCalls: true,
            IncludeExternalLinks: true,
            IncludePassFailTable: false));
}
