using Azure.AI.Projects;
using Azure.Core;
using Microsoft.Agents.AI;

namespace Jaws.AgentFramework.Agents;

/// <summary>
/// Shared construction point for role-oriented JAWS agents. The same Agent
/// Framework pattern used by FirstAgent is reused here: create an AIProjectClient,
/// convert it to an AIAgent, and apply role-specific instructions from a job
/// description. Later releases attach tools and memory at this boundary.
/// </summary>
public sealed class RoleAgentFactory
{
    private readonly Uri _endpoint;
    private readonly string _deploymentName;
    private readonly TokenCredential _credential;

    public RoleAgentFactory(Uri endpoint, string deploymentName, TokenCredential credential)
    {
        _endpoint = endpoint;
        _deploymentName = deploymentName;
        _credential = credential;
    }

    public AIAgent Create(AgentJobDescription jobDescription)
    {
        var errors = jobDescription.Validate();
        if (errors.Count > 0)
        {
            throw new ArgumentException(string.Join(" ", errors), nameof(jobDescription));
        }

        return new AIProjectClient(_endpoint, _credential)
            .AsAIAgent(
                model: _deploymentName,
                instructions: jobDescription.Instructions,
                name: jobDescription.DisplayName);
    }
}
