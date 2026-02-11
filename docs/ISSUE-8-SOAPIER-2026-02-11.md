# ISSUE-8 SOAPIER Session (2026-02-11)

## Presenting Issue
- User requested: remove Outlook COM fallback.
- Desired fallback: open Notepad with clear incident instructions and log so user can manually email Henry.

## Past History
- Active branch: `issue-8-remove-com-fallback-add-notepad-guidance`.
- Related docs:
  - `docs/issues/ISSUE-6-always-on-failure-notifications.md`
  - `docs/issues/ISSUE-7-full-failure-log-in-email-body.md`

## Subjective Assessment
- Default-client-first behavior works with New Outlook.
- COM fallback created confusing expectations and unwanted coupling to legacy Outlook.

## Objective Assessment (Testing + Source Review)
- Confirmed COM fallback references in launcher draft path and docs/tests.
- Implemented fallback replacement:
  - default mail-client draft attempt
  - Notepad instruction fallback with explicit `henry@supercivil.com.au` escalation
  - log opened in Notepad for immediate attachment context
- Ran full regression suite:
  - Command: `npm test`
  - Result: `Passed: 18 Failed: 0`
  - Evidence: `tests/artifacts/pester-results.xml`

## Analysis
### Current Codebase Gap
- Fallback path retained legacy COM behavior not desired in current user environment.

### Best-Practice Alignment
- Respect platform default app configuration.
- On automation failures, provide deterministic manual fallback with clear next action and source artifacts.

## Plan
1. Remove COM fallback branch.
2. Keep default mail client as only automated draft path.
3. Add manual Notepad fallback with explicit instructions to email Henry.
4. Update tests and docs.

## Intervention
- `Install-Brother-MFCL9570CDW-Launcher.ps1`
  - Removed COM fallback.
  - Added manual fallback note file + Notepad launch.
  - Added log-open in Notepad.
  - Updated mode log text to `fallback=notepad instructions`.
- `tests/Installer.Regression.Tests.ps1`
  - Updated expected fallback markers.
- `README-Install-Brother-MFCL9570CDW.md`
  - Updated draft mode/fallback documentation.

## Evaluation
- Regression suite green:
  - `18/18` tests passed.
  - Evidence artifact updated: `tests/artifacts/pester-results.xml`.

## Review
- Scope complete for this issue increment.
- Cannot validate conflicts with `origin/main` or post GitHub updates due no configured remote in this clone.

## Git Hygiene
- Unrelated local modification left untouched: `Install-Brother-MFCL9570CDW.ps1`.
- Changes scoped to issue-8 files.
