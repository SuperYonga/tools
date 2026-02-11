# ISSUE-9 SOAPIER Session (2026-02-11)

## Presenting Issue
- Failure email/draft body was not consistently showing full logs because mailto truncation was active.
- User requested full log body inclusion whenever failure email condition is opened and trigger logic verification.

## Past History
- Active branch: `issue-9-full-log-body-on-email-trigger`.
- Related issues: `ISSUE-6`, `ISSUE-7`, `ISSUE-8`.
- Existing branch was carrying a prior unrelated local change in `Install-Brother-MFCL9570CDW.ps1`; left untouched.

## Subjective Assessment
- Operationally confusing: failure template says full logs included, but users can receive truncated body text.
- Failure comms should be provably failure-only.

## Objective Assessment (Testing + Source Review)
- Source review:
  - truncation existed in `Prepare-OutlookFailureDraft` via `SC_MAILTO_MAX_BODY_CHARS`.
  - no defensive `ExitCode=0` guard existed inside `Invoke-FailureComms`.
- Code changes applied:
  - removed truncation branch, always pass full body to mailto attempt.
  - added `ExitCode -eq 0` early return in failure-comms handler.
  - updated tests and docs accordingly.
- Validation command:
  - `npm test`
- Validation result:
  - `Passed: 18 Failed: 0`
  - Evidence file: `tests/artifacts/pester-results.xml`

## Analysis
### Current Codebase Gap
- Full-log intent was not preserved end-to-end in the default mail-client path due to truncation behavior.

### Best-Practice Alignment
- RFC 6068 (`mailto`) describes format and leaves implementation constraints to clients, so application-level truncation is optional behavior.
- OWASP logging guidance emphasizes retaining useful context for investigations, supporting full failure-context inclusion.

## Plan
1. Remove draft truncation logic.
2. Add centralized non-zero guard for failure comms.
3. Update regression tests to enforce both outcomes.
4. Run full regression suite and capture evidence.

## Intervention
- Updated `Install-Brother-MFCL9570CDW-Launcher.ps1`:
  - removed `SC_MAILTO_MAX_BODY_CHARS` handling and `[TRUNCATED]` mutation.
  - updated draft-open log line to include `body=full-log`.
  - added early-return guard for `ExitCode=0` in `Invoke-FailureComms`.
- Updated `tests/Installer.Regression.Tests.ps1`:
  - revised failure-draft regression to assert no truncation logs.
  - added success-path assertions for absence of failure comms markers.
- Updated `README-Install-Brother-MFCL9570CDW.md`:
  - removed truncation cap and env var notes.

## Evaluation
- Regression suite green (`18/18`).
- Evidence captured in `tests/artifacts/pester-results.xml`.

## Review
- Issue scope complete locally.
- `origin/main` conflict status and GitHub issue sync cannot be validated in this clone because no git remote is configured.

## Git Hygiene
- Branch created for this session: `issue-9-full-log-body-on-email-trigger`.
- Local unrelated modification preserved and not altered: `Install-Brother-MFCL9570CDW.ps1`.
