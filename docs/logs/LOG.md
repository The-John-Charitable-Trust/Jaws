# JAWS work log (overall)

Brief record of every session: what changed and what was found. Each entry links to the week file with the full detail.

**This branch (`aakash-logs`) is never merged into `main`.** It's updated at the end of every session.

| Where | What |
|---|---|
| `docs/logs/LOG.md` | this file: one short entry per session, newest first |
| `docs/logs/weekly/YYYY-MM-DD_week.md` | one file per week (named by that week's Monday) with detailed logs, commands, output and screenshots |
| `docs/logs/screenshots/` | images referenced from the week files, named `YYYY-MM-DD_<topic>.png` |

Every change and finding is recorded with the date it happened or was found.

---

## 2026-10-21 (Wed) · [week of 2026-10-19](weekly/2026-10-19_week.md#2026-10-21-wed)

**Changed**
- Set up an isolated tester workstation in `C:\Users\aakas\CJ\.jaws-env\` (outside the repo): Azure CLI 2.91.0 in a Python 3.13 venv, local .NET SDK 10.0.402, local Pester 5.9.1, a separate Azure login folder, and a Docker image for the Linux-only test suite
- Created branch `aakash-logs` (this log)
- Created branch `fix/az-unsupported-yes-flag`, 3 commits, opened as **PR #62** (not merged)

**Found**
- Repo prerequisites check passes and the solution builds clean (0 warnings, 0 errors)
- Installer Pester tests only run on Linux. Windows: 4/81 pass. Linux container: 80/81 on `main`
- 1 failing test on `main`: a stale Step D stub still requires `--yes` after PR #39 removed it
- **Bug:** 6 production `az` calls pass `--yes` to commands that reject it (Uninstall ×5, Step B Dynamic quota ×1). A real uninstall would fail and leave billable resources running. Fixed in PR #62, which now passes 81/81
- `main` has no branch protection or rulesets. CODEOWNERS is only `@cezjah`, and `aakash-tir` has write but not admin access
- The prerequisites docx (old repo/branch, "21 tests") is out of date compared with the repo docs (`main`, 81 tests)
