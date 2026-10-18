# Step C installation

This is the operator path from a checked-out repository to a closed Step C on the dev project. It does not provision a new Foundry account, project, model, or vault. `installer/Install-Jaws.ps1` remains Discover, Plan, and Package. Greenfield `-Mode Install` is not part of this release.

The architecture the installer checks and repairs is:

- `jaws-supervisor-dev` is the hosted Supervisor. Version 1 stays active and is not modified. No new Supervisor version is posted by this installer.
- `jaws-investigation-planner-dev` is the prompt-based A2A planner and the RemoteA2A target.
- `jaws-investigation-dev` remains the hosted Investigation runtime. Connecting that runtime to the planner is outside Step C.
- The Supervisor instance identity has one Foundry Agent Consumer assignment at project scope. The planner and the Supervisor blueprint receive no role.

## One command

From the repository root in PowerShell 7, with Azure CLI already signed in to the dev subscription:

```powershell
.\installer\Install-JawsThroughStepC.ps1 -Mode Validate
```

Validate reads the dev project and writes no Azure changes. The receipt is `installer/.local/jaws-step-c-install.dev.generated.json`. That directory is gitignored. A clean result is `VALIDATED`: every non-billable gate passed.

The functional test of the closed delegation stays in Validate. It spends model usage and writes no Azure configuration:

```powershell
.\installer\Install-JawsThroughStepC.ps1 -Mode Validate -AcknowledgeInferenceCharges
```

A pass ends `CLOSED`, with Acceptance `Passed` and `TASK_STATE_COMPLETED` in the tool output. The acceptance report is `installer/.local/jaws-step-c-final-acceptance.dev.generated.json`. Acceptance keeps `store=false`, so the response cannot be read back later. The report records `TaskState` and `PlannerResponseId` from the tool output.

`-Mode Install` is the repair path, used only when Validate is `BLOCKED` on a gate this installer is allowed to correct. It requires `-AcknowledgeStepCInstall`. Add `-AcknowledgeInferenceCharges` when that same run should also make the billable call:

```powershell
.\installer\Install-JawsThroughStepC.ps1 -Mode Install -AcknowledgeStepCInstall -AcknowledgeInferenceCharges
```

`-Mode Install` without `-AcknowledgeStepCInstall` stops with `JAWS-INSTALL-C-001` before any Azure call. Install on an already-correct project performs no correction.

`Install-JawsStepC.ps1 -Mode ThroughStepC` and `-Mode ThroughStepCInstall` call the same script. The install mode from that dispatcher does not run the billable acceptance call.

## What it checks, and what it will repair

The gates run in this order. A failed gate is recorded in the receipt and the run stops. Each correctable gate is retried once after the repair, then stopped if it is still wrong.

| Gate | Already correct | One repair, and only in `-Mode Install` | Stops without a write |
| --- | --- | --- | --- |
| Prerequisites | PowerShell 7 and Azure CLI | None | Missing tool (`JAWS-INSTALL-C-002`) |
| State | Authoritative dev state file | None | Any other environment (`JAWS-INSTALL-C-014`) |
| Investigation A2A | Hosted Investigation v1 card verified | Patch the incoming A2A endpoint when it is absent | Version 1 is not the expected hosted agent, or the card read-back does not match |
| Planner | Active prompt agent `jaws-investigation-planner-dev` | Create it when it is absent | The agent exists but does not match (`JAWS-PLANNER-004`) |
| Connection | RemoteA2A connection targets the planner | Create it when absent, or retarget it when it still points at hosted Investigation | Any other target (`JAWS-DELEGATE-009` / overwrite refusal) |
| Toolbox | Default version is the connection-only A2A tool | Create the first version, or repair the known invalid v1 into v2 and promote it | Any other toolbox shape |
| RBAC | One Foundry Agent Consumer assignment on the routed Supervisor identity | Create that one assignment when it is missing | Duplicate assignments, or any other role |
| Supervisor | Latest route is the active non-draft image named by `-ExpectedImage`, with the Investigation toolbox, and it is not the v1 image | None. The historical draft release script throws `JAWS-SUP-REL-010` | List status is not trusted ahead of version detail. A failed or unexpected release is not replaced |
| Identity | Routed Supervisor identity and the ARM connection metadata agree | None | Incomplete identity or connection (`JAWS-A2A-IDENTITY-002`) |
| Acceptance | Supervisor tool call returns `TASK_STATE_COMPLETED` without a protocol failure | None | Missing `-AcknowledgeInferenceCharges` leaves the run `VALIDATED`. A failed call leaves it `BLOCKED` |

The default expected image is Supervisor `sha256:86c556fff7f54eb8ad81c84bc768093fd7bc083e941e9e16bbf1ea8bc0cfa289`.

## Receipt

`Status` is `VALIDATED`, `CLOSED`, or `BLOCKED`. `BLOCKED` includes `ErrorCode`, the failed gate, and the gates that already passed. Corrections are listed by name. `SupervisorV1Modified` and `SupervisorVersionPosted` are false for this installer. Run the same command again after fixing a blocked gate; completed gates pass without a second write.

## Local evidence

Installer tests do not call Azure:

```powershell
Invoke-Pester .\tests\installer\ -Output Minimal
```

The correction policy is covered by `tests/installer/StepCInstall.Tests.ps1`.

## Actual JAWS implementation source (C)

The [Step C source-code walkthrough](source-code/STEP-C.md) includes **verbatim PowerShell, C# excerpts**, reviewed file paths, source line ranges, and direct links to the complete source in the JAWS repository. No illustrative or Microsoft sample implementation has been substituted, and no Python code is included because this stage has no verified JAWS Python implementation. The excerpts are reference material, not standalone executable scripts. For complete behavior, consult the linked source and the install/validation commands above.
