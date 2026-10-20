# Observability integration secrets

Step G, the observability specialist and its MCP server, is not installable. Step B Install requests the ServiceNow developer instance and the Datadog parameters, stores the values in the Step B Key Vault, and marks one virtual machine as the default Datadog host. It does not install the Datadog Agent and it does not create the specialist. The standalone command below writes the same secrets after Install when a value changes.

The current test default is virtual machine `jaws-stepb-test` in resource group `rg-jaws-stepb-test`. That machine is Windows. Its resource id is:

```text
/subscriptions/<subscription-id>/resourceGroups/rg-jaws-stepb-test/providers/Microsoft.Compute/virtualMachines/jaws-stepb-test
```

The tag `jaws-datadog-default=true` on that machine is the same mark the command writes. The dev project vault is refused.

## Secret names

| Secret | Contents |
| --- | --- |
| `jaws-servicenow-url` | `https://<instance>.service-now.com` |
| `jaws-servicenow-username` | ServiceNow username |
| `jaws-servicenow-password` | ServiceNow password |
| `jaws-datadog-api-key` | Datadog API key |
| `jaws-datadog-app-key` | Datadog application key, when a query API needs one |
| `jaws-datadog-site` | One of `datadoghq.com`, `us3.datadoghq.com`, `us5.datadoghq.com`, `ap1.datadoghq.com`, `datadoghq.eu`, `ddog-gov.com` |
| `jaws-datadog-default-vm` | Resource id of the default virtual machine |

The MCP manifest names these secrets. It does not contain the values. The evidence file records the secret names and the virtual machine resource id. It does not record a password, an API key, or the ServiceNow URL. `Customer installation accepted` stays false.

ServiceNow URL, username, and password are stored together. The Datadog API key and site are stored together. The application key is optional. The default virtual machine can be stored on its own.

## Install

Copy `installer/config/jaws.install.example.json` to `installer/.local/jaws.install.your-environment.json`. Fill `ServiceNowUrl`, `ServiceNowUsername`, and `ServiceNowPassword`. Add `DatadogSite`, `DatadogApiKey`, and `DatadogAppKey` when you have them, and `DefaultVirtualMachineResourceId` for the default host. Pass that file to Step B Install:

```powershell
.\installer\Install-Jaws.ps1 -Mode Install -EnvironmentName your-environment -ResourceGroupName rg-jaws-your-environment -Location eastus -ApprovedPlanSha256 <plan-sha> -AcknowledgeStepBInstall -InstallConfig .\installer\.local\jaws.install.your-environment.json
```

Install prints `ServiceNow stored`, `ServiceNow skipped`, `Datadog stored`, `Datadog skipped`, `Default virtual machine stored`, `Datadog agent host required`, `FedRAMP Moderate: false`, and `FedRAMP open resources`. The generated config is `installer/.local/jaws-install.your-environment.generated.json`. It names the secrets and lists every Azure resource in the FedRAMP inventory. It does not contain the password, the API key, or the ServiceNow URL. `FedRampModerate.Accepted` stays false while any resource is still public. That record is customer configuration. It is not a FedRAMP authorization. An interactive console asks whether to configure ServiceNow and whether to configure Datadog. Answer `skip` to leave that product unset. Skipping Datadog requires no virtual machine for the Datadog Agent. Answer `yes` to enter the values. `-SkipServiceNow` and `-SkipDatadog` make that choice from `az vm run-command`, which cannot answer the prompts. Leaving every field empty still lets the functional install pass and stores nothing.

## Later update

Run this after Step B Install has written the receipt for the environment. Supply the ServiceNow values you have. Add the Datadog parameters when you have them. Do not commit the values.

```powershell
.\installer\Set-JawsObservabilityIntegration.ps1 -EnvironmentName your-environment -AcknowledgeObservabilitySecrets -ServiceNowUrl https://<instance>.service-now.com -ServiceNowUsername <username> -ServiceNowPassword <password> -DefaultVirtualMachineResourceId /subscriptions/<subscription-id>/resourceGroups/rg-jaws-stepb-test/providers/Microsoft.Compute/virtualMachines/jaws-stepb-test
```

When the Datadog parameters are available, run the same command with these added:

```powershell
-DatadogSite datadoghq.com -DatadogApiKey <api-key> -DatadogAppKey <app-key>
```

Use the site that matches the Datadog organization. Without `-AcknowledgeObservabilitySecrets` the command stops at `JAWS-OBS-001` and writes nothing. `-EnvironmentName dev` stops at `JAWS-OBS-002`. A missing Step B receipt stops at `JAWS-OBS-005`.

Expected: `Observability integration: recorded`, `Datadog Agent installed: false`, `Customer installation accepted: false`, `Ready for next step: false`, and `Next step: Step G is not installable`. Evidence: `installer/.local/jaws-observability-integration.your-environment.generated.json`.

## Acceptance criteria

- G-00: Install and the later-update command write only the secret names above into the Step B vault. The evidence file and `jaws-install.<environment>.generated.json` contain no password and no API key.
- G-01: The default virtual machine resource id is `jaws-stepb-test` for the current test, and that machine carries `jaws-datadog-default=true`.
- G-02: FedRAMP Moderate. The vault is the private Step B vault. The observability identity, when Step G exists, receives Key Vault Secrets User on these secrets and no broader vault role. The Datadog Agent on the virtual machine is the telemetry collector. JAWS still has one observability specialist and does not publish a public specialist URL.
- G-03: Step G remains uninstalled. A secret receipt is not a specialist, an MCP server, or a Datadog Agent installation.

The Datadog Agent install on `jaws-stepb-test` waits for the site and API key. Those parameters are the remaining input.
