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
                Description: "Returns the local JAWS MCP server status and release metadata.",
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
                Description: "Returns the tools currently registered with the local JAWS MCP server.",
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
                Description: "Returns demo Azure resource candidates that may need Datadog coverage.",
                InputSchema: ObjectSchema(("scope", "Optional authorized Azure scope or resource group name.")),
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
                Description: "Returns demo Azure Policy evidence for the selected resource.",
                InputSchema: ObjectSchema(("resourceName", "Azure resource name to evaluate.")),
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
                Description: "Returns demo Azure Monitor evidence for operational triage.",
                InputSchema: ObjectSchema(("resourceName", "Azure resource name to inspect."), ("timeRange", "Optional evidence time range.")),
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
                Description: "Recommends Datadog monitor or synthetic coverage for an Azure resource.",
                InputSchema: ObjectSchema(("resourceName", "Azure resource name to evaluate."), ("resourceType", "Azure resource type.")),
                IsWriteTool: false,
                Invoke: arguments => new JsonObject
                {
                    ["status"] = "ok",
                    ["provider"] = "Datadog",
                    ["resourceName"] = ReadString(arguments, "resourceName") ?? "app-jaws-api",
                    ["recommendation"] = "Create an HTTP synthetic for the public health endpoint and monitors for availability, 5xx rate, latency, and dependency failures.",
                    ["requiresApprovalBeforeCreate"] = true,
                    ["nextWriteTools"] = new JsonArray("datadog.synthetic.create", "datadog.webhook.test")
                }),
            new JawsMcpTool(
                Name: "servicenow.cmdb.lookup",
                Description: "Returns demo ServiceNow CMDB ownership context for a resource.",
                InputSchema: ObjectSchema(("resourceName", "Azure resource or service name to look up.")),
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
                Description: "Explains how customer-authored JSON job descriptions map agents to approved MCP tools.",
                InputSchema: ObjectSchema(("agentRole", "Optional role name to explain.")),
                IsWriteTool: false,
                Invoke: arguments => new JsonObject
                {
                    ["status"] = "ok",
                    ["provider"] = "JAWS",
                    ["agentRole"] = ReadString(arguments, "agentRole") ?? "deploy",
                    ["jobDescriptionPath"] = "docs/examples/deploy.datadog.synthetic.job-description.json",
                    ["extensibilityModel"] = "A job description declares role, instructions, allowedTools, approval policy, and evidence policy. The MCP registry must expose a matching approved tool before the agent can use it.",
                    ["futureToolExamples"] = new JsonArray("securitycopilot.investigate", "defender.recommendation.query", "contentSafety.promptShield.evaluate", "azureMcp.resource.query")
                }),
            new JawsMcpTool(
                Name: "datadog.synthetic.create",
                Description: "Write-capable future workflow tool for creating an approved Datadog synthetic test.",
                InputSchema: ObjectSchema(("resourceName", "Azure resource name."), ("approvalReference", "Human approval reference.")),
                IsWriteTool: true,
                Invoke: arguments => new JsonObject
                {
                    ["status"] = "created",
                    ["provider"] = "Datadog",
                    ["resourceName"] = ReadString(arguments, "resourceName") ?? "app-jaws-api"
                }),
            new JawsMcpTool(
                Name: "datadog.webhook.test",
                Description: "Write-capable future workflow tool for sending a Datadog webhook test notification.",
                InputSchema: ObjectSchema(("syntheticPublicId", "Datadog synthetic public ID."), ("approvalReference", "Human approval reference.")),
                IsWriteTool: true,
                Invoke: arguments => new JsonObject
                {
                    ["status"] = "sent",
                    ["provider"] = "Datadog",
                    ["syntheticPublicId"] = ReadString(arguments, "syntheticPublicId") ?? "demo-synthetic"
                }),
            new JawsMcpTool(
                Name: "servicenow.incident.createOrUpdate",
                Description: "Write-capable future workflow tool for creating or updating a ServiceNow incident.",
                InputSchema: ObjectSchema(("resourceName", "Affected resource name."), ("approvalReference", "Human approval reference.")),
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

