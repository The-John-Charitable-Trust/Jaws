using Microsoft.Agents.AI.Foundry.Hosting;
#pragma warning disable MAAI001

namespace Jaws.Supervisor.Host;

/// <summary>
/// Patches toolbox tools after <see cref="FoundryToolboxService"/> has enumerated them.
/// Registered after AddFoundryToolboxes so startup order runs this once the tool list exists.
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
        if (patched == 0)
        {
            _logger.LogWarning(
                "Foundry toolbox tools were enumerated without _meta. tools/call may be rejected by the toolbox proxy.");
        }

        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;
}
