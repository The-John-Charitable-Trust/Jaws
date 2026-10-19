# Step C installation

This is the operator path from a checked-out repository to Step C. The default command checks the accepted dev project. It does not provision a new Foundry account, project, model, or vault. `installer/Install-Jaws.ps1` 0.4.10 also has Discover, Plan, Preflight, Package, Install, and Accept. Step B Install creates that foundation and refuses `dev` and `rg-aiops-lab`. Step C for a foundation created by Step B is the same Step C entry point with `-EnvironmentName`. A fresh-subscription Step C acceptance receipt has not been recorded.

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

`Status` is `VALIDATED`, `CLOSED`, or `BLOCKED`. `BLOCKED` includes `ErrorCode`, the failed gate, and the gates that already passed. Corrections are listed by name. For the dev-project command, `SupervisorV1Modified` and `SupervisorVersionPosted` are false. Run the same command again after fixing a blocked gate; completed gates pass without a second write.

## Local evidence

Installer tests do not call Azure:

```powershell
Invoke-Pester .\tests\installer\ -Output Minimal
```

The correction policy is covered by `tests/installer/StepCInstall.Tests.ps1`. Those tests include a CLI stand-in for a Step B environment. A stand-in result is not a live Azure receipt and does not accept a customer installation.

## Actual JAWS implementation source (C)

The [Step C source-code walkthrough](source-code/STEP-C.md) includes verbatim PowerShell and C# excerpts, reviewed file paths, source line ranges, and links to the complete source. No illustrative or Microsoft sample implementation has been substituted, and no Python code is included because this stage has no JAWS Python implementation. The excerpts are reference material, not standalone executable scripts.

## Step C after Step B

Run this only after Step B has written both of these files for the same environment name:

- `installer/.local/jaws-step-b-install.<environment>.generated.json` with status `STEP_B_INSTALLED`
- `installer/.local/jaws-installation-state.<environment>.generated.json`

`<environment>` is the name passed to Step B. It is not `dev`. The command reads those files and the signed-in subscription. It does not read `jaws-foundry-dev`, project `jaws-dev`, or registry `jawsregistrydev001`. A receipt that names those resources stops with `JAWS-INSTALL-C-017` before any Azure call. A missing Step B receipt stops with `JAWS-INSTALL-C-016`.

```powershell
.\installer\Install-JawsThroughStepC.ps1 -Mode Validate -EnvironmentName your-environment
```

Validate is read-only. It discovers the Foundry account and Supervisor version 1 from the Step B receipt. Names come from that environment:

| Resource | Name |
| --- | --- |
| Foundry account | `jaws-foundry-<environment>` |
| Project | `jaws-<environment>` |
| Supervisor | `jaws-supervisor-<environment>` |
| Prompt planner | `jaws-investigation-planner-<environment>` |
| RemoteA2A connection | `jaws-investigation-a2a-<environment>` |
| Toolbox | `jaws-investigation-a2a-tools` |

No hosted Investigation agent is created. Foundry returns `HOSTED_AGENT_NOT_SUPPORTED` for A2A calls against a hosted agent, so the connection target is the prompt planner. The Investigation A2A gate is `Skipped` for that reason.

`-Mode Install` requires `-AcknowledgeStepCInstall`. Without that switch the command stops with `JAWS-INSTALL-C-001` before Azure. Install may create the planner, the RemoteA2A connection, and the first toolbox version, assign one Foundry Agent Consumer role, and post one new Supervisor version. Each of those actions uses the plan SHA written by the read that found the gap. The Supervisor post also requires the route plan SHA. Version 1 is not patched. If version 1 already has the Investigation toolbox variable, or its image is not the Step B digest, the run stops with `JAWS-INSTALL-C-018` and posts nothing.

```powershell
.\installer\Install-JawsThroughStepC.ps1 -Mode Install -EnvironmentName your-environment -AcknowledgeStepCInstall
```

The new Supervisor version uses the same image digest as Step B and adds `JAWS_INVESTIGATION_TOOLBOX_NAME`. On the dev project the routed digest must differ from version 1, because version 5 is a later build. A Step B environment has one published digest, so version 1 and the routed version share it. Version 1 stays active, keeps that digest, and does not receive the toolbox variable.

The functional check spends model usage and writes no configuration:

```powershell
.\installer\Install-JawsThroughStepC.ps1 -Mode Validate -EnvironmentName your-environment -AcknowledgeInferenceCharges
```

The acceptance input tells the Supervisor to call the Investigation A2A toolbox before it answers. A completed response that contains only reasoning and a message, with no `function_call` item, is `JAWS-C-ACCEPT-007: TOOL_NOT_INVOKED`. That means the model did not call the toolbox. The host built for this repository requires that tool when `JAWS_INVESTIGATION_TOOLBOX_NAME` is set and the request asks for the Investigation toolbox. If the tool was not offered on the run, the container fails the turn with `JAWS-TOOLBOX-CALL-003` instead of answering from memory. An image built before that host change does not do this. Step C does not rebuild the Supervisor image. Version 1 and the routed version stay on the Step B digest until a separately approved image is deployed.

A pass on a live project ends `CLOSED`, with Acceptance `Passed` and `TASK_STATE_COMPLETED` in the tool output. The report is `installer/.local/jaws-step-c-final-acceptance.<environment>.generated.json`. The response uses `store=false`. The receipt field `CustomerInstallationAccepted` stays false. Record a fresh-subscription run before treating Step C as accepted for that subscription. This repository does not contain that receipt.

A Supervisor response whose error is a model deployment rate limit is not a failed Investigation task and is not `JAWS-C-ACCEPT-007`. Acceptance waits 60 seconds and tries the same call twice more. Each try prints `Issue` and `Action`. The issue is the Azure error. The action gives the two ways out: re-run Step B Install with `-QuotaMode Dynamic` to turn on dynamic quota for this deployment, or wait for the limit to reset and retry this acceptance. Capacity stays 1. Dynamic Install uses the regional Standard SKU and replaces a GlobalStandard deployment. The report records `ResponseErrorCode`, `ResponseErrorMessage`, `RateLimitAttempts`, and `OperatorAction`. If all three calls are still rate limited, the run stops at `JAWS-C-ACCEPT-010` and Step C stays open. Use the same plan digest:

```powershell
.\installer\Install-Jaws.ps1 -Mode Install -EnvironmentName your-environment -ResourceGroupName rg-jaws-your-environment -Location eastus -ApprovedPlanSha256 <plan-sha> -QuotaMode Dynamic -AcknowledgeStepBInstall
```

That command does not build the Supervisor image again once version 1 is active. Step B Install refuses `dev`. On the accepted dev deployment, turn dynamic quota on in Foundry, or wait and retry. A Step B create that Azure refuses for lack of quota is different: that console prints `Issue`, `Action`, and `Quota request: https://aka.ms/oai/stuquotarequest`. Dynamic quota cannot create the capacity-1 deployment when the subscription has no quota for it.

The receipt for either mode is `installer/.local/jaws-step-c-install.<environment>.generated.json`. `SupervisorV1Modified` is false unless a read shows that version 1 changed. `SupervisorVersionPosted` is true only for the run that posted the route.
