namespace Jaws.AgentFramework.Agents;

/// <summary>
/// Governance agent job description for policy, compliance, approval, and risk
/// reasoning. It does not execute changes; it decides what must be true before
/// another agent is allowed to execute.
/// </summary>
public static class GovernanceAgent
{
    public static AgentJobDescription JobDescription { get; } = new(
        Id: "governance.operations",
        DisplayName: "JAWS Governance Agent",
        Role: AgentRole.Governance,
        Instructions: "Evaluate policy, compliance, approval, and evidence requirements before any external write action is allowed.",
        AllowedTools: new[]
        {
            "azure.policy.evidence",
            "jaws.tool.extensibility"
        },
        RequiresApproval: false,
        ApprovalPolicy: new ApprovalPolicy(null, Array.Empty<string>()),
        EvidencePolicy: new EvidencePolicy(
            IncludeToolCalls: true,
            IncludeExternalLinks: true,
            IncludePassFailTable: true));
}
