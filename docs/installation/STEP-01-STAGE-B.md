# Step B — Foundry foundation and packaging

Step B creates the foundation for one environment in the subscription already selected with `az account set`:

- resource group
- Foundry account and project, with a system-assigned project identity
- model deployment
- Key Vault with RBAC and purge protection
- Basic registry with admin disabled
- AcrPull for the project identity
- hosted Supervisor version 1, pinned to the registry image digest

The example blueprint stays a template. Its subscription id remains `00000000-0000-0000-0000-000000000000`. The installer copies the signed-in subscription into the plan. `dev` and `rg-aiops-lab` are refused so the accepted development project is left unchanged.

These resources are billable. Install does nothing unless `-AcknowledgeStepBInstall` and the plan digest from the plan command are both present.

## Prerequisites

- `az account set --subscription <your-subscription-id>` completed.
- PowerShell 7 at the repository root.
- Azure CLI. Install builds the Supervisor image in the registry with `az acr build` and does not use a local Docker daemon or the .NET SDK.
- Contributor on the subscription or resource group, plus permission to assign AcrPull. Contributor alone cannot assign roles. The registry build also needs permission to push the image, which Contributor on the registry includes.

## B1. Plan

```powershell
.\installer\Install-Jaws.ps1 -Mode Plan -NonInteractive -EnvironmentName your-environment -ResourceGroupName rg-jaws-your-environment -Location eastus
.\installer\Test-JawsStepB.ps1 -Mode Plan -ReportPath .\installer\.local\jaws-stage-b-plan.your-environment.offline.generated.json
```

**Expected result.** Both commands print `STEP-B PLAN PASS`, `Subscription source: AzureCli`, `Install authorized: false`, and `Plan SHA-256`. Azure writes stay 0. The report is `installer/.local/jaws-stage-b-plan.your-environment.offline.generated.json`. The digest binds the subscription, names, and model. It does not authorize every mutation or an open-ended cost.

## B1a. Preflight

```powershell
.\installer\Install-Jaws.ps1 -Mode Preflight -EnvironmentName your-environment -ResourceGroupName rg-jaws-your-environment -Location eastus
```

**Expected result.**

```text
STEP-B PREFLIGHT PASS
Azure writes: 0
Providers: Registered
Resource write: true
Role assignment: true
Model quota: deferred
Policy simulation: not performed
Authorized writes: bounded
```

The report is `installer/.local/jaws-step-b-preflight.your-environment.generated.json`. It lists the only writes Install is allowed to attempt. Model quota stays deferred until the Foundry account exists, and the install then refuses a model the account does not offer. Azure Policy deny effects are listed as not simulated. A caller with Contributor but without Owner, User Access Administrator, or Role Based Access Control Administrator stops at `JAWS-STEP-B-026`. No resource group is created. Install repeats this check before its first write, so an old report cannot skip it.

## B2. Package

Optional check that the Supervisor host publishes before the install spends money.

```powershell
.\installer\Install-Jaws.ps1 -Mode Package
.\installer\Test-JawsStepB.ps1 -Mode Package
```

**Expected result.** `STEP-B PACKAGE PASS`, `Status: LOCAL_PACKAGE_CREATED`, `Azure writes: 0`, `Registry push: false`, `Foundry deployment: false`, `Container built: false`. `installer/.local/supervisor/publish/Jaws.Supervisor.Host.dll` exists.

## B3. Install

```powershell
.\installer\Install-Jaws.ps1 -Mode Install -EnvironmentName your-environment -ResourceGroupName rg-jaws-your-environment -Location eastus -ApprovedPlanSha256 <plan-sha> -AcknowledgeStepBInstall
.\installer\Test-JawsStepB.ps1 -Mode Install
```

**Expected result.** `Install-Jaws.ps1` prints:

```text
STEP-B INSTALL PASS
Foundry account: jaws-foundry-your-environment
Project: jaws-your-environment
Model: gpt-5-mini 2025-08-07
Agent: jaws-supervisor-your-environment
Agent version: 1
Agent status: active
```

`Test-JawsStepB.ps1 -Mode Install` prints the same install lines and then `Live Azure read: false`. That score checks the receipt file. It does not re-read Azure and it is not acceptance.

Install uploads `src/Jaws.Supervisor.Host` and runs `az acr build --platform linux/amd64`. `--file` is the package plan's full Dockerfile path. When that argument is set, Azure CLI checks it from the current directory, so a bare `Dockerfile` name is not used. It does not run `docker build`, `docker tag`, or `docker push`. The image line ends in `@sha256:` and a 64-character digest read back from the registry. The receipt is `installer/.local/jaws-step-b-install.your-environment.generated.json`. The generated state file is `installer/.local/jaws-installation-state.your-environment.generated.json`. `installer/config/jaws-installation-state.dev.json` is unchanged.

| Condition | Result |
| --- | --- |
| Approval switch omitted | `JAWS-STEP-B-010`, no Azure writes |
| Preflight is not ready | `JAWS-STEP-B-026`, no Azure writes |
| Plan digest differs | `JAWS-STEP-B-011`, no Azure writes |
| Environment `dev` or resource group `rg-aiops-lab` | `JAWS-STEP-B-013` |
| Existing resource without the installer tags | `JAWS-STEP-B-012`, no adoption |
| Model quota or unsupported region | `JAWS-STEP-B-MODEL-001` or the provider error from Azure |
| Registry build fails | `JAWS-STEP-B-021`. Docker is not used. A second run does not build again once Supervisor version 1 is active |
| Second run | Same receipt, no second Foundry account or Supervisor |
| Approved model is not offered | `JAWS-STEP-B-MODEL-001` before the deployment is created |
| Account, project, deployment, vault, or registry stays provisioning | `JAWS-STEP-B-023` |
| Hosted Supervisor does not become active | `JAWS-STEP-B-018` |

## B4. Accept the foundation

Acceptance re-reads the signed-in subscription. It does not create resources. Run it in the same subscription that received B3.

```powershell
.\installer\Install-Jaws.ps1 -Mode Accept -EnvironmentName your-environment -ResourceGroupName rg-jaws-your-environment -Location eastus
.\installer\Test-JawsStepB.ps1 -Mode Accept
```

**Expected result.** Both commands print:

```text
STEP-B ACCEPTANCE PASS
Live Azure read: true
Azure writes: 0
Foundry account: jaws-foundry-your-environment
Foundry provisioning: Succeeded
Project: jaws-your-environment
Model: gpt-5-mini 2025-08-07
Deployment: Succeeded
Registry admin: false
AcrPull: true
Image: jawsacryourenvironment.azurecr.io/jaws/supervisor@sha256:<64 hex characters>
Agent: jaws-supervisor-your-environment
Agent version: 1
Agent status: active
Dev state: unchanged
```

The report is `installer/.local/jaws-step-b-acceptance.your-environment.generated.json`. A receipt file whose resources are not in the signed-in subscription throws `JAWS-STEP-B-024` and does not print `STEP-B ACCEPTANCE PASS`.

## Acceptance

`STEP-B ACCEPTANCE PASS` is the only Step B acceptance line. `STEP-B INSTALL PASS` records the installer receipt. A local stand-in for Azure CLI can exercise the commands, and that exercise is not a fresh-subscription receipt. Step B stays unaccepted until B4 prints `STEP-B ACCEPTANCE PASS` against a real subscription that is not the dev project.

## Actual JAWS implementation source (B)

The [Step B source-code walkthrough](source-code/STEP-B.md) includes **verbatim PowerShell, C# and repository JSON excerpts**, reviewed file paths, source line ranges, and direct links to the complete source in the JAWS repository. No illustrative or Microsoft sample implementation has been substituted, and no Python code is included because this stage has no verified JAWS Python implementation. The excerpts are reference material, not standalone executable scripts. For complete behavior, consult the linked source and the install/validation commands above.
