# JAWS Stage B1 — Installer-Only Provisioning Contract

> **Historical proposal.** The customer `-Mode Install` described here is not implemented. `Install-Jaws.ps1` is still Discover, Plan, and Package. The executable dev-project path through Step C is `installer/Install-JawsThroughStepC.ps1`. See `docs/installation/STEP-C-RUNBOOK.md`.

Status: PROPOSED FOR REVIEW | No installer source changes in B1

## 1. Baseline
Current repository `installer/Install-Jaws.ps1` v0.4.6 accepts only `-Mode Discover`; requires a pre-existing authoritative JAWS state file; tenant scan and target comparison are read-only; JSON reports go under `installer/.local`. The development state contains four externally owned resources and must remain untouched. Do not claim the Stage B test-candidate ZIP is merged into this branch.

## 2. Proposed installer modes
- `Discover`: preserve Stage A semantics unchanged.
- `Plan`: validate credentials, region/capability/quotas, state, ownership, RBAC, dependencies, intended SKUs and cost exposure; output a deterministic signed/hashable plan with Create/Reuse/Configure/Block actions; write NOTHING in Azure.
- `Install`: require explicit approval of a specific, unexpired plan; revalidate assumptions; implement only approved cloud writes, reusing compliant resources and stopping on ambiguous ownership/drift.
- `Validate`: verify provisioned resources, security configuration, endpoints, authenticated supervisor/worker messaging, permissions and optional specifically approved live inference. Do not auto-provision in validation.
- `Upgrade/Repair`: future explicit modes; diff/approve changes, preserve tracked resources, prevent destructive changes without separate approval.

## 3. Resource dependency graph
1. Subscription/tenant/region and resource group (user-selected, authorized).
2. Existing Foundry resource/project/model or approved new Foundry provision.
3. Key Vault with RBAC and purge protection, managed identities, scoped secrets and logging.
4. Supervisor Hosted Agent runtime and endpoint.
5. Azure worker runtime + official Azure MCP connectivity + authorization broker.
6. Datadog worker runtime + custom MCP server + user-scoped Datadog authorization.
7. Separate constrained worker execution sandboxes.
8. Session/project store, observability/audit telemetry, policy and approval service.
9. Teams/Bot integration and Teams package configuration; report any Microsoft 365 admin approval as an external manual authorization gate, not a workaround.
10. Application-level health checks and end-to-end response verification.

Resource creation order may change after validated technical dependencies; installer must compute a DAG and refuse missing dependency.

## 4. Desired-state and ownership records
Separate an operator-approved desired configuration (gold copy) from installer-generated observed deployment inventory and immutable audit evidence. Each record: type, name, scope, resource ID (only verified values), config fingerprint, ownership (External/InstallerCreated), CreatedByInstaller, version, prior state, timestamp, status. Reject duplicate and legacy resources. No silent adoption or rewriting of operator state in Discover. New customers generate state only after authenticated approved install and successful verification.

## 5. Cost safety
Offline mock tests cost no Azure usage. Plan mode must identify billable SKUs and estimate or state when costs cannot be reliably estimated (Foundry inference, Container Apps sessions, logs/storage, hosted agents, networking); budgets are alerts, NOT a hard cap. Require operator approval for live model inference, paid compute, and any resources with ongoing idle costs. Record cap configuration, test environment and anticipated cleanup in the plan. Never deploy through example commands outside installer.

## 6. Execution and rollback
- Lock against concurrent installation to same environment.
- Generate correlation ID and append-only operation log.
- Use minimal permissions and scoped ARM/CLI/SDK calls internally; prohibit accidental subscription switching.
- Apply deterministic retries only for safe/idempotent operations.
- Persist successful steps and verified resource IDs before continuing; resume safely after interruption.
- Do not delete externally owned resources. Rollback may delete only owned, tagged, explicitly approved resources where safe, respecting Key Vault purge protection.
- Stop on security/control drift; emit actionable but installer-mediated repair recommendations.

## 7. Documentation contract
Standard installation guide: Git clone, prerequisites, installer options, plan review, approvals, progress, validation, troubleshooting, cost disclosure.
Developer/Tester guide: code build, Pester 5 tests, negative cases, mocks, state migration, QA evidence, independent subscription testing.
Development tutorial: precise source paths, architecture diagrams, C#/Python code when implemented, test commands and expected results. No fabricated screenshots/results.

## 8. Exit checks before B2 acceptance
No Azure provisioning commands outside installer call chain; mock tests demonstrate zero writes for Discover/Plan/Validate; ownership/drift blocks; idempotent second install; approval requirement; default-deny on user permission mismatch; costs disclosed; full evidence files generated and excluded from Git where sensitive.

## 9. B2 implementation checkpoint (offline blueprint)
B2 begins with `-Mode Plan` using `installer/config/jaws-stage-b-plan.example.json`, `installer/modules/DeploymentPlan.psm1`, and `tests/installer/DeploymentPlan.Tests.ps1`. The operator must copy the blueprint to a local ignored location and replace the example subscription ID. The prototype validates dependency order, component approval flags and explicit no-write policy, produces a generated report under `installer/.local`, and performs **no** Azure discovery or network call. It deliberately blocks execution. Live `Install` and cloud-aware `Validate` remain future functionality. The prototype output cannot be authorized or executed as a cloud resource change plan.
