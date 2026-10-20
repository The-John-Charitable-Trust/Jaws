# Observability integration secrets

Step G, the observability specialist and its MCP server, is not installable. This command stores the ServiceNow developer instance and the Datadog parameters in the Step B Key Vault, and it marks one virtual machine as the default Datadog host. It does not install the Datadog Agent and it does not create the specialist.

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

## Command

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

- G-00: The command writes only the secret names above into the Step B vault. The evidence file contains no password and no API key.
- G-01: The default virtual machine resource id is `jaws-stepb-test` for the current test, and that machine carries `jaws-datadog-default=true`.
- G-02: FedRAMP Moderate. The vault is the private Step B vault. The observability identity, when Step G exists, receives Key Vault Secrets User on these secrets and no broader vault role. The Datadog Agent on the virtual machine is the telemetry collector. JAWS still has one observability specialist and does not publish a public specialist URL.
- G-03: Step G remains uninstalled. A secret receipt is not a specialist, an MCP server, or a Datadog Agent installation.

The Datadog Agent install on `jaws-stepb-test` waits for the site and API key. Those parameters are the remaining input.
