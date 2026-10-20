# Step H — Virtual-machine investigation and one approved change

Step H grants the virtual-machine specialist its machine tools and one write. The read tools are the machine, its identity, its network attachments, and Azure Policy: `vm.get`, `vm.identity.get`, `vm.network.get`, and `policy.state.get`. The write is `vm.run-command`, and it requires the `approve-vm-change` workflow. Install records that grant. It does not run the command. Accept prints `Change executed: false`.

Azure Monitor and Microsoft Defender stay on the observability agent from Step F. Datadog and ServiceNow stay on that agent's custom server from Step G.

Sources: [Azure MCP Server tools](https://learn.microsoft.com/en-us/azure/developer/azure-mcp-server/tools/) (the `compute` and `policy` namespaces), [Azure RBAC](https://learn.microsoft.com/en-us/azure/role-based-access-control/overview), [Agent Skills](https://learn.microsoft.com/en-us/agent-framework/agents/skills), and [Agent Framework workflows](https://learn.microsoft.com/en-us/agent-framework/workflows/orchestrations/).

```powershell
.\installer\Install-JawsStepH.ps1 -Mode Validate -EnvironmentName your-environment
.\installer\Install-JawsStepH.ps1 -Mode Install -EnvironmentName your-environment -AcknowledgeStepHInstall
.\installer\Install-JawsStepH.ps1 -Mode Accept -EnvironmentName your-environment
```

Validate requires a Step G acceptance whose `Result` is `PASS`. Install without the acknowledgement stops at `JAWS-STEP-H-001` and executes no change. A catalog that grants the write without `approve-vm-change` stops at `JAWS-CATALOG-005`.

Expected on Accept: `STEP-H ACCEPTANCE PASS`, `Change executed: false`, `Customer installation accepted: false`, `FedRAMP Moderate: false`, `Ready for next step: true`, and `Next step: Step I Validate`.

## Acceptance

- H-00: The virtual-machine specialist's allow-list is the machine, its identity, its network attachments, and Azure Policy, plus `vm.run-command` behind `approve-vm-change`.
- H-01: Accept does not execute a change.
- H-02: Investigation and deliberation remain skills on this specialist. No investigation, deliberation, or remediation agent is created.

## Uninstall to stop charges or start a new install

```powershell
.\installer\Uninstall-Jaws.ps1 -EnvironmentName your-environment -AcknowledgeJawsUninstall
```

Details are in [UNINSTALL.md](UNINSTALL.md).
