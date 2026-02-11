# ISSUE-7: Include full failure logs in email body and tighten failure trigger visibility

- Branch: `issue-7-full-failure-log-in-email-body`
- Date: 2026-02-11
- Status: DONE (local, awaiting remote push)

## Presenting Issue
- Failure notification content still showed truncated snippets in some paths.
- Request: append full logs in failure email body whenever failure communication is triggered.

## Past History
- `ISSUE-2`: SMTP failure notifications.
- `ISSUE-3`: default mail draft/Outlook COM behavior.
- `ISSUE-4`: embedded diagnostics + action guidance.
- `ISSUE-6`: always-on failure comms and pause-on-failure defaults.

## Subjective Assessment
- Failure trigger behavior was active, but body construction still used limited tail content.
- Draft path could hit `mailto` truncation too often.

## Objective Assessment (Testing + Source Review)
- Source review confirmed:
  - `Get-RecentLogLines -MaxLines 120` used for both SMTP and draft body generation.
  - Default draft mode prioritized `mailto`, increasing truncation likelihood.
- Implemented full-log body construction and centralized failure trigger helper.
- Full regression run: `npm test` => `Passed: 18 Failed: 0`.

## Analysis
- Current gap: mismatch between expected "full logs in body" and implemented "tail excerpt in body."
- Best-practice alignment: failure comms should include complete context where transport supports it, with explicit fallback when limits apply.

## Plan
1. Replace tail-read helper with full/partial log reader.
2. Build failure body from full log content.
3. Centralize failure comms trigger into one helper to prevent path drift.
4. Prefer the system default mail client first (new Outlook compatible), fallback to Outlook COM.
5. Add regression assertions and update docs.

## Intervention
- `Install-Brother-MFCL9570CDW-Launcher.ps1`
  - Replaced `Get-RecentLogLines` with `Get-LogContent` supporting `-Full`.
  - Updated `New-FailureMessageBody` to render `Full log content`.
  - SMTP path now uses `Get-LogContent -Full`.
  - Draft path now uses `Get-LogContent -Full`.
  - Added `Invoke-FailureComms` helper for all failure paths.
  - Default draft mode now prefers the system default mail client, with Outlook COM fallback if default launch fails.
- `tests/Installer.Regression.Tests.ps1`
  - Added assertions for full-log messaging and centralized failure handler.
  - Added runtime assertions that failure handler is triggered on failing paths.
- `README-Install-Brother-MFCL9570CDW.md`
  - Updated docs to state full log content in failure bodies and new draft preference/fallback behavior.

## Evaluation
- Evidence:
  - `tests/artifacts/pester-results.xml`
  - Regression summary: `18 passed, 0 failed`.

## Review
- DONE for this issue increment.
- `origin/main` conflict check and GitHub issue sync remain blocked due missing git remote in this clone.
