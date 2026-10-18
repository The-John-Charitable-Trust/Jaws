# Step A — Azure discovery for a new subscription

Step A is read-only. Installer 0.4.10 can start from an empty subscription. It checks the signed-in identity, inventories that subscription, and writes a discovery receipt. It does not create a resource group, a Foundry account, or a JAWS state file.

An existing JAWS installation can still be reconciled with its own state file. Do not point that command at `installer/config/jaws-installation-state.dev.json` unless you are checking the accepted dev project.

## Prerequisites

- PowerShell 7 and Azure CLI.
- An enabled subscription selected with `az account set`.
- Reader on that subscription is enough for discovery. Install of Step B needs more, and preflight checks that later.

## A1. Discover an empty subscription

```powershell
git clone --branch main https://github.com/The-John-Charitable-Trust/Jaws.git
Set-Location .\Jaws
az login
az account set --subscription "<your-subscription-id>"
.\installer\Install-Jaws.ps1 -Mode Discover -NonInteractive -EnvironmentName your-environment -ResourceGroupName rg-jaws-your-environment -Location eastus
.\installer\Test-JawsStepA.ps1 -ReportPath .\installer\.local\jaws-step-a-discovery.your-environment.generated.json
```

**Expected result.** `Install-Jaws.ps1` prints:

```text
STEP-A DISCOVERY PASS
Discovery: Greenfield
Subscription source: AzureCli
Resource groups: 0
Resources: 0
JAWS candidates: 0
State file required: false
State file written: false
Azure writes: 0
Prepared for Step B: true
```

The resource and candidate counts match the subscription. Zero is valid. `Test-JawsStepA.ps1` prints the same discovery lines and then `Live Azure read: false`, because it scores the receipt and does not call Azure again.

The receipt is `installer/.local/jaws-step-a-discovery.your-environment.generated.json`. Nothing is written under `installer/config/`. `installer/config/jaws-installation-state.dev.json` stays unchanged.

`Prepared for Step B: true` means the environment name is one Step B will accept. It does not create the resource group. The receipt's next command is the Step B plan command. Resource group and location are recorded only when you pass them.

## A2. Reconcile an existing installation

```powershell
.\installer\Install-Jaws.ps1 -Mode Discover -EnvironmentName dev
```

Use your own state file with `-StateFile` for any installation other than the dev project. **Expected result:** tenant scan and target comparison, `Azure writes: 0`, and the state file unchanged. A path passed in `-StateFile` that does not exist stops at `JAWS-STATE-003`. Discover does not invent that file.

## Failure recovery

| Condition | Result |
| --- | --- |
| Azure CLI is not signed in | `JAWS-AUTH-001`. Run `az login` and `az account set`. No resources are created. |
| `-SubscriptionId` does not match `az account show` | `JAWS-AUTH-007`. No resources are created. |
| `-StateFile` points at a missing file | `JAWS-STATE-003`. No receipt and no new state file. |
| Environment name `dev` with no dev state file | Discovery can still pass, with `Prepared for Step B: false`. |
| Resource group `rg-aiops-lab` | `Prepared for Step B: false`. The dev project is not reused. |

## What this does not accept

Pester `tests/installer/StepA.Tests.ps1` exercises a stand-in Azure CLI. That is offline evidence. A fresh-subscription discovery receipt has not been archived, so greenfield Step A is not accepted. The previously accepted evidence is read-only reconciliation of the dev project.

## Acceptance criteria

- A-00: The clone is the `main` branch and `installer/Install-Jaws.ps1` is present.
- A-01: The receipt names the signed-in subscription and tenant.
- A-02: Resource groups and resources are counted. An empty subscription prints `Resource groups: 0` and `Resources: 0`.
- A-03: An existing state file is reconciled. A new subscription does not need one.
- A-04: `Azure writes: 0`, and no file is added under `installer/config/`.
- A-05: The discovery receipt exists. The test script's `Live Azure read: false` line is not a second Azure read.
- A-06: Greenfield Step A is not accepted until a real subscription prints `STEP-A DISCOVERY PASS`.
