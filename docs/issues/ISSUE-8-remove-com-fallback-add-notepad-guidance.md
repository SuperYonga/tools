# ISSUE-8: Remove COM fallback; use Notepad manual fallback guidance

- Branch: `issue-8-remove-com-fallback-add-notepad-guidance`
- Date: 2026-02-11
- Status: DONE (local, awaiting remote push)

## Presenting Issue
- User requested removal of Outlook COM fallback.
- Required behavior: use currently configured default mail client; if that fails, open Notepad guidance and log so user can manually email Henry.

## Past History
- `ISSUE-6`: always-on failure comms.
- `ISSUE-7`: full logs included in failure body.
- Existing draft logic still contained COM fallback references and behavior.

## Subjective Assessment
- New Outlook/default-mail-client workflow is preferred in this environment.
- COM fallback messaging was causing the wrong operational direction.

## Objective Assessment (Testing + Source Review)
- Source review confirmed draft path still referenced `outlookcom` fallback and related logs.
- Implemented:
  - removed COM fallback behavior
  - added Notepad manual fallback guidance
  - opened run log in Notepad during manual fallback
- Regression validation:
  - `npm test`
  - Passed: `18`, Failed: `0`

## Analysis
- Current gap: fallback path implied classic Outlook dependence.
- Best-practice direction: honor default system client; when automated send/draft fails, provide deterministic manual recovery instructions and direct artifact access.

## Plan
1. Remove COM fallback branch from draft function.
2. Keep default mail client draft attempt as primary behavior.
3. On draft failure, open Notepad with explicit recovery instructions and full failure payload.
4. Open run log in Notepad at same time.
5. Update tests/docs.

## Intervention
- `Install-Brother-MFCL9570CDW-Launcher.ps1`
  - Removed COM fallback path from `Prepare-OutlookFailureDraft`.
  - Added manual fallback that writes instruction file to `%TEMP%` and opens it in Notepad.
  - Added explicit instruction to email `henry@supercivil.com.au`.
  - Opens run log in Notepad during manual fallback.
  - Updated startup mode log to `fallback=notepad instructions`.
- `tests/Installer.Regression.Tests.ps1`
  - Updated expected mode/fallback log line.
  - Updated acceptable mail-draft/fallback evidence patterns.
- `README-Install-Brother-MFCL9570CDW.md`
  - Removed COM fallback references.
  - Documented Notepad manual fallback behavior.

## Evaluation
- Evidence:
  - `tests/artifacts/pester-results.xml`
  - Regression summary: `18 passed, 0 failed`.

## Review
- DONE for this issue increment.
- Could not perform `origin/main` conflict check or GitHub issue sync due missing remote configuration.
