using System.Text.Json.Nodes;

namespace Jaws.AgentFramework.Mcp;

/// <summary>
/// Describes one JAWS MCP tool. Step 2 keeps the contract small and explicit:
/// a tool has a name, human-readable description, JSON input schema, and a
/// local handler. Later releases bind tools to provider adapters such as Azure,
/// Datadog, and ServiceNow.
/// </summary>
public sealed record JawsMcpTool(
    string Name,
    string Description,
    JsonObject InputSchema,
    bool IsWriteTool,
    Func<JsonObject?, JsonObject> Invoke);
