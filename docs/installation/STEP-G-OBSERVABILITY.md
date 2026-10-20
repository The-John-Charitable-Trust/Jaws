# Observability integration secrets

Step G grants the Step F observability agent a second MCP server, `jaws-observability`. The compiled modules in this build are Datadog and ServiceNow, and the tools are read-only: `datadog.metrics.query` and `servicenow.incident.get`. Azure Monitor and Microsoft Defender stay on Azure MCP. The manifest records the module and the secret name. Install does not deploy the MCP server process and prints `MCP server deployed: false` and `Live tool call: false`.

The metadata those modules use is supplied at install time and stored under the secret names below. Step B Install requests the ServiceNow developer instance and the Datadog parameters, stores the values in the Step B Key Vault, and marks one virtual machine as the default Datadog host. It does not install the Datadog Agent. The standalone secret command below writes the same secrets after Install when a value changes.

```powershell
.\installer\Install-JawsStepG.ps1 -Mode Validate -EnvironmentName your-environment
.\installer\Install-JawsStepG.ps1 -Mode Install -EnvironmentName your-environment -AcknowledgeStepGInstall
.\installer\Install-JawsStepG.ps1 -Mode Accept -EnvironmentName your-environment
```

Validate requires a Step F acceptance whose `Result` is `PASS`. Install without `-AcknowledgeStepGInstall` stops at `JAWS-STEP-G-001`. A module that is not `Datadog` or `ServiceNow`, or a tool that belongs on Azure MCP, stops at `JAWS-STEP-G-008`. Sources: [Model Context Protocol in Foundry](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/model-context-protocol) and [Adding tools](https://learn.microsoft.com/en-us/agent-framework/journey/adding-tools).

Expected on Accept: `STEP-G ACCEPTANCE PASS`, `MCP server deployed: false`, `Live tool call: false`, `Customer installation accepted: false`, `FedRAMP Moderate: false`, `Ready for next step: true`, and `Next step: Step H Validate`.

The Datadog Agent host must already exist in this environment when Datadog is configured. That is the same subscription, the environment resource group (`-ResourceGroupName`), and the environment location (`-Location`). For the current test those are subscription `c52f597b-7753-45b4-a764-67e290dcfd5e`, resource group `rg-aiops-lab-test2`, and location `eastus`. A new environment that keeps the generated resource group uses `rg-jaws-<environment>`. Install does not create the virtual machine. The minimum is Windows 11 or Windows Server 2016 or later, 2 vCPU, 8 GiB RAM, and 4 GiB free disk. `Standard_D2s_v3` meets that minimum. The Datadog Agent 7 must already be installed, configured with the site and API key you will enter, and the Windows service `datadogagent` must be Running. The full table and the install commands are in [SYSTEM-PREREQUISITES.md](SYSTEM-PREREQUISITES.md).

`jaws-stepb-test` in `rg-jaws-stepb-test` is the operator machine. It is not in `rg-aiops-lab-test2`, so it is not a Datadog host for that environment. A resource id outside the environment subscription or resource group, or a machine in a different location, stops at `JAWS-OBS-009`.

```text
/subscriptions/<subscription-id>/resourceGroups/<environment-resource-group>/providers/Microsoft.Compute/virtualMachines/<vm-name>
```

The tag `jaws-datadog-default=true` on that machine is the mark the command writes. The dev project vault is refused. A host created inside the environment resource group is deleted with that group by [UNINSTALL.md](UNINSTALL.md).

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
.\installer\Set-JawsObservabilityIntegration.ps1 -EnvironmentName your-environment -AcknowledgeObservabilitySecrets -ServiceNowUrl https://<instance>.service-now.com -ServiceNowUsername <username> -ServiceNowPassword <password> -DefaultVirtualMachineResourceId /subscriptions/<subscription-id>/resourceGroups/rg-jaws-your-environment/providers/Microsoft.Compute/virtualMachines/<vm-name>
```

When the Datadog parameters are available, run the same command with these added:

```powershell
-DatadogSite datadoghq.com -DatadogApiKey <api-key> -DatadogAppKey <app-key>
```

Use the site that matches the Datadog organization. Without `-AcknowledgeObservabilitySecrets` the command stops at `JAWS-OBS-001` and writes nothing. `-EnvironmentName dev` stops at `JAWS-OBS-002`. A missing Step B receipt stops at `JAWS-OBS-005`.

Expected from the secret command: `Observability integration: recorded`, `Datadog Agent installed: false`, and `Customer installation accepted: false`. Evidence: `installer/.local/jaws-observability-integration.your-environment.generated.json`. That command stores secrets. Step G Install is the manifest and the second MCP server grant above.

## Acceptance criteria

- G-00: Install and the later-update command write only the secret names above into the Step B vault. The evidence file and `jaws-install.<environment>.generated.json` contain no password and no API key.
- G-01: The default virtual machine is in this environment's subscription, resource group, and location, the Datadog Agent service `datadogagent` is Running on it, and the machine carries `jaws-datadog-default=true`.
- G-02: FedRAMP Moderate. The vault is the private Step B vault. The observability identity, when Step G exists, receives Key Vault Secrets User on these secrets and no broader vault role. The Datadog Agent on the virtual machine is the telemetry collector. JAWS still has one observability specialist and does not publish a public specialist URL.
- G-03: Step G Install records the manifest and the second-server grant. It does not deploy the MCP server, install the Datadog Agent, or claim a live tool call. A secret receipt is not that server.

## Uninstall to stop charges or start a new install

Run this command to delete the whole customer environment, stop its Azure charges, and clear the names before a new complete install. It removes every resource from Steps B, C, and D. It refuses `dev`. If the Key Vault purge is blocked, choose a different vault name on the next install until the purge date.

```powershell
.\installer\Uninstall-Jaws.ps1 -EnvironmentName your-environment -AcknowledgeJawsUninstall
```

Details are in [UNINSTALL.md](UNINSTALL.md).
