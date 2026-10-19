# Step D browser control

Browser control is part of Step D. Step E stays allow-listed Azure MCP investigation and has no installer. Accept, and a passing capability check, still print `Ready for next step: false` and `Next step: Step E is not installable`.

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

- a Container Apps environment with a public HTTPS endpoint and Container App `jaws-br-<environment>`
- image `jaws/browser:step-d`, built with `az acr build` and pinned to the registry digest
- Key Vault secrets `jaws-browser-allow-list` and `jaws-browser-credentials`
- Foundry toolbox `jaws-browser-tools`, authenticated as managed identity audience `api://jaws-browser`
- one later Supervisor version that names the toolbox and keeps the Step B digest

Foundry's tool calls leave Microsoft's network, so the browser API is a public HTTPS name on port 8089. The bearer token for audience `api://jaws-browser` is the boundary. The allow-list still starts empty, and a vault password is filled only after the token signature is validated. Scale is minimum 0 and maximum 3 replicas. An environment created earlier with internal ingress cannot be switched in place. Install deletes that app and environment and creates the public one, then posts a toolbox version whose server URL is the public name and promotes it. Before the two secrets are written, Install grants the signed-in account Key Vault Secrets Officer on the vault when that assignment is missing. Step B creates the vault with RBAC authorization and does not grant this data-plane role. The app identity receives Key Vault Secrets User on those two secrets and AcrPull on the registry. The container environment includes `JAWS_BROWSER_TENANT_ID` from the signed-in tenant.

The install receipt records `PlaywrightServiceEndpoint`, `BrowserToolsetVersion`, and `CredentialScopeId`. A passing Install prints `Supervisor image rebuilt: false` and either `Browser allow-list: empty. No navigation will succeed until an operator adds a URL.` or the current entry count. Install does not rebuild the Supervisor image.

## Supervisor image

`Publish-JawsSupervisorBrowserImage.ps1` builds `src/Jaws.Supervisor.Host` with `az acr build` for `linux/amd64`. It does not use Docker. It posts one new Supervisor version whose digest differs from version 1, copies the latest environment variables (including `JAWS_INVESTIGATION_TOOLBOX_NAME` when that version has it), and sets `JAWS_BROWSER_TOOLBOX_NAME`. Version 1 is read again and must be unchanged.

Without `-AcknowledgeSupervisorBrowserImage`, or for `-EnvironmentName dev`, the command throws `JAWS-STEP-D-035` and builds nothing. A latest image that already differs from version 1, and is not a digest-pinned `jaws/supervisor` image in this registry, also throws `JAWS-STEP-D-035`. A second run that finds that published image does not build again.

Expected: `STEP-D BROWSER IMAGE PASS`, `Supervisor image rebuilt: true`, `Supervisor version 1 unchanged: true`, `Customer installation accepted: false`, `Ready for next step: true`, and `Next step: Test-JawsBrowserPrivatePath.ps1`. Evidence: `installer/.local/jaws-step-d-browser-image.<environment>.generated.json`.

## Private path

`Test-JawsBrowserPrivatePath.ps1` makes one Foundry responses call. The prompt opens a session and closes it. It does not navigate. Foundry calls the public browser API with the toolbox token. A pass proves that call reached the browser. It does not prove a page load.

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

Expected on a pass: `STEP-D BROWSER CAPABILITY PASS`, `Customer installation accepted: false`, `Ready for next step: false`, and `Next step: Step E is not installable`. Evidence: `installer/.local/jaws-step-d-browser-capability.<environment>.generated.json`. The receipt sets `LiveNavigationClaimed`, `VaultLoginClaimed`, and `SignatureValidationClaimed` to false. A stand-in that prints those markers is not a live page load.

## Tools and session limit

The toolbox exposes `browser_open`, `browser_navigate`, `browser_snapshot`, `browser_click`, `browser_type`, `browser_screenshot`, and `browser_close`. The specialist catalog lists the six action names. Those tools do not require `approve-vm-change`. `vm.run-command` still does.

Credential selectors whose names contain `password`, `passwd`, `secret`, or `token` discard the agent's text. The service fills them from secret `jaws-browser-credentials` only when the bearer token's signature was validated. Otherwise the outcome is `credential_signature_required` and the text is discarded. When `JAWS_BROWSER_TENANT_ID` is unset, audience-only acceptance still allows non-credential calls and does not allow a vault fill. Install sets that tenant id from `az account show`.

Evidence JSONL records `requested_by`, `delegation_id`, the action, target, outcome, duration, and a screenshot reference. It does not record typed text or passwords.

A task stops after 10 minutes or 50 steps. The service returns `allow_list_rejected`, `browser_timeout`, `browser_unreachable`, `credential_not_registered`, or `credential_signature_required`. Downloads are disabled. A fourth concurrent session fails immediately with `browser_queue_timeout`. There is no wait queue.

## What this release does not prove

These checks are not claimed as accepted:

- a fresh-subscription receipt
- a live navigation and value extraction on a real allow-listed page
- a vault login whose password is absent from a real site log
- an unreachable Container App returning within 30 seconds on a live private path
- signature validation against the live tenant. The host code validates the signature when the tenant id is set, and a local unit test signs a token with a test key. That test does not call the tenant.

CAPTCHA solving, downloads, uploads, multiple tabs, video or audio capture, and specialist-to-Supervisor browser delegation are out of scope.
