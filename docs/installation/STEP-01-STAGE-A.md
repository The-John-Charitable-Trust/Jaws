# Step A — Read-only discovery

Step A inventories one Azure subscription. It does not create a resource group, adopt resources, or rewrite an installation state file.

Microsoft's [Azure Resource Graph](https://learn.microsoft.com/en-us/azure/governance/resource-graph/overview) is the inventory source. The installer runs that query through the [Azure CLI](https://learn.microsoft.com/en-us/azure/governance/resource-graph/first-query-azurecli). The signed-in identity needs `Microsoft.ResourceGraph/resources/read` on the selected subscription. The built-in [Reader](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles#reader) role includes that action. A denied query reports the missing action, role, and subscription scope.

## Acceptance criteria

- Read-only discovery succeeds without a JAWS state file.
- Resource Graph rows in the selected subscription stay **Unclaimed**. A matching name is not adoption.
- When `-StateFile` is supplied, each named resource is compared with Azure. Identity drift stops the run before the manifest is rewritten.
- Azure writes stay at 0, and Discover does not create or rewrite the state file.

A missing Resource Graph row does not prove a resource is absent. Targeted reads are authoritative when a state file names the resource.

## Discover a subscription

From the repository root, in PowerShell 7:

```powershell
az login
.\installer\Install-Jaws.ps1 -Mode Discover -SubscriptionId <your-subscription-id> -NonInteractive
```

Leave `-ResourceGroupName` unset to inventory the subscription. Pass an existing resource group to mark that group in scope. Discover does not create a resource group.

The report is `installer/.local/jaws-step-a-discovery.<environment>.generated.json`. Outcome `NoInstallationState` means no state file was supplied. Every inventory row has `Adoption` `Unclaimed` and `AzureWrites` is 0.

## Validate the report

This reads the report. It does not call Azure.

```powershell
.\installer\Test-JawsStepADiscovery.ps1 -ReportPath .\installer\.local\jaws-step-a-discovery.selected.generated.json
```

`STEP-A PASS` requires Outcome `NoInstallationState`, `AzureWrites` 0, `InstallationStateCreated` false, and every row `Unclaimed`. `JAWS-STEP-A-001` means the report is missing and is not a pass. `JAWS-STEP-A-002` means Outcome `Drift`. `JAWS-STEP-A-003` means a write, an adopted row, or another outcome that fails the criteria.

The same checks are on the [manual verification page](../verification/index.html). A Discover command that has not been run against Azure is BLOCKED, not passed.

Do not pass `installer/config/jaws-installation-state.dev.json` for a subscription other than the development project. That file is not loaded unless `-StateFile` points at it.

## Reconcile an existing state file

```powershell
.\installer\Install-Jaws.ps1 -Mode Discover -StateFile .\installer\config\jaws-installation-state.dev.json -NonInteractive
```

The state file selects the subscription and resource group. The installer compares its Foundry account, project, model deployment, and Key Vault with Azure, then queries Resource Graph for the same subscription. Outcome `Reconciled` means every named resource matched. Outcome `Drift` means a targeted read disagreed. `JAWS-STATE-008` means an identity mismatch; the state file and manifest are left unchanged.

This command does not install JAWS. Provisioning remains a later step.
