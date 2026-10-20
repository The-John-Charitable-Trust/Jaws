# JAWS System Prerequisites (Standard and Developer/Tester)

## Operating system and environment
- **Windows 11** workstation with hardware virtualization enabled, suitable memory/disk space (32 GB RAM and 1 TB SSD recommended for development).
- **PowerShell 7** for installer execution. Check with `$PSVersionTable.PSVersion`.
- **Git** for source control and **Azure CLI** (`az --version`) for authenticated Azure deployment.
- **Microsoft Entra access** with permissions appropriate to the targeted JAWS subscription, Foundry project, Container Registry and role assignments. No registry admin user required.

## Datadog Agent host

A virtual machine is required in advance only when Step B Install configures Datadog. The installer does not create that machine and does not install the Datadog Agent. It records the existing resource id and tags the machine `jaws-datadog-default=true`. Skipping Datadog leaves `Datadog agent host required: false` and does not ask for a virtual machine. ServiceNow does not require one. The operator workstation that runs PowerShell can be a separate physical Windows 11 computer.

Create the host in the same subscription before Install, then supply its resource id when Install asks for Datadog:

```text
/subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.Compute/virtualMachines/<vm-name>
```

| Requirement | Minimum |
| --- | --- |
| Operating system | Windows 11, or Windows Server 2016, 2019, 2022, or 2025, x64. These are the platforms Datadog Agent 7 supports. |
| Compute | 2 vCPU and 8 GiB RAM. `Standard_D2s_v3` meets this minimum: 2 vCPU and 8 GiB. The current test host `jaws-stepb-test` is that size, Windows 11 Pro, in `eastus`. |
| Disk | 4 GiB free on the operating-system disk. Datadog documents about 870 MB for the Windows Agent, 2 GB for the initial install, and another 2 GB while an upgrade keeps the previous install. |
| Network | Outbound HTTPS to the Datadog site chosen at install, such as `us5.datadoghq.com`. |
| Permission | The signed-in account can read the virtual machine and merge the `jaws-datadog-default` tag. |

`installer/Test-JawsPrerequisites.ps1` checks the workstation. It does not check this host. A missing site, API key, or resource id stops Datadog configuration at `JAWS-INSTALL-CONFIG-005`. A resource id that is not a virtual machine id stops at `JAWS-OBS-007`.

Sources: [Datadog Agent supported platforms](https://docs.datadoghq.com/agent/supported_platforms/?tab=windows), [Datadog Agent overhead](https://docs.datadoghq.com/agent/), [Datadog Agent install disk space](https://docs.datadoghq.com/agent/fleet_automation/upgrade_agents/), and [Dsv3 sizes](https://learn.microsoft.com/en-us/azure/virtual-machines/sizes/general-purpose/dsv3-series).

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
