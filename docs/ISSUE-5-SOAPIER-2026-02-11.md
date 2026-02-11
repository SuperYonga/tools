# ISSUE-5 SOAPIER Session (2026-02-11)

## Presenting Issue
- Users reported uncertainty during runs: terminal disappears, no immediate test page, no clear in-window "still running" signal.

## Past History
- Active branch for this increment: `issue-5-terminal-progress-feedback`.
- Related docs reviewed:
  - `docs/issues/ISSUE-1-pluggable-printer-driver-input.md`
  - `docs/issues/ISSUE-2-failure-email-notification.md`
  - `docs/issues/ISSUE-3-outlook-failure-draft.md`
  - `docs/issues/ISSUE-4-embed-failure-logs-in-mail-body.md`
- Existing issue-4 branch content already improved failure notifications but not runtime terminal feedback.

## Subjective Assessment
- End-user confidence gap persisted for "is this still running?".
- Existing logs and notifications were useful post-failure, but insufficient as live execution feedback.

## Objective Assessment (Testing + Source Review)
- Verified launch flow:
  - `INSTALL.bat` closes immediately unless `SC_PAUSE` is set.
  - Launcher logged wait heartbeats only on elevated path.
  - Non-elevated path executed installer directly without spinner.
- Implemented shared wait helper and reused in both process paths.
- Added failure-only pause in batch launcher.
- Added regression guards and executed test suite:
  - Command: `npm test`
  - Result: `Passed: 17 Failed: 0`
  - Evidence: `tests/artifacts/pester-results.xml`

## Analysis
### Current Codebase Gap
- Runtime feedback was inconsistent by code path.
- No standard failure-only terminal hold option for desktop troubleshooting.

### Best-Practice Alignment
- CLI and installer UX patterns favor visible liveness indicators for long-running tasks.
- Operational reliability favors periodic heartbeat logs even when visual spinner is disabled.

## Plan
1. DRY process-launch argument building.
2. Add one reusable wait/progress helper.
3. Apply helper to all launcher wait paths.
4. Add `SC_PAUSE_ON_FAILURE` to reduce false "it crashed" interpretations.
5. Protect behavior with regression tests and docs.

## Intervention
- `Install-Brother-MFCL9570CDW-Launcher.ps1`
  - Added `Get-InstallerPowerShellPath`, `New-InstallerArgumentLine`, `Wait-InstallerProcess`.
  - Moved non-elevated invocation to `Start-Process` + wait helper.
  - Kept periodic heartbeat logging every 15s.
  - Added spinner toggle `SC_SHOW_PROGRESS=0`.
- `INSTALL.bat`
  - Added `SC_PAUSE_ON_FAILURE=1` conditional pause.
- `tests/Installer.Regression.Tests.ps1`
  - Added regression assertions for progress helper and pause-on-failure support.
- `README-Install-Brother-MFCL9570CDW.md`
  - Added usage notes for progress and window hold options.

## Evaluation
- Green regression evidence:
  - `npm test`
  - `tests/artifacts/pester-results.xml`
  - Summary: `17 passed, 0 failed`.

## Review
- Scope complete for issue-5 increment.
- Cannot validate `origin/main` conflicts or post to GitHub issue because this clone currently has no `origin` remote.

## Git Hygiene
- Left pre-existing unrelated modification untouched: `Install-Brother-MFCL9570CDW.ps1`.
- Committed only issue-5 related files.
