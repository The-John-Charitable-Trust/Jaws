# JAWS Stage A Documentation Release — v0.4.3

This ZIP is a **developer handoff artifact** for updating the JAWS repository, not a download required of end users. The public installation guide now starts with cloning GitHub and uses the checked-in installer and HTML documentation. It no longer asks customers to download and merge a second ZIP.

- `docs/installation/index.html`: expandable, first-time GitHub-based setup guide.
- `docs/verification/index.html`: HTML manual verification.
- `docs/installation/GITHUB_README_LINKS.md`: snippet to **append** to the existing project README, preserving the project's actual README content.

The implementation remains Stage A discovery-only. It will not provision Microsoft Foundry or supporting services.

To merge this ZIP into the developer workspace, preserve the current repository's existing root `README.md`; only the files under `installer/`, `docs/`, `tests/`, and `CODEX_TEST_ONLY.md` are intended to replace/extend Stage A assets.

Static HTML and archive structure were inspected; no authenticated Azure installation was executed.

### v0.4.4 manual-test corrections
- Prompt language identifies subscription/resource group as the installation target.
- Tenant scanner safely reads optional resource metadata and does not report the same subscription as both Scanned and Failed.
- HTML sidebar navigation lists only the eight primary installation steps.
- Still a read-only Stage A test candidate. Requires Windows/PowerShell and Azure re-test.


## v0.4.5 — JAWS-only state

- `installer/modules/AzurePreflight.psm1` and `tests/installer/AzurePreflight.Tests.ps1` are **based on the user's supplied corrected versions**, not the earlier ZIP files.
- Tenant scan prints a compact report splitting `JAWS`, `LegacyTightFang`, and `Unclassified` candidate matches.
- `installer/.local/jaws-installation-state.<environment>.generated.json` persists **only** verified JAWS target resources. It never adopts resources from tenant scan heuristics.
- Existing JAWS state is loaded and its resource names reused on repeated discovery. The manifest separately tracks historical ownership and missing resources.
- Discovery-only release: no automatic provisioning, skip/overwrite Azure action, or cloud resource modification.
- Tests and actual Azure CLI execution are required before acceptance.


## v0.4.6 State-first correction

- `installer/config/jaws-installation-state.dev.json` is authoritative for the current JAWS development installation.
- The JAWS tenant scan compares to this state, omitting Tight Fang resources from JAWS output.
- `Discover` never writes the gold state JSON, only generated comparison/manifest reports.
- Resource IDs intentionally remain null until Azure reconciliation verifies them; that fact does not signify a missing resource.
