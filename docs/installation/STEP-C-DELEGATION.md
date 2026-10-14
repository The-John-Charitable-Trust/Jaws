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

The overall Step C milestone is incomplete until Supervisor v2 has been built/deployed and a real delegated investigation succeeds.
