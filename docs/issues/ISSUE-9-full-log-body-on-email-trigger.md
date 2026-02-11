# ISSUE-9: Always include full run logs in failure email body and tighten failure trigger logic

- Branch: `issue-9-full-log-body-on-email-trigger`
- Date: 2026-02-11
- Status: DONE (local, awaiting remote push)

## Presenting Issue
- Failure draft/email body was being truncated in the default mail-client (`mailto`) path.
- User requirement: include full log content whenever failure email/draft condition is triggered, and verify trigger logic is correct.

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
  - `Install-Brother-MFCL9570CDW-Launcher.ps1` used `SC_MAILTO_MAX_BODY_CHARS` with truncation marker in draft path.
  - Failure comms function lacked a defensive zero-exit guard.
- Implemented updates:
  - removed draft truncation logic; full body now passed to default mail client attempt.
  - added explicit guard: skip failure comms if `ExitCode = 0`.
  - updated tests to enforce no truncation warning and no failure comms on successful run.
- Regression validation:
  - `npm test`
  - Passed: `18`, Failed: `0`
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
1. Remove `mailto` truncation path so draft body always uses full failure payload.
2. Add a central non-zero guard in `Invoke-FailureComms`.
3. Update regression tests and README to match behavior.
4. Re-run full regression tests.

## Intervention
- `Install-Brother-MFCL9570CDW-Launcher.ps1`
  - Removed `SC_MAILTO_MAX_BODY_CHARS` truncation branch.
  - Updated draft success log to indicate `body=full-log`.
  - Added explicit guard in `Invoke-FailureComms` to skip on `ExitCode=0`.
- `tests/Installer.Regression.Tests.ps1`
  - Updated mail-draft regression test to assert no truncation warnings.
  - Added success-path assertion: no failure comms/draft send markers in successful `ValidateOnly` run.
- `README-Install-Brother-MFCL9570CDW.md`
  - Removed truncation and `SC_MAILTO_MAX_BODY_CHARS` documentation.

## Evaluation
- Executed: `npm test`
- Result: `18 passed, 0 failed`
- Evidence:
  - `tests/artifacts/pester-results.xml`
  - Updated regression case `launcher mail-draft path logs enabled and uses full log body without truncation`

## Review
- DONE for this issue scope.
- Could not check conflict state against `origin/main` or open/update GitHub issue because this clone has no configured remote.
