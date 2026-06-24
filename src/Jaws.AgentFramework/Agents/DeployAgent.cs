namespace Jaws.AgentFramework.Agents;

/// <summary>
/// Deploy agent job description for approved write actions. In release 0.1 this
/// defines the role and approval contract. Later releases attach Datadog,
/// ServiceNow, Azure, and webhook tools to this agent.
/// </summary>
public static class DeployAgent
{
    public static AgentJobDescription JobDescription { get; } = new(
        Id: "deploy.datadog.synthetic",
        DisplayName: "JAWS Deploy Agent",
        Role: AgentRole.Deploy,
        Instructions: "Create or update Datadog monitors, synthetics, webhook tests, and ServiceNow records only after approval is present. Return evidence, links, and validation results.",
        AllowedTools: new[]
        {
            "azure.resource.inventory",
            "datadog.synthetic.create",
            "datadog.webhook.test",
            "servicenow.incident.createOrUpdate"
        },
        RequiresApproval: true,
        ApprovalPolicy: new ApprovalPolicy(
            RequiredReferencePattern: "^APP-[0-9]{8,}-[a-z0-9-]+$",
            WriteActions: new[] { "create", "update", "testNotification" }),
        EvidencePolicy: new EvidencePolicy(
            IncludeToolCalls: true,
            IncludeExternalLinks: true,
            IncludePassFailTable: true));
}
