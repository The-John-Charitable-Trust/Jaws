# Step C delegated A2A installer boundaries

The existing Investigation v1 has an active hosted Responses endpoint and an authenticated A2A card. Supervisor v1 MUST remain unchanged.

## Microsoft-supported pattern
1. Create/verify an AgenticIdentityToken RemoteA2A connection targeting Investigation's A2A endpoint.
2. Create an A2A toolbox using the generally available `a2a` tool with `a2a_version=1.0` and the verified connection ID.
3. Extend the **hosted Supervisor runtime code** to register a Foundry toolbox with `AddFoundryToolboxes`, build a *new immutable Supervisor image*, and create **Supervisor v2** with explicit approval. Do not edit Supervisor v1.
4. Validate agentic identity/least-privilege consumer RBAC and invoke Supervisor v2, verifying a genuine delegation tool call and Investigation response. Fail closed on authorization errors.
5. Record live operation evidence and receipts, then update the Standard and Developer/Tester guides.

Official references:
- https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/agent-to-agent
- https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/use-toolbox-hosted-agent

## Current incremental implementation
`Install-JawsStepC.ps1` supports `DelegationPlan`, `DelegationInstall`, and `DelegationVerify`, invoking new connection and toolbox modules. The connection uses the Azure ARM resource API; the toolbox uses the Foundry v1 data plane.

No new Supervisor agent is created by these commands. Supervisor v1 stays unchanged. **Review the plan and API resource shape before approving writes**; partial failures require inspecting existing Azure resources, not blindly retrying. Live closure evidence is in the section below.

From PowerShell 7 in repository root:

```powershell
.\installer\Install-JawsStepC.ps1 -Mode DelegationPlan
```

Do not use `DelegationInstall` until the read-only discovery succeeds and approves the exact plan hash. The toolbox planning stage depends on a verified connection receipt.

## Step C closure (2026-10-15)

Approved architecture, left as deployed:

- `jaws-supervisor-dev` is the hosted Supervisor.
- `jaws-investigation-planner-dev` is the prompt-based A2A Investigation Planner and the RemoteA2A target.
- `jaws-investigation-dev` remains the hosted Investigation runtime. Connecting that runtime to the planner is outside Step C.

Read-only checks against Foundry, plus one stored Supervisor responses call. That call is inference, not a configuration change. No connection, toolbox, role, or agent write was made for this closure.

| Check | Live result |
| --- | --- |
| Supervisor v5 | active, not a draft, kind `hosted`, toolbox `jaws-investigation-a2a-tools`, image `jawsregistrydev001.azurecr.io/jaws/supervisor@sha256:86c556fff7f54eb8ad81c84bc768093fd7bc083e941e9e16bbf1ea8bc0cfa289` |
| Traffic | endpoint selector `@latest`, and `versions.latest` is version 5 |
| Supervisor v1 | active, not a draft, no toolbox variable, image `sha256:d1e03b6c0cf5a1f6f8b531da3af6a63aef6a038d7892cdaec43b456ec4cb7062` |
| RemoteA2A `jaws-investigation-a2a-dev` | `AgenticIdentityToken`, category `RemoteA2A`, audience `https://ai.azure.com`, `isSharedToAll` false, target `.../agents/jaws-investigation-planner-dev/endpoint/protocols/a2a` |
| Toolbox `jaws-investigation-a2a-tools` | default version 2, one `a2a` 1.0 tool, `project_connection_id` only |
| Project agents | `jaws-supervisor-dev`, `jaws-investigation-dev`, `jaws-investigation-planner-dev` |
| RBAC at project scope | one assignment: Foundry Agent Consumer on Supervisor instance principal `e65f1c50-4b9f-4c48-af1f-ccb7c3177f67` |
| Other identities | Supervisor blueprint `acbace23-0d1e-423f-aa25-fad3a12ef97b` and planner principal `02758783-e67e-49f1-b06b-56bde0e49059` have no role assignments |

Version 4's detail is `failed` (`ProvisioningError`). The version list can still show that row as active; the detail GET is the status used here. Versions 2 and 3 remain active historical images and are not `@latest`.

Stored Supervisor response `caresp_0ca3823766edf3dc00biTZLQVBWJSTvfc8sy4PrBBEV9zGJyvB` is `completed` and can be read back. Session `5b802679850695a0c6f87e1189f128cd796efb7d63554c7cabc77425b59478e` is on Supervisor version 5. Container logs for that session show the toolbox `jaws-investigation-a2a-tools` and `Forwarded tools/list metadata onto 1 of 1`. The tool call is `jaws-investigation-a2a-dev___SendMessage` (`call_tlHohbiDcuQQ43WqvR9kFl7E`).

The tool result is the planner's A2A task `resp_098c29f8a8806df9006ad10966aa708190ba2564f9e0b2959e`, context `ctxt_039ac19eefbe45069fcdf51170aa1147`, state `TASK_STATE_COMPLETED`. Its artifact is a read-only plan whose summary and checks are:

- Check 1 — Azure platform / instance state and recent control-plane operations
- Check 2 — Boot diagnostics and serial console (boot-time failure detection)
- Check 3 — Guest OS performance, heartbeats and logs (VM Insights / Log Analytics)

The Supervisor message quotes that response id, `TASK_STATE_COMPLETED`, and those three headings. It reports the plan and does not request remediation.

The planner's own response list stores A2A work with `agent_reference.name` `jaws-investigation-planner-dev` version 1 and `metadata.protocol` `a2a`. The stored row is the direct `SendMessage` `resp_0be360f86e19617e006ad1019d2c108190bac9557c35c23004` (context `ctxt_d1134ca39cfa48eda89cf478595d9a0b`). The Supervisor-mediated task id is not on that list, and a later GET of it returns 404. Foundry returned that task inline. The toolbox tool has no `base_url`, so the completed task was produced by the connection target, which is the planner A2A endpoint.

Earlier acceptance response `caresp_040f45cfb362e093003JXExmmqYApTAgvNgPTx8QNzbrBTDlbx` used `store=false` and is no longer readable. The stored response above is the closure evidence.

Regression on this closure: installer Pester 168 passed; Step C offline tests 15 passed; toolbox metadata probe passed; first-agent checks 26 passed.

Hosted Investigation v1 stays active for later read-only execution work. This closure does not require that container to run the planning call.

## JAWS-C-ACCEPT-007 / TOOL_INVOKED_FAILED

`SupervisorV2Verify` can show a completed response, a real `jaws-investigation-a2a-dev__SendMessage` call, and tool output `Error: Function failed.` Connection, toolbox v2, and Foundry Agent Consumer checks can all pass before that. Two separate causes have shown up behind that text.

The hosting package lists the toolbox tool, then calls it without the `_meta` block from `tools/list` (including `tool_configuration`). The Foundry toolbox proxy rejects that call. The agent framework hides the proxy error when detailed function errors are off, so the acceptance report only contains `Error: Function failed.`

After that metadata is forwarded, Foundry still returns A2A JSON-RPC `-32099` with reason `HOSTED_AGENT_NOT_SUPPORTED` when the RemoteA2A target is hosted `jaws-investigation-dev`. Direct `SendMessage` against that endpoint returns the same error and tells the caller to use a prompt agent. Hosted Investigation v1 stays active and unchanged. The connection target for `jaws-investigation-a2a-dev` is prompt agent `jaws-investigation-planner-dev`, which accepts A2A 1.0 `SendMessage` and returns a read-only plan. Retarget the existing connection only from the hosted URL, with the plan SHA:

```powershell
.\installer\Configure-JawsDelegationConnection.ps1 -Mode Plan
.\installer\Configure-JawsDelegationConnection.ps1 -Mode Retarget -ApprovedPlanSha256 '<plan-sha>' -AcknowledgeA2AConnection
```

`FoundryToolboxMetadataStartup` forwards that listed metadata onto toolbox tools enumerated at startup. Foundry can also create those wrappers later, on the request, after a deferred toolbox retry. `ForwardBeforeInvocation` forwards the same metadata onto the tools for that run before the agent invokes them, and it leaves non-MCP tools in the list unchanged. Candidate release uses the same paginated version inventory as deployment, and every page requests drafts. Supervisor v1 stays unchanged. From the repository root in PowerShell 7:

```powershell
.\installer\Install-JawsStepC.ps1 -Mode SupervisorV2Build
.\installer\Install-JawsStepC.ps1 -Mode SupervisorV2Publish
.\installer\Install-JawsStepC.ps1 -Mode SupervisorV2Deploy
.\installer\Install-JawsStepC.ps1 -Mode SupervisorCandidateRelease
.\installer\Install-JawsStepC.ps1 -Mode SupervisorV2Verify -ExpectedImage 'jawsregistrydev001.azurecr.io/jaws/supervisor@sha256:<new-digest>'
```

`SupervisorV2Deploy` creates a draft for the published digest and does not patch an existing version. `SupervisorCandidateRelease` creates the next non-draft version from that draft. Acceptance invokes whichever released version Foundry routes as latest, and it rejects the call unless that version's image is the digest you pass.

## Supervisor candidate deployment reconciliation (October 2026)

The Step C installer now reconciles the *published immutable image* against Foundry agent versions. Do not manually GET a draft identifier from a submission response or blindly repeat `SupervisorV2Deploy` after HTTP 404.

Use:
```powershell
.\installer\Install-JawsStepC.ps1 -Mode SupervisorCandidateReconcile
```
This is read-only and produces `installer/.local/jaws-step-c-supervisor-deployment-verified.dev.generated.json`. If the candidate is still being indexed or provisioning:
```powershell
.\installer\Install-JawsStepC.ps1 -Mode SupervisorCandidateWait
```
The bounded monitor locates versions by the verified ACR image digest and toolbox configuration. Foundry's version list omits drafts unless `include_drafts=true`, so every inventory page, including a continuation, requests that flag. A candidate that is active on one read can still fail provisioning, so the wait requires the same version to stay active across repeated reads before release. The monitor also inspects version details when list responses contain summaries. A 404 on a version detail is treated as temporary inventory inconsistency, not permission to create another draft. Build the Supervisor image with Buildx. The legacy builder pushed docker layer media types, and Foundry provisioning failed for that image.

A new approved `SupervisorV2Deploy` operation also runs reconciliation automatically after submitting the draft. Success means an active and unique matching draft. If reconciliation fails or times out, the installer records an indeterminate/failed receipt and **must not automatically create another draft**.

`SupervisorCandidateRelease` requires the active candidate's verified local receipt, matching released image and resolved draft version. Release has its own approval because it can change latest-version traffic. Final `SupervisorV2Verify` still requires successful authenticated Investigation invocation. The installer never treats a completed Supervisor response with failed function output as acceptance.

Regression suite (requires PowerShell 7 and Pester 5):
```powershell
Invoke-Pester .\tests\installer\SupervisorCandidateLifecycle.Tests.ps1 -Output Detailed
```
The mocked suite covers empty inventories, delayed visibility, version detail hydration, ambiguity, pagination, terminal errors, and timeout. These tests do not replace live read-only reconciliation.
