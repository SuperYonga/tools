# ISSUE-6 SOAPIER Session (2026-02-11)

## Presenting Issue
- User expectation: failure comms and visible failure terminal state should always happen with no operator toggles.

## Past History
- Active branch for this increment: `issue-6-always-on-failure-notifications`.
- Related prior issue docs:
  - `docs/issues/ISSUE-2-failure-email-notification.md`
  - `docs/issues/ISSUE-3-outlook-failure-draft.md`
  - `docs/issues/ISSUE-4-embed-failure-logs-in-mail-body.md`
  - `docs/issues/ISSUE-5-terminal-progress-feedback.md`

## Subjective Assessment
- The system had strong failure handling logic, but optional switches created a practical gap in responder UX.

## Objective Assessment (Testing + Source Review)
- Verified root cause in launcher:
  - Notification and draft pathways gated behind optional flags/env vars.
- Verified batch behavior:
  - Failure pause depended on `SC_PAUSE_ON_FAILURE`.
- Implemented always-on notification and draft attempt paths.
- Implemented default pause on non-zero exit.
- Executed full regression suite:
  - Command: `npm test`
  - Result: `Passed: 17 Failed: 0`
  - Evidence: `tests/artifacts/pester-results.xml`

## Analysis
### Current Codebase Gap
- Operationally critical failure behaviors were opt-in, enabling accidental silence.

### Best-Practice Alignment
- Secure/reliable defaults should be on by default.
- Optional controls are appropriate for opt-out of non-critical behavior, not critical failure signaling.

## Plan
1. Remove notification/draft opt-in gating.
2. Keep existing SMTP/draft send error handling unchanged.
3. Make failure pause default in batch launcher.
4. Update tests and documentation.

## Intervention
- `Install-Brother-MFCL9570CDW-Launcher.ps1`
  - Removed early returns tied to `NotifyOnFailure`/`PrepareOutlookMailOnFailure` flags/env vars.
  - Added always-on mode log lines for visibility.
- `INSTALL.bat`
  - Changed to pause automatically on non-zero exit.
- `tests/Installer.Regression.Tests.ps1`
  - Updated failure pause assertion.
  - Updated failure notification and draft tests to no longer require env flag setup.
- `README-Install-Brother-MFCL9570CDW.md`
  - Updated runtime and failure-notification behavior documentation.

## Evaluation
- Re-ran objective verification with full suite:
  - `npm test` green
  - `17/17` passing
  - evidence file written at `tests/artifacts/pester-results.xml`.

## Review
- Issue scope complete for this increment.
- Could not run `origin/main` merge-conflict check or post GitHub issue update due missing remote configuration.

## Git Hygiene
- Preserved unrelated pre-existing local modification in `Install-Brother-MFCL9570CDW.ps1`.
- Scoped commit to issue-6 files only.
