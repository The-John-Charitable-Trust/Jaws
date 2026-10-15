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

No new Supervisor agent version is created by these commands. The code has not yet been run against this Azure tenant or regression tested. **Review the plan and API resource shape before approving writes**; partial failures require inspecting existing Azure resources, not blindly retrying.

From PowerShell 7 in repository root:

```powershell
.\installer\Install-JawsStepC.ps1 -Mode DelegationPlan
```

Do not use `DelegationInstall` until the read-only discovery succeeds and approves the exact plan hash. The toolbox planning stage depends on a verified connection receipt.

Live acceptance on 2026-10-15 passed against released Supervisor version 5, image `jawsregistrydev001.azurecr.io/jaws/supervisor@sha256:86c556fff7f54eb8ad81c84bc768093fd7bc083e941e9e16bbf1ea8bc0cfa289`. Supervisor v1 is still active on `sha256:d1e03b6c0cf5a1f6f8b531da3af6a63aef6a038d7892cdaec43b456ec4cb7062` and has no toolbox. The call was `jaws-investigation-a2a-dev___SendMessage`, classification `TOOL_INVOKED_SUCCEEDED`, response `caresp_040f45cfb362e093003JXExmmqYApTAgvNgPTx8QNzbrBTDlbx`. The tool result was an A2A task in `TASK_STATE_COMPLETED` whose artifact is a read-only VM investigation plan. Report: `installer/.local/jaws-step-c-final-acceptance.dev.generated.json` (local only). Hosted Investigation v1 remains the Responses runtime and is not the A2A callee.

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
