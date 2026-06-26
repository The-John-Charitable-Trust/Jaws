namespace Jaws.AgentFramework.Agents;

/// <summary>
/// Workflow agent job description for coordinating the end-to-end operational
/// scenario. It can inspect the same read tools used by support and governance,
/// then hand approved write actions to the deploy role in later workflow code.
/// </summary>
public static class WorkflowAgent
{
    public static AgentJobDescription JobDescription { get; } = new(
        Id: "workflow.datadog.onboarding",
        DisplayName: "JAWS Workflow Agent",
        Role: AgentRole.Workflow,
        Instructions: "Coordinate support, governance, and deploy agents from recommendation through approval, execution, validation, and final evidence reporting.",
        AllowedTools: new[]
        {
            "azure.resource.inventory",
            "azure.policy.evidence",
            "azure.monitor.evidence",
            "datadog.coverage.recommend",
            "servicenow.cmdb.lookup",
            "jaws.tool.extensibility"
        },
        RequiresApproval: true,
        ApprovalPolicy: new ApprovalPolicy(
            RequiredReferencePattern: "^APP-[0-9]{8,}-[a-z0-9-]+$",
            WriteActions: new[] { "executeWorkflow" }),
        EvidencePolicy: new EvidencePolicy(
            IncludeToolCalls: true,
            IncludeExternalLinks: true,
            IncludePassFailTable: true));
}
