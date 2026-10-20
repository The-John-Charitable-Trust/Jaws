# Uninstall a JAWS environment

`installer/Uninstall-Jaws.ps1` hard-deletes one customer environment so the next install of the same names starts empty. It refuses the accepted dev project. It does not recreate resources.

This is not `Install-JawsFoundryPrivateNetwork.ps1`. That script deletes a Foundry account and recreates it with network injection while public network access stays enabled. Do not run it. Uninstall stops after the delete.

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

1. Every Foundry agent on the project, with `DELETE .../agents/{name}?api-version=v1&force=true`.
2. Every toolbox and every connection on that project.
3. The Foundry project.
4. The Foundry account, then `az cognitiveservices account purge` in the environment location.
5. Container apps in the resource group, then their managed environments.
6. The environment Key Vault: delete, then purge.
7. The resource group. The command polls `az group exists` until the group is gone. If it is still present, the command stops at `JAWS-UNINSTALL-011`. Foundry agents have already been deleted at that point.
8. Files under `installer/.local` whose names contain `.<environment>.`, except the uninstall receipt itself.

A virtual machine inside that resource group is deleted with the group. That includes a Datadog Agent host created in the environment resource group. Virtual machines outside the group are left in place. `jaws-stepb-test` in `rg-jaws-stepb-test` is outside `rg-aiops-lab-test2` and is not deleted.

## Why agents are force-deleted first

On 20 October 2026 the resource group `rg-aiops-lab-test2` was deleted and the soft-deleted Foundry account `jaws-foundry-aiops-lab-test2` was purged. Both operations succeeded, and the replacement account write was Created. When the same account and project names were created again, the Foundry data plane still returned agent versions dated 19 October 2026. Ordinary ARM resources, including the registry contents, the virtual network, and the browser Container App, did not return. Force-deleting the agents before the account is removed is how this command addresses that. This script has not been executed against the live `aiops-lab-test2` environment. If a later recreate still restores agents after this force-delete and purge, that remaining behavior is a platform limit and must be recorded rather than treated as a clean install.

## Key Vault purge protection

A vault with purge protection cannot be purged before its scheduled date. Uninstall records `Key Vault purge: blocked` and `Key Vault purge not before`, then continues and still deletes the resource group. The next install must use a different Key Vault name until that date. The generated name `kvjawsaiopslabtest2` is purge-protected until `2027-01-18T04:29:10Z`. The vault the current test install uses is `kv-jaws-lab-test2`. A vault that was not present is recorded as `absent`. A vault that purge accepted is recorded as `purged`.

## What is left unchanged

- `installer/config/jaws-installation-state.dev.json`. If that file changes, Uninstall stops at `JAWS-UNINSTALL-012`.
- Resources outside the environment resource group.
- The operator machine `jaws-stepb-test`.

## Receipt

`installer/.local/jaws-uninstall.<environment>.generated.json`

A pass prints `JAWS UNINSTALL PASS`, `Resource group deleted: true`, and `Customer installation accepted: false`. The milestone line is `Ready for next step: true` and `Next step: Step B Plan`. That ready line means the environment was removed. It does not accept a customer installation.

Run this only when that environment should be destroyed. The current `aiops-lab-test2` resources are the Step D install under test. Do not point this command at that environment unless the intent is to delete it.
