# Step D browser control

Browser control is part of Step D. Step E is the Teams channel in [STEP-E-TEAMS.md](STEP-E-TEAMS.md). Accept, and a passing capability check, print `Ready for next step: true` and `Next step: Step E Validate`.

`Customer installation accepted` stays false. A Pester pass uses a CLI stand-in. It is not a fresh-subscription receipt, a live page load, or a vault login.

## Command sequence

Run these after Step C has printed `Result: PASS` and `Next step: Step D Validate`.

```powershell
.\installer\Install-JawsStepD.ps1 -Mode Validate -EnvironmentName your-environment
.\installer\Install-JawsStepD.ps1 -Mode Install -EnvironmentName your-environment -AcknowledgeStepDInstall
.\installer\Install-JawsStepD.ps1 -Mode Accept -EnvironmentName your-environment
.\installer\Publish-JawsSupervisorBrowserImage.ps1 -EnvironmentName your-environment -AcknowledgeSupervisorBrowserImage
.\installer\Test-JawsBrowserPrivatePath.ps1 -EnvironmentName your-environment -AcknowledgeBrowserPrivatePath
.\installer\Set-JawsBrowserAllowList.ps1 -Action Add -Url https://portal.contoso.example/reports -EnvironmentName your-environment -AcknowledgeBrowserAllowList
.\installer\Test-JawsBrowserCapability.ps1 -EnvironmentName your-environment -Url https://portal.contoso.example/reports -AcknowledgeBrowserCapability
```

Install is the infrastructure receipt. It prints `Supervisor image rebuilt: false`. Accept re-reads that infrastructure. The image publish, the private-path check, and the capability check are separate commands because each one spends registry, model, or browser usage. The dev project is refused by the image, private-path, allow-list, and capability commands.

## Who receives the browser

Outside the dev project, Install registers toolbox `jaws-browser-tools` on two agents:

- the Supervisor, as a new version after version 1
- the hosted virtual-machine specialist `jaws-vm-specialist-<environment>`

The virtual-machine specialist is the only catalog entry that receives the six browser action names. Any other specialist that lists one of those names fails catalog validation with `JAWS-STEP-D-034`. Specialist-to-Supervisor browser delegation is not implemented. When the session-open body names a caller, evidence records that `requested_by` and `delegation_id`. When the body omits them, `requested_by` is `direct` and `delegation_id` is empty.

The Investigation prompt planner is the Step C planning callee. It does not receive browser tools. The dev project does not receive a Container App, a Supervisor version, or the toolbox. Supervisor version 1 stays active, keeps the Step B image digest, and does not receive `JAWS_BROWSER_TOOLBOX_NAME`.

## What Install creates

Install, after `-AcknowledgeStepDInstall`, creates:

- virtual network `jaws-br-vnet-<compact>` with subnet `jaws-br-apps` (`10.42.0.0/23`) and subnet `jaws-foundry-agents` (`10.42.2.0/24`), both delegated to `Microsoft.App/environments`
- an internal-only Container Apps environment on `jaws-br-apps` and Container App `jaws-br-<compact>`

`<compact>` is the environment name with every character that is not a letter or digit removed. `aiops-lab-test2` becomes `aiopslabtest2`. Foundry names keep the hyphens.
- image `jaws/browser:step-d`, built with `az acr build` and pinned to the registry digest
- Key Vault secrets `jaws-browser-allow-list` and `jaws-browser-credentials`
- Foundry toolbox `jaws-browser-tools`, authenticated as managed identity audience `api://jaws-browser`
- one later Supervisor version that names the toolbox and keeps the Step B digest

The environment has no public endpoint. App ingress is external, which publishes the app on that environment's internal load balancer so clients in the virtual network can reach it. It does not publish the app to the internet. An `.internal.` hostname is not used, because clients elsewhere in the virtual network receive HTTP 404 for that name. A public Container Apps environment is deleted and recreated as internal-only. The bearer token for audience `api://jaws-browser` is still required. The allow-list still starts empty, and a vault password is filled only after the token signature is validated. Scale is minimum 0 and maximum 3 replicas. Before the two secrets are written, Install grants the signed-in account Key Vault Secrets Officer on the vault when that assignment is missing. Step B creates the vault with RBAC authorization and does not grant this data-plane role. The app identity receives Key Vault Secrets User on those two secrets and AcrPull on the registry. The container environment includes `JAWS_BROWSER_TENANT_ID` from the signed-in tenant.

The install receipt records `PlaywrightServiceEndpoint`, `BrowserToolsetVersion`, and `CredentialScopeId`. A passing Install prints `Supervisor image rebuilt: false` and either `Browser allow-list: empty. No navigation will succeed until an operator adds a URL.` or the current entry count. Install does not rebuild the Supervisor image.

## Foundry virtual-network injection

A Foundry account created without `networkInjections` sends tool calls from Microsoft's network. Those calls cannot reach the internal load balancer. Injection is set when the account is created and cannot be added later. Foundry's built-in browser automation is not supported under network isolation. The JAWS browser is this internal OpenAPI app, which is the supported private path.

`Install-JawsFoundryPrivateNetwork.ps1 -AcknowledgeFoundryReplacement` deletes that account, purges the soft-deleted name, and creates it again with agent injection into `jaws-foundry-agents` while public network access stays enabled. That combination is the half-injected account that broke Step C on `aiops-lab-test2`. It is not a FedRAMP Moderate account, and it is not the next test. Do not run it before Step C prints `TOOL_INVOKED_SUCCEEDED` and `TASK_STATE_COMPLETED`. The FedRAMP account is created private from the start, with public network access disabled, a private endpoint, and private DNS, as described in [STEP-01-STAGE-B.md](STEP-01-STAGE-B.md). The A2A and responses names stay on `services.ai.azure.com` and resolve to that private endpoint. The operator machine is in that virtual network or peered to it.

The command removes the project, the model deployment, the Supervisor, and the Investigation toolbox with the account. Re-run Step B Install, Step C Install, and Step D Install afterward, and only after the Step C functional line exists on the account you intend to replace. Without the acknowledgement, or for `-EnvironmentName dev`, it throws `JAWS-STEP-D-044` and writes nothing. The private-path check throws `JAWS-STEP-D-043` when the account has no agent injection, and it does not call the Supervisor. Responses calls for the private path and the capability check use `services.ai.azure.com`.

If the new account create reports that the name is still reserved, wait 5 minutes and run the same command once. Do not retry in a loop. If it is still reserved, wait another 5 minutes and run it once more.

The Step B re-run uses the digest already recorded for this environment. Open `installer/.local/jaws-step-b-install.<environment>.generated.json` and copy `PlanSha256`. The same value is `PlanSha256` in `installer/.local/jaws-stage-b-plan.<environment>.offline.generated.json`, and it is the `Plan SHA-256` line printed by Step B Plan. Copy `ResourceGroupName`, `Location`, and `QuotaMode` from the install receipt as well. Quota mode is not part of the digest. Pass the same `-QuotaMode` that receipt records.

## Test environment aiops-lab-test2

`rg-aiops-lab-test2` has been deleted. The names below are the names a new Install of that environment uses. They are not a live account until Step B Install runs again. An Accept against the old receipt fails because the resource group is gone. `aiopslabtest2` is only the compact form used by the Container Apps resources. It is not the environment name and it is not the Foundry account name.

The next test is public-egress Step B, then Step C on `services.ai.azure.com`, then Step D. Skip `Install-JawsFoundryPrivateNetwork.ps1` until Step C has printed `TASK_STATE_COMPLETED` on that new account.

| Use this | Name |
| --- | --- |
| `-EnvironmentName` | `aiops-lab-test2` |
| Foundry account | `jaws-foundry-aiops-lab-test2` |
| Project | `jaws-aiops-lab-test2` |
| Supervisor | `jaws-supervisor-aiops-lab-test2` |
| Virtual-machine specialist | `jaws-vm-specialist-aiops-lab-test2` |
| Container App | `jaws-br-aiopslabtest2` |
| Container Apps environment | `jaws-br-env-aiopslabtest2` |
| Virtual network | `jaws-br-vnet-aiopslabtest2` |

After the new Step B Install, resource group, location, quota mode, and plan digest are in `installer/.local/jaws-step-b-install.aiops-lab-test2.generated.json`. The plan digest is also the `Plan SHA-256` line from Step B Plan.

```powershell
git checkout main
git pull origin main
.\installer\Install-Jaws.ps1 -Mode Install -EnvironmentName aiops-lab-test2 -ResourceGroupName rg-aiops-lab-test2 -Location eastus -ApprovedPlanSha256 <PlanSha256> -AcknowledgeStepBInstall
.\installer\Install-Jaws.ps1 -Mode Accept -EnvironmentName aiops-lab-test2 -ResourceGroupName rg-aiops-lab-test2 -Location eastus
.\installer\Install-JawsThroughStepC.ps1 -Mode Install -EnvironmentName aiops-lab-test2 -AcknowledgeStepCInstall
.\installer\Install-JawsThroughStepC.ps1 -Mode Validate -EnvironmentName aiops-lab-test2 -AcknowledgeInferenceCharges
```

Run the Step D commands only after that Validate prints `TASK_STATE_COMPLETED`. Copy `PlanSha256` from the new Step B plan, not from a receipt left on the test VM for the deleted account.

```powershell
.\installer\Install-JawsStepD.ps1 -Mode Install -EnvironmentName aiops-lab-test2 -AcknowledgeStepDInstall
.\installer\Install-JawsStepD.ps1 -Mode Accept -EnvironmentName aiops-lab-test2
.\installer\Publish-JawsSupervisorBrowserImage.ps1 -EnvironmentName aiops-lab-test2 -AcknowledgeSupervisorBrowserImage
.\installer\Test-JawsBrowserPrivatePath.ps1 -EnvironmentName aiops-lab-test2 -AcknowledgeBrowserPrivatePath
```

Install prints `Browser network: private`. Accept prints `Ready for next step: true` and `Next step: Step E Validate`. The private-path pass prints `STEP-D PRIVATE PATH PASS` and `Navigation attempted: false`. `Customer installation accepted` stays false on every one of those commands.

## Supervisor image

`Publish-JawsSupervisorBrowserImage.ps1` builds `src/Jaws.Supervisor.Host` with `az acr build` for `linux/amd64`. It does not use Docker. It posts one new Supervisor version whose digest differs from version 1, copies the latest environment variables (including `JAWS_INVESTIGATION_TOOLBOX_NAME` when that version has it), and sets `JAWS_BROWSER_TOOLBOX_NAME`. Version 1 is read again and must be unchanged.

Without `-AcknowledgeSupervisorBrowserImage`, or for `-EnvironmentName dev`, the command throws `JAWS-STEP-D-035` and builds nothing. A latest image that already differs from version 1, and is not a digest-pinned `jaws/supervisor` image in this registry, also throws `JAWS-STEP-D-035`. A second run that finds that published image does not build again.

Expected: `STEP-D BROWSER IMAGE PASS`, `Supervisor image rebuilt: true`, `Supervisor version 1 unchanged: true`, `Customer installation accepted: false`, `Ready for next step: true`, and `Next step: Test-JawsBrowserPrivatePath.ps1`. Evidence: `installer/.local/jaws-step-d-browser-image.<environment>.generated.json`.

## Private path

`Test-JawsBrowserPrivatePath.ps1` makes one Foundry responses call. The prompt opens a session and closes it. It does not navigate. Foundry calls the browser through the virtual network with the toolbox token. A pass proves that call reached the browser. It does not prove a page load.

The command refuses to run until the image receipt says the Supervisor image was rebuilt and differs from version 1 (`JAWS-STEP-D-036`). Without `-AcknowledgeBrowserPrivatePath` it throws `JAWS-STEP-D-037`. A pass requires a browser-open result that contains a session id and does not contain `browser_unreachable`, and it requires that the response did not call browser navigate. Foundry names the OpenAPI tool `jaws-browser.browser_open`; a bare `browser_open` name and a `___` prefixed name also pass. Anything else is `JAWS-STEP-D-040` and stops the capability path.

Expected on a pass: `STEP-D PRIVATE PATH PASS`, `Navigation attempted: false`, `Customer installation accepted: false`, `Ready for next step: true`, and `Next step: Set-JawsBrowserAllowList.ps1, then Test-JawsBrowserCapability.ps1`. Evidence: `installer/.local/jaws-step-d-browser-private-path.<environment>.generated.json`. A stand-in is not a live Foundry receipt.

## Allow-list

The allow-list starts empty. There is no seed list. Navigation is rejected until an operator adds a URL. The command updates the Key Vault secret and does not rebuild an image:

```powershell
.\installer\Set-JawsBrowserAllowList.ps1 -Action Add -Url https://portal.contoso.example/reports -EnvironmentName your-environment -AcknowledgeBrowserAllowList
.\installer\Set-JawsBrowserAllowList.ps1 -Action Remove -Url https://portal.contoso.example/reports -EnvironmentName your-environment -AcknowledgeBrowserAllowList
```

Expected: `Browser allow-list: Add` or `Remove`, `Azure writes: 1`, and `Customer installation accepted: false`. Without `-AcknowledgeBrowserAllowList`, or with `-EnvironmentName dev`, the command throws `JAWS-STEP-D-033` and writes nothing. The URL must be absolute `http` or `https` and must not contain user info.

## Capability check

`Test-JawsBrowserCapability.ps1` spends model and browser usage. It requires the private-path receipt (`JAWS-STEP-D-041` otherwise) and `-Url` already on the allow-list (`JAWS-STEP-D-039` otherwise). Without `-AcknowledgeBrowserCapability` it throws `JAWS-STEP-D-038`.

The prompt asks the Supervisor to open a session, navigate to that URL, extract a value, and try one URL that is not on the list. Navigate needs the session from browser open. A pass requires the tool output to contain both `EXTRACTED_VALUE` and `allow_list_rejected`. Otherwise the command throws `JAWS-STEP-D-042`.

Expected on a pass: `STEP-D BROWSER CAPABILITY PASS`, `Customer installation accepted: false`, `Ready for next step: true`, and `Next step: Step E Validate`. Evidence: `installer/.local/jaws-step-d-browser-capability.<environment>.generated.json`. The receipt sets `LiveNavigationClaimed`, `VaultLoginClaimed`, and `SignatureValidationClaimed` to false. A stand-in that prints those markers is not a live page load.

## Tools and session limit

The toolbox exposes `browser_open`, `browser_navigate`, `browser_snapshot`, `browser_click`, `browser_type`, `browser_screenshot`, and `browser_close`. The specialist catalog lists the six action names. Those tools do not require `approve-vm-change`. `vm.run-command` still does.

Credential selectors whose names contain `password`, `passwd`, `secret`, or `token` discard the agent's text. The service fills them from secret `jaws-browser-credentials` only when the bearer token's signature was validated. Otherwise the outcome is `credential_signature_required` and the text is discarded. When `JAWS_BROWSER_TENANT_ID` is unset, audience-only acceptance still allows non-credential calls and does not allow a vault fill. Install sets that tenant id from `az account show`.

Evidence JSONL records `requested_by`, `delegation_id`, the action, target, outcome, duration, and a screenshot reference. It does not record typed text or passwords.

A task stops after 10 minutes or 50 steps. The service returns `allow_list_rejected`, `browser_timeout`, `browser_unreachable`, `credential_not_registered`, or `credential_signature_required`. Downloads are disabled. A fourth concurrent session fails immediately with `browser_queue_timeout`. There is no wait queue.

## Acceptance criteria

- D-00: Functional. Accept prints `STEP-D ACCEPTANCE PASS`, `Ready for next step: true`, and `Next step: Step E Validate`. `Customer installation accepted` stays false.
- D-01: Supervisor version 1 stays the Step B digest and does not receive `JAWS_BROWSER_TOOLBOX_NAME`. Install prints `Supervisor image rebuilt: false`.
- D-02: The Container App has no public endpoint. The allow-list starts empty. Browser tools are listed only on the virtual-machine specialist.
- D-03: FedRAMP Moderate. The browser is the internal OpenAPI app on a Foundry account created with public network access disabled, a private endpoint, private DNS, and agent injection. Key Vault secrets and the registry use private endpoints. The virtual-machine specialist and the later observability server are reached as private MCP or OpenAPI. No public specialist URL is created. The public-egress Step D run leaves this criterion open. `Install-JawsFoundryPrivateNetwork.ps1` does not close it.

## What this release does not prove

These checks are not claimed as accepted:

- a fresh-subscription receipt
- a live navigation and value extraction on a real allow-listed page
- a vault login whose password is absent from a real site log
- an unreachable Container App returning within 30 seconds on a live private path
- signature validation against the live tenant. The host code validates the signature when the tenant id is set, and a local unit test signs a token with a test key. That test does not call the tenant.

CAPTCHA solving, downloads, uploads, multiple tabs, video or audio capture, and specialist-to-Supervisor browser delegation are out of scope.

## Uninstall to stop charges or start a new install

Run this command to delete the whole customer environment, stop its Azure charges, and clear the names before a new complete install. It removes every resource from Steps B, C, and D. It refuses `dev`. If the Key Vault purge is blocked, choose a different vault name on the next install until the purge date.

```powershell
.\installer\Uninstall-Jaws.ps1 -EnvironmentName your-environment -AcknowledgeJawsUninstall
```

Details are in [UNINSTALL.md](UNINSTALL.md).
