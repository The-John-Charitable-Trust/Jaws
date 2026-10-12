# Stage B2.1 — First Supervisor Installation Checkpoint

**Status:** Deployment preparation implemented; deployment NOT executed, not approved and not yet enabled. No Azure resources modified.

## What exists
- Stage A read-only `Discover` and B2 offline/Azure-aware `Plan` remain unchanged in intent.
- New `installer/modules/SupervisorInstall.psm1` constructs a proposal bound to a Foundry resource, project, Supervisor name, subscription and exact ACR sha256 image digest.
- `installer/Install-Jaws.ps1 -Mode Plan -AzureAware -SupervisorImage <ACR-digest>` writes a blocked proposal under `installer/.local`.
- Seven Pester tests under `tests/installer/SupervisorInstall.Tests.ps1` test fingerprint stability, unpinned-image rejection, drift/ownership checks and absence of active Install mode.
- The project `docs/tutorial/index.html` original learning tutorial remains untouched.

## Architecture and Microsoft Foundry basis
Microsoft's current hosted-agent documentation describes a Linux/amd64 container supporting Responses v2.0.0, a Foundry project, a supported model, appropriate Foundry project permissions and ACR image-reader access for the Foundry project managed identity. Foundry charges may begin on deployment. See:
- https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/deploy-hosted-agent
- https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/deploy-hosted-agent-code

## Deployment prerequisites (must be satisfied before any Azure write)
1. Build and test the actual .NET 10 JAWS Supervisor Responses agent runtime. A local tutorial agent or a Foundry model deployment alone is not a hosted-agent runtime.
2. Decide installer-managed source-code deployment versus container-image deployment. Current B2.1 proposal supports the container image route. For the chosen route, automate build/package/ACR creation and publishing INSIDE the installer, not in manual Azure commands.
3. Verify project/region supports hosted agents, requested CPU/memory, model and the chosen hosting method.
4. Verify authenticated installer's project authorization, project identity registry-read rights, resource ownership and required service identities.
5. Produce real SKU/cost exposure, an expiry-bound operator approval, and a no-duplicate safe deployment/retry process.
6. Implement installer `Install` for only the exact approved operation, verify deployment reaches Active, record immutable evidence/state and support safe resume.
7. Run independent mocked tests first and live testing only after explicit authorization.

## Next QA steps
- Synchronize branch `codex/0.2-add-mcp-server`.
- In PowerShell 7, run `Import-Module Pester -RequiredVersion 5.9.1 -Force; Invoke-Pester .\tests\installer\ -Output Detailed`. Previous accepted baseline 38; with seven added tests expect 45 discovered. These seven have NOT been independently executed at commit time.
- Verify no `-Mode Install` and no Azure writes. Test name/image constraints and proposal fingerprint.
- Do not use a fabricated digest as if it were a built image. Do not run the sample proposal against Azure until a real image is approved.

**End-of-Stage-B acceptance:** a deployed operational Supervisor, Azure security/compliance worker, Datadog worker, isolated compute, project conversation persistence, authorization and Teams end-to-end capability. B2.1 is only the first installation-enablement step.

## Runtime source and packaging checkpoint (new; pending execution)
- Source: `src/Jaws.Supervisor.Host/Program.cs`, project `Jaws.Supervisor.Host.csproj` and its Linux/amd64 `Dockerfile`.
- Uses Microsoft Agent Framework Foundry Responses hosting, `DefaultAzureCredential`, `FOUNDRY_PROJECT_ENDPOINT` and `AZURE_AI_MODEL_DEPLOYMENT_NAME`. Supervisor has no worker tools or authorization broker yet and must never imply otherwise.
- The JAWS installer now supports `-Mode Package`: local `.NET 10 dotnet publish` and optional `-BuildContainer` (local Docker build only). Results reside in `installer/.local/supervisor/publish`; no ACR image push or Azure deployment occurs.
- Run `dotnet build Jaws.slnx -c Release`, `.\installer\Install-Jaws.ps1 -Mode Package`, then `Invoke-Pester .\tests\installer\ -Output Detailed` in an approved PowerShell 7 terminal. Optional `.\installer\Install-Jaws.ps1 -Mode Package -BuildContainer` requires Docker.
- Baseline is 45 accepted Pester tests; five new tests target a total of 50. Build and tests are **unverified** until run on an actual Windows .NET 10 workstation.
- Target Azure deployment remains blocked until image registry creation/push, Foundry supported deployment API integration, proper delegated/installer authorization, cost approval, controlled Install, and live validation are implemented.

Microsoft source: https://learn.microsoft.com/en-us/azure/foundry/how-to/develop/framework-hosted-agents

## Milestone 1: ACR readiness checkpoint (implemented, untested)
The installer supports **opt-in read-only assessment** of an existing Azure Container Registry when the Azure-aware Plan runs. It does not create, configure or publish an image; the installer still does not expose a cloud `Install` mode. This is the first registry-integration substep, not the complete milestone.

The operator supplies the *real* authorized registry name only if an existing registry is available:
```powershell
.\installer\Install-Jaws.ps1 -Mode Plan -AzureAware `
    -PlanFile ".\installer\.local\jaws-plan.dev.json" `
    -StateFile ".\installer\config\jaws-installation-state.dev.json" `
    -RegistryName "<existing-registry-name>" -NonInteractive
```
The generated ignored report is `installer/.local/jaws-acr-readiness.dev.generated.json`. If the registry is absent, the installer blocks with `JAWS-ACR-005` rather than automatically provisioning or creating costs. It verifies registry ID and login server match the exact subscription/resource group, observes SKU and admin/network fields, and records **CanPublish=false**, **AzureWrites=0**, and unverified push/pull authorization, costs and ownership. The assessment should not be run with a guessed registry name.

Microsoft currently recommends reusing a centrally administered ACR where possible. Local Docker push requires `AcrPush` or scoped Repository Writer for ABAC registries; managed Foundry agent image pull requires separate permissions. ACR Basic/Standard/Premium registries can incur charges even without active image pushes. Choose reuse or new-registry provisioning only after pricing, networking, role scopes and ownership review.
Source: https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/deploy-hosted-agent-private-azure-container-registry

### Tests
`tests/installer/RegistryReadiness.Tests.ps1` adds six mocked cases; accepted previous baseline: 51 tests. Expected new discovery count: **57** (not executed yet). No permission or billing claims are made based on mocked tests.

### Next required implementation
1. Select the existing ACR for reuse, or approve creation through the JAWS installer with clear SKU/network/retention and budget.
2. Implement opt-in installer publishing, verify registry write authorization and content digest, use no passwords or local privileged token persistence.
3. Implement hosted-agent version creation via supported Foundry API/SDK; validate live health/invocation, agent pull permissions, and state ownership. Require a separately authorized exact installation plan and cost exposure before Azure writes.
