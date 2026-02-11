# ISSUE-5: Keep terminal visible and show runtime progress feedback

- Branch: `issue-5-terminal-progress-feedback`
- Date: 2026-02-11
- Status: DONE (local, awaiting remote push)

## Presenting Issue
- End users can misread silent/short runs as failures because the launcher window closes quickly.
- Request: keep visible runtime feedback while installer runs and add a practical hold-open option for troubleshooting.

## Past History
- `ISSUE-2`: SMTP failure notification path.
- `ISSUE-3`: default mail-client draft + Outlook COM fallback.
- `ISSUE-4`: embedded log tail + user action guidance in failure body.
- Existing launcher had 15-second wait logs only for elevated process path; normal path had no spinner.

## Subjective Assessment
- Current diagnostics are strong in logs and notifications.
- User confidence during execution is weak when no visible progress is shown in the terminal.

## Objective Assessment (Testing + Source Review)
- Source review:
  - `INSTALL.bat` exited immediately unless `SC_PAUSE` was set.
  - `Install-Brother-MFCL9570CDW-Launcher.ps1` direct run path invoked installer inline without progress wait feedback.
- Added shared process wait helper with spinner + heartbeat and reused it in both elevated and non-elevated paths.
- Added failure-only pause support in `INSTALL.bat`.
- Regression suite passed: `npm test` => `Passed: 17 Failed: 0`.

## Analysis
- Codebase gap: runtime UX signaling differed by execution path and lacked a default visible "still running" cue.
- Best-practice direction: long-running CLI tasks should provide continuous feedback and deterministic completion/failure signals.

## Plan
1. Centralize installer process launch arg construction.
2. Add a reusable wait helper that prints spinner and logs periodic heartbeat.
3. Apply helper to elevated and non-elevated runs.
4. Add batch failure-only pause toggle.
5. Add regression tests and update docs.

## Intervention
- `Install-Brother-MFCL9570CDW-Launcher.ps1`
  - Added:
    - `Get-InstallerPowerShellPath`
    - `New-InstallerArgumentLine`
    - `Wait-InstallerProcess`
  - Updated both launch paths to use `Start-Process ... -PassThru` + `Wait-InstallerProcess`.
  - Added progress toggle via env var `SC_SHOW_PROGRESS=0` (disable spinner).
- `INSTALL.bat`
  - Added `SC_PAUSE_ON_FAILURE=1` support.
- `tests/Installer.Regression.Tests.ps1`
  - Added assertions for:
    - `SC_PAUSE_ON_FAILURE`
    - `Wait-InstallerProcess`/`SC_SHOW_PROGRESS`/heartbeat marker.
- `README-Install-Brother-MFCL9570CDW.md`
  - Added runtime visibility and pause behavior documentation.

## Evaluation
- Evidence:
  - `tests/artifacts/pester-results.xml`
  - Regression summary: `17 passed, 0 failed`.

## Review
- DONE for this issue increment.
- Merge conflict check against `origin/main` and GitHub issue sync remain blocked because no git remote is configured in this clone.
