using System.Reflection;
using System.Text.Json.Nodes;
using Jaws.Supervisor.Host;
using Microsoft.Agents.AI;
using Microsoft.Extensions.AI;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using ModelContextProtocol.Client;
using ModelContextProtocol.Protocol;
using ModelContextProtocol.Server;

if (args.Contains("--mcp-meta-server"))
{
    await RunMetaServerAsync();
    return 0;
}

var failures = 0;
failures += await CheckForwardedCallSucceedsAsync();
failures += CheckUnpatchableToolFailsClosed();
failures += CheckEmptyMcpHolderFailsClosed();
if (failures != 0)
{
    Console.Error.WriteLine($"FAIL {failures}");
    return 1;
}

Console.WriteLine("PASS toolbox metadata forwarding");
return 0;

static async Task<int> CheckForwardedCallSucceedsAsync()
{
    var (command, arguments) = ServerLaunch();
    var transport = new StdioClientTransport(new StdioClientTransportOptions
    {
        Command = command,
        Arguments = arguments,
        Name = "jaws-toolbox-meta-probe"
    });
    await using var client = await McpClient.CreateAsync(transport);
    var listed = await client.ListToolsAsync();
    var tool = listed.Single();
    var listedMeta = tool.ProtocolTool.Meta?["tool_configuration"]?.ToJsonString();
    if (listedMeta is null || !listedMeta.Contains("foundry_toolbox", StringComparison.Ordinal))
    {
        Console.Error.WriteLine("tools/list did not return tool_configuration metadata.");
        return 1;
    }

    var dropped = await tool.CallAsync(new Dictionary<string, object?>());
    if (Text(dropped) != "MISSING_TOOL_CONFIGURATION")
    {
        Console.Error.WriteLine($"Unpatched tools/call returned '{Text(dropped)}'.");
        return 1;
    }

    var forwarded = await FoundryToolboxCallMetadata.ForwardListedMetadata(tool).CallAsync(new Dictionary<string, object?>());
    if (Text(forwarded) != "FORWARDED")
    {
        Console.Error.WriteLine($"Forwarded tools/call returned '{Text(forwarded)}'.");
        return 1;
    }

    var wrapped = new ToolWrapper(tool);
    var patched = FoundryToolboxCallMetadata.Apply([wrapped]);
    if (patched != 1)
    {
        Console.Error.WriteLine($"Expected one patched wrapper, got {patched}.");
        return 1;
    }

    var throughWrapper = await wrapped.Inner.CallAsync(new Dictionary<string, object?>());
    if (Text(throughWrapper) != "FORWARDED")
    {
        Console.Error.WriteLine($"Patched wrapper call returned '{Text(throughWrapper)}'.");
        return 1;
    }

    var plain = AIFunctionFactory.Create(() => "plain", name: "plain_tool");
    var callable = new List<AITool> { plain, tool };
    var callablePatched = FoundryToolboxCallMetadata.ApplyCallable(callable);
    if (callablePatched != 1 || !ReferenceEquals(callable[0], plain))
    {
        Console.Error.WriteLine("Mixed tool list was not patched without disturbing the non-MCP tool.");
        return 1;
    }

    var throughList = await ((McpClientTool)callable[1]).CallAsync(new Dictionary<string, object?>());
    if (Text(throughList) != "FORWARDED")
    {
        Console.Error.WriteLine($"Per-call tool list returned '{Text(throughList)}'.");
        return 1;
    }

    var options = new ChatClientAgentRunOptions(new ChatOptions
    {
        Tools = new List<AITool> { tool }
    });
    var invoked = false;
    await FoundryToolboxCallMetadata.ForwardBeforeInvocation(
        [],
        session: null,
        options,
        (_, _, _, _) =>
        {
            invoked = true;
            return Task.CompletedTask;
        },
        CancellationToken.None);
    if (!invoked || options.ChatOptions?.Tools is not { Count: 1 })
    {
        Console.Error.WriteLine("Per-call forwarding did not reach the agent invocation.");
        return 1;
    }

    var throughRun = await ((McpClientTool)options.ChatOptions.Tools[0]).CallAsync(new Dictionary<string, object?>());
    if (Text(throughRun) != "FORWARDED")
    {
        Console.Error.WriteLine($"Run-option tool returned '{Text(throughRun)}'.");
        return 1;
    }

    return 0;
}

static int CheckUnpatchableToolFailsClosed()
{
    try
    {
        FoundryToolboxCallMetadata.Apply([new object()]);
    }
    catch (InvalidOperationException ex) when (ex.Message.Contains("JAWS-TOOLBOX-META-001", StringComparison.Ordinal))
    {
        return 0;
    }

    Console.Error.WriteLine("A tool with no MCP client field was not rejected.");
    return 1;
}

static int CheckEmptyMcpHolderFailsClosed()
{
    try
    {
        FoundryToolboxCallMetadata.Apply([new EmptyMcpHolder()]);
    }
    catch (InvalidOperationException ex) when (ex.Message.Contains("JAWS-TOOLBOX-META-001", StringComparison.Ordinal))
    {
        return 0;
    }

    Console.Error.WriteLine("A wrapper with an empty MCP field was not rejected.");
    return 1;
}

static string Text(CallToolResult result)
{
    return result.Content.OfType<TextContentBlock>().Single().Text;
}

static (string Command, string[] Arguments) ServerLaunch()
{
    var process = Environment.ProcessPath ?? throw new InvalidOperationException("Process path is unavailable.");
    var name = Path.GetFileName(process);
    if (name.Equals("dotnet", StringComparison.OrdinalIgnoreCase) ||
        name.Equals("dotnet.exe", StringComparison.OrdinalIgnoreCase))
    {
        var dll = Assembly.GetEntryAssembly()?.Location
            ?? throw new InvalidOperationException("Entry assembly location is unavailable.");
        return (process, [dll, "--mcp-meta-server"]);
    }

    return (process, ["--mcp-meta-server"]);
}

static async Task RunMetaServerAsync()
{
    var tool = McpServerTool.Create(
        typeof(MetaProbe).GetMethod(nameof(MetaProbe.SendMessage), BindingFlags.Public | BindingFlags.Static)!,
        target: null,
        new McpServerToolCreateOptions
        {
            Name = "jaws-investigation-a2a-dev__SendMessage",
            Description = "Probe that requires tools/list metadata on tools/call.",
            Meta = new JsonObject
            {
                ["tool_configuration"] = new JsonObject
                {
                    ["name"] = "jaws-investigation-a2a-dev__SendMessage",
                    ["type"] = "foundry_toolbox"
                }
            }
        });

    var builder = Host.CreateEmptyApplicationBuilder(new HostApplicationBuilderSettings { Args = [] });
    builder.Services.AddMcpServer().WithStdioServerTransport().WithTools([tool]);
    await builder.Build().RunAsync();
}

internal static class MetaProbe
{
    public static string SendMessage(RequestContext<CallToolRequestParams> context)
    {
        return context.Params?.Meta?["tool_configuration"] is null
            ? "MISSING_TOOL_CONFIGURATION"
            : "FORWARDED";
    }
}

internal sealed class ToolWrapper
{
    private readonly McpClientTool _inner;

    public ToolWrapper(McpClientTool inner) => _inner = inner;

    public McpClientTool Inner => _inner;
}

internal sealed class EmptyMcpHolder
{
    // Reflection reads this field. It stays null so patching must fail closed.
#pragma warning disable CS0169
    private readonly McpClientTool? _inner;
#pragma warning restore CS0169
}
