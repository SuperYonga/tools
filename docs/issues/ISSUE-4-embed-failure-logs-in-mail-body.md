# ISSUE-4: Embed failure logs directly in default mail draft body

- Branch: `issue-4-embed-failure-logs-in-mail-body`
- Date: 2026-02-11
- Status: DONE (local, awaiting remote push)

## Presenting Issue
- Failure notifications included diagnostics but minimal responder guidance.
- Request: add concise "User Action Required" instructions to both SMTP and mail-draft bodies.

## Past History
- Issue 2 introduced SMTP failure notifications.
- Issue 3 added default mail-client draft + Outlook COM fallback.
- Earlier issue 4 work embedded log tails and added mailto truncation control.

## Subjective Assessment
- Hard-failure detection is robust.
- Degraded outcome handling improves materially when notification bodies include explicit next steps.

## Objective Assessment (Testing + Source Review)
- Added a shared body composer in launcher and routed both notification paths through it.
- Added regression assertions for required guidance markers.
- Test run: `npm test` => `Passed: 16 Failed: 0`.

## Analysis
- Gap in current implementation was not detection, but human-operability in incident response.
- Best-practice alignment: actionable messaging + inline diagnostics + URI-length constraints.

## Plan
1. Keep existing detection paths unchanged.
2. Add user-action and auto-attempted blocks to failure body.
3. Validate with regression tests.

## Intervention
- `Install-Brother-MFCL9570CDW-Launcher.ps1`
  - Added `New-FailureMessageBody`.
  - Added guidance text:
    - `User Action Required`
    - `Auto-attempted`
  - Reused helper for:
    - `Send-FailureNotification`
    - `Prepare-OutlookFailureDraft`
- `tests/Installer.Regression.Tests.ps1`
  - Added test: `launcher failure notifications include a user action guidance block`.

## Evaluation
- Evidence:
  - `tests/artifacts/pester-results.xml`
  - Regression summary: `16 passed, 0 failed`.

## Review
- DONE for this increment.
- Merge conflict check against `origin/main` and GitHub issue comment update are blocked because no git remote is configured in this clone.
