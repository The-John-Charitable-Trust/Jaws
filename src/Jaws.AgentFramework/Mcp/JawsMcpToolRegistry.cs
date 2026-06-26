using System.Text.Json.Nodes;

namespace Jaws.AgentFramework.Mcp;

/// <summary>
/// Central registry for the tools exposed by the local JAWS MCP server. The
/// registry is intentionally explicit: every tool needs a name, description,
/// schema, read/write classification, and handler before an agent can use it.
/// Release 0.4 adds the demo-scoped operational tools needed for the final
/// JAWS operations scenario while keeping write-capable tools approval-gated.
/// </summary>
public sealed class JawsMcpToolRegistry
{
    public const string Release = "0.4";
    public const string ServerName = "jaws-custom-mcp";

    private readonly IReadOnlyDictionary<string, JawsMcpTool> _tools;

    public JawsMcpToolRegistry()
    {
        var tools = new[]
        {
            new JawsMcpTool(
                Name: "jaws_mcp_status",
                Description: "Use when an agent or tester needs to confirm the local MCP boundary is available. Requires no input. Returns server status, release, tool scope, security mode, provider families, and whether write tools are enabled.",
                InputSchema: EmptyObjectSchema(),
                IsWriteTool: false,
                Invoke: _ => new JsonObject
                {
                    ["status"] = "ok",
                    ["server"] = ServerName,
                    ["release"] = Release,
                    ["mode"] = "local",
                    ["toolScope"] = "tutorial-demo",
                    ["writeToolsEnabled"] = false,
                    ["securityMode"] = "hardened-local",
                    ["coreToolProviders"] = new JsonArray("Azure", "Datadog", "ServiceNow", "JAWS"),
                    ["futureToolProviders"] = new JsonArray("Azure MCP Server", "Microsoft Defender", "Microsoft Sentinel", "Security Copilot", "Azure AI Content Safety")
                }),
            new JawsMcpTool(
                Name: "jaws_tool_registry",
                Description: "Use when an agent needs to discover the approved local MCP tool surface. Requires no input. Returns stable tool names only; the agent must still respect role-based allowedTools and write approval gates.",
                InputSchema: EmptyObjectSchema(),
                IsWriteTool: false,
                Invoke: _ => new JsonObject
                {
                    ["status"] = "ok",
                    ["server"] = ServerName,
                    ["release"] = Release,
                    ["tools"] = new JsonArray(Tools.Select(tool => JsonValue.Create(tool.Name)).OrderBy(node => node?.GetValue<string>(), StringComparer.Ordinal).ToArray<JsonNode?>())
                }),
            new JawsMcpTool(
                Name: "azure.resource.inventory",
                Description: "Use when support or workflow agents need Azure resource candidates for observability coverage analysis. Accepts an optional authorized scope. Returns resource names, resource types, priority, and recommended Datadog coverage categories; it does not modify Azure.",
                InputSchema: ObjectSchema(("scope", "Optional authorized Azure scope or resource group name. If omitted, the tutorial-local scope is used for demo evidence.")),
                IsWriteTool: false,
                Invoke: arguments => new JsonObject
                {
                    ["status"] = "ok",
                    ["provider"] = "Azure",
                    ["scope"] = ReadString(arguments, "scope") ?? "tutorial-local-scope",
                    ["resources"] = new JsonArray
                    {
                        new JsonObject
                        {
                            ["name"] = "app-jaws-api",
                            ["type"] = "Microsoft.Web/sites",
                            ["priority"] = "high",
                            ["recommendedCoverage"] = new JsonArray("httpSynthetic", "5xxRate", "availability", "latency")
                        },
                        new JsonObject
                        {
                            ["name"] = "func-jaws-worker",
                            ["type"] = "Microsoft.Web/sites/functions",
                            ["priority"] = "medium",
                            ["recommendedCoverage"] = new JsonArray("executionFailures", "duration", "dependencyFailures")
                        }
                    }
                }),
            new JawsMcpTool(
                Name: "azure.policy.evidence",
                Description: "Use when governance agents need compliance context for a selected Azure resource. Requires resourceName. Returns policy-oriented evidence and a compliance summary for approval reasoning; it does not create exemptions or change policy.",
                InputSchema: ObjectSchema(("resourceName", "Azure resource name to evaluate. Use the exact resource name from inventory or user-approved context.")),
                IsWriteTool: false,
                Invoke: arguments => new JsonObject
                {
                    ["status"] = "ok",
                    ["provider"] = "Azure Policy",
                    ["resourceName"] = ReadString(arguments, "resourceName") ?? "app-jaws-api",
                    ["complianceSummary"] = "No blocking policy violation is present in the tutorial evidence set.",
                    ["evidence"] = new JsonArray("diagnostic settings expected", "managed identity expected", "HTTPS only expected")
                }),
            new JawsMcpTool(
                Name: "azure.monitor.evidence",
                Description: "Use when support agents need operational signals for a selected Azure resource and time range. Requires resourceName and optionally timeRange. Returns evidence signals for triage and Datadog coverage reasoning; it does not query or mutate live alerts in this release.",
                InputSchema: ObjectSchema(("resourceName", "Azure resource name to inspect. Use the exact resource name from inventory or user-approved context."), ("timeRange", "Optional ISO-8601 evidence time range such as PT1H. Defaults to PT1H.")),
                IsWriteTool: false,
                Invoke: arguments => new JsonObject
                {
                    ["status"] = "ok",
                    ["provider"] = "Azure Monitor",
                    ["resourceName"] = ReadString(arguments, "resourceName") ?? "app-jaws-api",
                    ["timeRange"] = ReadString(arguments, "timeRange") ?? "PT1H",
                    ["signals"] = new JsonArray("availability check required", "latency baseline required", "5xx monitor recommended")
                }),
            new JawsMcpTool(
                Name: "datadog.coverage.recommend",
                Description: "Use when support or workflow agents need to decide which Datadog monitor or synthetic coverage fits an Azure resource. Requires resourceName and resourceType. Returns an approval-gated recommendation, rationale, and the next write-capable tools; it does not create Datadog assets.",
                InputSchema: ObjectSchema(("resourceName", "Azure resource name to evaluate. Use the exact resource name from inventory or user-approved context."), ("resourceType", "Azure resource type.")),
                IsWriteTool: false,
                Invoke: arguments => new JsonObject
                {
                    ["status"] = "ok",
                    ["provider"] = "Datadog",
                    ["resourceName"] = ReadString(arguments, "resourceName") ?? "app-jaws-api",
                    ["recommendation"] = "Create an HTTP synthetic for the public health endpoint and monitors for availability, 5xx rate, latency, and dependency failures.",
                    ["rationale"] = "The resource is a public API surface where availability, latency, and server-error coverage provide actionable operational evidence.",
                    ["requiresApprovalBeforeCreate"] = true,
                    ["nextWriteTools"] = new JsonArray("datadog.synthetic.create", "datadog.webhook.test")
                }),
            new JawsMcpTool(
                Name: "servicenow.cmdb.lookup",
                Description: "Use when support, governance, or workflow agents need ownership and service context before recommending or executing work. Requires resourceName. Returns business service, assignment group, and CI match status; it does not create or update ServiceNow records.",
                InputSchema: ObjectSchema(("resourceName", "Azure resource or service name to look up in CMDB context.")),
                IsWriteTool: false,
                Invoke: arguments => new JsonObject
                {
                    ["status"] = "ok",
                    ["provider"] = "ServiceNow",
                    ["resourceName"] = ReadString(arguments, "resourceName") ?? "app-jaws-api",
                    ["businessService"] = "JAWS Tutorial API",
                    ["assignmentGroup"] = "Cloud Operations",
                    ["matchedCi"] = true
                }),
            new JawsMcpTool(
                Name: "jaws.tool.extensibility",
                Description: "Use when platform owners or governance agents need to understand how JSON job descriptions constrain an agent. Accepts an optional agentRole. Returns the job-description path, extensibility model, required approval concepts, and future tool examples.",
                InputSchema: ObjectSchema(("agentRole", "Optional JAWS role name such as support, governance, deploy, or workflow.")),
                IsWriteTool: false,
                Invoke: arguments => new JsonObject
                {
                    ["status"] = "ok",
                    ["provider"] = "JAWS",
                    ["agentRole"] = ReadString(arguments, "agentRole") ?? "deploy",
                    ["jobDescriptionPath"] = "docs/examples/deploy.datadog.synthetic.job-description.json",
                    ["extensibilityModel"] = "A job description declares role, instructions, responsibilities, allowedTools, requiredContext, reasoningProcedure, guardrails, approval policy, evidence policy, and expected tool contracts. The MCP registry must expose a matching approved tool before the agent can use it.",
                    ["futureToolExamples"] = new JsonArray("securitycopilot.investigate", "defender.recommendation.query", "contentSafety.promptShield.evaluate", "azureMcp.resource.query")
                }),
            new JawsMcpTool(
                Name: "datadog.synthetic.create",
                Description: "Use only inside an approved workflow when the deploy agent must create a Datadog synthetic for a selected resource. Requires resourceName and approvalReference. Returns creation evidence and Datadog identifiers; blocked unless write tools are enabled by workflow approval.",
                InputSchema: ObjectSchema(("resourceName", "Azure resource name approved for Datadog synthetic creation."), ("approvalReference", "Human approval reference matching the workflow approval policy.")),
                IsWriteTool: true,
                Invoke: arguments => new JsonObject
                {
                    ["status"] = "created",
                    ["provider"] = "Datadog",
                    ["resourceName"] = ReadString(arguments, "resourceName") ?? "app-jaws-api"
                }),
            new JawsMcpTool(
                Name: "datadog.webhook.test",
                Description: "Use only inside an approved workflow when the deploy agent must validate Datadog-to-JAWS webhook delivery. Requires syntheticPublicId and approvalReference. Returns notification evidence; blocked unless write tools are enabled by workflow approval.",
                InputSchema: ObjectSchema(("syntheticPublicId", "Datadog synthetic public ID selected for webhook test notification."), ("approvalReference", "Human approval reference matching the workflow approval policy.")),
                IsWriteTool: true,
                Invoke: arguments => new JsonObject
                {
                    ["status"] = "sent",
                    ["provider"] = "Datadog",
                    ["syntheticPublicId"] = ReadString(arguments, "syntheticPublicId") ?? "demo-synthetic"
                }),
            new JawsMcpTool(
                Name: "servicenow.incident.createOrUpdate",
                Description: "Use only inside an approved workflow when JAWS must record incident evidence in ServiceNow. Requires resourceName and approvalReference. Returns incident creation or update evidence; blocked unless write tools are enabled by workflow approval.",
                InputSchema: ObjectSchema(("resourceName", "Affected Azure resource name to record in the ServiceNow incident evidence."), ("approvalReference", "Human approval reference matching the workflow approval policy.")),
                IsWriteTool: true,
                Invoke: arguments => new JsonObject
                {
                    ["status"] = "created",
                    ["provider"] = "ServiceNow",
                    ["resourceName"] = ReadString(arguments, "resourceName") ?? "app-jaws-api"
                })
        };

        _tools = tools.ToDictionary(tool => tool.Name, StringComparer.Ordinal);
    }

    public IReadOnlyCollection<JawsMcpTool> Tools => _tools.Values.ToArray();

    public bool TryGetTool(string name, out JawsMcpTool tool) =>
        _tools.TryGetValue(name, out tool!);

    private static JsonObject EmptyObjectSchema() => new()
    {
        ["type"] = "object",
        ["additionalProperties"] = false,
        ["properties"] = new JsonObject()
    };

    private static JsonObject ObjectSchema(params (string Name, string Description)[] properties) => new()
    {
        ["type"] = "object",
        ["additionalProperties"] = false,
        ["properties"] = new JsonObject(properties.Select(property =>
            new KeyValuePair<string, JsonNode?>(property.Name, new JsonObject
            {
                ["type"] = "string",
                ["description"] = property.Description
            })))
    };

    private static string? ReadString(JsonObject? arguments, string name)
    {
        return arguments is not null &&
            arguments.TryGetPropertyValue(name, out var value) &&
            value is not null &&
            value.GetValueKind() == System.Text.Json.JsonValueKind.String
                ? value.GetValue<string>()
                : null;
    }
}
