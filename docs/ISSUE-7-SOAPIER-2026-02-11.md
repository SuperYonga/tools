# ISSUE-7 SOAPIER Session (2026-02-11)

## Presenting Issue
- Operator feedback showed failure mail body still arriving with truncated content in some scenarios.
- Requirement clarified: include full logs in failure body whenever failure comms are triggered.

## Past History
- Active branch: `issue-7-full-failure-log-in-email-body`.
- Related docs reviewed:
  - `docs/issues/ISSUE-2-failure-email-notification.md`
  - `docs/issues/ISSUE-3-outlook-failure-draft.md`
  - `docs/issues/ISSUE-4-embed-failure-logs-in-mail-body.md`
  - `docs/issues/ISSUE-6-always-on-failure-notifications.md`

## Subjective Assessment
- Failure comms were firing, but payload completeness did not meet operator expectations.
- Any mode that forces classic Outlook COM first can conflict with users who rely on New Outlook/default mail client behavior.

## Objective Assessment (Testing + Source Review)
- Confirmed body generation used `Get-RecentLogLines -MaxLines 120`.
- Confirmed failure comms invoked from multiple code paths with duplicated calls.
- Implemented:
  - full-log reader helper (`Get-LogContent -Full`)
  - centralized failure comms trigger (`Invoke-FailureComms`)
  - default draft preference for the system default mail client, with explicit Outlook COM fallback
- Ran full suite:
  - Command: `npm test`
  - Result: `Passed: 18 Failed: 0`
  - Evidence: `tests/artifacts/pester-results.xml`

## Analysis
### Current Codebase Gap
- 120-line tail in body conflicted with full-context requirement.
- Duplicated trigger calls increased risk of drift.

### Best-Practice Alignment
- On incident/failure paths, provide complete diagnostic context where channel supports it.
- Centralize critical branching to reduce behavioral divergence.
- When channel constraints exist (`mailto` URI length), degrade explicitly with clear operator guidance.

## Plan
1. Replace log-tail body input with full-log input.
2. DRY failure notification trigger into one helper.
3. Prefer currently configured default mail client first; fallback to Outlook COM only when needed.
4. Maintain explicit fallback and warning logs.
5. Update tests and docs.

## Intervention
- `Install-Brother-MFCL9570CDW-Launcher.ps1`
  - Added/updated: `Get-LogContent`, `Invoke-FailureComms`.
  - Updated `New-FailureMessageBody` to include `Full log content`.
  - SMTP and draft body generation now use `Get-LogContent -Full`.
  - Default draft mode switched to system default mail client first, with Outlook COM fallback on default launch failure.
- `tests/Installer.Regression.Tests.ps1`
  - Added assertions for:
    - `Full log content:` marker
    - `Invoke-FailureComms` presence
    - `Failure handler triggered` runtime log on failed runs
- `README-Install-Brother-MFCL9570CDW.md`
  - Updated failure-content and draft behavior sections.

## Evaluation
- Validation output:
  - `npm test` green
  - `18/18` tests passed
  - evidence file updated: `tests/artifacts/pester-results.xml`.

## Review
- Issue scope complete for this increment.
- Could not perform `origin/main` conflict check or GitHub issue posting due missing remote configuration.

## Git Hygiene
- Unrelated pre-existing local modification remained untouched: `Install-Brother-MFCL9570CDW.ps1`.
- Issue-scoped files only included in this increment commit.
