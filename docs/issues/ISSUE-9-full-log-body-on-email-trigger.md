# ISSUE-9: Always include full run logs in failure email body and tighten failure trigger logic

- Branch: `issue-9-full-log-body-on-email-trigger`
- Date: 2026-02-11
- Status: DONE (local, awaiting remote push)

## Presenting Issue
- Failure draft/email body was being truncated in the default mail-client (`mailto`) path.
- User requirement: include full log content whenever failure email/draft condition is triggered, and verify trigger logic is correct.
- Additional requirement: only one email action should be created per failed run.

## Past History
- `ISSUE-6`: made failure comms always-on.
- `ISSUE-7`: included full logs in failure body content.
- `ISSUE-8`: removed Outlook COM fallback and switched fallback to Notepad guidance.
- Existing code still had `mailto` truncation guard that prevented full log body delivery.

## Subjective Assessment
- Current behavior looked inconsistent: body template claims full log content but actual draft could end with `[TRUNCATED]`.
- Trigger behavior should remain failure-only (non-zero exit) and never run on successful installs.

## Objective Assessment (Testing + Source Review)
- Source review findings:
  - `Install-Brother-MFCL9570CDW-Launcher.ps1` previously used `SC_MAILTO_MAX_BODY_CHARS` with truncation marker in draft path.
  - Failure comms had a mode where both draft and SMTP paths could run in the same failed invocation.
- Implemented updates:
  - removed draft truncation logic; full body now passed to default mail client attempt.
  - added central duplicate guard (`$script:FailureCommsTriggered`) to avoid re-handling.
  - switched to single-channel per run: SMTP primary when configured, otherwise draft primary; SMTP failure falls back to draft.
  - kept failure-only trigger behavior (`ExitCode <> 0`) and full-log body in all email paths.
  - updated tests to enforce these outcomes.
- Regression validation:
  - `npm test`
  - Passed: `19`, Failed: `0`
  - Evidence: `tests/artifacts/pester-results.xml`

## Analysis
### (a) Current codebase implementation gap
- `mailto` draft path diverged from intended full-log failure payload due to local truncation logic.
- Trigger logic relied on call sites only; no central guard in failure-communications function.

### (b) Best-practice gap vs authoritative guidance
- RFC 6068 defines `mailto` URI format but does not guarantee large body portability; implementations vary. This means app-level truncation is a product choice, not a protocol requirement.
- OWASP Logging guidance stresses preserving sufficient event context for investigation; truncating failure evidence reduces operational clarity.

References:
- RFC 6068 (`mailto` URI): https://datatracker.ietf.org/doc/html/rfc6068
- OWASP Logging Cheat Sheet: https://cheatsheetseries.owasp.org/cheatsheets/Logging_Cheat_Sheet.html

## Plan
1. Keep full-log body behavior in failure comms.
2. Enforce one failure email action per run.
3. Add duplicate-trigger guard in failure comms.
4. Update regression tests and README.
5. Re-run full regression tests.

## Intervention
- `Install-Brother-MFCL9570CDW-Launcher.ps1`
  - Maintained full-log body in draft and SMTP paths.
  - Added `$script:FailureCommsTriggered` duplicate guard and skip log.
  - Added single-channel selection in `Invoke-FailureComms`:
    - `smtp-primary` when SMTP is configured.
    - `mail-draft-primary` when SMTP is not configured.
    - draft fallback if SMTP send fails.
- `tests/Installer.Regression.Tests.ps1`
  - Updated failure test to assert `mail-draft-primary` channel selection when SMTP is missing.
  - Added assertion that SMTP skip log is absent in draft-primary path.
  - Added guard-presence regression for duplicate handling protection.
- `README-Install-Brother-MFCL9570CDW.md`
  - Documented single-email-action-per-run channel behavior.

## Evaluation
- Executed: `npm test`
- Result: `19 passed, 0 failed`
- Evidence:
  - `tests/artifacts/pester-results.xml`
  - Updated regression cases:
    - `launcher failure notification path uses a single mail-draft channel when SMTP is not configured`
    - `launcher central failure comms guard prevents duplicate trigger handling in one run`

## Review
- DONE for this issue scope.
- Could not check conflict state against `origin/main` or open/update GitHub issue because this clone has no configured remote.
