# Step I — One incident across the path

Step I checks that Steps E, F, G, and H each have an acceptance receipt whose `Result` is `PASS`, and that the catalog still matches the target grant. It has Validate and Accept. It does not have Install, because it creates nothing. Accept prints `Live incident: false`, `Ready for next step: false`, and `Next step: none`.

A live incident is one Teams thread in which the Supervisor uses both specialists, a second conversation in that project can name the incident, the last decision, and the last citation, and a conversation from another project is not returned. This installer does not run that incident.

Sources: [Azure Well-Architected Framework](https://learn.microsoft.com/en-us/azure/well-architected/) and [Azure RBAC](https://learn.microsoft.com/en-us/azure/role-based-access-control/overview). The Teams and specialist references stay on [STEP-E-TEAMS.md](STEP-E-TEAMS.md), [STEP-F-OBSERVABILITY-AGENT.md](STEP-F-OBSERVABILITY-AGENT.md), [STEP-G-OBSERVABILITY.md](STEP-G-OBSERVABILITY.md), and [STEP-H-VM-CHANGE.md](STEP-H-VM-CHANGE.md).

```powershell
.\installer\Install-JawsStepI.ps1 -Mode Validate -EnvironmentName your-environment
.\installer\Install-JawsStepI.ps1 -Mode Accept -EnvironmentName your-environment
```

A missing prior acceptance stops at `JAWS-STEP-I-002`.

Expected: `STEP-I ACCEPTANCE PASS`, `Live incident: false`, `Customer installation accepted: false`, `FedRAMP Moderate: false`, `Ready for next step: false`, and `Next step: none`. Evidence: `installer/.local/jaws-step-i-acceptance.your-environment.generated.json`.

## Acceptance

- I-00: The receipt chain for E, F, G, and H is present and the catalog matches.
- I-01: `Live incident` stays false until an operator records one Teams incident. A receipt-chain pass is not that incident.
- I-02: Customer installation stays unaccepted until the functional line and the FedRAMP Moderate gate are both recorded for the resources the path uses.

## Uninstall to stop charges or start a new install

```powershell
.\installer\Uninstall-Jaws.ps1 -EnvironmentName your-environment -AcknowledgeJawsUninstall
```

Details are in [UNINSTALL.md](UNINSTALL.md).
