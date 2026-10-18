# JAWS installation implementation roadmap

**Baseline:** 15 October 2026. **Authority:** Microsoft Learn / Microsoft technical documentation for product capabilities and best practices; checked-in code and acceptance receipts for actual JAWS implementation state.

This is the **installation and architecture track (Steps A onward)**, not the separate legacy [Agent Framework tutorial track](../agent-framework-track.md) (Steps 1–10). Steps A and C are accepted for the dev project. Step B and Step D have installers. A fresh-subscription receipt is not recorded for either, so neither is accepted. Steps E–I are not implemented.

## Approved end state

An operator converses with the Supervisor in Microsoft Teams. The Supervisor is the proxy to the specialist agents. It does not call Azure or observability products itself. The planned routing contract is a versioned JSON catalog that the Supervisor loads from the project. `RoleAgentCatalog` in `src/Jaws.AgentFramework/Agents/RoleAgentCatalog.cs` is the older tutorial scaffold (Support, Governance, Deploy, Workflow). It is not this catalog, and `SpecialistCatalog.cs` is not in the repository.

- One specialist is one agent. That agent investigates, deliberates, and remediates its own job. Investigation, deliberation, and remediation are not separate agents.
- A tool is one callable action. A skill is a versioned procedure the specialist loads when the task matches. A skill does not create an agent. Investigation and deliberation are skills. An approved change is a workflow: it checks identity, the operator's RBAC, and a human approval, then calls one write tool. Acceptance does not depend on the Foundry Skills API preview. The same `SKILL.md` files ship with the specialist.
- The virtual-machine specialist owns one compute environment for development, configuration, and remediation. It is a hosted agent. Hosted `jaws-investigation-dev` is the starting point for this specialist. The Step C prompt planner remains the planning callee and is not this specialist. The virtual-machine specialist's Azure MCP allow-list is the tools for one virtual-machine security incident: the machine and its identity, its network attachments, Azure Policy and Microsoft Defender evidence, and the metrics and logs for that machine. It does not receive the entire Azure MCP catalog. Investigation runs read-only.
- The observability specialist is a prompt agent. It uses that same compute environment through one custom MCP server. There is no Datadog agent and no second sandbox. The server is stateless and scales by adding replicas. Each product action is a compiled module named by a JSON manifest. The manifest selects a module and a secret name. It cannot add an arbitrary URL or a script. Enabling a tool on the server does not grant it to every agent. The specialist's `allowedTools` list is the grant. The first modules are Datadog, Azure Monitor, Azure Sentinel, and ServiceNow incident records.
- A later specialist, including Azure network, Azure storage, and ServiceNow change or request fulfillment, is another catalog entry. Those specialists are not gates in Steps D–I. A prompt specialist does not need a new container. Loading a valid catalog entry does not require a new Supervisor image.
- Every specialist acts only within the RBAC role of the operator who started the Teams conversation. A missing role denies the call. It is not a prompt to grant a broader role.
- Teams conversations are categorized by project. One project has many conversations, and each conversation belongs to one project. The conversation stores that thread, including tool calls and approvals. The project record stores the durable shared facts: incident, machine, decisions, approvals, and evidence citations. A new conversation in the same project starts from that record. A conversation from another project is not returned. Foundry long-term memory is preview and is reserved for one operator's preferences. It is not the incident record, and acceptance does not depend on it.

## Extension contract

Recorded 18 October 2026. Step D writes `installer/.local/jaws-specialist-catalog.<environment>.generated.json` and can create one hosted virtual-machine specialist. The custom MCP server, skill files, and Steps E–I are not implemented. A stub or local catalog is not a fresh-subscription receipt.

A specialist entry names the Foundry agent, `prompt` or `hosted`, the model, instructions, skill names, one MCP server, an allow-list of tool names, and whether writes require approval:

```json
{
  "id": "observability",
  "foundryAgentName": "jaws-observability",
  "kind": "prompt",
  "skills": ["correlate-incident-signals"],
  "mcpServer": "jaws-observability",
  "allowedTools": ["datadog.metrics.query", "monitor.metrics.query", "sentinel.incidents.query", "servicenow.incident.update"],
  "writesRequireApproval": true
}
```

A custom MCP manifest entry names a tool, the compiled module that implements it, whether it is read-only, and the secret it may use:

```json
{
  "name": "datadog.metrics.query",
  "module": "Datadog",
  "readOnly": true,
  "secret": "datadog-api-key"
}
```

The Supervisor refuses a catalog that names an unknown tool, splits one job into phase agents, or grants a write without the approval workflow. The MCP server refuses a manifest entry whose module is not in the build.

| Step | Installation milestone | Current status | Intended deliverable and acceptance gate | Microsoft Learn / technical documentation source |
|---|---|---|---|---|
| **A — Discover and reconcile** | Read-only Azure authentication, inventory and optional existing-state reconciliation | **Greenfield Discover implemented; fresh-subscription receipt not yet recorded. Existing DEV reconciliation remains the accepted evidence.** | Installer 0.4.10 Discover inventories an empty subscription, writes a receipt, and does not create resources or a state file. | [Azure Resource Graph overview](https://learn.microsoft.com/en-us/azure/governance/resource-graph/overview); [Azure CLI overview](https://learn.microsoft.com/en-us/cli/azure/) |
| **B — Foundry foundation and packaging** | Verify/provision approved Foundry project, model, ACR, identities and installer-gated hosting | **Preflight and acceptance commands exist; fresh-subscription receipt not yet recorded** | Preflight blocks the first write until providers, resource write, and AcrPull assignment rights are present. Install builds the Supervisor image with `az acr build` for `linux/amd64` and pins the registry digest. Accept re-reads an active digest-pinned Supervisor. The plan digest binds names and model, not an unbounded cost. | [Deploy a hosted agent](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/deploy-hosted-agent); [Host Agent Framework agents in Foundry](https://learn.microsoft.com/en-us/azure/foundry/how-to/develop/framework-hosted-agents) |
| **C — Investigation planning delegation** | Supervisor to Investigation Planner through secured RemoteA2A toolbox | **CLOSED on the dev project. The Step B environment path is implemented; a fresh-subscription functional receipt is not recorded.** | Dev: Supervisor v5 delegates to prompt planner v1 and receives a completed read-only plan. Supervisor v1 and hosted Investigation stay unchanged. A Step B environment uses `Install-JawsThroughStepC.ps1 -EnvironmentName` to configure the prompt planner and RemoteA2A connection from that receipt. This planner is not the end-state worker. Accepted dev merge: PR #1 / `099e1818a3fb`. | [A2A endpoint integration](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/agent-to-agent); [Toolbox integration for hosted agents](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/use-toolbox-hosted-agent) |
| **D — Virtual-machine specialist and compute** | JSON catalog, one hosted virtual-machine specialist, and the compute environment it owns | **Installer implemented; fresh-subscription receipt not recorded** | `installer/Install-JawsStepD.ps1` Validate, Install, and Accept. Validate is read-only. Install creates `jaws-vm-specialist-<environment>` from the Step B image only after `-AcknowledgeStepDInstall`. The dev project binds the existing `jaws-investigation-dev` and does not post a second agent. The catalog refuses an unknown tool, a phase id, a second compute environment, and `vm.run-command` without `approve-vm-change`. A prompt specialist may share that compute id. Accept re-reads the hosted agent. The Supervisor image is not changed to load the catalog, and Step E is not installable. Each command prints `Result`, `Ready for next step`, `Next step`, and `Evidence`. | [Deploy a hosted agent](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/deploy-hosted-agent); [Host Agent Framework agents in Foundry](https://learn.microsoft.com/en-us/azure/foundry/how-to/develop/framework-hosted-agents); [Foundry agents REST](https://learn.microsoft.com/en-us/rest/api/aifoundry/project/agents) |
| **E — Azure MCP investigation** | Allow-listed Azure MCP tools on the virtual-machine specialist | **Planned** | The same specialist loads the investigation skill and returns cited evidence for one virtual machine through the allow-listed Azure MCP tools. A tool outside that list, and a call outside the operator's RBAC role, are denied. | [Azure MCP Server tools](https://learn.microsoft.com/en-us/azure/developer/azure-mcp-server/tools/); [Connect agents to MCP server endpoints](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/model-context-protocol); [Azure RBAC overview](https://learn.microsoft.com/en-us/azure/role-based-access-control/overview) |
| **F — Deliberation and remediation** | Deliberation skill and one approval workflow on the same virtual-machine specialist | **Planned** | The deliberation skill compares options and names the exact change. The workflow checks identity, RBAC, and human approval before the write tool runs, then records execution, validation, and recovery. No deliberation or remediation agent is introduced. | [Agent Skills](https://learn.microsoft.com/en-us/agent-framework/agents/skills); [Agent Framework workflows](https://learn.microsoft.com/en-us/agent-framework/workflows/orchestrations/); [Azure RBAC overview](https://learn.microsoft.com/en-us/azure/role-based-access-control/overview) |
| **G — Observability specialist** | One extensible custom MCP server and one prompt specialist | **Planned** | The Supervisor delegates observability work to the catalog entry. The specialist uses the virtual-machine compute environment. Its allow-list is Datadog, Azure Monitor, Azure Sentinel, and ServiceNow incident tools published by compiled modules. A manifest entry for a module that is not in the build is refused. The specialist does not exceed the operator's RBAC role and does not receive its own sandbox. | [Model Context Protocol in Foundry](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/model-context-protocol); [Adding tools](https://learn.microsoft.com/en-us/agent-framework/journey/adding-tools) |
| **H — Teams projects and conversations** | Operator channel, conversation history, and the project record | **Planned** | The operator converses with the Supervisor in Teams. Each conversation belongs to one project and retains that thread. The project record retains the incident, decisions, approvals, and citations for a new conversation in the same project. A conversation from another project is not returned. The operator's RBAC role is the role both agents are checked against. Personal preferences stay with that operator. | [Microsoft Teams developer documentation](https://learn.microsoft.com/en-us/microsoftteams/platform/); [Foundry conversations](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/runtime-components); [Foundry agent memory](https://learn.microsoft.com/en-us/azure/ai-foundry/agents/concepts/what-is-memory) |
| **I — End-to-end acceptance** | One virtual-machine security incident across the finished path | **Planned** | From one Teams conversation, the Supervisor delegates the incident to the virtual-machine specialist and observability work to the observability specialist. Both use the one compute environment and their allow-lists. Evidence and any change stay within the operator's role and the approval workflow. The conversation remains under its project, and a second conversation in that project can name the incident, the last decision, and the last citation. | [Azure Well-Architected Framework](https://learn.microsoft.com/en-us/azure/well-architected/); [Azure RBAC overview](https://learn.microsoft.com/en-us/azure/role-based-access-control/overview) |

## Step C final architecture and evidence

`jaws-supervisor-dev` v5 -> `jaws-investigation-a2a-dev` (`AgenticIdentityToken`, RemoteA2A) -> toolbox `jaws-investigation-a2a-tools` v2 -> `jaws-investigation-planner-dev` prompt agent v1. The standalone hosted `jaws-investigation-dev` v1 remains in place but **did not execute** the Step C A2A task. Hosted-agent A2A `SendMessage` returned `HOSTED_AGENT_NOT_SUPPORTED`; this is why the approved A2A callee is the prompt planner.

Acceptance, as reported in the Step C closure: Supervisor v5 immutable image `sha256:86c556fff7f54eb8ad81c84bc768093fd7bc083e941e9e16bbf1ea8bc0cfa289`; response `caresp_0ca3823766edf3dc00biTZLQVBWJSTvfc8sy4PrBBEV9zGJyvB`; A2A task `TASK_STATE_COMPLETED`. The operator check for that project is `installer/Install-JawsThroughStepC.ps1 -Mode Validate`. The functional test of the delegation is the same command with `-AcknowledgeInferenceCharges` (model usage, no Azure configuration writes). `-Mode Install -AcknowledgeStepCInstall` repairs one known gap per gate and is not required when Validate is already clean. [Closure commit](https://github.com/The-John-Charitable-Trust/Jaws/commit/401c7af751906a47c6d42cd0ffc1f473ad37f320); [merged PR #1](https://github.com/The-John-Charitable-Trust/Jaws/pull/1); runbook: [STEP-C-RUNBOOK.md](STEP-C-RUNBOOK.md).

The same entry point accepts `-EnvironmentName` and reads the Step B receipt for that environment. It configures `jaws-investigation-planner-<environment>` and RemoteA2A connection `jaws-investigation-a2a-<environment>`. It does not call the dev project. Offline Pester covers that path with a CLI stand-in. A fresh-subscription `TASK_STATE_COMPLETED` receipt has not been recorded, so that path is not accepted.

**Do not** interpret Step C closure, or a Step D stub pass, as proof of the end state. Step D can record the catalog and one hosted specialist. Azure MCP, deliberation, remediation, the observability specialist, and Teams are Steps E–I and are not installable.

## Documentation ownership and maintenance

- **This file:** authoritative installation milestone map, statuses and Microsoft source column.
- [Standard installer guide](standard/index.html): operator actions and expected results.
- [Developer/Tester guide](developer/index.html): code, tests, diagnostics and evidence.
- [Step C delegation details](STEP-C-DELEGATION.md): accepted A2A architecture and limitations.
- [Agent Framework tutorial](../tutorial/index.html): separate older numbered educational sequence; not the installation phase register.

Before beginning any planned step: check current Microsoft Learn guidance and applicable SDK versions, specify testable acceptance criteria, preserve plan/approval gates, and update this roadmap only after evidence-backed acceptance. A listed Microsoft source supports the **design approach**, not an assertion that JAWS implemented that capability.
