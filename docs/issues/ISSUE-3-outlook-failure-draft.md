# ISSUE-3: Use default configured mail client for failure drafts

- Branch: `issue-3-outlook-failure-draft`
- Date: 2026-02-11
- Status: DONE (local)

## Presenting Issue
- Failure-draft feature opened classic Outlook 2016 via COM.
- Requirement changed to use whichever mail/Outlook app is already configured on the PC.

## Past History
- Issue 2 added failure notifications and Outlook COM draft flow.
- Existing launcher centralized all failure handling paths.
- Regression suite existed and covered launcher failure-notification behavior.

## Subjective Assessment
- COM is tied to classic Outlook registration and may not match user default mail app.

## Objective Assessment (Testing)
- Implemented default-mail-client-first draft creation via `mailto:`.
- Kept optional `outlookcom` mode for auto-attachment when needed.
- Ran `npm test`: Passed 15, Failed 0.

## Analysis
- Gap in current implementation: forced Outlook COM path.
- Best practice: use system default handler for user-facing compose unless strict client integration is required.

## Plan
1. Use default mail client draft by default.
2. Keep Outlook COM as explicit fallback mode.
3. Update tests/docs.

## Intervention
- `Install-Brother-MFCL9570CDW-Launcher.ps1`
  - `Prepare-OutlookFailureDraft` now:
    - defaults to `mailto:` draft (`SC_MAIL_DRAFT_MODE=default`)
    - logs manual-attachment instruction for default mode
    - supports forced COM via `SC_MAIL_DRAFT_MODE=outlookcom`
- `tests/Installer.Regression.Tests.ps1`
  - updated mail-draft regression assertion for default/fallback paths
- `README-Install-Brother-MFCL9570CDW.md`
  - documented default behavior + fallback mode and attachment behavior

## Evaluation
- `npm test` green: 15/15.
- Evidence artifact: `tests/artifacts/pester-results.xml`.

## Review
- DONE for requested scope.
- Cannot verify conflicts with `origin/main` in this clone (no remote/main configured).
