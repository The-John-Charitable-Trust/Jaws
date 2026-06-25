using Jaws.AgentFramework.Agents;
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
    ("MCP registry exposes Step 2 read-only tools", McpRegistryExposesReadOnlyTools),
    ("MCP server initializes", McpServerInitializes),
    ("MCP server lists tools", McpServerListsTools),
    ("MCP server calls status tool", McpServerCallsStatusTool),
    ("MCP server rejects unknown tools", McpServerRejectsUnknownTools),
    ("MCP server rejects invalid JSON-RPC version", McpServerRejectsInvalidJsonRpcVersion),
    ("MCP server returns safe unsupported method errors", McpServerReturnsSafeUnsupportedMethodErrors),
    ("MCP server rejects undeclared tool arguments", McpServerRejectsUndeclaredToolArguments),
    ("MCP tool metadata declares read-only annotations", McpToolMetadataDeclaresReadOnlyAnnotations)
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

    AssertEqual(2, registry.Tools.Count, "Step 2 MCP tool count");
    AssertTrue(toolNames.Contains("jaws_mcp_status"), "MCP status tool missing");
    AssertTrue(toolNames.Contains("jaws_tool_registry"), "MCP registry tool missing");
    AssertTrue(registry.Tools.All(tool => tool.InputSchema["additionalProperties"]?.GetValue<bool>() == false),
        "Step 2 tools should reject undeclared input properties");
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
    AssertEqual("0.3", result?["serverInfo"]?["version"]?.GetValue<string>(), "MCP initialize server version");
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
    AssertEqual(2, tools?.Count ?? 0, "listed MCP tool count");
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
    AssertEqual("0.3", structuredContent?["release"]?.GetValue<string>(), "MCP release");
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
    foreach (var tool in tools!)
    {
        AssertEqual(true, tool?["annotations"]?["readOnlyHint"]?.GetValue<bool>(), "read-only tool annotation");
        AssertEqual(false, tool?["annotations"]?["destructiveHint"]?.GetValue<bool>(), "destructive tool annotation");
    }
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


