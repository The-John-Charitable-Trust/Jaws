# Stage B2 — Independent QA Findings and Next Checkpoint
Status: Previous Azure-aware read-only assessment CONDITIONALLY ACCEPTED; current configuration-evidence changes AWAIT INDEPENDENT TESTS.
Assessment date: 2026-10-12 | Development branch: `codex/0.2-add-mcp-server`

## Independent Codex QA baseline
The previously submitted QA report records 36 Pester tests passed, zero failed/zero skipped when run in an isolated PowerShell process. Read-only live assessment discovered four externally owned JAWS resources: Foundry resource `jaws-foundry-dev`, project `jaws-dev`, model `gpt-5-mini` version `2025-08-07`, and Key Vault `kv-jaws-dev-001`. All were candidates for reuse, **not cleared for installation**. Twelve additional components had not been checked. The plan reported zero Azure writes and `CanExecute=false`.

## Findings disposition
- DEF-INPUT-001: Earlier brief contained an incorrect subscription ID. The correct authoritative ID is supplied by the checked-in development state JSON, not user-supplied documentation. Preserve existing fail-closed validation.
- DEF-ENV-001: Workstation signing restrictions blocked default commands. Codex succeeded under process-scoped test execution; organizations should approve a development execution policy and sign trusted release scripts. Do not change global policy in installer.
- Improvement: Capture expected and observed configuration fields in generated plan, with a non-secret allowlist and `PartialReadOnlyObservation` annotation. Explicitly check location drift when Azure discovery reports a location. Keep cost, quotas, role assignments, Key Vault RBAC/purge assertions and provider capacities unverified until dedicated read-only checks are implemented.

## Current checkpoint source changes
- `installer/modules/AzureDeploymentPlan.psm1`: Include non-secret config evidence; detect known location mismatch. Still only a read-only, non-executable plan.
- `tests/installer/AzureDeploymentPlan.Tests.ps1`: Two additional Pester cases for captured model version and discovered location mismatch.
- `docs/development/index.html`: Updated tutorial and scope guidance.

## Independent QA procedure
1. Sync local repository; ensure no uncommitted work is lost.
2. Run `Invoke-Pester .\tests\installer\ -Output Detailed` in approved PowerShell 7 environment (previous baseline 36; newly added two tests imply a target of 38).
3. Run authorized read-only `-Mode Plan -AzureAware` with local blueprint matching the authoritative state and existing Azure CLI sign-in.
4. Verify observed and expected model fields, no new secrets, no changed state, `CanExecute=false`, `AzureWrites=0`.
5. Return test counts, observed differences and defects; do not edit code or deploy Azure resources.

## Remaining work before enabling Install
Read-only configuration verification for Foundry and Key Vault; discovery/hosting design for 12 other components; user/installer effective privileges; cost/quotas/availability; Teams/Datadog administration; signed, time-limited operator-approved plan with specific actions and rollback. Stage B only closes once JAWS is installed and works through Teams end to end.
