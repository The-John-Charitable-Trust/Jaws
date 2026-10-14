# Step C consolidated installer (current incremental release)

Step C has an active Investigation v1, published immutable ACR image, and a passed authenticated Responses invocation. This release consolidates reconciliation and *incoming* A2A configuration. It **does not** yet configure the Foundry RemoteA2A project connection/tool or demonstrate live Supervisor delegation.

## Usage in PowerShell 7 (from repository root)

```powershell
git pull --ff-only origin feature/step-c-investigation-publishing
.\installer\Install-JawsStepC.ps1 -Mode Plan
```

Review the printed fingerprint and generated `installer/.local/jaws-step-c-a2a-plan.dev.generated.json`. **The Plan mode performs authenticated Azure GET calls**, but makes no Azure writes.

After reviewing and approving that exact plan, run:

```powershell
.\installer\Install-JawsStepC.ps1 -Mode Install -ApprovedA2APlanSha256 '<plan fingerprint>' -AcknowledgeAgentEndpointChange
```

Only the Investigation **agent endpoint metadata** is patched, and only if incoming A2A is missing. It does not create new agent versions, rebuild the image, or change Supervisor. The installer performs an authenticated GET of the A2A v1.0 card and persists a receipt. Existing A2A configuration is not overwritten.

```powershell
.\installer\Install-JawsStepC.ps1 -Mode Verify
```

Verify makes no Azure writes. Changes to the agent card, protocols, identity and permissions should be reviewed if verification fails.

## Constraints and next gate
- The consolidated entry point reconciles existing Investigation image/deployment receipts; missing publish/deploy receipts fail closed rather than silently republishing or replacing active resources.
- Foundry A2A requires Microsoft Entra authentication. A2A v1.0 uses JSON-RPC. Tool/connection security will use an agentic identity token and least privilege.
- **Not complete:** Configure the Supervisor's RemoteA2A connection and tool, apply required A2A consumer role, deploy a new Supervisor version without changing v1, and run an end-to-end delegation acceptance test.
- Use no manual agent PATCH commands; this module owns A2A configuration. Test new code locally before approving Azure writes.

Microsoft reference: https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/enable-agent-to-agent-endpoint
