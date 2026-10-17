# Tutorial Step 1 — Read-only Azure discovery

Step A checks who is signed in, which subscription they selected, and which Foundry, Key Vault, and container registry resources Resource Graph can see there. It never creates, updates, or deletes Azure resources.

The signed-in Entra tenant has to be the tenant of the selected subscription. Reader, or another role that includes `Microsoft.ResourceGraph/resources/read`, is enough for this step. Discovery does not infer access from a role name; a failed query names the missing action.

Without `-StateFile`, the installer does not open `installer/config/jaws-installation-state.dev.json`. Rows come back as unclaimed evidence. A resource whose name contains "jaws" is still unclaimed.

With `-StateFile`, Step A reconciles the named resources. The state file remains the operator's copy. Discover does not rewrite it.

```powershell
az login
.\installer\Install-Jaws.ps1 -Mode Discover -SubscriptionId <your-subscription-id> -NonInteractive
```

Expected: Outcome `NoInstallationState`, `AzureWrites` 0, and a report under `installer/.local/`.

The acceptance criteria and the state-file command are in `docs/installation/STEP-01-STAGE-A.md`. The manual checks are in `docs/verification/STEP-01-MANUAL-TESTS.md`.
