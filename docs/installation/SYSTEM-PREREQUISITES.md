# JAWS System Prerequisites (Standard and Developer/Tester)

## Operating system and environment
- **Windows 11** workstation with hardware virtualization enabled, suitable memory/disk space (32 GB RAM and 1 TB SSD recommended for development).
- **PowerShell 7** for installer execution. Check with `$PSVersionTable.PSVersion`.
- **Git** for source control and **Azure CLI** (`az --version`) for authenticated Azure deployment.
- **Microsoft Entra access** with permissions appropriate to the targeted JAWS subscription, Foundry project, Container Registry and role assignments. No registry admin user required.

## Build and container prerequisites (Step C and development)
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
