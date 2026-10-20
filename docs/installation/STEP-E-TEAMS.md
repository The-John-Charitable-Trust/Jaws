# Step E — Teams channel

Step E publishes the Supervisor to Microsoft Teams so an operator can test communication. The specialists stay unpublished. Validate is read-only. Install requires `-AcknowledgeStepEInstall`. Accept re-reads the Azure Bot. A pass prints `Teams reply recorded: false`. Sending a Teams message and reading the reply is the operator check. This installer does not record that reply.

The publish scope is `Shared` (the portal choice "Just you"). It uses `BotServiceRbac`. It does not submit the agent for tenant-wide admin approval.

Microsoft documents the path in [Publish agents to Microsoft Copilot and Microsoft Teams](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/publish-copilot) and [Publish by using the REST API](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/publish-copilot-virtual-network). The bot template in `installer/templates/jaws-teams-bot.bicep` follows that REST article: public network access disabled, a Teams channel, and the Supervisor activity-protocol endpoint. The app package schema is the [Teams manifest schema](https://learn.microsoft.com/en-us/microsoftteams/platform/resources/schema/manifest-schema).

```powershell
.\installer\Install-JawsStepE.ps1 -Mode Validate -EnvironmentName your-environment
.\installer\Install-JawsStepE.ps1 -Mode Install -EnvironmentName your-environment -AcknowledgeStepEInstall
.\installer\Install-JawsStepE.ps1 -Mode Accept -EnvironmentName your-environment
```

Run these after Step D Accept prints `STEP-D ACCEPTANCE PASS` and `Next step: Step E Validate`. The command refuses `dev` with `JAWS-STEP-E-014`. Install without the acknowledgement stops at `JAWS-STEP-E-001` and does not create a bot. A missing Supervisor client id stops at `JAWS-STEP-E-020`.

Expected on Accept: `STEP-E ACCEPTANCE PASS`, `Publish scope: Shared`, `Specialists published: false`, `Teams reply recorded: false`, `FedRAMP Moderate: false`, `Customer installation accepted: false`, `Ready for next step: true`, and `Next step: Step F Validate`. Evidence: `installer/.local/jaws-step-e-acceptance.your-environment.generated.json`.

## Acceptance

- E-00: Install publishes the Supervisor only, with `publishScope` `Shared`, and Accept re-reads a bot whose public network access is disabled and whose endpoint is that Supervisor's activity-protocol route.
- E-01: A Teams reply in the same thread is the operator's communication check. Accept leaves `Teams reply recorded` false.
- E-02: FedRAMP Moderate stays open. Microsoft 365 requires a publicly routable Activity Protocol path. This installer does not set `enable_m365_public_endpoint` and does not claim that gate. On a private Foundry account that setting is a later, scoped exception for the Activity Protocol route only. It is not a public specialist URL.

A fresh-subscription receipt has not been recorded. Pester `tests/installer/LaterSteps.Tests.ps1` uses a stand-in Azure CLI. That stand-in is not a live Teams conversation.

## Uninstall to stop charges or start a new install

The bot is created in the environment resource group. Run this command to delete the whole environment, stop those charges, and clear the names before a new complete install. It refuses `dev`.

```powershell
.\installer\Uninstall-Jaws.ps1 -EnvironmentName your-environment -AcknowledgeJawsUninstall
```

Details are in [UNINSTALL.md](UNINSTALL.md).
