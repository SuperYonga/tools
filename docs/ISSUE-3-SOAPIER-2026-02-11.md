# ISSUE-3 SOAPIER Session (2026-02-11)

## Presenting Issue
- Failure draft flow launched classic Outlook 2016 instead of user's current default mail setup.

## Past History
- Previous issue added Outlook COM-based failure draft support.

## Subjective Assessment
- Need default-client behavior first, with COM only when explicitly requested.

## Objective Assessment
- Updated launcher to use default `mailto:` draft path first.
- Added optional `SC_MAIL_DRAFT_MODE=outlookcom` fallback.
- Ran regression tests: 15 passed, 0 failed.

## Analysis
- COM binding is not equivalent to "whatever Outlook is already set up".
- Default URI mail handler aligns with user expectation on Windows.

## Plan
- Prefer default mail client, preserve COM fallback, document limitations on auto-attachments.

## Intervention
- Launcher + tests + README updated.

## Evaluation
- `npm test` successful; artifact generated at `tests/artifacts/pester-results.xml`.

## Review
- Status: DONE (local).
- No remote available for GitHub issue/PR linkage in this clone.
