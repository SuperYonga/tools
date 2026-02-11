# ISSUE-6: Enforce always-on failure notifications and visible failure pause

- Branch: `issue-6-always-on-failure-notifications`
- Date: 2026-02-11
- Status: DONE (local, awaiting remote push)

## Presenting Issue
- Operators expected failure notifications/drafts and visible error windows without having to set feature flags.
- Existing design allowed silent no-notification runs when optional flags were not set.

## Past History
- `ISSUE-2` introduced SMTP failure notifications.
- `ISSUE-3` introduced default mail draft + Outlook COM fallback.
- `ISSUE-4` added action-oriented failure body text.
- `ISSUE-5` added spinner and optional pause controls, but notifications remained opt-in.

## Subjective Assessment
- Current behavior was technically correct but operationally surprising.
- Optional flags increased the chance of missing responder signals.

## Objective Assessment (Testing + Source Review)
- Source review showed notification and draft pathways were gated by:
  - `-NotifyOnFailure` / `SC_NOTIFY_ON_FAILURE`
  - `-PrepareOutlookMailOnFailure` / `SC_OUTLOOK_DRAFT_ON_FAILURE`
- `INSTALL.bat` only paused on failure when `SC_PAUSE_ON_FAILURE=1` was set.
- Updated code to make failure notifications/drafts always attempted, and failure pause default.
- Test run: `npm test` => `Passed: 17 Failed: 0`.

## Analysis
- Gap in current implementation: critical responder behaviors depended on flags.
- Best-practice alignment: default-safe operational behavior should be on-by-default, not opt-in.

## Plan
1. Remove opt-in notification gates.
2. Keep draft behavior active on every failure path.
3. Pause `cmd` on non-zero exit by default.
4. Update regression tests and docs.

## Intervention
- `Install-Brother-MFCL9570CDW-Launcher.ps1`
  - Removed notification/draft gate checks.
  - Added explicit startup logs:
    - `Failure notification mode: always-on`
    - `Outlook failure draft mode: always-on`
- `INSTALL.bat`
  - Changed to unconditional pause on non-zero exit.
- `tests/Installer.Regression.Tests.ps1`
  - Updated assertions for always-on log markers and unconditional failure pause.
- `README-Install-Brother-MFCL9570CDW.md`
  - Updated docs to always-on behavior (no enable flags required).

## Evaluation
- Evidence:
  - `tests/artifacts/pester-results.xml`
  - Regression summary: `17 passed, 0 failed`.

## Review
- DONE for this issue increment.
- Merge conflict check against `origin/main` and GitHub issue sync are blocked because no `origin` remote is configured in this clone.
