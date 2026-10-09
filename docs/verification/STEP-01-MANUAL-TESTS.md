# JAWS Step 1 — Stage A Manual Verification

Independent tester: use a different authorized Azure subscription/resource group.
Only run Azure interactions through `Install-Jaws.ps1`. Codex reports defects,
does not modify source code or cloud resources.

| ID | Procedure | Expected |
|---|---|---|
| A-001 | Interactive Discover with valid sign-in | Subscription and RG selectable, scan report created |
| A-002 | Run with no existing Azure sign-in | Guided sign-in prompt or actionable failure |
| A-003 | Noninteractive Discover without sign-in | Clear authentication failure; no resource writes |
| A-004 | Select inaccessible subscription | Block with target-visibility error |
| A-005 | Select target RG without read rights | Stop with authorization error; preserve old inventory |
| A-006 | Two enabled visible subscriptions in selected tenant | Both attempted and separately reported |
| A-007 | One visible subscription scan fails | Report incomplete scan; no refreshed resource manifest |
| A-008 | Resources with name/tag indicating JAWS exist | Possible installation candidates in tenant scan report |
| A-009 | No named candidates | No guarantee of absence; report describes heuristic limitation |
| A-010 | Existing 4 JAWS Stage A resources | Correct IDs/status; external ownership |
| A-011 | Run Discover twice | No duplicates or ownership reset; no Azure writes |
| A-012 | Model version mismatches expected | Configuration drift detected |
| A-013 | Reuse manifest for a different subscription | Fail without overwriting prior manifest |
| A-014 | Pester suites | All tests pass (`StageA.Tests.ps1`, `AzurePreflight.Tests.ps1`) |
| A-015 | Static review | No unapproved Azure changes, no secrets in generated JSON |

Record commit, tester account/tenant (sanitized), tested subscriptions,
expected/actual results, PASS/FAIL, command output and reproduction steps.

| A-011 | Subscriptions contain resources without tags or optional name metadata | No StrictMode property exceptions; one Scanned result per readable subscription |
| A-012 | Subscription scan fails mid-processing | One Failed result, no Scanned duplicate, incomplete report, resource manifest not updated |


## v0.4.5 JAWS-only installation state

The tenant scan reports JAWS and legacy Tight-Fang matches separately. Legacy resources are informational and never copied into current JAWS installation state. After successful discovery, inspect `installer/.local/jaws-installation-state.<environment>.generated.json` for the resources explicitly selected for this JAWS installation. Rerun Discover to confirm it reuses existing state and does not create resources. Stage A does not yet implement an Install or overwrite option.
