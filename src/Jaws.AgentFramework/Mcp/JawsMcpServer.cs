using System.Text.Json;
using System.Text.Json.Nodes;

namespace Jaws.AgentFramework.Mcp;

/// <summary>
/// Minimal JSON-RPC dispatcher for the local JAWS MCP server. This is the Step
/// 2 foundation: it proves that JAWS has a standards-shaped MCP boundary before
/// operational tools are added. Step 3 hardens this boundary with authentication,
/// authorization, request limits, and approval enforcement.
/// </summary>
public sealed class JawsMcpServer
{
    private const string JsonRpcVersion = "2.0";
    private readonly JawsMcpToolRegistry _registry;

    public JawsMcpServer(JawsMcpToolRegistry registry)
    {
        _registry = registry;
    }

    public JsonObject Handle(JsonElement request)
    {
        var id = TryReadId(request);
        var method = TryReadStringProperty(request, "method");

        return method switch
        {
            "initialize" => Success(id, new JsonObject
            {
                ["protocolVersion"] = "2024-11-05",
                ["serverInfo"] = new JsonObject
                {
                    ["name"] = JawsMcpToolRegistry.ServerName,
                    ["version"] = JawsMcpToolRegistry.Release
                },
                ["capabilities"] = new JsonObject
                {
                    ["tools"] = new JsonObject()
                }
            }),
            "tools/list" => Success(id, new JsonObject
            {
                ["tools"] = new JsonArray(_registry.Tools.Select(ToToolMetadata).ToArray<JsonNode?>())
            }),
            "tools/call" => HandleToolCall(id, request),
            _ => Error(id, -32601, $"Unsupported MCP method '{method ?? "<missing>"}'.")
        };
    }

    private JsonObject HandleToolCall(JsonNode? id, JsonElement request)
    {
        if (!request.TryGetProperty("params", out var parameters))
        {
            return Error(id, -32602, "tools/call requires params.");
        }

        var toolName = TryReadStringProperty(parameters, "name");
        if (string.IsNullOrWhiteSpace(toolName))
        {
            return Error(id, -32602, "tools/call requires params.name.");
        }

        if (!_registry.TryGetTool(toolName, out var tool))
        {
            return Error(id, -32602, $"Unknown MCP tool '{toolName}'.");
        }

        var arguments = parameters.TryGetProperty("arguments", out var argumentElement)
            ? JsonNode.Parse(argumentElement.GetRawText()) as JsonObject
            : null;

        var structuredContent = tool.Invoke(arguments);
        return Success(id, new JsonObject
        {
            ["content"] = new JsonArray
            {
                new JsonObject
                {
                    ["type"] = "text",
                    ["text"] = structuredContent.ToJsonString()
                }
            },
            ["structuredContent"] = structuredContent
        });
    }

    private static JsonObject ToToolMetadata(JawsMcpTool tool) => new()
    {
        ["name"] = tool.Name,
        ["description"] = tool.Description,
        ["inputSchema"] = tool.InputSchema.DeepClone()
    };

    private static JsonObject Success(JsonNode? id, JsonObject result) => new()
    {
        ["jsonrpc"] = JsonRpcVersion,
        ["id"] = id?.DeepClone(),
        ["result"] = result
    };

    private static JsonObject Error(JsonNode? id, int code, string message) => new()
    {
        ["jsonrpc"] = JsonRpcVersion,
        ["id"] = id?.DeepClone(),
        ["error"] = new JsonObject
        {
            ["code"] = code,
            ["message"] = message
        }
    };

    private static string? TryReadStringProperty(JsonElement element, string propertyName)
    {
        return element.ValueKind == JsonValueKind.Object &&
            element.TryGetProperty(propertyName, out var property) &&
            property.ValueKind == JsonValueKind.String
                ? property.GetString()
                : null;
    }

    private static JsonNode? TryReadId(JsonElement request)
    {
        if (request.ValueKind != JsonValueKind.Object ||
            !request.TryGetProperty("id", out var idElement))
        {
            return null;
        }

        return JsonNode.Parse(idElement.GetRawText());
    }
}
