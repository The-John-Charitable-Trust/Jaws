# Step A — Azure Discovery and Reconciliation (First-Time Reader Guide)

> **Audience:** A new Azure administrator or developer who has never installed JAWS. **Step A is a read-only assessment, not JAWS deployment.** You may start with an empty Azure subscription. The current installer v0.4.6 has an additional *existing-installation reconciliation* function that needs a JAWS state file; **do not copy the developer's state into your subscription**.

## What Step A achieves

Step A establishes your signed-in Azure identity and subscription scope, inventories visible Azure resources, identifies possible existing JAWS resources, and produces an audit-friendly baseline **without creating, updating, or deleting Azure resources**. A clean subscription is a valid starting point, not a test failure. Full JAWS provisioning is an additional installer deliverable and is **not implemented in the current primary installer**.

## Prerequisites

- An active Azure subscription and Microsoft Entra sign-in with at least resource read permission for the intended subscription/resource group. Without access, request a scoped Reader assignment from your Azure administrator. Readers can inspect resources but cannot deploy them.
- Windows 11, PowerShell 7, Git and Azure CLI. Official downloads and version checks: [Quick Start](../status/quick-start.html).
- Internet access for GitHub and Azure management endpoints. **Docker, WSL 2, .NET 10 and Pester 5 are developer/build/test requirements, not necessary to run read-only inventory.**
- For an *existing* JAWS installation only: the matching, operator-owned state file recording subscription, resource group, Foundry resource, Foundry project, model deployment and Key Vault. Do not use the checked-in DEV state for a different subscription.

## Four activities

### 1. Authenticate and verify your Azure scope

Open **PowerShell 7** in a terminal:

```powershell
az login
az account list --query "[].{Name:name,SubscriptionId:id,State:state}" --output table
az account set --subscription "<your-subscription-id>"
az account show --query "{name:name,id:id,tenantId:tenantId}" --output table
```

**Expected result:** Your intended subscription appears as Enabled and `az account show` identifies its tenant and subscription. If access is missing, contact the subscription administrator. These commands do **not** install JAWS.

### 2. Inspect subscriptions and resource inventory

Use the authorized Azure CLI session to list resource groups and (when permitted) resources in **your selected subscription**, even when it is empty.

```powershell
az group list --output table
az resource list --output table
```

**Expected result:** Azure returns the resources visible to your identity, possibly an empty list. Empty inventory is an acceptable Step A discovery finding. This is a manual Azure CLI verification, **not** a claim that the old JAWS state-first installer supports uninitialized customer state.

### 3. Reconcile resources against installation state, if JAWS already exists

For an existing JAWS deployment with its **own verified state file**, run from the checked-out repository root:

```powershell
.\installer\Install-Jaws.ps1 -Mode Discover -EnvironmentName <environment-name> -StateFile "<path-to-your-installation-state.json>"
```

**Expected result:** All enabled, accessible subscriptions in the selected tenant are scanned; matching Foundry resource, project, model deployment and Key Vault are queried. The console prints a tenant comparison and targeted resource status such as `Match` or drift. Model deployments may not appear in a broad candidate scan; targeted discovery is authoritative.

**For a new subscription without JAWS:** Skip the command above. In the current v0.4.6 installer, `Discover` requires an existing state file and will fail with `JAWS-STATE-003` if one is absent. This is a documented product gap, **not an instruction to create imaginary JAWS state or resources**. The future greenfield installer must generate state during approved provisioning.

### 4. Record reports and verify no configuration changes

With an existing state file and successful installer reconciliation, inspect:

- `installer/.local/jaws-tenant-scan.<environment>.generated.json`
- `installer/.local/jaws-resources.<environment>.generated.json`
- `installer/.local/jaws-state-comparison.<environment>.generated.json`

**Expected result:** Reports are generated, the operator-managed state file is unchanged, and the terminal shows `Azure writes: 0`. For a clean subscription, record the subscription/tenant selection and the empty or observed Azure CLI inventory as the Step A **manual discovery baseline**; no JAWS comparison reports exist until a JAWS installation state exists.

## Expected results for completion

| Evidence | Empty customer subscription | Existing JAWS installation |
|---|---|---|
| Identity and subscription | Authorized tenant/subscription confirmed | Confirmed |
| Visible resource inventory | Listed, even when empty | Listed |
| JAWS resource comparison | Not applicable until provisioning | Reported per resource |
| Installation-state file | Not required and not fabricated | Preserved unchanged |
| Azure configuration writes | **Zero** | **Zero** |
| Outcome | **Manual discovery complete; greenfield installer gate remains open** | **Step A installer reconciliation complete when checks match** |

## Step A acceptance criteria

- **A-01 Authentication:** The selected Entra identity and target subscription are explicit; failures are actionable.
- **A-02 Inventory:** All accessible selected-scope resources can be enumerated; empty inventory is valid; unreadable scope is identified rather than silently accepted.
- **A-03 Reconciliation (existing installations):** The correct installation state is matched to subscription/resource group; expected resources are identified; identity/configuration drift is reported. A greenfield customer is **not** required to supply an existing JAWS state.
- **A-04 Read-only guarantee:** No Azure configuration writes; existing gold-copy state remains unchanged.
- **A-05 Evidence:** For existing installations the JAWS reports are produced; for a new empty subscription, manual discovery evidence is recorded until the greenfield installer can generate its own receipts.
- **A-06 Release gate:** Do not label **greenfield Step A installer acceptance** as passed until the new installer can discover and initialize an empty subscription without pre-existing JAWS state and produce a testable installation baseline.

**Acceptance decision:** Existing DEV reconciliation is previously accepted. First-time customer **greenfield automated** Step A is **not yet accepted** under installer v0.4.6.

## References

1. [Azure CLI sign-in](https://learn.microsoft.com/en-us/cli/azure/authenticate-azure-cli-interactively)
2. [Azure RBAC overview](https://learn.microsoft.com/en-us/azure/role-based-access-control/overview)
3. [Azure Resource Graph overview](https://learn.microsoft.com/en-us/azure/governance/resource-graph/overview)
4. [Azure Resource Manager overview](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/overview)
5. [JAWS Quick Start](../status/quick-start.html) · [References and Acceptance](../status/references.html#step-A) · [Manual test cases](../verification/STEP-01-MANUAL-TESTS.md)
