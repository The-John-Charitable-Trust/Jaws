# Uninstall a JAWS environment

`installer/Uninstall-Jaws.ps1` hard-deletes one customer environment so the next install of the same names starts empty. It refuses the accepted dev project. It does not recreate resources.

This is not `Install-JawsFoundryPrivateNetwork.ps1`. That script is deprecated. It deletes a Foundry account and recreates it with network injection while public network access stays enabled. Do not run it. Uninstall stops after the delete. A private-profile gateway and DNS resolver are deleted before the virtual network.

## Command

When the Step B receipt is still present, the receipt supplies the subscription, resource group, location, Foundry account, project, and Key Vault:

```powershell
.\installer\Uninstall-Jaws.ps1 -EnvironmentName your-environment -AcknowledgeJawsUninstall
```

Without that receipt, pass the same names yourself:

```powershell
.\installer\Uninstall-Jaws.ps1 `
  -EnvironmentName your-environment `
  -SubscriptionId <subscription-id> `
  -ResourceGroupName rg-jaws-your-environment `
  -Location eastus `
  -FoundryAccountName jaws-foundry-your-environment `
  -ProjectName jaws-your-environment `
  -KeyVaultName <vault-name> `
  -AcknowledgeJawsUninstall
```

`-AcknowledgeJawsUninstall` is required. Without it the command stops at `JAWS-UNINSTALL-001` and calls no Azure command. A parameter that disagrees with the Step B receipt stops at `JAWS-UNINSTALL-005` and deletes nothing. A missing subscription, resource group, or location stops at `JAWS-UNINSTALL-002`. Environment name `dev`, resource group `rg-aiops-lab`, and the reserved dev names `jaws-foundry-dev`, `jaws-dev`, `jawsregistrydev001`, `jaws-supervisor-dev`, and `kv-jaws-dev-001` stop at `JAWS-UNINSTALL-006`.

## Delete order

The command deletes the resources each installed step creates. Steps A, E, F, G, H, and I create no Azure resources. A later resource placed in this resource group or on this Foundry project is deleted by the same sweep.

| Step | What is deleted |
| --- | --- |
| B | Resource group, Foundry account and its purge, project, model deployment, Key Vault and its purge, container registry and the Supervisor image, AcrPull role assignments, and every Supervisor agent version. |
| C | Investigation planner agent, RemoteA2A connection, investigation toolbox, later Supervisor versions, and the Foundry Agent Consumer role assignment at project scope. |
| D | Virtual-machine specialist agent, browser virtual network and both subnets, Container Apps environment, browser Container App, browser image, browser toolbox, browser Key Vault secrets, later Supervisor versions, and the specialist AcrPull and Key Vault roles. |
| Datadog tag | The `jaws-datadog-default` tag. A virtual machine inside the environment resource group is deleted with that group. A virtual machine outside the group, including `jaws-stepb-test`, is left in place and only loses that tag. |

Order of the Azure calls:

1. Every Foundry agent on the project, with `DELETE .../agents/{name}?api-version=v1&force=true`. This covers the Supervisor, the investigation planner, and the virtual-machine specialist.
2. Every toolbox and every connection on that project.
3. Every model deployment on the Foundry account, then every project, then the account, then `az cognitiveservices account purge`.
4. Container apps, then their managed environments.
5. Resource locks in the group.
6. Role assignments whose scope is the resource group or a resource inside it. An assignment inherited from the subscription is left.
7. Every remaining resource in the group, children before parents: container apps, virtual machines, managed environments, private endpoints, network interfaces, the Foundry account if a record remains, Key Vaults, the virtual network, then the container registry. Another Foundry account found in the group is deleted and purged as well.
8. Each Key Vault name: delete, then purge.
9. The `jaws-datadog-default` tag when the recorded virtual machine is outside this resource group.
10. The resource group. The command polls `az group exists` until the group is gone. If it is still present, the command stops at `JAWS-UNINSTALL-011`.
11. Files under `installer/.local` whose names contain `.<environment>.`, except the uninstall receipt itself. That removes the Step A, B, C, and D receipts for this environment.

## Why agents are force-deleted first

On 20 October 2026 the resource group `rg-aiops-lab-test2` was deleted and the soft-deleted Foundry account `jaws-foundry-aiops-lab-test2` was purged. Both operations succeeded, and the replacement account write was Created. When the same account and project names were created again, the Foundry data plane still returned agent versions dated 19 October 2026. Ordinary ARM resources, including the registry contents, the virtual network, and the browser Container App, did not return. Force-deleting the agents before the account is removed is how this command addresses that. This script has not been executed against the live `aiops-lab-test2` environment. If a later recreate still restores agents after this force-delete and purge, that remaining behavior is a platform limit and must be recorded rather than treated as a clean install.

## Key Vault purge protection

A vault with purge protection cannot be purged before its scheduled date. Uninstall records `Key Vault purge: blocked` and `Key Vault purge not before`, then continues and still deletes the resource group. The next install must use a different Key Vault name until that date. A vault that was not present is recorded as `absent`. A vault that purge accepted is recorded as `purged`.

On 20 October 2026, no live JAWS resource remains in subscription `c52f597b-7753-45b4-a764-67e290dcfd5e`. Four JAWS Key Vault names are still soft-deleted. Azure will not purge them early, and each name stays reserved until its scheduled purge.

| Name | Deleted (UTC) | Scheduled purge (UTC) | Why it stays |
| --- | --- | --- | --- |
| `kv-jaws-lab-test2` | 2026-10-20T22:06:00Z | 2027-01-18T22:06:00Z | Purge protection. Deleted today. |
| `kv-jaws-dev-001` | 2026-10-20T22:05:39Z | 2027-01-18T22:05:39Z | Purge protection. Deleted today. The installer also refuses this reserved dev name with `JAWS-STEP-B-017`. |
| `kvjawsaiopslabtest2` | 2026-10-20T04:29:10Z | 2027-01-18T04:29:10Z | `DeletedVaultPurge`, the same refusal recorded in October. |
| `kvjawsaiopslabtest` | 2026-10-19T00:22:58Z | 2027-01-17T00:22:58Z | `DeletedVaultPurge`, the same refusal recorded in October. |

Azure auto-purges `kvjawsaiopslabtest` on 17 January 2027 and the other three on 18 January 2027. These four soft-deleted names are the only JAWS resources left in the subscription. Pass `-KeyVaultName` with a name that is not in this list.

## What is left unchanged

- `installer/config/jaws-installation-state.dev.json`. If that file changes, Uninstall stops at `JAWS-UNINSTALL-012`.
- Resources outside the environment resource group, except the `jaws-datadog-default` tag on the recorded Datadog host.
- The operator machine `jaws-stepb-test`. Uninstall does not delete that virtual machine. If it carries `jaws-datadog-default`, only that tag is removed.

## Receipt

`installer/.local/jaws-uninstall.<environment>.generated.json`

A pass prints `JAWS UNINSTALL PASS`, `Resource group deleted: true`, and `Customer installation accepted: false`. The milestone line is `Ready for next step: true` and `Next step: Step B Plan`. That ready line means the environment was removed. It does not accept a customer installation.

Run this only when that environment should be destroyed. `rg-aiops-lab-test2` has already been deleted. The four soft-deleted Key Vault names above are what remains of JAWS in the subscription.
