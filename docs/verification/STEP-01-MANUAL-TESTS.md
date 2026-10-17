# JAWS Step A — Manual verification

Run Azure only through `installer/Install-Jaws.ps1 -Mode Discover`. Use an identity with Reader on the subscription under test. Do not copy `installer/config/jaws-installation-state.dev.json` into another subscription.

| ID | Procedure | Expected |
|---|---|---|
| A-001 | `.\installer\Install-Jaws.ps1 -Mode Discover -SubscriptionId <id> -NonInteractive` | Resource Graph inventory for that subscription. Report `installer/.local/jaws-step-a-discovery.selected.generated.json`. Outcome `NoInstallationState`. |
| A-002 | Discover with no Azure sign-in | `JAWS-AUTH-001`. No resource writes. |
| A-003 | Same as A-002 with `-NonInteractive` | Authentication failure. No resource writes. |
| A-004 | `-SubscriptionId` for a subscription the identity cannot see | `JAWS-AUTH-007`. |
| A-005 | `-ResourceGroupName` for a group the identity cannot read | Authorization error. No state file created. |
| A-006 | Subscription in a different Entra tenant than the signed-in account | `JAWS-AUTH-009`. Inventory is not accepted. |
| A-007 | Resource Graph denies `Microsoft.ResourceGraph/resources/read` | `JAWS-AUTH-010` names that action and Reader. No state file created. |
| A-008 | Subscription contains Foundry, Key Vault, or registry resources | Those rows are `Unclaimed`. A name containing "jaws" does not set adoption. |
| A-009 | Resource Graph returns no rows | Outcome `NoInstallationState`. The disclaimer says an empty result is not proof of absence. |
| A-010 | `-StateFile` naming four resources that targeted reads match | Outcome `Reconciled`. `AzureWrites` 0. State file bytes unchanged. |
| A-011 | Run A-001 twice | A second report. No installation state file appears. No Azure writes. |
| A-012 | State file model version differs from the targeted deployment read | Outcome `Drift`. State file unchanged. |
| A-013 | Resource Graph id for a named resource differs from the targeted read | `JAWS-STATE-008`. Manifest not rewritten. |
| A-014 | `Invoke-Pester .\tests\installer\StepADiscovery.Tests.ps1,.\tests\installer\AzurePreflight.Tests.ps1,.\tests\installer\StageA.Tests.ps1,.\tests\installer\InstallationState.Tests.ps1,.\tests\installer\StateGold.Tests.ps1` | All tests pass. These tests do not call Azure. |
| A-015 | Review the generated report | No secrets, tokens, or tag values. `AzureWrites` is 0. `InstallationStateCreated` is false. |

Record the commit, a sanitized subscription id, and PASS, FAIL, or BLOCKED. A test that was not run against Azure is BLOCKED, not passed.

Pester covers A-006, A-008, A-009, A-010, and A-013 without Azure. A-001 through A-005, A-007, A-011, and A-012 need an authorized subscription and are BLOCKED until that run is recorded.
