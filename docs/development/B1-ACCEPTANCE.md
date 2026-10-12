# JAWS Stage B1 — Architecture Review and Acceptance Plan
Status: PROPOSED FOR REVIEW | No cloud testing/deployment in B1

## 1. B1 documentation acceptance
| ID | Acceptance criterion | Evidence |
|---|---|---|
| B1-001 | Original Agent Framework tutorial preserved unchanged | Git diff excludes docs/tutorial/index.html |
| B1-002 | Architecture shows Teams, Supervisor, Azure specialist, Datadog specialist, MCP and isolated runtimes | B1-ARCHITECTURE.md |
| B1-003 | Identity/authorization prevents privilege elevation beyond the user | B1-SECURITY.md, negative test matrix |
| B1-004 | Installer exclusively controls Azure installation/configuration | B1-INSTALLER.md, future static tests |
| B1-005 | Stage A Discover behavior and accepted tests preserved | Installer unchanged; 21/21 prior accepted baseline |
| B1-006 | Clear Plan/Install/Validate approval, drift and ownership contracts | B1-INSTALLER.md |
| B1-007 | Test cost policy and cloud deployment gates explicit | B1-INSTALLER.md, below |
| B1-008 | New development tutorial links to specifications and separates planned versus completed | docs/development/index.html |
| B1-009 | Design uncertainties and operational dependencies stated without claims of readiness | B1-ARCHITECTURE.md open decisions |
| B1-010 | No Azure mutations and no executable source changes in B1 | Git changes only docs/development |

## 2. Subsequent testing gates (NOT B1 test execution)
**Gate 0: Offline**. Dotnet build/tests, Pester 5 all installer tests, mocked worker/MCP/Teams, security denials. Cost: no Azure resource provisioning.
**Gate 1: Read-only**. Authorized Azure Reader, existing resources, Stage A Discover/Stage B Plan when implemented. No resource creation or model inference required.
**Gate 2: Controlled live**. Dedicated subscription or approved isolated resource group; explicit authorized cost-bearing plan; minimum SKUs/quotas; no public endpoints unless reviewed; runtime limits; budget alerts and charge monitoring (not hard spending limit). Execute only through approved installer.
**Gate 3: Reinstallation and incident cases**. Idempotency, drift, denied writes, timeout, worker failure, external ownership preservation, cost and cleanup receipts.

## 3. Implementation-level test case register
| ID | Scenario | Expected |
|---|---|---|
| B-SEC-01 | A Reader asks worker to modify VM | Denied regardless of worker service identity |
| B-SEC-02 | User authorized for Azure but not Datadog | Datadog tools denied |
| B-SEC-03 | Worker for project A asks for project B context | Denied and logged |
| B-SEC-04 | Model text requests forbidden MCP tool | Denied, no execution |
| B-SEC-05 | Approval expired, reused, or mismatched script | Denied |
| B-SEC-06 | Sandbox attempts unapproved network or filesystem access | Denied, terminated and logged |
| B-INST-01 | Discover, Plan, Validate executed in offline test | Zero Azure writes |
| B-INST-02 | New installation plan missing authorized permissions | Block before write |
| B-INST-03 | Second identical install | No duplicate resources or RBAC assignments |
| B-INST-04 | Existing external Foundry/Key Vault differs from desired state | Safe Block, no overwrite |
| B-INST-05 | Partly failed install resumes | No orphaned duplicated resources |
| B-INST-06 | SKU not available or cost unestimated | Explicit Block or separate informed approval |
| B-A2A-01 | Supervisor delegates to both workers | Valid typed responses share correlation and project scope |
| B-A2A-02 | Worker exceeds timeout / loops | Supervisor terminates, preserves partial evidence, returns safe error |
| B-TEAMS-01 | Teams user switches project | New context bound; no bleed from prior project |
| B-TEAMS-02 | Teams admin consent absent | Installer reports pending approval; does not bypass |
| B-E2E-01 | Teams compliance + observability question | Evidence returned from both specialist paths with provenance |

## 4. Test case evidence required
ID, source revision, prereqs, identity/scope, test procedure, expected/actual, PASS/FAIL/BLOCKED, correlated output, screenshots where genuine, environment spend when live, and defects with severity/reproduction. Codex is independent QA only; no code edit, Git push or Azure mutations without separate authorization.

## 5. B1 approval checkpoint
Approve: supervisor/worker split; hosted-agent vs sandbox feasibility assumptions; credentials/delegation approach; project mapping; MCP responsibility boundary; installer scope and cost controls. Until explicit architecture approval, all Stage B components remain proposed, not production-ready.

## 6. Mandatory end-of-Stage-B operational acceptance (controlling requirement)
Stage B is NOT complete when only specifications, source code, simulated MCP calls or deployment scripts exist. It closes only after the installer provisions/configures the approved Azure environment and the following installed components pass authorized live tests: Microsoft Foundry resources and model; a reachable Supervisor; Azure VM security/compliance worker with working Azure MCP integration; Datadog worker with working custom MCP integration; separate bounded worker execution environments; Teams app and authenticated conversation routing; validated supervisor-worker communications; project-scoped conversation persistence; delegated authorization and human approvals; installation state, reinstallation and end-to-end evidence. Tenant administrator approvals and third-party Datadog authorization may legitimately be BLOCKED; any blocked mandatory item prevents Stage B acceptance. All Azure provisioning and configuration is installer-only. Cost-bearing tests require an explicitly approved plan and spending exposure.

## 7. B2 first checkpoint — offline Plan prototype
The first B2 checkpoint validates a 16-component dependency blueprint without contacting Azure, querying prices, performing inference or creating resources. Its output must explicitly report `BLOCKED_PENDING_AZURE_DISCOVERY_AND_APPROVAL` and `CanExecute=false`. This is **not** an executable provisioning plan. Before implementing `Install`, a later Azure-aware Plan must verify actual resource state, RBAC, cost estimates, SKUs, ownership, and required admin approvals.
