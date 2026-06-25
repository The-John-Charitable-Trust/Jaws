using Jaws.AgentFramework.Agents;
using Jaws.AgentFramework.Configuration;
using Jaws.AgentFramework.FirstAgent;

var tests = new List<(string Name, Action Test)>
{
    ("First agent options validate required fields", FirstAgentOptionsValidateRequiredFields),
    ("First agent options accept valid configuration", FirstAgentOptionsAcceptValidConfiguration),
    ("Role agent catalog includes workflow agents", RoleAgentCatalogIncludesWorkflowAgents),
    ("Deploy agent requires approval", DeployAgentRequiresApproval),
    ("Naming policy generates expected resource names", NamingPolicyGeneratesExpectedNames)
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


