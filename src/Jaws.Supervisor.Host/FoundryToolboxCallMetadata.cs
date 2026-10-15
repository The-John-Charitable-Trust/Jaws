using System.Reflection;
using System.Text.Json.Nodes;
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

            var field = FindMcpClientToolField(tool.GetType());
            if (field is null)
            {
                throw new InvalidOperationException(
                    $"JAWS-TOOLBOX-META-001: {tool.GetType().FullName} has no McpClientTool field, so tools/list metadata cannot be forwarded.");
            }

            if (field.GetValue(tool) is not McpClientTool inner)
            {
                throw new InvalidOperationException(
                    $"JAWS-TOOLBOX-META-001: {tool.GetType().FullName} does not hold an MCP tool instance.");
            }

            var forwarded = ForwardListedMetadata(inner);
            if (ReferenceEquals(forwarded, inner))
            {
                continue;
            }

            field.SetValue(tool, forwarded);
            patched++;
        }

        return patched;
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
