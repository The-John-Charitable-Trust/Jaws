using Microsoft.Agents.AI.Foundry.Hosting;
using Microsoft.Extensions.AI;
#pragma warning disable MAAI001

namespace Jaws.Supervisor.Host;

/// <summary>
/// Patches toolbox tools after <see cref="FoundryToolboxService"/> has enumerated them.
/// Tools created later, during a deferred per-request retry, are patched by
/// <see cref="FoundryToolboxCallMetadata.ForwardBeforeInvocation"/> before that run.
/// </summary>
internal sealed class FoundryToolboxMetadataStartup : IHostedService
{
    private readonly FoundryToolboxService _toolboxes;
    private readonly ILogger<FoundryToolboxMetadataStartup> _logger;

    public FoundryToolboxMetadataStartup(
        FoundryToolboxService toolboxes,
        ILogger<FoundryToolboxMetadataStartup> logger)
    {
        _toolboxes = toolboxes;
        _logger = logger;
    }

    public Task StartAsync(CancellationToken cancellationToken)
    {
        var tools = _toolboxes.Tools;
        if (tools.Count == 0)
        {
            _logger.LogInformation(
                "No Foundry toolbox tools were enumerated at startup. Metadata forwarding had nothing to patch.");
            return Task.CompletedTask;
        }

        var patched = FoundryToolboxCallMetadata.Apply(tools);
        _logger.LogInformation(
            "Forwarded tools/list metadata onto {Patched} of {Total} Foundry toolbox tool(s).",
            patched,
            tools.Count);
        foreach (var tool in tools)
        {
            if (tool is not AIFunction function)
            {
                continue;
            }

            var schema = function.JsonSchema.ValueKind == System.Text.Json.JsonValueKind.Undefined
                ? ""
                : function.JsonSchema.GetRawText();
            _logger.LogInformation("Toolbox tool {Name} input schema: {Schema}", function.Name, schema);
        }
        if (patched == 0)
        {
            _logger.LogWarning(
                "Foundry toolbox tools were enumerated without _meta. tools/call may be rejected by the toolbox proxy.");
        }

        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;
}
