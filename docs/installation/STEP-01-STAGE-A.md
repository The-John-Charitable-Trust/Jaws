# Step 1 — JAWS State-First Discovery (Stage A 0.4.6)

JAWS installation state is the operator-managed **gold copy**. Discovery compares tenant and targeted resource inventory to the state file; it never rewrites that file. Legacy Tight Fang is ignored in JAWS reports.

## Existing development environment

`installer/config/jaws-installation-state.dev.json` already contains the expected four JAWS resource names, types, location and model version. The Azure resource IDs remain null until verified by the installer; no IDs were fabricated.

## Start discovery

From the cloned JAWS repository root:

```powershell
.\installer\Install-Jaws.ps1 -Mode Discover
```

The installer loads state first and uses its subscription and resource group, checks Azure access, scans readable subscriptions, and compares observations against the expected state. It writes tenant and comparison **reports** under `installer/.local/`, not changes to the state file.

## A new user's first run

There is no prepopulated state for an independent customer. The intended first-time action is `Install`, which will generate and populate the new installation state after successful deployment. **Stage A does not implement Install mode**; this document describes the developer/tester verification scenario only.

Never copy the seeded development state to a different subscription. The installed source may contain a sample state file for tests, not a universal default installation.
