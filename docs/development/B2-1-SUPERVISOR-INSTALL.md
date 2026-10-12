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

## Dedicated ACR decision and creation procedure (B2, new)

Decision: A dedicated JAWS registry managed by the JAWS installer in the existing `rg-aiops-lab` resource group, `eastus`. The initial SKU is **Basic** with administrator credentials disabled. Public network access is initially enabled to allow the image publishing/hosting path to be validated; this is a provisional network choice and **must be reviewed before an internet-facing production deployment**. The installer does not publish an image, configure RBAC or create a hosted agent in this step.

Registry names must be globally unique, 5-50 lowercase letters/numbers. Choose an available name without assuming the sample name is unique.

**Plan (zero cloud reads or writes):**

```powershell
.\installer\Install-JawsRegistry.ps1 -Mode Plan -RegistryName <unique-lowercase-registry-name>
```

Read `installer/.local/jaws-registry-plan.dev.generated.json`. The report contains `PlanSha256`, exact subscription/resource group/location, SKU, admin setting and billable-cost disclaimer. An actual Basic registry has **ongoing costs**; the report does not verify the precise East US dollar amount. Check the [official pricing calculator](https://azure.microsoft.com/en-us/pricing/calculator/) and obtain spending approval before any creation. Azure budgets issue notifications but do not block spending.

**Explicitly approved Create (billable Azure write):**

```powershell
.\installer\Install-JawsRegistry.ps1 -Mode Create -RegistryName <the-same-name> -ApprovedPlanSha256 <64-hex-character-digest-from-report> -AcknowledgeBillableBasicSku
```

The installer validates the state-selected subscription and resource group, checks global name availability, refuses to adopt an existing registry, issues a single scoped `az acr create`, verifies identity/SKU/login server/admin setting and generates `installer/.local/jaws-registry-receipt.dev.generated.json`. Creation failures may leave a billable partially created registry: **do not immediately retry**; inspect state first. No direct provisioning commands outside installer are permitted.

**Restrictions:** This implementation must pass independent Pester tests before running Create; RegistryName is explicitly operator-chosen and not auto-invented; the plan digest is not an authentication token; Azure RBAC still determines actual provisioning authority; no real prices, available SKU/permissions, private networking, registry-push rights or Foundry pull permissions have been verified. The initial registry is tagged `application=JAWS`, `managedBy=JAWS-Installer`, `environment=dev`. Installer receipts and generated plan files are ignored local evidence, not operator-managed gold state.

Next: installer-controlled ACR image upload and Foundry hosted-agent deployment under separate approved proposals.

## Milestone 1 continuation: publish Supervisor container to dedicated registry

The installer adds `installer/Publish-JawsSupervisor.ps1` with `Plan` and `Publish`. Registry has already been created through `Install-JawsRegistry.ps1`; its locally retained receipt proves only the installation result, and publishing rechecks actual registry identity and tags in Azure.

**First build the local Linux/amd64 Supervisor image through the JAWS installer** (Docker Desktop running):
```powershell
.\installer\Install-Jaws.ps1 -Mode Package -BuildContainer
```
Do not use direct `docker build`, direct `docker push` or manual Azure provisioning commands.

**Create image publication plan (no Azure calls or writes):**
```powershell
.\installer\Publish-JawsSupervisor.ps1 -Mode Plan
```
This requires the saved `installer/.local/jaws-registry-receipt.dev.generated.json`, an authentic local Docker `jaws-supervisor:local` image ID and the JAWS installation state. Review `installer/.local/jaws-supervisor-publish-plan.dev.generated.json`. Record `PlanSha256`, image ID, target fully-qualified immutable-build tag, subscription and resource group. Local image content can change, so approval binds the exact SHA-256 image ID.

**Publish only after separate authorization for this image write and possible storage/network charges:**
```powershell
.\installer\Publish-JawsSupervisor.ps1 -Mode Publish -ApprovedPlanSha256 "<hash-from-the-publish-plan>" -AcknowledgeImageStorageAndTransferCharges
```
The installer verifies subscription and registry identity/ownership, confirms the local image ID has not changed, checks for tag collisions, signs in using Entra-backed Azure CLI + Docker credentials, tags and pushes the image, then verifies the registry manifest digest. An unavailable ACR repository metadata query blocks publication. This command is the only registry image write path. The installer **does not assign RBAC**, so the signed-in publisher must already have `AcrPush` for an RBAC registry (or the corresponding repository writer in ABAC mode). ACR admin credentials remain disabled.

The installation receipt `installer/.local/jaws-supervisor-publish-receipt.dev.generated.json` records the fully qualified digest-pinned image (not the mutable build tag). Failed push/verification may leave a partial registry artifact; **do not retry blindly**.

Microsoft sources:
- https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/deploy-hosted-agent-private-azure-container-registry
- https://learn.microsoft.com/en-us/azure/container-registry/container-registry-authentication-managed-identity
- https://learn.microsoft.com/en-us/cli/azure/acr/manifest

### Acceptance status and remaining deployment work
Prior offline test baseline: 65 passed. Nine new publication tests increase the target to **74**. New tests have not yet run independently. The .NET project was compiled and packaged earlier, but the Linux image is not yet known to be built. **Do not execute Publish until independent tests pass and the exact plan is reviewed.** The next milestone is Foundry hosted-agent deployment through installer under a separate approved plan and ACR pull/hosting permissions.

## Stage B milestone 2: deploy existing published Supervisor image to Foundry (awaiting QA)

Microsoft Foundry's hosted-agent REST API v1 supports agent creation using a published container image, `kind: hosted`, `cpu: 1`, `memory: 2Gi` and Responses protocol version `2.0.0`. It automatically creates an agent version and platform-hosted agent identity. Microsoft documents that Foundry Project Manager at project scope is normally required for deployments, and the project managed identity needs `AcrPull` or `Container Registry Repository Reader` on the ACR. References:
- https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/deploy-hosted-agent
- https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/deploy-hosted-agent-private-azure-container-registry
- https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/hosted-agents

The installer now has `installer/Deploy-JawsSupervisor.ps1` with modes `Plan` and `Deploy`. `Plan` uses the verified image publishing receipt and current authoritative state **without Azure calls or writes**. It binds the exact digest to the Foundry project `jaws-dev`, Foundry account `jaws-foundry-dev`, model deployment `gpt-5-mini` and Supervisor `jaws-supervisor-dev`. Reports go in the ignored `installer/.local` directory.

```powershell
.\installer\Deploy-JawsSupervisor.ps1 -Mode Plan
```

Before billable deployment, independently validate the image URI and plan fingerprint, Foundry quota/hosting support, compute/inference cost exposure, project manager rights and project managed identity image pull. The installer Deployment operation performs read-only project/ACR/RBAC checks and stops on absent permissions. **This first version does NOT automatically grant missing pull permissions or bypass user authorization.** Required RBAC configuration must be implemented through the installer, not manual portal/CLI provisioning.

Only after explicitly approving this exact agent deployment and charges, execute:
```powershell
.\installer\Deploy-JawsSupervisor.ps1 -Mode Deploy -ApprovedPlanSha256 "<plan-sha256>" -AcknowledgeHostingAndInferenceCharges
```

The command uses Microsoft Foundry REST v1 via Azure CLI internally; it refuses an existing agent, then creates one new hosted agent version and writes a local receipt. An Azure error can occur after resource creation; never retry without checking for partial provisioning. This initial operation verifies only that creation began, **not** that hosting became active or responded. Read-only status inspection after creation:
```powershell
.\installer\Test-JawsSupervisorDeployment.ps1
```
This checks the version status from the exact recorded project and agent, without running inference. An authenticated test response will be a separate cost-approved acceptance gate.

New Pester tests (10 deployment tests plus the prior 75 baseline; target at least 85 tests) await independent execution. No Azure hosted agent has been created by these commits.
