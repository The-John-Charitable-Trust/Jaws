using Jaws.AgentFramework.Agents;
using Jaws.AgentFramework.Conversations;
using Jaws.AgentFramework.Configuration;
using Jaws.AgentFramework.FirstAgent;
using Jaws.AgentFramework.Mcp;
using System.Text.Json;

var tests = new List<(string Name, Action Test)>
{
    ("First agent options validate required fields", FirstAgentOptionsValidateRequiredFields),
    ("First agent options accept valid configuration", FirstAgentOptionsAcceptValidConfiguration),
    ("Role agent catalog includes workflow agents", RoleAgentCatalogIncludesWorkflowAgents),
    ("Deploy agent requires approval", DeployAgentRequiresApproval),
    ("Naming policy generates expected resource names", NamingPolicyGeneratesExpectedNames),
    ("MCP registry exposes foundation tools", McpRegistryExposesReadOnlyTools),
    ("MCP server initializes", McpServerInitializes),
    ("MCP server lists tools", McpServerListsTools),
    ("MCP server calls status tool", McpServerCallsStatusTool),
    ("MCP server rejects unknown tools", McpServerRejectsUnknownTools),
    ("MCP server rejects invalid JSON-RPC version", McpServerRejectsInvalidJsonRpcVersion),
    ("MCP server returns safe unsupported method errors", McpServerReturnsSafeUnsupportedMethodErrors),
    ("MCP server rejects undeclared tool arguments", McpServerRejectsUndeclaredToolArguments),
    ("MCP tool metadata declares read and write annotations", McpToolMetadataDeclaresReadOnlyAnnotations),
    ("MCP registry exposes core demo tools", McpRegistryExposesCoreDemoTools),
    ("Role agent allowed tools exist in MCP registry", RoleAgentAllowedToolsExistInRegistry),
    ("MCP server calls Azure inventory tool", McpServerCallsAzureInventoryTool),
    ("MCP server calls Datadog recommendation tool", McpServerCallsDatadogRecommendationTool),
    ("MCP write tools remain approval gated", McpWriteToolsRemainApprovalGated),
    ("MCP tool extensibility describes job descriptions", McpToolExtensibilityDescribesJobDescriptions),
    ("MCP tool descriptions expose agent interface guidance", McpToolDescriptionsExposeAgentInterfaceGuidance),
    ("JSON job description includes context reasoning guardrails and tool contracts", JsonJobDescriptionIncludesContextReasoningGuardrailsAndToolContracts),
    ("Conversation store creates conversation IDs", ConversationStoreCreatesConversationIds),
    ("Conversation store increments turns for same conversation", ConversationStoreIncrementsTurns),
    ("Conversation store reset starts a fresh local turn state", ConversationStoreResetStartsFreshState),
    ("First agent response exposes conversation metadata", FirstAgentResponseExposesConversationMetadata)
};

var failures = new List<string>();

foreach (var (name, test) in tests)
{
    try
    {
        test();
        Console.WriteLine($"PASS: {name}");
    }
    catch (Exception ex)
    {
        failures.Add($"FAIL: {name} - {ex.Message}");
        Console.WriteLine(failures[^1]);
    }
}

if (failures.Count > 0)
{
    Console.WriteLine();
    Console.WriteLine($"Summary: {tests.Count - failures.Count}/{tests.Count} passed.");
    Environment.ExitCode = 1;
    return;
}

Console.WriteLine();
Console.WriteLine($"Summary: {tests.Count}/{tests.Count} passed.");

static void FirstAgentOptionsValidateRequiredFields()
{
    var options = new FirstAgentOptions();
    var errors = options.Validate();

    AssertTrue(errors.Count >= 2, "empty options should produce validation errors");
    AssertTrue(errors.Any(error => error.Contains("Endpoint", StringComparison.Ordinal)), "endpoint error missing");
    AssertTrue(errors.Any(error => error.Contains("DeploymentName", StringComparison.Ordinal)), "deployment name error missing");
    AssertTrue(errors.Any(error => error.Contains("ApiKey", StringComparison.Ordinal)), "API key error missing");
}

static void FirstAgentOptionsAcceptValidConfiguration()
{
    var options = new FirstAgentOptions
    {
        Endpoint = "https://example-project.services.ai.azure.com/api/projects/example-project",
        DeploymentName = "gpt-4.1-mini",
        ApiKey = "test-api-key"
    };

    AssertTrue(options.IsConfigured, "valid options should be configured");
    AssertEqual(0, options.Validate().Count, "valid options error count");
}

static void RoleAgentCatalogIncludesWorkflowAgents()
{
    var roles = RoleAgentCatalog.All.Select(agent => agent.Role).ToHashSet();

    AssertEqual(4, RoleAgentCatalog.All.Count, "role agent count");
    AssertTrue(roles.Contains(AgentRole.Support), "support role missing");
    AssertTrue(roles.Contains(AgentRole.Governance), "governance role missing");
    AssertTrue(roles.Contains(AgentRole.Deploy), "deploy role missing");
    AssertTrue(roles.Contains(AgentRole.Workflow), "workflow role missing");
    AssertTrue(RoleAgentCatalog.All.All(agent => agent.Validate().Count == 0), "catalog job descriptions should validate");
}

static void DeployAgentRequiresApproval()
{
    var deploy = DeployAgent.JobDescription;

    AssertTrue(deploy.RequiresApproval, "deploy agent should require approval");
    AssertTrue(deploy.AllowedTools.Contains("datadog.synthetic.create", StringComparer.Ordinal), "datadog synthetic tool missing");
    AssertTrue(deploy.AllowedTools.Contains("servicenow.incident.createOrUpdate", StringComparer.Ordinal), "ServiceNow incident tool missing");
    AssertTrue(deploy.ApprovalPolicy.WriteActions.Contains("testNotification", StringComparer.Ordinal), "test notification approval action missing");
    AssertTrue(deploy.EvidencePolicy.IncludePassFailTable, "deploy evidence should include pass/fail table");
}

static void NamingPolicyGeneratesExpectedNames()
{
    var names = JawsNamingPolicy.Generate(new NamingInputs(
        Organization: "contoso",
        Environment: "dev",
        Region: "eastus",
        Workload: "jaws",
        Prefix: "aiops",
        Suffix: "001"));

    AssertEqual("rg-aiops-contoso-jaws-dev-eastus-001", names.ResourceGroup, "resource group");
    AssertEqual("app-aiops-contoso-jaws-dev-eastus-001", names.AppService, "app service");
    AssertEqual("asp-aiops-contoso-jaws-dev-eastus-001", names.AppServicePlan, "app service plan");
    AssertEqual("law-aiops-contoso-jaws-dev-eastus-001", names.LogAnalyticsWorkspace, "log analytics workspace");
    AssertEqual("appi-aiops-contoso-jaws-dev-eastus-001", names.ApplicationInsights, "application insights");
    AssertTrue(names.KeyVault.StartsWith("kv-aiops-contoso-jaws", StringComparison.Ordinal), "key vault prefix");
    AssertTrue(names.KeyVault.Length <= 24, "key vault length");
    AssertEqual("aiopscontosojawsdev001", names.StorageAccount, "storage account");
}

static void McpRegistryExposesReadOnlyTools()
{
    var registry = new JawsMcpToolRegistry();
    var toolNames = registry.Tools.Select(tool => tool.Name).ToHashSet(StringComparer.Ordinal);

    AssertTrue(registry.Tools.Count >= 2, "MCP registry should include foundation tools");
    AssertTrue(toolNames.Contains("jaws_mcp_status"), "MCP status tool missing");
    AssertTrue(toolNames.Contains("jaws_tool_registry"), "MCP registry tool missing");
    AssertTrue(registry.Tools.All(tool => tool.InputSchema["additionalProperties"]?.GetValue<bool>() == false),
        "MCP tools should reject undeclared input properties");
}

static void McpServerInitializes()
{
    var server = new JawsMcpServer(new JawsMcpToolRegistry());
    using var document = JsonDocument.Parse("""
        {"jsonrpc":"2.0","id":0,"method":"initialize"}
        """);

    var response = server.Handle(document.RootElement);
    var result = response["result"];

    AssertEqual("2.0", response["jsonrpc"]?.GetValue<string>(), "JSON-RPC version");
    AssertEqual("jaws-custom-mcp", result?["serverInfo"]?["name"]?.GetValue<string>(), "MCP initialize server name");
    AssertEqual("0.4", result?["serverInfo"]?["version"]?.GetValue<string>(), "MCP initialize server version");
}

static void McpServerListsTools()
{
    var server = new JawsMcpServer(new JawsMcpToolRegistry());
    using var document = JsonDocument.Parse("""
        {"jsonrpc":"2.0","id":1,"method":"tools/list"}
        """);

    var response = server.Handle(document.RootElement);
    var tools = response["result"]?["tools"]?.AsArray();

    AssertEqual("2.0", response["jsonrpc"]?.GetValue<string>(), "JSON-RPC version");
    AssertTrue((tools?.Count ?? 0) >= 2, "listed MCP tool count");
}

static void McpServerCallsStatusTool()
{
    var server = new JawsMcpServer(new JawsMcpToolRegistry());
    using var document = JsonDocument.Parse("""
        {"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"jaws_mcp_status","arguments":{}}}
        """);

    var response = server.Handle(document.RootElement);
    var structuredContent = response["result"]?["structuredContent"];

    AssertEqual("ok", structuredContent?["status"]?.GetValue<string>(), "MCP status");
    AssertEqual("jaws-custom-mcp", structuredContent?["server"]?.GetValue<string>(), "MCP server name");
    AssertEqual("0.4", structuredContent?["release"]?.GetValue<string>(), "MCP release");
    AssertEqual(false, structuredContent?["writeToolsEnabled"]?.GetValue<bool>(), "write tools flag");
    AssertEqual("hardened-local", structuredContent?["securityMode"]?.GetValue<string>(), "MCP security mode");
}

static void McpServerRejectsUnknownTools()
{
    var server = new JawsMcpServer(new JawsMcpToolRegistry());
    using var document = JsonDocument.Parse("""
        {"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"unknown_tool","arguments":{}}}
        """);

    var response = server.Handle(document.RootElement);
    var error = response["error"];

    AssertEqual(-32602, error?["code"]?.GetValue<int>(), "unknown tool error code");
    AssertEqual("Unknown MCP tool.", error?["message"]?.GetValue<string>(), "unknown tool error message");
    AssertTrue(!error?["message"]?.GetValue<string>().Contains("unknown_tool", StringComparison.Ordinal) == true,
        "unknown tool error should not echo caller-supplied tool name");
    AssertTrue(!string.IsNullOrWhiteSpace(error?["data"]?["correlationId"]?.GetValue<string>()),
        "unknown tool error correlation ID");
}

static void McpServerRejectsInvalidJsonRpcVersion()
{
    var server = new JawsMcpServer(new JawsMcpToolRegistry());
    using var document = JsonDocument.Parse("""
        {"jsonrpc":"1.0","id":4,"method":"tools/list"}
        """);

    var response = server.Handle(document.RootElement);
    var error = response["error"];

    AssertEqual(-32600, error?["code"]?.GetValue<int>(), "invalid JSON-RPC version error code");
    AssertEqual("Invalid MCP request.", error?["message"]?.GetValue<string>(), "invalid JSON-RPC version error message");
    AssertTrue(!string.IsNullOrWhiteSpace(error?["data"]?["correlationId"]?.GetValue<string>()),
        "invalid JSON-RPC version correlation ID");
}

static void McpServerReturnsSafeUnsupportedMethodErrors()
{
    var server = new JawsMcpServer(new JawsMcpToolRegistry());
    using var document = JsonDocument.Parse("""
        {"jsonrpc":"2.0","id":5,"method":"dangerous/deleteEverything"}
        """);

    var response = server.Handle(document.RootElement);
    var error = response["error"];

    AssertEqual(-32601, error?["code"]?.GetValue<int>(), "unsupported method error code");
    AssertEqual("Unsupported MCP method.", error?["message"]?.GetValue<string>(), "unsupported method error message");
    AssertTrue(!error?["message"]?.GetValue<string>().Contains("dangerous", StringComparison.Ordinal) == true,
        "unsupported method error should not echo caller-supplied method");
}

static void McpServerRejectsUndeclaredToolArguments()
{
    var server = new JawsMcpServer(new JawsMcpToolRegistry());
    using var document = JsonDocument.Parse("""
        {"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"jaws_mcp_status","arguments":{"unexpected":"value"}}}
        """);

    var response = server.Handle(document.RootElement);
    var error = response["error"];

    AssertEqual(-32602, error?["code"]?.GetValue<int>(), "undeclared argument error code");
    AssertEqual("Tool arguments failed validation.", error?["message"]?.GetValue<string>(), "undeclared argument error message");
}

static void McpToolMetadataDeclaresReadOnlyAnnotations()
{
    var server = new JawsMcpServer(new JawsMcpToolRegistry());
    using var document = JsonDocument.Parse("""
        {"jsonrpc":"2.0","id":7,"method":"tools/list"}
        """);

    var response = server.Handle(document.RootElement);
    var tools = response["result"]?["tools"]?.AsArray();

    AssertTrue(tools is not null && tools.Count > 0, "MCP tools should be listed");
    var listedTools = tools!;
    AssertTrue(listedTools.Any(tool => tool?["annotations"]?["readOnlyHint"]?.GetValue<bool>() == true),
        "read-only tools should be annotated");
    AssertTrue(listedTools.Any(tool => tool?["annotations"]?["destructiveHint"]?.GetValue<bool>() == true),
        "write-capable tools should be annotated");
}

static void McpRegistryExposesCoreDemoTools()
{
    var registry = new JawsMcpToolRegistry();
    var toolNames = registry.Tools.Select(tool => tool.Name).ToHashSet(StringComparer.Ordinal);

    AssertTrue(toolNames.Contains("azure.resource.inventory"), "Azure inventory tool missing");
    AssertTrue(toolNames.Contains("azure.policy.evidence"), "Azure policy evidence tool missing");
    AssertTrue(toolNames.Contains("azure.monitor.evidence"), "Azure monitor evidence tool missing");
    AssertTrue(toolNames.Contains("datadog.coverage.recommend"), "Datadog recommendation tool missing");
    AssertTrue(toolNames.Contains("servicenow.cmdb.lookup"), "ServiceNow CMDB tool missing");
    AssertTrue(toolNames.Contains("jaws.tool.extensibility"), "JAWS extensibility tool missing");
    AssertTrue(toolNames.Contains("datadog.synthetic.create"), "Datadog create tool missing");
    AssertTrue(toolNames.Contains("datadog.webhook.test"), "Datadog webhook test tool missing");
    AssertTrue(toolNames.Contains("servicenow.incident.createOrUpdate"), "ServiceNow incident write tool missing");
}

static void RoleAgentAllowedToolsExistInRegistry()
{
    var registry = new JawsMcpToolRegistry();
    var toolNames = registry.Tools.Select(tool => tool.Name).ToHashSet(StringComparer.Ordinal);

    foreach (var jobDescription in RoleAgentCatalog.All)
    {
        foreach (var allowedTool in jobDescription.AllowedTools)
        {
            AssertTrue(toolNames.Contains(allowedTool), $"allowed tool '{allowedTool}' should exist in the MCP registry");
        }
    }
}

static void McpServerCallsAzureInventoryTool()
{
    var server = new JawsMcpServer(new JawsMcpToolRegistry());
    using var document = JsonDocument.Parse("""
        {"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"azure.resource.inventory","arguments":{"scope":"rg-jaws-demo"}}}
        """);

    var response = server.Handle(document.RootElement);
    var structuredContent = response["result"]?["structuredContent"];

    AssertEqual("ok", structuredContent?["status"]?.GetValue<string>(), "Azure inventory status");
    AssertEqual("Azure", structuredContent?["provider"]?.GetValue<string>(), "Azure inventory provider");
    AssertTrue((structuredContent?["resources"]?.AsArray().Count ?? 0) > 0, "Azure inventory resources");
}

static void McpServerCallsDatadogRecommendationTool()
{
    var server = new JawsMcpServer(new JawsMcpToolRegistry());
    using var document = JsonDocument.Parse("""
        {"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"datadog.coverage.recommend","arguments":{"resourceName":"app-jaws-api","resourceType":"Microsoft.Web/sites"}}}
        """);

    var response = server.Handle(document.RootElement);
    var structuredContent = response["result"]?["structuredContent"];

    AssertEqual("ok", structuredContent?["status"]?.GetValue<string>(), "Datadog recommendation status");
    AssertEqual("Datadog", structuredContent?["provider"]?.GetValue<string>(), "Datadog recommendation provider");
    AssertEqual(true, structuredContent?["requiresApprovalBeforeCreate"]?.GetValue<bool>(), "Datadog recommendation approval flag");
}

static void McpWriteToolsRemainApprovalGated()
{
    var server = new JawsMcpServer(new JawsMcpToolRegistry());
    using var document = JsonDocument.Parse("""
        {"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"datadog.synthetic.create","arguments":{"resourceName":"app-jaws-api","approvalReference":"APP-20260626-app-jaws-api"}}}
        """);

    var response = server.Handle(document.RootElement);
    var error = response["error"];

    AssertEqual(-32050, error?["code"]?.GetValue<int>(), "write tool denied error code");
    AssertEqual("Write-capable MCP tool denied.", error?["message"]?.GetValue<string>(), "write tool denied error message");
}

static void McpToolExtensibilityDescribesJobDescriptions()
{
    var server = new JawsMcpServer(new JawsMcpToolRegistry());
    using var document = JsonDocument.Parse("""
        {"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"jaws.tool.extensibility","arguments":{"agentRole":"deploy"}}}
        """);

    var response = server.Handle(document.RootElement);
    var structuredContent = response["result"]?["structuredContent"];

    AssertEqual("ok", structuredContent?["status"]?.GetValue<string>(), "extensibility status");
    AssertEqual("JAWS", structuredContent?["provider"]?.GetValue<string>(), "extensibility provider");
    AssertTrue(structuredContent?["extensibilityModel"]?.GetValue<string>().Contains("job description", StringComparison.OrdinalIgnoreCase) == true,
        "extensibility model should mention job descriptions");
}

static void McpToolDescriptionsExposeAgentInterfaceGuidance()
{
    var registry = new JawsMcpToolRegistry();

    foreach (var tool in registry.Tools)
    {
        AssertTrue(tool.Description.Contains("Use", StringComparison.OrdinalIgnoreCase), $"{tool.Name} description should explain when to use the tool");
        AssertTrue(
            tool.Description.Contains("Requires", StringComparison.OrdinalIgnoreCase) ||
            tool.Description.Contains("Accepts", StringComparison.OrdinalIgnoreCase),
            $"{tool.Name} description should explain required or accepted inputs");
        AssertTrue(
            tool.Description.Contains("Returns", StringComparison.OrdinalIgnoreCase) ||
            tool.Description.Contains("blocked", StringComparison.OrdinalIgnoreCase),
            $"{tool.Name} description should explain returned evidence or blocking behavior");
    }
}

static void JsonJobDescriptionIncludesContextReasoningGuardrailsAndToolContracts()
{
    var path = Path.Combine("docs", "examples", "deploy.datadog.synthetic.job-description.json");
    AssertTrue(File.Exists(path), "job-description JSON example should exist");

    using var document = JsonDocument.Parse(File.ReadAllText(path));
    var root = document.RootElement;

    AssertTrue(root.GetProperty("responsibilities").GetArrayLength() > 0, "responsibilities should be declared");
    AssertTrue(root.GetProperty("requiredContext").GetArrayLength() > 0, "required context should be declared");
    AssertTrue(root.GetProperty("reasoningProcedure").GetArrayLength() > 0, "reasoning procedure should be declared");
    AssertTrue(root.GetProperty("guardrails").GetArrayLength() > 0, "guardrails should be declared");
    AssertTrue(root.GetProperty("toolContracts").GetArrayLength() > 0, "tool contracts should be declared");

    var firstContract = root.GetProperty("toolContracts")[0];
    AssertTrue(firstContract.GetProperty("requiredParameters").GetArrayLength() > 0, "tool contract required parameters should be declared");
    AssertTrue(firstContract.GetProperty("expectedEvidence").GetArrayLength() > 0, "tool contract expected evidence should be declared");
}
static void ConversationStoreCreatesConversationIds()
{
    var store = new InMemoryConversationStore();
    var turn = store.BeginTurn(null);

    AssertTrue(turn.ConversationId.StartsWith("JCN-", StringComparison.Ordinal), "generated conversation ID prefix");
    AssertEqual(1, turn.TurnNumber, "initial turn number");
    AssertEqual(false, turn.WasReset, "initial reset flag");
    AssertTrue(store.Contains(turn.ConversationId), "store should contain generated conversation");
}

static void ConversationStoreIncrementsTurns()
{
    var store = new InMemoryConversationStore();
    var first = store.BeginTurn("conversation-1");
    var second = store.BeginTurn("conversation-1");

    AssertEqual("conversation-1", first.ConversationId, "first conversation ID");
    AssertEqual("conversation-1", second.ConversationId, "second conversation ID");
    AssertEqual(1, first.TurnNumber, "first turn number");
    AssertEqual(2, second.TurnNumber, "second turn number");
}

static void ConversationStoreResetStartsFreshState()
{
    var store = new InMemoryConversationStore();
    _ = store.BeginTurn("conversation-2");
    _ = store.BeginTurn("conversation-2");

    var reset = store.Reset("conversation-2");
    var firstAfterReset = store.BeginTurn("conversation-2");

    AssertEqual("conversation-2", reset.ConversationId, "reset conversation ID");
    AssertEqual(0, reset.TurnNumber, "reset turn marker");
    AssertEqual(true, reset.WasReset, "reset flag");
    AssertEqual(1, firstAfterReset.TurnNumber, "turn number after reset");
}

static void FirstAgentResponseExposesConversationMetadata()
{
    var response = new FirstAgentResponse(
        Answer: "ok",
        AgentName: "JawsFirstAgent",
        Release: "0.1",
        ConversationId: "conversation-3",
        TurnNumber: 2,
        ConversationReset: false,
        ConversationRelease: InMemoryConversationStore.Release);

    AssertEqual("conversation-3", response.ConversationId, "response conversation ID");
    AssertEqual(2, response.TurnNumber, "response turn number");
    AssertEqual("0.5", response.ConversationRelease, "response conversation release");
}
static void AssertTrue(bool condition, string message)
{
    if (!condition)
    {
        throw new InvalidOperationException(message);
    }
}

static void AssertEqual<T>(T expected, T actual, string name)
{
    if (!EqualityComparer<T>.Default.Equals(expected, actual))
    {
        throw new InvalidOperationException($"{name}: expected '{expected}', actual '{actual}'.");
    }
}
