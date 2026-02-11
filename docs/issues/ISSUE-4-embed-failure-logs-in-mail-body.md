# ISSUE-4: Embed failure logs directly in default mail draft body

- Branch: `issue-4-embed-failure-logs-in-mail-body`
- Date: 2026-02-11
- Status: DONE (local)

## Presenting Issue
- Default-mail-client draft mode (`mailto:`) cannot reliably attach files across Windows mail handlers.
- Priority is reliable delivery of failure logs.

## Past History
- Issue 3 switched to default mail client first, with Outlook COM fallback.
- Failure draft body previously had metadata only, with logs mainly as attachment/path.

## Subjective Assessment
- To maximize reliability, logs must be embedded directly into draft body.

## Objective Assessment (Testing + Source Review)
- Updated launcher default draft body to include recent log lines.
- Added mailto-safe truncation guard with explicit warning logging.
- Updated regression test to assert truncation behavior.
- Ran `npm test`: Passed 15, Failed 0.

## Analysis
- Gap in implementation: default draft lacked inline logs; attachment path still manual for many clients.
- Best-practice fit: include actionable diagnostics directly in primary communication payload; constrain payload for transport limits.

## Plan
1. Embed recent logs in all failure draft bodies.
2. Add length cap for `mailto:` URI reliability.
3. Validate via regression tests and docs.

## Intervention
- `Install-Brother-MFCL9570CDW-Launcher.ps1`
  - `Prepare-OutlookFailureDraft` now includes `Get-RecentLogLines -MaxLines 120` in message body.
  - Added `SC_MAILTO_MAX_BODY_CHARS` control (default 4500, min validation >512).
  - Added warning log when body is truncated.
- `tests/Installer.Regression.Tests.ps1`
  - Mail-draft test now sets `SC_MAILTO_MAX_BODY_CHARS=700` and asserts truncation warning log appears.
- `README-Install-Brother-MFCL9570CDW.md`
  - Documented inline log behavior and body-length cap.

## Evaluation
- Command: `npm test`
- Result: `Passed: 15 Failed: 0`
- Evidence: `tests/artifacts/pester-results.xml`

## Review
- DONE for requested scope.
- Merge conflict check vs `origin/main` blocked: no `origin` remote and no local `main` branch in this clone.
