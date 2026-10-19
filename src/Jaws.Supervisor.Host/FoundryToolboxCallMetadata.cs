using System.Reflection;
using System.Runtime.CompilerServices;
using System.Text.Json.Nodes;
using Microsoft.Agents.AI;
using Microsoft.Extensions.AI;
using ModelContextProtocol.Client;

namespace Jaws.Supervisor.Host;

/// <summary>
/// Foundry toolbox proxies require each tools/call to echo the _meta block returned by tools/list,
/// including tool_configuration. The hosting client keeps that block on ProtocolTool and does not
/// send it, so the proxy rejects the call and the agent framework reports "Error: Function failed."
/// </summary>
public static class FoundryToolboxCallMetadata
{
    public static McpClientTool ForwardListedMetadata(McpClientTool tool)
    {
        ArgumentNullException.ThrowIfNull(tool);
        var listed = tool.ProtocolTool.Meta;
        if (listed is null || listed.Count == 0)
        {
            return tool;
        }

        if (listed.DeepClone() is not JsonObject copy)
        {
            return tool;
        }

        return tool.WithMeta(copy);
    }

    /// <summary>
    /// Patches toolbox tools on the chat options for this run. Foundry may create those wrappers
    /// after startup, so a startup-only pass never sees them. Non-MCP tools in the same list stay
    /// unchanged. A wrapper that should hold an MCP tool and does not fails closed.
    /// </summary>
    public static Task ForwardBeforeInvocation(
        IEnumerable<ChatMessage> messages,
        AgentSession? session,
        AgentRunOptions? options,
        Func<IEnumerable<ChatMessage>, AgentSession?, AgentRunOptions?, CancellationToken, Task> next,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(next);
        if (options is ChatClientAgentRunOptions chat && chat.ChatOptions?.Tools is { } tools)
        {
            ApplyCallable(tools);
        }

        return next(messages, session, options, cancellationToken);
    }

    public static async Task<AgentResponse> ForwardBeforeRun(
        IEnumerable<ChatMessage> messages,
        AgentSession? session,
        AgentRunOptions? options,
        AIAgent inner,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(inner);
        ForwardListedTools(options);
        RequireInvestigationDelegation(messages, options);
        var response = await inner.RunAsync(messages, session, options, cancellationToken);
        LogFunctionFailures(response.Messages.SelectMany(message => message.Contents));
        return response;
    }

    public static async IAsyncEnumerable<AgentResponseUpdate> ForwardBeforeStreamingRun(
        IEnumerable<ChatMessage> messages,
        AgentSession? session,
        AgentRunOptions? options,
        AIAgent inner,
        [EnumeratorCancellation] CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(inner);
        ForwardListedTools(options);
        RequireInvestigationDelegation(messages, options);
        await foreach (var update in inner.RunStreamingAsync(messages, session, options, cancellationToken))
        {
            LogFunctionFailures(update.Contents);
            yield return update;
        }
    }

    /// <summary>
    /// The agent framework replaces function exceptions with "Error: Function failed." unless this is set.
    /// The toolbox candidate needs the proxy error in order to correct the call.
    /// </summary>
    public static void EnableDetailedFunctionErrors(AIAgent agent)
    {
        ArgumentNullException.ThrowIfNull(agent);
        var seen = new HashSet<int>();
        var client = agent.GetService<IChatClient>();
        for (var depth = 0; client is not null && depth < 8; depth++)
        {
            if (!seen.Add(RuntimeHelpers.GetHashCode(client)))
            {
                break;
            }

            if (client is FunctionInvokingChatClient invoking)
            {
                invoking.IncludeDetailedErrors = true;
                Console.Error.WriteLine("JAWS-TOOLBOX-CALL-002: Detailed function errors enabled.");
                return;
            }

            if (client.GetService(typeof(IChatClient)) is not IChatClient next || ReferenceEquals(next, client))
            {
                break;
            }

            client = next;
        }

        Console.Error.WriteLine("JAWS-TOOLBOX-CALL-002: FunctionInvokingChatClient was not found.");
    }

    /// <summary>
    /// An explicit investigation request must call the Investigation toolbox tool.
    /// Tool choice stays optional for every other turn. A configured toolbox that did not
    /// arrive on this run fails closed, so the model cannot answer the investigation itself.
    /// </summary>
    public static void RequireInvestigationDelegation(
        IEnumerable<ChatMessage>? messages,
        AgentRunOptions? options,
        string? investigationToolboxName = null)
    {
        investigationToolboxName ??= Environment.GetEnvironmentVariable("JAWS_INVESTIGATION_TOOLBOX_NAME");
        if (string.IsNullOrWhiteSpace(investigationToolboxName) || !RequestsInvestigationDelegation(messages))
        {
            return;
        }

        if (options is not ChatClientAgentRunOptions chat)
        {
            throw new InvalidOperationException(
                "JAWS-TOOLBOX-CALL-003: The request asks for the Investigation toolbox, but this run has no chat options.");
        }

        var tools = chat.ChatOptions?.Tools;
        var match = FindInvestigationTool(tools);
        if (match is null || string.IsNullOrWhiteSpace(match.Name))
        {
            var seen = tools is null || tools.Count == 0
                ? "<none>"
                : string.Join(", ", tools.Select(tool => string.IsNullOrWhiteSpace(tool?.Name) ? "<unnamed>" : tool.Name));
            throw new InvalidOperationException(
                "JAWS-TOOLBOX-CALL-003: The request asks for the Investigation toolbox, but this run has no Investigation tool. " +
                $"Tools on the run: {seen}. The container did not offer the toolbox to the model.");
        }

        chat.ChatOptions!.ToolMode = ChatToolMode.RequireSpecific(match.Name);
        Console.Error.WriteLine("JAWS-TOOLBOX-CALL-003: Requiring Investigation tool " + match.Name + ".");
    }

    private static bool RequestsInvestigationDelegation(IEnumerable<ChatMessage>? messages)
    {
        if (messages is null)
        {
            return false;
        }

        foreach (var message in messages)
        {
            var text = message.Text;
            if (string.IsNullOrWhiteSpace(text) && message.Contents is not null)
            {
                text = string.Concat(message.Contents.OfType<TextContent>().Select(content => content.Text));
            }

            if (string.IsNullOrWhiteSpace(text) ||
                text.IndexOf("Investigation", StringComparison.OrdinalIgnoreCase) < 0)
            {
                continue;
            }

            if (text.IndexOf("toolbox", StringComparison.OrdinalIgnoreCase) >= 0 ||
                text.IndexOf("A2A", StringComparison.OrdinalIgnoreCase) >= 0 ||
                text.IndexOf("diagnostic", StringComparison.OrdinalIgnoreCase) >= 0 ||
                text.IndexOf("plan", StringComparison.OrdinalIgnoreCase) >= 0)
            {
                return true;
            }
        }

        return false;
    }

    private static AITool? FindInvestigationTool(IList<AITool>? tools)
    {
        if (tools is null)
        {
            return null;
        }

        AITool? fallback = null;
        foreach (var tool in tools)
        {
            if (tool is null || string.IsNullOrWhiteSpace(tool.Name))
            {
                continue;
            }

            if (tool.Name.Contains("SendMessage", StringComparison.OrdinalIgnoreCase))
            {
                return tool;
            }

            if (fallback is null && tool.Name.Contains("investigation", StringComparison.OrdinalIgnoreCase))
            {
                fallback = tool;
            }
        }

        return fallback;
    }

    private static void ForwardListedTools(AgentRunOptions? options)
    {
        if (options is ChatClientAgentRunOptions chat && chat.ChatOptions?.Tools is { } tools)
        {
            ApplyCallable(tools);
        }
    }

    private static void LogFunctionFailures(IEnumerable<AIContent> contents)
    {
        foreach (var content in contents)
        {
            if (content is FunctionResultContent result && result.Exception is not null)
            {
                Console.Error.WriteLine("JAWS-TOOLBOX-CALL-001: " + result.Exception);
            }
        }
    }

    /// <summary>
    /// Forwards listed metadata for MCP tools in a mixed tool list.
    /// </summary>
    public static int ApplyCallable(IList<AITool> tools)
    {
        ArgumentNullException.ThrowIfNull(tools);
        var patched = 0;
        for (var index = 0; index < tools.Count; index++)
        {
            var tool = tools[index];
            if (tool is null)
            {
                throw new InvalidOperationException("JAWS-TOOLBOX-META-001: Toolbox tool list contains a null entry.");
            }

            if (tool is McpClientTool mcp)
            {
                var forwarded = ForwardListedMetadata(mcp);
                if (ReferenceEquals(forwarded, mcp))
                {
                    continue;
                }

                tools[index] = forwarded;
                patched++;
                continue;
            }

            if (!TryPatchWrapper(tool, out var changed))
            {
                continue;
            }

            if (changed)
            {
                patched++;
            }
        }

        return patched;
    }

    /// <summary>
    /// Replaces each wrapped MCP tool so later invocations send the metadata captured at tools/list.
    /// Fails closed when a discovered tool cannot be patched.
    /// </summary>
    public static int Apply(IEnumerable<object> tools)
    {
        ArgumentNullException.ThrowIfNull(tools);
        var patched = 0;
        foreach (var tool in tools)
        {
            if (tool is null)
            {
                throw new InvalidOperationException("JAWS-TOOLBOX-META-001: Toolbox tool list contains a null entry.");
            }

            if (!TryPatchWrapper(tool, out var changed))
            {
                throw new InvalidOperationException(
                    $"JAWS-TOOLBOX-META-001: {tool.GetType().FullName} has no McpClientTool field, so tools/list metadata cannot be forwarded.");
            }

            if (changed)
            {
                patched++;
            }
        }

        return patched;
    }

    private static bool TryPatchWrapper(object tool, out bool changed)
    {
        changed = false;
        var field = FindMcpClientToolField(tool.GetType());
        if (field is null)
        {
            return false;
        }

        if (field.GetValue(tool) is not McpClientTool inner)
        {
            throw new InvalidOperationException(
                $"JAWS-TOOLBOX-META-001: {tool.GetType().FullName} does not hold an MCP tool instance.");
        }

        var forwarded = ForwardListedMetadata(inner);
        if (ReferenceEquals(forwarded, inner))
        {
            return true;
        }

        field.SetValue(tool, forwarded);
        changed = true;
        return true;
    }

    private static FieldInfo? FindMcpClientToolField(Type type)
    {
        const BindingFlags flags = BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic;
        FieldInfo? only = null;
        for (var current = type; current is not null && current != typeof(object); current = current.BaseType)
        {
            foreach (var field in current.GetFields(flags))
            {
                if (field.FieldType != typeof(McpClientTool))
                {
                    continue;
                }

                if (field.Name == "_inner")
                {
                    return field;
                }

                only = only is null ? field : throw new InvalidOperationException(
                    $"JAWS-TOOLBOX-META-001: {type.FullName} has more than one McpClientTool field.");
            }
        }

        return only;
    }
}
