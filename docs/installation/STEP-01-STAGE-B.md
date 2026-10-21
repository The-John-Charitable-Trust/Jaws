# Step B — Foundry foundation and packaging

Step B creates the foundation for one environment in the subscription already selected with `az account set`:

- resource group
- Foundry account and project, with a system-assigned project identity
- model deployment at capacity 1: GlobalStandard when quota mode is Static, regional Standard when Install is given `-QuotaMode Dynamic`
- Key Vault with RBAC and purge protection
- Basic registry with admin disabled
- AcrPull for the project identity and for the Supervisor agent identity. The hosted agent runtime pulls the image with the agent identity.
- hosted Supervisor version 1, pinned to the registry image digest

The example blueprint stays a template. Its subscription id remains `00000000-0000-0000-0000-000000000000`. The installer copies the signed-in subscription into the plan. `dev` and `rg-aiops-lab` are refused so the accepted development project is left unchanged.

`-NetworkProfile` is `Public` or `Private`. The default is `Public`. A public plan keeps the historical digest: the account has public egress and no `networkInjections`. A private plan adds one digest line, so a public approval cannot be replayed as a private install. The private profile creates the account private from the start: `publicNetworkAccess` disabled, agent injection on `jaws-foundry-agents`, a private endpoint, and private DNS for `privatelink.services.ai.azure.com`, `privatelink.cognitiveservices.azure.com`, and `privatelink.openai.azure.com`. Injection cannot be added later. Key Vault and the registry stay public in this profile. `FedRAMP Moderate` stays false. `Install-JawsFoundryPrivateNetwork.ps1` is deprecated and is not this profile.

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

`your-environment` is the name you choose. On an interactive console, leave `-EnvironmentName` off and Plan asks `Environment name`. Enter at the next two prompts uses resource group `rg-jaws-<environment>` and location `eastus`. `-NonInteractive` does not ask, so pass all three. The name is 2–21 characters, starts with a lowercase letter, and uses lowercase letters, digits, and hyphens. `dev` is reserved. That name selects the default Foundry account, project, Key Vault, registry, and Supervisor. A new environment name is how a second install avoids a Key Vault name left behind by an earlier one.

**Expected result.** Both commands print `STEP-B PLAN PASS`, `Environment`, `Subscription source: AzureCli`, `Install authorized: false`, `Quota mode: Static`, `Network profile: Public`, `Key Vault`, and `Plan SHA-256`. Azure writes stay 0. The report is `installer/.local/jaws-stage-b-plan.your-environment.offline.generated.json`. The digest binds the subscription, names, and model. It does not include the quota mode. It does include `NetworkProfile=Private` when that profile is requested, and a private plan's digest differs from the public plan for the same names. Pass `-QuotaMode Dynamic` on Plan to print that choice before Install. The value used at Install is the one that is applied. Pass `-NetworkProfile Private` on Plan to select the private profile. Install reads that choice from the saved plan.

Plan prints the names it will create. Omit a name parameter to keep the generated default. The resource group and region are the `-ResourceGroupName` and `-Location` you already pass. The model deployment name is `-ModelName`.

| Resource | Default | Plan parameter |
| --- | --- | --- |
| Foundry account | `jaws-foundry-<environment>` | `-FoundryAccountName` |
| Project | `jaws-<environment>` | `-ProjectName` |
| Key Vault | `kvjaws` plus the environment with hyphens removed, at most 24 characters | `-KeyVaultName` |
| Registry | `jawsacr` plus that compact name, at most 50 characters | `-AcrName` |
| Supervisor | `jaws-supervisor-<environment>` | `-SupervisorAgentName` |

```powershell
.\installer\Install-Jaws.ps1 -Mode Plan -NonInteractive -EnvironmentName your-environment -ResourceGroupName rg-jaws-your-environment -Location eastus -FoundryAccountName jaws-foundry-your-name -ProjectName jaws-your-project -KeyVaultName kv-jaws-your-vault -AcrName jawsacryourregistry -SupervisorAgentName jaws-supervisor-your-name
```

A name you supply replaces only that resource. The other names stay at the defaults above. The final names are part of the plan digest, so a custom name produces a new `Plan SHA-256`. Preflight and Install read the saved plan. Passing a different name on those commands stops at `JAWS-STEP-B-016` before any write. Accept reads the same saved plan when you omit the name parameters.

Foundry, project, and Supervisor names are 3–64 characters: a lowercase letter, then lowercase letters, digits, or hyphens, ending with a letter or digit. A Key Vault name is 3–24 characters: a letter, then letters, digits, or hyphens, ending with a letter or digit, with no consecutive hyphens. A registry name is 5–50 letters or digits. `-RegistryName` is not this setting; it remains the Azure-aware registry assessment switch. An invalid name stops at `JAWS-STEP-B-027`. The reserved dev names `jaws-foundry-dev`, `jaws-dev`, `jawsregistrydev001`, `jaws-supervisor-dev`, and `kv-jaws-dev-001` stop at `JAWS-STEP-B-017`.

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

When the Foundry account, Key Vault, or registry name is already taken, Preflight prints `is not available` and asks `Enter another` name. An invalid answer is printed and the prompt repeats. The accepted name is saved into the plan, and Preflight prints the new `Plan SHA-256`. Use that digest for Install. `-NonInteractive` does not ask. It stops at `JAWS-STEP-B-026` and names `-FoundryAccountName`, `-KeyVaultName`, or `-AcrName`. Install asks the same question before its first write.

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

A second Install does not patch when the deployment already matches the chosen mode. It also does not build the Supervisor image again once version 1 is active and that pinned digest is present in this registry. If version 1 pins a digest this registry does not contain, Install stops with `JAWS-STEP-B-018` and does not rebuild or patch that version. Delete the Supervisor agent and run Install again so version 1 is created from an image in this registry. `Static` on a Standard deployment that already has dynamic quota on sets the property back to false and leaves the Standard SKU in place. The console prints `Model SKU: GlobalStandard` or `Model SKU: Standard`.

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

`ServiceNow stored` and `Datadog stored` are `false` when those products were skipped or their values were not supplied. `Datadog agent host required` is `false` when Datadog is skipped. `FedRAMP Moderate: false` is expected. The open-resource count is the number of inventory rows that do not meet the criterion. A skipped Datadog row is closed because no agent host is required. `Quota mode: Dynamic` replaces the quota line when Install was given `-QuotaMode Dynamic`. Microsoft documents the property at [Azure OpenAI dynamic quota](https://learn.microsoft.com/en-us/azure/ai-foundry/openai/how-to/dynamic-quota).

## Private profile

Run every command on your computer with Azure CLI. There is no jump VM. Plan and the first Install can run before the VPN exists. The Install creates the virtual network, the private account, the private endpoint, the DNS zones, a point-to-site VPN gateway, and a DNS private resolver. It then stops before the Supervisor create if this computer cannot reach `services.ai.azure.com`.

```powershell
.\installer\Install-Jaws.ps1 -Mode Plan -NonInteractive -EnvironmentName your-environment -ResourceGroupName rg-jaws-your-environment -Location eastus -NetworkProfile Private
.\installer\Install-Jaws.ps1 -Mode Preflight -EnvironmentName your-environment -ResourceGroupName rg-jaws-your-environment -Location eastus
.\installer\Install-Jaws.ps1 -Mode Install -EnvironmentName your-environment -ResourceGroupName rg-jaws-your-environment -Location eastus -ApprovedPlanSha256 <plan-sha> -AcknowledgeStepBInstall
```

Use the `Plan SHA-256` from the private plan. A public digest stops at `JAWS-STEP-B-011`.

The address table lives in one place: `10.42.0.0/16`, apps `10.42.0.0/23`, agents `10.42.2.0/24`, private endpoints `10.42.3.0/24`, `GatewaySubnet` `10.42.5.0/27`, DNS inbound `10.42.6.0/28`. The VPN client pool is `172.16.201.0/24`. The gateway uses Entra ID and the Azure VPN client audience `41b23e61-6c1e-4545-b367-cd054e0ed4b4`. Its SKU is VpnGw1. It bills for each hour it exists. The first Install waits while Azure provisions that gateway, often 30 to 45 minutes.

**Expected first Install.** `STEP-B INSTALL PAUSED`, `Private posture: verified`, `Supervisor created: false`, the gateway name `jaws-vpn-<compact>`, and the resolver address. Connect that VPN on this computer and set its DNS server to the resolver address. Run the same Install command again. The second run adopts the account with no further account write and creates the Supervisor. It prints `STEP-B INSTALL PASS`. Accept then runs on this same computer. A DNS failure pauses. A refusal that says public access is disabled pauses the same way, because the public name can still resolve. A later data-plane failure, after this probe has succeeded, stops at `JAWS-STEP-B-029`.

An existing account whose preview read is not exactly that posture stops at `JAWS-STEP-B-028` and is left unchanged. `JAWS-STEP-B-028` is also the code for a network profile value that is neither Public nor Private. `JAWS-STEP-B-029` is the code for a data-plane failure after the reachability probe has already succeeded, and Accept uses the same code when the receipt is still paused. Microsoft documents the account shape in [How to use a virtual network with the Azure AI Foundry Agent Service](https://learn.microsoft.com/en-us/azure/ai-foundry/agents/how-to/virtual-networks).

Key Vault and the registry stay reachable on the public network in this profile. `FedRAMP Moderate` stays false.

`Test-JawsStepB.ps1 -Mode Install` prints the same install lines and then `Live Azure read: false`. That score checks the receipt file. It does not re-read Azure and it is not acceptance.

Install uploads `src/Jaws.Supervisor.Host` and runs `az acr build --platform linux/amd64`. `--file` is the package plan's full Dockerfile path. When that argument is set, Azure CLI checks it from the current directory, so a bare `Dockerfile` name is not used. It does not run `docker build`, `docker tag`, or `docker push`. The image line ends in `@sha256:` and a 64-character digest read back from the registry. The receipt is `installer/.local/jaws-step-b-install.your-environment.generated.json`. The install config, with secret names and the FedRAMP inventory, is `installer/.local/jaws-install.your-environment.generated.json`. The generated state file is `installer/.local/jaws-installation-state.your-environment.generated.json`. `installer/config/jaws-installation-state.dev.json` is unchanged.

| Condition | Result |
| --- | --- |
| Approval switch omitted | `JAWS-STEP-B-010`, no Azure writes |
| Preflight is not ready | `JAWS-STEP-B-026`, no Azure writes |
| Plan digest differs | `JAWS-STEP-B-011`, no Azure writes |
| Environment `dev` or resource group `rg-aiops-lab` | `JAWS-STEP-B-013` |
| Resource name does not match the saved plan | `JAWS-STEP-B-016`, no Azure writes |
| Custom resource name is invalid | `JAWS-STEP-B-027`, no Azure writes |
| Existing resource without the installer tags | `JAWS-STEP-B-012`, no adoption |
| Existing Foundry account does not match the private profile | `JAWS-STEP-B-028`, the account is not changed |
| Private data plane is not reachable from this computer | `STEP-B INSTALL PAUSED` before the Supervisor exists. After the VPN is connected, a later data-plane failure is `JAWS-STEP-B-029` |
| Model quota or unsupported region | `JAWS-STEP-B-MODEL-001`. A quota refusal prints `Issue`, `Action`, and `Quota request: https://aka.ms/oai/stuquotarequest`. Dynamic quota cannot create the deployment when Azure has no quota for capacity 1 |
| Requested quota mode is not recorded | `JAWS-STEP-B-MODEL-002`. Capacity stays 1. Dynamic uses the regional Standard SKU |
| Regional Standard SKU is not offered | `JAWS-STEP-B-MODEL-001` before a Dynamic deployment is created. GlobalStandard is not used as a substitute |
| Registry build fails | `JAWS-STEP-B-021`. Docker is not used. A second run does not build again once Supervisor version 1 is active and its digest is in this registry |
| Version 1 pins a digest this registry does not contain | `JAWS-STEP-B-018`. Install does not run `az acr build` and does not patch the version. Delete the Supervisor agent and run Install again |
| Second run | Same receipt, no second Foundry account or Supervisor |
| Approved model is not offered | `JAWS-STEP-B-MODEL-001` before the deployment is created |
| Account, project, deployment, vault, or registry stays provisioning | `JAWS-STEP-B-023` |
| Hosted Supervisor does not become active | `JAWS-STEP-B-018` |
| `-InstallConfig` path is missing | `JAWS-INSTALL-CONFIG-001`, before the first write |
| ServiceNow URL, username, and password are not supplied together | `JAWS-OBS-003`, after the foundation exists |
| Datadog key and site are not supplied together | `JAWS-OBS-006`, after the foundation exists |
| Datadog host is outside this environment | `JAWS-OBS-009`, after the foundation exists. The virtual machine must be in this subscription, this resource group, and this location. The Datadog Agent install is in [SYSTEM-PREREQUISITES.md](SYSTEM-PREREQUISITES.md) |

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

`STEP-B ACCEPTANCE PASS` is the functional acceptance line. `STEP-B INSTALL PASS` records the installer receipt. A local stand-in for Azure CLI can exercise the commands, and that exercise is not a fresh-subscription receipt. Step B stays functionally unaccepted until B4 prints `STEP-B ACCEPTANCE PASS` against a real subscription that is not the dev project. That line was printed on 21 October 2026 for environment `stepb-accept`, resource group `rg-jaws-stepb-accept`, location `eastus`, in subscription `c52f597b-7753-45b4-a764-67e290dcfd5e`. Supervisor `jaws-supervisor-stepb-accept` version 1 is active on `jawsacrstepbaccept.azurecr.io/jaws/supervisor@sha256:fa6b05c9c55f8efb4ac4f8f141d828ef51b14a6b1b554246df0eff774cbbd173`. `FedRAMP Moderate` is false, so customer installation acceptance stays false.

- B-09: FedRAMP Moderate. The Foundry account in the signed-in subscription has public network access disabled, a private endpoint, the three private DNS zones named above, and agent injection chosen at create time. Key Vault has public access disabled, a private endpoint, RBAC, and purge protection. The registry has admin disabled and a private endpoint. Local authentication is disabled. RequestResponse and Audit diagnostics are on. The install config lists the resource group, Foundry account, project, model deployment, Key Vault, registry, project identity, hosted Supervisor, diagnostics, virtual network, browser Container App, and default virtual machine. A public-egress `STEP-B ACCEPTANCE PASS` leaves this criterion open and leaves `Customer installation accepted` false. The inventory is a customer configuration record. It is not a FedRAMP authorization.

## Restart

`rg-aiops-lab-test2` has been deleted. An old receipt under `installer/.local` for that name fails Accept with `JAWS-STEP-B-024` because the resource group is gone. On 20 October 2026 the only JAWS resources left in subscription `c52f597b-7753-45b4-a764-67e290dcfd5e` are four soft-deleted Key Vault names. Azure will not purge them early. The two deleted that evening, `kv-jaws-lab-test2` (purge `2027-01-18T22:06:00Z`) and `kv-jaws-dev-001` (purge `2027-01-18T22:05:39Z`), have purge protection. The two older names, `kvjawsaiopslabtest2` (purge `2027-01-18T04:29:10Z`) and `kvjawsaiopslabtest` (purge `2027-01-17T00:22:58Z`), return `DeletedVaultPurge`, the same refusal recorded in October. Azure auto-purges them on 17 and 18 January 2027, and the names stay reserved until then. Choose a new `-EnvironmentName` so the generated Key Vault name is different, or pass `-KeyVaultName`. `kv-jaws-dev-001` is also reserved and stops at `JAWS-STEP-B-017`. Preflight prints that a taken name is not available and asks for another. `-NonInteractive` does not ask, so pass `-KeyVaultName`. Run Plan, then Preflight, and use the `Plan SHA-256` Preflight prints when a name was replaced. `Install-JawsFoundryPrivateNetwork.ps1` is deprecated. Do not run it. A private rebuild uses `-NetworkProfile Private` on Plan. The dev project state file stays unchanged.

## Uninstall to stop charges or start a new install

Step B leaves billable Azure resources. Run this command to delete the whole environment, stop those charges, and clear the names before a new complete install. It force-deletes the Foundry agents, purges the account, and deletes every resource from Steps B, C, and D. It refuses `dev`. A purge-protected Key Vault is recorded as blocked, and the next install needs a different vault name until the purge date.

```powershell
.\installer\Uninstall-Jaws.ps1 -EnvironmentName your-environment -AcknowledgeJawsUninstall
```

Details, including why a resource-group delete alone is not enough, are in [UNINSTALL.md](UNINSTALL.md).

## Actual JAWS implementation source (B)

The [Step B source-code walkthrough](source-code/STEP-B.md) includes **verbatim PowerShell, C# and repository JSON excerpts**, reviewed file paths, source line ranges, and direct links to the complete source in the JAWS repository. No illustrative or Microsoft sample implementation has been substituted, and no Python code is included because this stage has no verified JAWS Python implementation. The excerpts are reference material, not standalone executable scripts. For complete behavior, consult the linked source and the install/validation commands above.
