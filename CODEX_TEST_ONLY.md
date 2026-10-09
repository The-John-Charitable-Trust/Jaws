# Codex Stage A v0.4.0 — Independent QA Only

Do not edit files, commit, push, or modify Azure. Execute automated tests and
read-only installer discovery only with authorized identity.

1. Run PowerShell syntax/PSScriptAnalyzer on all installer modules and entry point.
2. Run Pester 5:
   `Invoke-Pester ./tests/installer/StageA.Tests.ps1,./tests/installer/AzurePreflight.Tests.ps1 -Output Detailed`
3. Test Azure subscription selection and resource-group authorization errors.
4. Test with 2+ enabled visible subscriptions in the same tenant; each must be
   attempted, and failed scans must not be reported as complete.
5. Verify heuristic tenant scan candidates from names, groups, and tags.
6. Execute `Install-Jaws.ps1 -Mode Discover -NonInteractive` with approved parameters.
7. Repeat discovery; compare resource IDs and ownership; ensure no duplicates.
8. Verify only read-only Azure resource calls occur and no secrets are collected.
9. Run prior JAWS build/tests; report regression status.
10. Report case ID, expected, actual, PASS/FAIL, evidence and defects. No fixes.

Do not claim Azure testing if credentials or RBAC are unavailable.
