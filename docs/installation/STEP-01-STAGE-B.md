# Step B — Subscription capture and local Supervisor package

Step B records the Azure subscription already selected with `az account set`, then publishes the Supervisor host on the workstation. It does not create a resource group, a Foundry project, a model deployment, a registry image, or a managed identity.

The example blueprint stays a template. Its subscription id remains `00000000-0000-0000-0000-000000000000`. The installer copies the signed-in subscription into the generated plan.

## Prerequisites

- Step A completed through `az account set --subscription <your-subscription-id>`.
- PowerShell 7 at the repository root.
- .NET SDK 10 for the package command. Check with `dotnet --list-sdks`.
- Docker is required only for the optional `-BuildContainer` command.

## B1. Capture the subscription

```powershell
.\installer\Install-Jaws.ps1 -Mode Plan -NonInteractive
.\installer\Test-JawsStepB.ps1 -Mode Plan
```

**Expected result.** Both commands print:

```text
STEP-B PLAN PASS
Subscription: <id from az account show>
Subscription source: AzureCli
Resource group: rg-jaws-test
Location: eastus
Status: BLOCKED_PENDING_AZURE_DISCOVERY_AND_APPROVAL
Can execute: false
Azure writes: 0
Example blueprint: unchanged
```

The report is `installer/.local/jaws-stage-b-plan.tester.offline.generated.json`. `rg-jaws-test` is recorded from the blueprint and is not created. With no Azure CLI session, Plan stops at `JAWS-AUTH-001` or `JAWS-PLAN-011`.

## B2. Publish the Supervisor host

This is the package gate.

```powershell
.\installer\Install-Jaws.ps1 -Mode Package
.\installer\Test-JawsStepB.ps1 -Mode Package
```

**Expected result.** Both commands print:

```text
STEP-B PACKAGE PASS
Status: LOCAL_PACKAGE_CREATED
Azure writes: 0
Registry push: false
Foundry deployment: false
Container built: false
```

`installer/.local/supervisor/publish/Jaws.Supervisor.Host.dll` exists. The report is `installer/.local/jaws-step-b-package.generated.json`.

| Condition | Result |
| --- | --- |
| .NET SDK missing | `JAWS-PACKAGE-003` |
| `dotnet publish` fails | `JAWS-PACKAGE-004` |
| Optional `-BuildContainer` without Docker | `JAWS-PACKAGE-005` |

`-BuildContainer` is not part of the default gate. When Docker can build `linux/amd64`, that command instead prints `Container built: true` and `Container tag: jaws-supervisor:local`. Registry push and Foundry deployment stay false.

## What this pass does not prove

Foundry account and project, model deployment, container registry, image digest, managed identity, and RBAC are unchanged by B1 and B2. A later gate has to verify them before any deployment claim.
