# CODEX Implementation Specification: JAWS Greenfield Installer, Customer Documentation, and Acceptance Validation

**Repository:** https://github.com/The-John-Charitable-Trust/Jaws  
**Integration branch:** `feature/step-c-investigation-publishing`  
**Priority:** High  
**Objective:** Support first-time JAWS installation into a customer's own Azure subscription, with synchronized documentation, tests, traceability, and implementation status.

## 1. Problem Statement

JAWS has engineering implementations accepted through Step C in the existing development environment. The current process relies on established Azure resources and installation state. `installer/Install-Jaws.ps1` supports `Discover`, `Plan`, and `Package`, but lacks a complete greenfield `Install` workflow. The Step C installer validates and selectively repairs the existing development environment; it is not a customer installation solution. Documentation is also written partly for project insiders rather than first-time customers.

**Objective:** A customer can clone JAWS, authenticate to an authorized Azure subscription, review and approve the deployment, install the currently supported JAWS release without pre-existing JAWS resources or manual resource provisioning, and validate the installation.

## 2. Governing Principles

1. Microsoft Learn and Microsoft technical documentation govern supported Foundry, agent hosting, MCP, A2A, identity, deployment and security patterns.
2. Preserve the accepted JAWS architecture and Step C implementation, including regression tests.
3. The main PowerShell installer orchestrates installation, configuration, validation, upgrades and repairs; customers must not manually provision resources using separate Azure CLI commands.
4. Do not require pre-existing JAWS resources or manual edits to configuration JSON.
5. Apply managed identities, Microsoft Entra ID, least-privilege Azure RBAC, Azure Key Vault and security boundaries as appropriate.
6. Require explicit authorization for Azure mutations; distinguish deployment consent from billable inference consent.
7. Support safe retries, discovery, reconciliation, idempotency and recovery. Never silently adopt, overwrite or delete unrelated resources.
8. Preserve immutable container image references and verified versions. Do not introduce unnecessary agents or infrastructure.
9. Document implemented functionality truthfully. Every accepted milestone needs objective tests, evidence, and a concrete achieved value proposition.
10. Preserve existing code, tests, and documentation except where justified by this work.

## 3. Approved Architecture and Scope

Follow `docs/installation/IMPLEMENTATION_ROADMAP.md` as the authoritative Steps A–I architecture.

- Microsoft Teams is the planned interaction channel; a Supervisor routes requests to specialist agents.
- The future Virtual Machine Specialist is **one agent** that investigates, deliberates and remediates VM issues, owning one compute environment and using Azure MCP.
- The future Observability Specialist accesses shared compute through one custom MCP server supporting Datadog, Azure Monitor, Microsoft Sentinel and ServiceNow incident records.
- Operator-scoped RBAC, project-specific conversations and audit evidence govern the system.
- **Do not introduce separate Investigation, Deliberation and Remediation agents.**

Preserve Step C: hosted Supervisor v5, RemoteA2A connection, Investigation Planner prompt agent v1, toolbox v2, and the hosted Investigation runtime. Step C's successful A2A planning **does not** prove that the hosted Investigation runtime executed investigation steps.

**Release scope:** Implement greenfield installation of capabilities that currently exist through Step C. Do not manufacture Steps D–I merely to make the documentation appear complete.

## 4. Workstream A: Greenfield Installer

### A1. Single entry point

Extend `installer/Install-Jaws.ps1` with:

```powershell
.\installer\Install-Jaws.ps1 -Mode Install
```

Preserve existing `Discover`, `Plan`, and `Package` modes. The main installer must orchestrate internal scripts and modules. Support noninteractive operation with explicit inputs and approval parameters for automated deployment.

### A2. Interactive installation sequence

1. Verify host software and Azure prerequisites.
2. Authenticate or reuse an authorized Azure CLI session.
3. List accessible subscriptions and prompt for selection.
4. Verify selected Entra tenant and subscription identity.
5. Prompt for existing/new resource group, Azure region and environment name.
6. Validate resource provider availability, model region/quota, capacity, billing constraints and Azure Policy restrictions.
7. Check resource management, role assignment, Foundry management and data-plane permissions at the **actual required scopes**.
8. Discover candidate existing resources, verifying provenance before reuse.
9. Generate a dependency-aware deployment plan listing resources, names, identities, network/security settings, changes and expected costs.
10. Obtain explicit consent before each category of billable provisioning, privileged role assignment or inference.
11. Provision or reconcile authorized resources.
12. Deploy and configure supported hosted agents, models, MCP/A2A connections and toolbox.
13. Generate installation-specific verified state.
14. Run resource and functional validation by milestone.
15. Report successful, partial or failed installation with detailed evidence, diagnostics and recovery actions.

Never hardcode the development subscription, tenant, resource group, registry or Foundry project.

### A3. Azure authorization

| Operation | Expected access / behavior |
|---|---|
| Subscription discovery / read-only inventory | Reader or equivalent scoped access; extra Foundry data-plane rights where required |
| Resource group and resources | Contributor at the resource group, or subscription scope if creating the resource group; narrower custom roles permitted |
| RBAC role assignment | Role Based Access Control Administrator or other narrowly scoped role with required `Microsoft.Authorization/roleAssignments/write` permission, possibly assigned to a separate administrator |
| Foundry projects / hosted agents | Required Foundry management and data-plane privileges, validated separately |
| Operational investigation / changes | Task- and operator-scoped permissions; approvals before writes |

Contributor alone is **not** sufficient for role assignment. Do not automatically grant Owner or broad User Access Administrator roles. A failed permission check must report the missing action, role and scope.

### A4. Provisioning

Provision or verify the resources needed for the *currently supported* JAWS release:

- Resource group; Foundry resources, project and supported model deployment.
- Azure Container Registry, Key Vault, identities and least-privilege role assignments.
- Immutable hosted-agent container images and approved releases.
- Supervisor, A2A prompt planner, RemoteA2A connection, toolbox and required identity binding.
- Logging/diagnostic configuration, applicable networking and security restrictions.

Use existing supported modules and IaC definitions where possible. Any Bicep or other templates remain behind the PowerShell installer, never an undocumented operator procedure.

### A5. State, installation modes and recovery

Generate unique state per subscription, resource group and environment, including verified resource IDs, ownership/adoption status, deployment versions and digests, identities, roles, model information, milestone outcomes and evidence references. **Never store secrets.** Never use the existing development state as a mandatory customer template.

Support the following customer-facing capabilities, via modes or consistently documented subcommands:

| Capability | Required behavior |
|---|---|
| Discover | Read-only inventory |
| Plan | No-write deployment/reconciliation proposal |
| Package | Build and validate local artifacts |
| Install | Approved new resource provisioning |
| Validate | Resource and functional acceptance tests |
| Repair | Approved corrections of supported drift |
| Upgrade | Approved version transition retaining state |

Avoid destructive uninstall without separate approval. On rerun, verify resources, avoid duplicates, reject unsafe adoption and allow safe resume. Never mark a partially completed installation as fully accepted.

### A6. Approval gates

Obtain explicit authorization for billable infrastructure, model deployments, role assignments, configuration changes, agent-version release, repair, upgrade, and separately billed inference validation. Pure validation must not modify Azure configuration. Clearly record approval categories and decisions.

## 5. Workstream B: New-Customer Documentation

Every public page must speak to a first-time customer, Azure administrator, installation engineer, developer or tester, not to the original architect.

### B1. Quick Start: `docs/status/quick-start.html`

Explain what JAWS installs, host and software prerequisites (with official download links), Azure subscription and roles, supported regions/model capacity, clone procedure, single installer entry point, required prompts, approval, acceptance commands, expected results, evidence locations, troubleshooting and recovery.

Software inventory must cover PowerShell 7, Git, Azure CLI, WSL 2, Docker Desktop Linux containers, .NET SDK 10, Pester 5 and VS Code **where applicable**. Distinguish normal operators from local source builders/testers. Never present speculative, nonfunctional commands as supported.

### B2. Standard Guide: `docs/installation/standard/index.html`

Write a complete user walkthrough for subscription/resource group selection, permission preflight, proposed deployment, consent gates, provisioning, configuration, validation, expected results, and recovery. No code editing or standalone manual Azure provisioning.

### B3. Developer / Tester Guide: `docs/installation/developer/index.html`

Document reproducible development environment setup, source and branch management, PowerShell/.NET tests, Docker image checks, module tests, greenfield integration testing, repair/upgrade/idempotency regression, Azure functional acceptance and sanitized evidence.

### B4. Microsoft References & Acceptance: `docs/status/references.html`

For each Step A–I provide: title, value proposition, components, installer module, code files, Azure resources, relevant **specific** Microsoft Learn and technical documentation, configuration requirements, objective criteria, test cases, expected and actual results, evidence links, status and limitations.

### B5. Status: `docs/status/index.html`

Distinguish planned, implemented-unvalidated, partial, accepted in development, validated in new subscription, production-ready, and blocked. Development acceptance is **not** customer installation acceptance.

### B6. Architecture & ConOps

Maintain canonical diagrams:

- `docs/architecture/system-architecture.svg`
- `docs/architecture/concept-of-operations.svg`

And status versions:

- `docs/status/system-architecture-status.svg`
- `docs/status/concept-of-operations-status.svg`

Reference diagrams show the end state; status versions show verified, evidence-backed implementation with matching components, relationships and labels. Preserve the original enterprise architecture poster's quality and detail standards.

### B7. Documentation landing page: `docs/index.html`

Directly link Quick Start, Standard Guide, Developer Guide, end-state architecture, ConOps, status, references/acceptance, tutorial and repository. Verify **rendered GitHub Pages URLs**, not just GitHub source links.

## 6. Workstream C: Traceability

For every Step A–I, align the roadmap, code, installer modules, published HTML and structured status records with:

| Field | Required record |
|---|---|
| Step and capability | What is implemented |
| Value proposition | What customer can now achieve |
| Installer source | Installing/configuring code |
| Azure resources | Deployed/updated infrastructure |
| Code | C#, PowerShell, JSON and IaC references |
| Microsoft source | Exact relevant guidance |
| Acceptance case | Objective test, expected output and actual result |
| Evidence | Sanitized output, test report and commit/release |
| Status | Evidence-backed outcome |

Avoid conflicting step definitions across different pages.

## 7. Workstream D: Acceptance Tests

| ID | Scenario | Required result |
|---|---|---|
| GF-01 | New subscription without JAWS | Successful discovery, plan and supported-release installation |
| GF-02 | Empty existing resource group | Install without existing JAWS state |
| GF-03 | New resource group | Create only after approval |
| GF-04 | Reader-only identity | Discover succeeds; unauthorized provisioning blocked |
| GF-05 | Contributor without role assignment | Report missing RBAC assignment authority |
| GF-06 | Insufficient model quota | Block early with specific diagnostic |
| GF-07 | Unsupported region/model | Identify before deployment |
| GF-08 | Required provider unavailable | Report missing provider and registration path |
| GF-09 | Approved greenfield installation | Required resources and agent connections pass validation |
| GF-10 | Repeated installation | No needless duplicates or release churn |
| GF-11 | Interrupted installation | Resume verified work safely |
| GF-12 | Conflicting resource | Refuse unapproved adoption/overwrite |
| GF-13 | Secret handling | No secrets in output, reports or commits |
| GF-14 | Approval rejected | Zero unauthorized Azure writes |
| GF-15 | No inference consent | No billable model functional test |
| GF-16 | Step C regression | Supervisor → planner A2A still succeeds |
| GF-17 | Supervisor version preservation | Retain previously accepted versions |
| GF-18 | Repair/upgrade | Only approved changes; preserve audit state |
| GF-19 | Public documentation links | Pages URLs resolve correctly |
| GF-20 | Published commands | Match implemented and tested commands |
| GF-21 | Status consistency | Status/criteria match acceptance evidence |
| GF-22 | Independent new-customer walkthrough | Install successfully without undocumented manual setup |

Run billable/live tests only with explicit authorization in a designated Azure test subscription. Report unavailable tests as **BLOCKED**, never PASSED.

## 8. Deliverables

1. Functional greenfield installer with subscription-independent discovery, preflight, permissions, plan, consent, provisioning and verification.
2. Resource/identity/model/container/tool integration for supported Steps A–C.
3. Per-installation state, safe rerun, repair and upgrade interfaces.
4. Automated unit/Pester/.NET tests and authorized Azure integration evidence.
5. Updated Quick Start, Standard and Developer/Tester guides.
6. Updated Microsoft References & Acceptance page with per-step business value.
7. Updated implementation status, diagrams and associated structured state.
8. Updated homepage and GitHub Pages navigation/links.
9. Consolidated test/defect report and release readiness report.
10. Pull request with code inventory, evidence, limitations and commit references.

## 9. GitHub and Delivery Constraints

- Create a dedicated feature branch.
- Preserve accepted Step C functionality and tests.
- Use logically scoped commits.
- Never commit secrets, tokens, private keys or sensitive state.
- Do not deploy or run billable Azure acceptance without explicit approval.
- Submit a PR with exact file changes, executed tests and blockers.
- **Do not merge before review and authorization.**
- **Do not claim complete installation from mock tests, documentation edits or existing DEV validation alone.**

## 10. Definition of Done

Mark this task **Greenfield Installation Accepted** only after an independent tester, starting without JAWS resources, can:

1. Obtain and verify appropriate Azure permissions.
2. Follow the published Quick Start.
3. Select an authorized subscription and resource group.
4. Run one supported installer entry point.
5. Review and approve a complete deployment plan.
6. Provision all supported JAWS resources without manual Azure configuration.
7. Pass functional Supervisor/Planner A2A and installation acceptance tests.
8. Re-run idempotently and recover safely from controlled failure.
9. Locate sanitized acceptance and installation evidence.
10. Confirm documentation, Microsoft references, diagrams and status reflect actual implementation.

Automated regressions and authorized live tests must pass. If essential Azure tests remain blocked, report **Greenfield Installation Not Accepted**.

## 11. CODEX Execution and Final Report

First audit the repository and produce a dependency-ordered engineering plan distinguishing reusable functionality, missing modules, required changes, Azure permissions, test arrangements and documentation updates.

Implement incrementally, test before advancing, and prioritize a working greenfield release of **current Steps A–C** over speculative Steps D–I.

Final report must state:

1. Implementation summary and source changes.
2. Supported installer commands/parameters.
3. Azure resources provisioned and verified.
4. Identity and permissions model.
5. Automated Pester/.NET results.
6. Authorized live Azure test outcomes.
7. Published documentation/link verification.
8. Remaining gaps and blocked acceptance cases.
9. PR and commits.
10. **Explicit result: Greenfield Installation Accepted / Not Accepted.**

**Do not merge without user approval.**
