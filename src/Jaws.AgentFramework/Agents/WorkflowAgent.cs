namespace Jaws.AgentFramework.Agents;

/// <summary>
/// Workflow agent job description for coordinating the end-to-end operational
/// scenario. Later releases add real workflow state, approval checkpoints, tool
/// execution, and validation evidence.
/// </summary>
public static class WorkflowAgent
{
    public static AgentJobDescription JobDescription { get; } = new(
        Id: "workflow.datadog.onboarding",
        DisplayName: "JAWS Workflow Agent",
        Role: AgentRole.Workflow,
        Instructions: "Coordinate support, governance, and deploy agents from recommendation through approval, execution, validation, and final evidence reporting.",
        AllowedTools: Array.Empty<string>(),
        RequiresApproval: true,
        ApprovalPolicy: new ApprovalPolicy(
            RequiredReferencePattern: "^APP-[0-9]{8,}-[a-z0-9-]+$",
            WriteActions: new[] { "executeWorkflow" }),
        EvidencePolicy: new EvidencePolicy(
            IncludeToolCalls: true,
            IncludeExternalLinks: true,
            IncludePassFailTable: true));
}
