# JAWS Stage A Documentation Release — v0.4.3

This ZIP is a **developer handoff artifact** for updating the JAWS repository, not a download required of end users. The public installation guide now starts with cloning GitHub and uses the checked-in installer and HTML documentation. It no longer asks customers to download and merge a second ZIP.

- `docs/installation/index.html`: expandable, first-time GitHub-based setup guide.
- `docs/verification/index.html`: HTML manual verification.
- `docs/installation/GITHUB_README_LINKS.md`: snippet to **append** to the existing project README, preserving the project's actual README content.

The implementation remains Stage A discovery-only. It will not provision Microsoft Foundry or supporting services.

To merge this ZIP into the developer workspace, preserve the current repository's existing root `README.md`; only the files under `installer/`, `docs/`, `tests/`, and `CODEX_TEST_ONLY.md` are intended to replace/extend Stage A assets.

Static HTML and archive structure were inspected; no authenticated Azure installation was executed.
