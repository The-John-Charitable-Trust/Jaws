# Step B — Foundry foundation and packaging

Step B creates the foundation for one environment in the subscription already selected with `az account set`:

- resource group
- Foundry account and project, with a system-assigned project identity
- model deployment at capacity 1: GlobalStandard when quota mode is Static, regional Standard when Install is given `-QuotaMode Dynamic`
- Key Vault with RBAC and purge protection
- Basic registry with admin disabled
- AcrPull for the project identity
- hosted Supervisor version 1, pinned to the registry image digest

The example blueprint stays a template. Its subscription id remains `00000000-0000-0000-0000-000000000000`. The installer copies the signed-in subscription into the plan. `dev` and `rg-aiops-lab` are refused so the accepted development project is left unchanged.

The account this command creates has public egress and no `networkInjections`. That is the shape of the dev account and the shape of the next functional test. It is not the FedRAMP Moderate account. The FedRAMP account is created private, before any project or agent exists: public network access disabled, a private endpoint, private DNS for `privatelink.services.ai.azure.com`, `privatelink.cognitiveservices.azure.com`, and `privatelink.openai.azure.com`, and a dedicated `/24` delegated to `Microsoft.App/environments`. Injection cannot be added later. The current Key Vault uses RBAC and purge protection and is publicly reachable. The current registry is Basic with admin disabled and is publicly reachable. FedRAMP Moderate for those resources adds a private endpoint on each, and the registry is Premium because Basic has no private endpoint. Local authentication on the Foundry account is disabled, and RequestResponse and Audit diagnostics are enabled. The installer does not create that private account yet.

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

**Expected result.** Both commands print `STEP-B PLAN PASS`, `Subscription source: AzureCli`, `Install authorized: false`, `Quota mode: Static`, and `Plan SHA-256`. Azure writes stay 0. The report is `installer/.local/jaws-stage-b-plan.your-environment.offline.generated.json`. The digest binds the subscription, names, and model. It does not include the quota mode, and it does not authorize every mutation or an open-ended cost. Pass `-QuotaMode Dynamic` on Plan to print that choice before Install. The value used at Install is the one that is applied.

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

Copy `installer/config/jaws.install.example.json` to `installer/.local/jaws.install.your-environment.json` and fill the ServiceNow login URL, username, and password there. Add the Datadog site, API key, and application key when you have them, and the resource id of the default virtual machine. Leave a field empty when you do not have that value yet. The filled file stays under `.local` and is not committed. Secret values are written to the Step B Key Vault. The generated file `installer/.local/jaws-install.your-environment.generated.json` records the secret names and one FedRAMP Moderate row for each Azure resource. It does not record a password, an API key, or the ServiceNow URL.

```powershell
Copy-Item .\installer\config\jaws.install.example.json .\installer\.local\jaws.install.your-environment.json
.\installer\Install-Jaws.ps1 -Mode Install -EnvironmentName your-environment -ResourceGroupName rg-jaws-your-environment -Location eastus -ApprovedPlanSha256 <plan-sha> -AcknowledgeStepBInstall -InstallConfig .\installer\.local\jaws.install.your-environment.json
.\installer\Test-JawsStepB.ps1 -Mode Install
```

The same seven fields can be passed as parameters, and a parameter replaces the matching field in the file. On an interactive console, Install first asks `Configure ServiceNow during this install? (yes/skip)` and `Configure Datadog during this install? (yes/skip)`. `yes` asks for that product's values. `skip` leaves it unset. Skipping Datadog does not ask for a virtual machine, stores no Datadog secrets, and records `Datadog agent host required: false`. Configuring Datadog requires the site, the API key, and the virtual machine resource id that hosts the Datadog Agent. The application key stays optional. `-SkipServiceNow` and `-SkipDatadog` make the same choice without a prompt. The install file accepts `"SkipServiceNow": true` and `"SkipDatadog": true`. A skip combined with values for that product stops at `JAWS-INSTALL-CONFIG-002` or `JAWS-INSTALL-CONFIG-003`. `az vm run-command` cannot answer the prompts, so use the file or the switches. `-NonInteractive` does not ask. Install with every field empty, and without a skip, still prints `STEP-B INSTALL PASS` and stores nothing. A partial ServiceNow login, or Datadog details without the site, API key, and agent host, fails the install milestone after the foundation exists. Fix the file and run Install again. `Set-JawsObservabilityIntegration.ps1` remains available for a later update of the same secrets.

`-QuotaMode` is `Static` or `Dynamic`. The default is `Static`. Static creates GlobalStandard capacity 1 (1,000 tokens per minute) and leaves dynamic quota off. Requests above that rate are refused. `Dynamic` does not change the plan digest or the capacity. It creates the regional Standard SKU, because Azure rejects `dynamicThrottlingEnabled` on GlobalStandard. After that deployment exists, Install sets `properties.dynamicThrottlingEnabled` to true with `az rest --method patch` and API version `2023-10-01-preview`. Azure may then serve more than the capacity-1 rate when it has spare capacity. Those extra tokens are billed at the normal rate, and dynamic quota has no throughput ceiling. Turning the property on has no separate fee. If a GlobalStandard deployment is already present, Dynamic Install deletes it and creates the Standard deployment under the same name. A later Dynamic Install does not delete a deployment that is already Standard. Use the same plan digest:

```powershell
.\installer\Install-Jaws.ps1 -Mode Install -EnvironmentName your-environment -ResourceGroupName rg-jaws-your-environment -Location eastus -ApprovedPlanSha256 <plan-sha> -QuotaMode Dynamic -AcknowledgeStepBInstall
```

A second Install does not patch when the deployment already matches the chosen mode. It also does not build the Supervisor image again once version 1 is active. `Static` on a Standard deployment that already has dynamic quota on sets the property back to false and leaves the Standard SKU in place. The console prints `Model SKU: GlobalStandard` or `Model SKU: Standard`.

**Expected result.** `Install-Jaws.ps1` prints:

```text
STEP-B INSTALL PASS
Foundry account: jaws-foundry-your-environment
Project: jaws-your-environment
Model: gpt-5-mini 2025-08-07
Quota mode: Static
Agent: jaws-supervisor-your-environment
Agent version: 1
Agent status: active
ServiceNow stored: true
ServiceNow skipped: false
Datadog stored: false
Datadog skipped: true
Default virtual machine stored: false
Datadog agent host required: false
FedRAMP Moderate: false
FedRAMP open resources: 10
Install config: installer/.local/jaws-install.your-environment.generated.json
```

`ServiceNow stored` and `Datadog stored` are `false` when those products were skipped or their values were not supplied. `Datadog agent host required` is `false` when Datadog is skipped. `FedRAMP Moderate: false` is expected on this public-egress install. The open-resource count is the number of inventory rows that do not meet the criterion. A skipped Datadog row is closed because no agent host is required. `Quota mode: Dynamic` replaces the quota line when Install was given `-QuotaMode Dynamic`. Microsoft documents the property at [Azure OpenAI dynamic quota](https://learn.microsoft.com/en-us/azure/ai-foundry/openai/how-to/dynamic-quota).

`Test-JawsStepB.ps1 -Mode Install` prints the same install lines and then `Live Azure read: false`. That score checks the receipt file. It does not re-read Azure and it is not acceptance.

Install uploads `src/Jaws.Supervisor.Host` and runs `az acr build --platform linux/amd64`. `--file` is the package plan's full Dockerfile path. When that argument is set, Azure CLI checks it from the current directory, so a bare `Dockerfile` name is not used. It does not run `docker build`, `docker tag`, or `docker push`. The image line ends in `@sha256:` and a 64-character digest read back from the registry. The receipt is `installer/.local/jaws-step-b-install.your-environment.generated.json`. The install config, with secret names and the FedRAMP inventory, is `installer/.local/jaws-install.your-environment.generated.json`. The generated state file is `installer/.local/jaws-installation-state.your-environment.generated.json`. `installer/config/jaws-installation-state.dev.json` is unchanged.

| Condition | Result |
| --- | --- |
| Approval switch omitted | `JAWS-STEP-B-010`, no Azure writes |
| Preflight is not ready | `JAWS-STEP-B-026`, no Azure writes |
| Plan digest differs | `JAWS-STEP-B-011`, no Azure writes |
| Environment `dev` or resource group `rg-aiops-lab` | `JAWS-STEP-B-013` |
| Existing resource without the installer tags | `JAWS-STEP-B-012`, no adoption |
| Model quota or unsupported region | `JAWS-STEP-B-MODEL-001`. A quota refusal prints `Issue`, `Action`, and `Quota request: https://aka.ms/oai/stuquotarequest`. Dynamic quota cannot create the deployment when Azure has no quota for capacity 1 |
| Requested quota mode is not recorded | `JAWS-STEP-B-MODEL-002`. Capacity stays 1. Dynamic uses the regional Standard SKU |
| Regional Standard SKU is not offered | `JAWS-STEP-B-MODEL-001` before a Dynamic deployment is created. GlobalStandard is not used as a substitute |
| Registry build fails | `JAWS-STEP-B-021`. Docker is not used. A second run does not build again once Supervisor version 1 is active |
| Second run | Same receipt, no second Foundry account or Supervisor |
| Approved model is not offered | `JAWS-STEP-B-MODEL-001` before the deployment is created |
| Account, project, deployment, vault, or registry stays provisioning | `JAWS-STEP-B-023` |
| Hosted Supervisor does not become active | `JAWS-STEP-B-018` |
| `-InstallConfig` path is missing | `JAWS-INSTALL-CONFIG-001`, before the first write |
| ServiceNow URL, username, and password are not supplied together | `JAWS-OBS-003`, after the foundation exists |
| Datadog key and site are not supplied together | `JAWS-OBS-006`, after the foundation exists |

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
Quota mode: Static
Deployment: Succeeded
Registry admin: false
AcrPull: true
Image: jawsacryourenvironment.azurecr.io/jaws/supervisor@sha256:<64 hex characters>
Agent: jaws-supervisor-your-environment
Agent version: 1
Agent status: active
Dev state: unchanged
FedRAMP Moderate: false
```

Accept also prints `FedRAMP open resources` and `Install config` when B3 wrote the inventory. A public-egress pass still prints `STEP-B ACCEPTANCE PASS`. That line is the functional result. `FedRAMP Moderate: false` means B-09 stays open. The report is `installer/.local/jaws-step-b-acceptance.your-environment.generated.json`. A receipt file whose resources are not in the signed-in subscription throws `JAWS-STEP-B-024` and does not print `STEP-B ACCEPTANCE PASS`.

## Acceptance

`STEP-B ACCEPTANCE PASS` is the functional acceptance line. `STEP-B INSTALL PASS` records the installer receipt. A local stand-in for Azure CLI can exercise the commands, and that exercise is not a fresh-subscription receipt. Step B stays functionally unaccepted until B4 prints `STEP-B ACCEPTANCE PASS` against a real subscription that is not the dev project.

- B-09: FedRAMP Moderate. The Foundry account in the signed-in subscription has public network access disabled, a private endpoint, the three private DNS zones named above, and agent injection chosen at create time. Key Vault has public access disabled, a private endpoint, RBAC, and purge protection. The registry has admin disabled and a private endpoint. Local authentication is disabled. RequestResponse and Audit diagnostics are on. The install config lists the resource group, Foundry account, project, model deployment, Key Vault, registry, project identity, hosted Supervisor, diagnostics, virtual network, browser Container App, and default virtual machine. A public-egress `STEP-B ACCEPTANCE PASS` leaves this criterion open and leaves `Customer installation accepted` false. The inventory is a customer configuration record. It is not a FedRAMP authorization.

## Restart

`rg-aiops-lab-test2` has been deleted. An old receipt under `installer/.local` for that name will fail Accept with `JAWS-STEP-B-024` because the resource group is gone. Run Plan, Preflight, and Install again before Accept. Reuse the name `aiops-lab-test2` only on that new Install. Pull `main` after the A2A host change is merged, so Step C keeps the planner on `services.ai.azure.com`. Do not run `Install-JawsFoundryPrivateNetwork.ps1` during this restart. The dev project stays unchanged.

## Actual JAWS implementation source (B)

The [Step B source-code walkthrough](source-code/STEP-B.md) includes **verbatim PowerShell, C# and repository JSON excerpts**, reviewed file paths, source line ranges, and direct links to the complete source in the JAWS repository. No illustrative or Microsoft sample implementation has been substituted, and no Python code is included because this stage has no verified JAWS Python implementation. The excerpts are reference material, not standalone executable scripts. For complete behavior, consult the linked source and the install/validation commands above.
