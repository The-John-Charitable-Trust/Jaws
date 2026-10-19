# Step D browser control

Browser control is part of Step D. Step E stays allow-listed Azure MCP investigation and has no installer. Accept still prints `Ready for next step: false` and `Next step: Step E is not installable`.

## Who receives the browser

Outside the dev project, Install registers toolbox `jaws-browser-tools` on two agents:

- the Supervisor, as a new version after version 1
- the hosted virtual-machine specialist `jaws-vm-specialist-<environment>`

The Investigation prompt planner is the Step C planning callee. It does not receive browser tools. The dev project does not receive a Container App, a Supervisor version, or the toolbox. Supervisor version 1 stays active, keeps the Step B image digest, and does not receive `JAWS_BROWSER_TOOLBOX_NAME`.

## What Install creates

Install, after `-AcknowledgeStepDInstall`, creates:

- virtual network `jaws-br-vnet-<environment>` (`10.42.0.0/16`) and subnet `jaws-br-apps` (`10.42.0.0/23`), delegated to `Microsoft.App/environments`
- an internal-only Container Apps environment and Container App `jaws-br-<environment>`
- image `jaws/browser:step-d`, built with `az acr build` and pinned to the registry digest
- Key Vault secrets `jaws-browser-allow-list` and `jaws-browser-credentials`
- Foundry toolbox `jaws-browser-tools`, authenticated as managed identity audience `api://jaws-browser`

The Container App has no public ingress. Ingress is internal on port 8089. Scale is minimum 0 and maximum 3 replicas. The app identity receives Key Vault Secrets User on those two secrets and AcrPull on the registry.

The install receipt records `PlaywrightServiceEndpoint`, `BrowserToolsetVersion`, and `CredentialScopeId`. A passing Install also prints `Supervisor image rebuilt: false`.

## The running Supervisor image

Step D does not rebuild the Supervisor image. Version 1 and the new Supervisor version share the Step B digest. The host source now reads `JAWS_BROWSER_TOOLBOX_NAME`, but an image built before that change ignores the variable. Browser tools appear on a running agent only after a separately approved Supervisor image, built from this host, is deployed. This installer does not do that deploy.

## Allow-list

The allow-list starts empty. Navigation is rejected until an operator adds a URL. The command updates the Key Vault secret and does not rebuild an image:

```powershell
.\installer\Set-JawsBrowserAllowList.ps1 -Action Add -Url https://portal.contoso.example/reports -EnvironmentName your-environment -AcknowledgeBrowserAllowList
.\installer\Set-JawsBrowserAllowList.ps1 -Action Remove -Url https://portal.contoso.example/reports -EnvironmentName your-environment -AcknowledgeBrowserAllowList
```

Expected: `Browser allow-list: Add` or `Remove`, `Azure writes: 1`, and `Customer installation accepted: false`. Without `-AcknowledgeBrowserAllowList`, or with `-EnvironmentName dev`, the command throws `JAWS-STEP-D-033` and writes nothing. The URL must be absolute `http` or `https` and must not contain user info.

## Tools

The toolbox exposes `browser_open`, `browser_navigate`, `browser_snapshot`, `browser_click`, `browser_type`, `browser_screenshot`, and `browser_close`. The specialist catalog lists the six action names. Those tools do not require `approve-vm-change`. `vm.run-command` still does.

Credential selectors whose names contain `password`, `passwd`, `secret`, or `token` discard the agent's text. The service fills them from secret `jaws-browser-credentials`, a JSON map of host to `{ "username", "password" }`. Evidence JSONL records the action, target, outcome, duration, and a screenshot reference. It does not record typed text or passwords.

A task stops after 10 minutes or 50 steps. The service returns `allow_list_rejected`, `browser_timeout`, `browser_unreachable`, or `credential_not_registered`. Downloads are disabled. A fourth concurrent session receives `browser_queue_timeout` immediately. There is no wait queue in this release.

## What this release does not prove

`Customer installation accepted` stays false. A Pester pass uses a CLI stand-in. It is not a fresh-subscription receipt.

These checks are not claimed from this installer:

- the Supervisor listing browser tools from an image built before this host change
- a live navigation and value extraction on an allow-listed page
- a vault login whose password is absent from a real site log
- an unreachable Container App returning within 30 seconds
- Foundry reaching the internal Container App over the private path
- JWT signature validation. The service checks that a bearer token's audience contains `api://jaws-browser`. It does not validate the signature against the tenant.

CAPTCHA solving, downloads, uploads, multiple tabs, and video or audio capture are out of scope.
