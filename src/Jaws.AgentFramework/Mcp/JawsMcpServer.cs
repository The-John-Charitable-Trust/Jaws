using System.Text.Json;
using System.Text.Json.Nodes;

namespace Jaws.AgentFramework.Mcp;

/// <summary>
/// Minimal JSON-RPC dispatcher for the local JAWS MCP server. This is the Step
/// 2 foundation: it proves that JAWS has a standards-shaped MCP boundary before
/// operational tools are added. Step 3 hardens this local boundary with request
/// validation, safe errors, schema checks, and read/write tool separation.
/// </summary>
public sealed class JawsMcpServer
{
    private const string JsonRpcVersion = "2.0";
    private readonly JawsMcpToolRegistry _registry;
    private readonly bool _writeToolsEnabled;

    public JawsMcpServer(JawsMcpToolRegistry registry, bool writeToolsEnabled = false)
    {
        _registry = registry;
        _writeToolsEnabled = writeToolsEnabled;
    }

    public JsonObject Handle(JsonElement request)
    {
        var correlationId = Guid.NewGuid().ToString("N");

        if (request.ValueKind != JsonValueKind.Object)
        {
            return Error(null, -32600, "Invalid MCP request.", correlationId);
        }

        var id = TryReadId(request);
        var method = TryReadStringProperty(request, "method");

        if (TryReadStringProperty(request, "jsonrpc") is not JsonRpcVersion)
        {
            return Error(id, -32600, "Invalid MCP request.", correlationId);
        }

        if (string.IsNullOrWhiteSpace(method))
        {
            return Error(id, -32600, "Invalid MCP request.", correlationId);
        }

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
            "tools/call" => HandleToolCall(id, request, correlationId),
            _ => Error(id, -32601, "Unsupported MCP method.", correlationId)
        };
    }

    private JsonObject HandleToolCall(JsonNode? id, JsonElement request, string correlationId)
    {
        if (!request.TryGetProperty("params", out var parameters))
        {
            return Error(id, -32602, "Invalid tool call request.", correlationId);
        }

        var toolName = TryReadStringProperty(parameters, "name");
        if (string.IsNullOrWhiteSpace(toolName))
        {
            return Error(id, -32602, "Invalid tool call request.", correlationId);
        }

        if (!_registry.TryGetTool(toolName, out var tool))
        {
            return Error(id, -32602, "Unknown MCP tool.", correlationId);
        }

        if (tool.IsWriteTool && !_writeToolsEnabled)
        {
            return Error(id, -32050, "Write-capable MCP tool denied.", correlationId);
        }

        var arguments = parameters.TryGetProperty("arguments", out var argumentElement)
            ? JsonNode.Parse(argumentElement.GetRawText()) as JsonObject
            : null;

        if (!ArgumentsMatchSchema(tool, arguments))
        {
            return Error(id, -32602, "Tool arguments failed validation.", correlationId);
        }

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
        ["inputSchema"] = tool.InputSchema.DeepClone(),
        ["annotations"] = new JsonObject
        {
            ["readOnlyHint"] = !tool.IsWriteTool,
            ["destructiveHint"] = tool.IsWriteTool
        }
    };

    private static JsonObject Success(JsonNode? id, JsonObject result) => new()
    {
        ["jsonrpc"] = JsonRpcVersion,
        ["id"] = id?.DeepClone(),
        ["result"] = result
    };

    private static JsonObject Error(JsonNode? id, int code, string message, string correlationId) => new()
    {
        ["jsonrpc"] = JsonRpcVersion,
        ["id"] = id?.DeepClone(),
        ["error"] = new JsonObject
        {
            ["code"] = code,
            ["message"] = message,
            ["data"] = new JsonObject
            {
                ["correlationId"] = correlationId
            }
        }
    };

    private static bool ArgumentsMatchSchema(JawsMcpTool tool, JsonObject? arguments)
    {
        arguments ??= new JsonObject();

        var additionalPropertiesAllowed = tool.InputSchema["additionalProperties"]?.GetValue<bool>() ?? true;
        if (additionalPropertiesAllowed)
        {
            return true;
        }

        var properties = tool.InputSchema["properties"] as JsonObject ?? new JsonObject();
        var allowedNames = properties.Select(property => property.Key).ToHashSet(StringComparer.Ordinal);

        return arguments.All(argument => allowedNames.Contains(argument.Key));
    }

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
