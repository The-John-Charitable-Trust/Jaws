# JAWS System Prerequisites (Standard and Developer/Tester)

## Operating system and environment
- **Windows 11** workstation with hardware virtualization enabled, suitable memory/disk space (32 GB RAM and 1 TB SSD recommended for development).
- **PowerShell 7** for installer execution. Check with `$PSVersionTable.PSVersion`.
- **Git** for source control and **Azure CLI** (`az --version`) for authenticated Azure deployment.
- **Microsoft Entra access** with permissions appropriate to the targeted JAWS subscription, Foundry project, Container Registry and role assignments. No registry admin user required.

## Datadog Agent host

A virtual machine is required in advance only when Step B Install configures Datadog. JAWS does not create that machine and does not install the Datadog Agent. Install records the existing resource id and tags the machine `jaws-datadog-default=true`. Skipping Datadog leaves `Datadog agent host required: false` and does not ask for a virtual machine. ServiceNow does not require one. The operator workstation that runs PowerShell can be a different computer.

### Same environment

The host must already exist in the same Azure environment as the JAWS install. That means all three of these match the Step B plan:

| Place | What must match |
| --- | --- |
| Subscription | The subscription Install uses. For the current test that is `c52f597b-7753-45b4-a764-67e290dcfd5e`. |
| Resource group | The plan's `-ResourceGroupName`. For the current test that is `rg-aiops-lab-test2`. A new environment that keeps the generated name uses `rg-jaws-<environment>`. |
| Location | The plan's `-Location`. For the current test that is `eastus`. |

A virtual machine in another resource group is not this environment. `jaws-stepb-test` in `rg-jaws-stepb-test` is the operator machine used for `az vm run-command`. It is Windows 11 Pro, size `Standard_D2s_v3`, in `eastus`, and it is not a valid Datadog host for `aiops-lab-test2`. A host placed inside the environment resource group is deleted when [Uninstall-Jaws.ps1](UNINSTALL.md) deletes that group. Keep the operator machine outside that group.

Supply this resource id when Install asks for Datadog:

```text
/subscriptions/<subscription-id>/resourceGroups/<environment-resource-group>/providers/Microsoft.Compute/virtualMachines/<vm-name>
```

A resource id in a different subscription or resource group stops at `JAWS-OBS-009` after the foundation exists. A machine whose Azure location differs from the environment also stops at `JAWS-OBS-009`. A resource id that is not a virtual machine id stops at `JAWS-OBS-007`. A missing site, API key, or resource id stops at `JAWS-INSTALL-CONFIG-005`.

### Minimum size

| Requirement | Minimum |
| --- | --- |
| Operating system | Windows 11, or Windows Server 2016, 2019, 2022, or 2025, x64. These are the platforms Datadog Agent 7 supports. |
| Compute | 2 vCPU and 8 GiB RAM. `Standard_D2s_v3` meets this minimum: 2 vCPU and 8 GiB. |
| Disk | 4 GiB free on the operating-system disk. Datadog documents about 870 MB for the Windows Agent, 2 GB for the initial install, and another 2 GB while an upgrade keeps the previous install. |
| Network | Outbound HTTPS to the Datadog site chosen at install, such as `us5.datadoghq.com`. |
| Permission | The signed-in account can read the virtual machine and merge the `jaws-datadog-default` tag. |

`installer/Test-JawsPrerequisites.ps1` checks the workstation. It does not check this host and it does not check the Datadog Agent service.

### Install, configure, and run the Datadog Agent

Do this on the host before Step B Install configures Datadog. The site and API key must be the values you will enter at install time. JAWS stores those values in Key Vault. It does not start the Agent.

1. Sign in to the virtual machine as an administrator.
2. Download Datadog Agent 7 for 64-bit Windows from Datadog's stable installer: `https://windows-agent.datadoghq.com/datadog-agent-7-latest.amd64.msi`.
3. Install it with the API key and site. `SITE` is the host only, one of `datadoghq.com`, `us3.datadoghq.com`, `us5.datadoghq.com`, `ap1.datadoghq.com`, `datadoghq.eu`, or `ddog-gov.com`.

```powershell
$msi = Join-Path $env:TEMP 'datadog-agent-7-latest.amd64.msi'
Invoke-WebRequest -Uri 'https://windows-agent.datadoghq.com/datadog-agent-7-latest.amd64.msi' -OutFile $msi
$p = Start-Process -FilePath msiexec.exe -Wait -PassThru -ArgumentList @(
    '/qn', '/i', $msi,
    'APIKEY=<api-key>',
    'SITE=<site>',
    'REBOOT=ReallySuppress'
)
if ($p.ExitCode -ne 0) { throw "Datadog Agent install exited $($p.ExitCode)." }
```

The installer writes `C:\ProgramData\Datadog\datadog.yaml`. The `api_key` and `site` entries in that file are the configuration. Datadog documents that an existing valid `datadog.yaml` takes precedence over the MSI properties, so edit those two entries when the file is already present and then restart the service. The Windows service name is `datadogagent`.

4. Confirm the service is running before you answer `yes` to Datadog in JAWS Install:

```powershell
Get-Service datadogagent | Select-Object Status, Name
Restart-Service datadogagent
& "${env:ProgramFiles}\Datadog\Datadog Agent\bin\agent.exe" status
```

`Status` must be `Running`. The installer does not query this service. A stopped Agent still lets the secret write succeed, and the observability specialist will have no telemetry from that host until the service is running.

Sources: [Datadog Agent supported platforms](https://docs.datadoghq.com/agent/supported_platforms/?tab=windows), [Windows Agent install](https://docs.datadoghq.com/agent/supported_platforms/windows/), [Datadog Agent](https://docs.datadoghq.com/agent/), [Windows Agent configuration](https://docs.datadoghq.com/agent/basic_agent_usage/windows/), [install disk space](https://docs.datadoghq.com/agent/fleet_automation/upgrade_agents/), and [Dsv3 sizes](https://learn.microsoft.com/en-us/azure/virtual-machines/sizes/general-purpose/dsv3-series).

To remove a JAWS environment before a new install, use [UNINSTALL.md](UNINSTALL.md).

## Step B image build

Step B Install builds the Supervisor image in Azure Container Registry with `az acr build --platform linux/amd64` and reads the digest back from the registry. That command needs the Azure CLI and permission to push to the registry. It does not need Docker Desktop, WSL 2, or a local .NET SDK.

## Build and container prerequisites (optional local package and development)
- **.NET SDK 10** (`dotnet --list-sdks`) for JAWS Investigation Host.
- **WSL 2** installed and updated (`wsl --status`, `wsl --list --verbose`), with a Linux distribution configured at version 2. Linux distro needed for optional interactive development; Docker Desktop can use its own WSL distributions for the engine.
- **Docker Desktop**, started with its **WSL 2 backend** and **Linux containers**, not Windows containers.
- Validate `docker info --format '{{.OSType}}/{{.Architecture}}'` reports Linux, and build/publish explicitly for `linux/amd64`.
- Root `.dockerignore` must exclude `**/bin/` and `**/obj/` to avoid host artifacts corrupting container-local NuGet restores.
- **Pester 5.x** for automated developer/tester validation (`Get-Module Pester -ListAvailable`). Standard users do not need Pester or .NET SDK unless performing source builds.

## PowerShell execution policy and downloaded-file trust
- Run `Get-ExecutionPolicy -List` before installer execution. Policy is environment-controlled and might be set by Group Policy.
- Prefer **RemoteSigned**, rather than changing the workstation policy to unrestricted/bypass. The original failure occurred with RemoteSigned active when an imported `.psm1` was marked as downloaded from the internet.
- For trusted checked-out JAWS files, verify their origin, then remove Mark-of-the-Web only from the blocked files with `Unblock-File -LiteralPath '<path>'` where appropriate. Do not bulk-unblock unknown files.
- Do not override **MachinePolicy** or **UserPolicy** restrictions. Contact an administrator if policy requires signatures.
- A short-lived process-scoped Bypass may aid approved troubleshooting, but is **not** the installation prerequisite or preferred permanent solution.

## Preflight from VS Code terminal
```powershell
pwsh -NoProfile -File .\installer\Test-JawsPrerequisites.ps1 -RequireContainerBuild
```
If this script is also blocked by trust/policy, inspect `Get-ExecutionPolicy -List` and the file's origin before proceeding.

## Troubleshooting
- `NETSDK1064` after Docker restore: confirm `.dockerignore` excludes `bin/obj`, then rebuild without cache.
- Docker `desktop-linux` context metadata locked: quit/restart Docker Desktop, then check `docker info`.
- Docker fails with Windows containers: switch Docker Desktop to Linux containers and ensure WSL 2 is enabled.
- Imported PowerShell module is unsigned: inspect effective policy and file provenance; use file-specific unblock when appropriate.
- Foundry deployment requires separate **explicit approval**, verified immutable registry digest, project identity/RBAC and charge acknowledgment. Preflight does not deploy, mutate Azure or bypass approvals.

For host setup, see [Microsoft WSL installation](https://learn.microsoft.com/windows/wsl/install), [Docker Desktop WSL 2 backend](https://docs.docker.com/desktop/features/wsl/), [PowerShell execution policies](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_execution_policies), and [.NET downloads](https://dotnet.microsoft.com/download/dotnet/10.0).
