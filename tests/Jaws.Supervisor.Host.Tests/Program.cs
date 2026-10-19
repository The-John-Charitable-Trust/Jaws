using System.Text.Json;
using Jaws.Supervisor.Host;
using Microsoft.Agents.AI;
using Microsoft.Extensions.AI;

const string Acceptance =
    "Call the Investigation A2A toolbox tool now for a read-only investigation planning request. " +
    "Identify three diagnostic checks for an unhealthy Azure VM. Do not perform any remediation. " +
    "Do not answer from your own knowledge. Report what the Investigation agent actually returned.";
const string Toolbox = "jaws-investigation-a2a-tools";
const string InvestigationTool = "jaws-investigation-a2a-tools___SendMessage";

var schemaDocument = JsonDocument.Parse("""{"type":"object","properties":{}}""");
var schema = schemaDocument.RootElement;
var tests = new List<(string Name, Action Test)>
{
    ("acceptance requires the Investigation SendMessage tool", AcceptanceRequiresSendMessage),
    ("acceptance prefers SendMessage over another investigation tool", AcceptancePrefersSendMessage),
    ("acceptance fails closed when the toolbox tool is missing", AcceptanceFailsClosedWithoutTool),
    ("acceptance fails closed when only a browser tool is present", AcceptanceFailsClosedForBrowserOnly),
    ("an unrelated turn leaves tool choice optional", UnrelatedTurnStaysOptional),
    ("version 1 does not require a tool", VersionOneDoesNotRequire)
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
    Console.WriteLine($"Summary: {tests.Count - failures.Count}/{tests.Count} passed.");
    Environment.ExitCode = 1;
    return;
}

Console.WriteLine($"Summary: {tests.Count}/{tests.Count} passed.");

void AcceptanceRequiresSendMessage()
{
    var options = Options(Declare(InvestigationTool));
    FoundryToolboxCallMetadata.RequireInvestigationDelegation(User(Acceptance), options, Toolbox);
    var required = options.ChatOptions!.ToolMode as RequiredChatToolMode;
    if (required?.RequiredFunctionName != InvestigationTool)
    {
        throw new InvalidOperationException($"Tool choice was '{required?.RequiredFunctionName ?? "<none>"}'.");
    }
}

void AcceptancePrefersSendMessage()
{
    var options = Options(Declare("investigation-planner"), Declare(InvestigationTool), Declare("browser_navigate"));
    FoundryToolboxCallMetadata.RequireInvestigationDelegation(User(Acceptance), options, Toolbox);
    var required = options.ChatOptions!.ToolMode as RequiredChatToolMode;
    if (required?.RequiredFunctionName != InvestigationTool)
    {
        throw new InvalidOperationException($"Tool choice was '{required?.RequiredFunctionName ?? "<none>"}'.");
    }
}

void AcceptanceFailsClosedWithoutTool()
{
    var options = Options();
    var error = AssertThrows(options);
    if (!error.Contains("Tools on the run: <none>", StringComparison.Ordinal))
    {
        throw new InvalidOperationException(error);
    }
}

void AcceptanceFailsClosedForBrowserOnly()
{
    var options = Options(Declare("browser_navigate"));
    var error = AssertThrows(options);
    if (!error.Contains("browser_navigate", StringComparison.Ordinal))
    {
        throw new InvalidOperationException(error);
    }
}

void UnrelatedTurnStaysOptional()
{
    var options = Options(Declare(InvestigationTool));
    FoundryToolboxCallMetadata.RequireInvestigationDelegation(User("Summarize the last change window."), options, Toolbox);
    if (options.ChatOptions!.ToolMode is not null)
    {
        throw new InvalidOperationException("An unrelated turn required a tool.");
    }
}

void VersionOneDoesNotRequire()
{
    var options = Options(Declare(InvestigationTool));
    FoundryToolboxCallMetadata.RequireInvestigationDelegation(User(Acceptance), options, investigationToolboxName: "  ");
    if (options.ChatOptions!.ToolMode is not null)
    {
        throw new InvalidOperationException("Version 1 required a tool.");
    }
}

string AssertThrows(ChatClientAgentRunOptions options)
{
    try
    {
        FoundryToolboxCallMetadata.RequireInvestigationDelegation(User(Acceptance), options, Toolbox);
    }
    catch (InvalidOperationException ex) when (ex.Message.StartsWith("JAWS-TOOLBOX-CALL-003:", StringComparison.Ordinal))
    {
        return ex.Message;
    }

    throw new InvalidOperationException("The missing Investigation tool was not rejected.");
}

ChatClientAgentRunOptions Options(params AITool[] tools)
{
    return new ChatClientAgentRunOptions(new ChatOptions
    {
        Tools = tools.ToList()
    });
}

AIFunctionDeclaration Declare(string name)
{
    return AIFunctionFactory.CreateDeclaration(name, name, schema);
}

IEnumerable<ChatMessage> User(string text)
{
    return [new ChatMessage(ChatRole.User, text)];
}
