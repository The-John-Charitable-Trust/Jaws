using System.Text.Json.Nodes;

namespace Jaws.AgentFramework.Mcp;

/// <summary>
/// Central registry for the tools exposed by the Step 2 local MCP server.
/// Keeping the registry explicit makes tool extensibility reviewable: every
/// new tool needs a name, description, schema, and handler before it can be
/// surfaced through MCP.
/// </summary>
public sealed class JawsMcpToolRegistry
{
    public const string Release = "0.3";
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
                    ["writeToolsEnabled"] = false,
                    ["securityMode"] = "hardened-local"
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
                    ["tools"] = new JsonArray(
                        "jaws_mcp_status",
                        "jaws_tool_registry")
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
}
