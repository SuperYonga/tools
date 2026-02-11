# ISSUE-9 SOAPIER Session (2026-02-11)

## Presenting Issue
- Failure email/draft body was not consistently showing full logs because mailto truncation was active.
- User requested full log body inclusion whenever failure email condition is opened and trigger logic verification.
- User also required only one email action per failed run.

## Past History
- Active branch: `issue-9-full-log-body-on-email-trigger`.
- Related issues: `ISSUE-6`, `ISSUE-7`, `ISSUE-8`.
- Existing branch was carrying a prior unrelated local change in `Install-Brother-MFCL9570CDW.ps1`; left untouched.

## Subjective Assessment
- Operationally confusing: failure template says full logs included, but users can receive truncated body text.
- Failure comms should be provably failure-only.

## Objective Assessment (Testing + Source Review)
- Source review:
  - full-log behavior was present, but failure comms could execute both draft and SMTP actions in one run.
  - no duplicate-trigger sentinel existed inside `Invoke-FailureComms`.
- Code changes applied:
  - kept full-log body behavior in all failure email paths.
  - added duplicate-trigger sentinel (`$script:FailureCommsTriggered`) in failure-comms handler.
  - enforced single-channel behavior per run (`smtp-primary` else `mail-draft-primary`, with draft fallback on SMTP failure).
  - updated tests and docs accordingly.
- Validation command:
  - `npm test`
- Validation result:
  - `Passed: 19 Failed: 0`
  - Evidence file: `tests/artifacts/pester-results.xml`

## Analysis
### Current Codebase Gap
- Failure comms flow could execute more than one email action for a single failed run.

### Best-Practice Alignment
- RFC 6068 (`mailto`) describes format and leaves implementation constraints to clients, so application-level truncation is optional behavior.
- OWASP logging guidance emphasizes retaining useful context for investigations, supporting full failure-context inclusion.

## Plan
1. Enforce one failure email action per run in the comms dispatcher.
2. Add duplicate-trigger sentinel guard.
3. Keep full-log body behavior unchanged.
4. Update regression tests and run full suite.

## Intervention
- Updated `Install-Brother-MFCL9570CDW-Launcher.ps1`:
  - added `$script:FailureCommsTriggered` sentinel and duplicate-skip log.
  - switched dispatch to one channel per run:
    - SMTP primary when configured.
    - draft primary when SMTP is unavailable.
    - draft fallback when SMTP send fails.
- Updated `tests/Installer.Regression.Tests.ps1`:
  - revised SMTP-missing regression to assert `mail-draft-primary` channel.
  - added guard regression asserting duplicate-protection code markers.
- Updated `README-Install-Brother-MFCL9570CDW.md`:
  - documented single-email-action channel behavior on failure.

## Evaluation
- Regression suite green (`19/19`).
- Evidence captured in `tests/artifacts/pester-results.xml`.

## Review
- Issue scope complete locally.
- Branch pushed to `origin/issue-9-full-log-body-on-email-trigger`.
- `origin/main` conflict status cannot be meaningfully validated because histories are unrelated (`git merge-tree` reported unrelated histories).

## Git Hygiene
- Branch created for this session: `issue-9-full-log-body-on-email-trigger`.
- Local unrelated modification preserved and not altered: `Install-Brother-MFCL9570CDW.ps1`.
