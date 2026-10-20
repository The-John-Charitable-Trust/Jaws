# Step F — Observability agent on Azure MCP

Step F adds one prompt observability agent, `jaws-observability-<environment>`, on the virtual-machine specialist's compute environment. Its Step F grant is Azure Monitor and Microsoft Defender through Azure MCP. The catalog names are `monitor.metrics.query`, `monitor.logs.query`, and `defender.alert.get`. Those names are the JAWS allow-list. They are not a claim that Foundry already has the Azure MCP connection attached.

Install creates the prompt agent when it is missing. It rewrites the specialist catalog so Monitor and Defender leave the virtual-machine specialist. It prints `Mcp connection written: false` and `Live tool call: false`.

Sources: [Azure MCP Server tools](https://learn.microsoft.com/en-us/azure/developer/azure-mcp-server/tools/), [Azure Monitor tools](https://learn.microsoft.com/en-us/azure/developer/azure-mcp-server/tools/azure-monitor), [Microsoft Defender for Cloud](https://learn.microsoft.com/en-us/azure/defender-for-cloud/defender-for-cloud-introduction), [Connect to an MCP server](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/model-context-protocol), and [Azure RBAC](https://learn.microsoft.com/en-us/azure/role-based-access-control/overview).

```powershell
.\installer\Install-JawsStepF.ps1 -Mode Validate -EnvironmentName your-environment
.\installer\Install-JawsStepF.ps1 -Mode Install -EnvironmentName your-environment -AcknowledgeStepFInstall
.\installer\Install-JawsStepF.ps1 -Mode Accept -EnvironmentName your-environment
```

Validate requires a Step E acceptance whose `Result` is `PASS`. Install without `-AcknowledgeStepFInstall` stops at `JAWS-STEP-F-001`. An agent that already exists and is not this read-only prompt stops at `JAWS-STEP-F-018` and is not overwritten. `dev` stops at `JAWS-STEP-F-014`.

Expected on Accept: `STEP-F ACCEPTANCE PASS`, `Live tool call: false`, `Customer installation accepted: false`, `FedRAMP Moderate: false`, `Ready for next step: true`, and `Next step: Step G Validate`.

## Acceptance

- F-00: One prompt observability agent is active. The catalog grants it Azure Monitor and Microsoft Defender and removes those tools from the virtual-machine specialist.
- F-01: The Azure MCP connection is not written by this installer, and Accept does not claim a live query.
- F-02: FedRAMP Moderate stays open while the Foundry account is public. The agent is reached on the virtual network when that account is private. No public specialist URL is created.

## Uninstall to stop charges or start a new install

```powershell
.\installer\Uninstall-Jaws.ps1 -EnvironmentName your-environment -AcknowledgeJawsUninstall
```

Details are in [UNINSTALL.md](UNINSTALL.md).
