# ISSUE-2: Add failure email notifications for installer runs

- Branch: `issue-2-failure-email-notification`
- Date: 2026-02-11
- Status: DONE (local)

## 1) Session / branch hygiene
- Existing worktree was on `issue-1-pluggable-printer-driver-input`.
- Created dedicated branch `issue-2-failure-email-notification` for this feature.
- GitHub issue creation via `gh` is blocked because this repo has no remote configured.
- Local issue tracking file created here as fallback.

## 2) Presenting issue
- Request: add functionality to automatically collect errors and email them to `henry@supercivil.com.au` when installer runs fail.

## 3) Past history
- Existing scripts already wrote detailed logs to `logs/`.
- Launcher already centralized elevation and installer exit handling, making it the correct integration point.
- Regression suite existed (`npm test` / Pester), but had no notifier assertions.

## 4) Subjective assessment
- Feature complexity is low-to-moderate if scoped to launcher-level failure events and SMTP config via environment variables.
- Risk mainly sits in email transport configuration, not script logic.

## 5) Objective assessment
- Source review identified non-zero exit and exception points in `Install-Brother-MFCL9570CDW-Launcher.ps1`.
- Added notifier path and regression test.
- Executed `npm test` with result `Passed: 14 Failed: 0`.

## 6) Analysis / gap analysis
### 6a) Current codebase gaps (before fix)
- No automated failure notification existed.
- Failures only surfaced in local log files.

### 6b) Best-practice alignment
- Keep notifications opt-in and secretless in repo.
- Use environment variables for SMTP host/from/credentials.
- Never let notification failure break primary install flow.
- Include actionable context (exit code, host/user, log tail).

## 7) Problem list
### 7a) Immediate fix
1. Add opt-in notification trigger on run failure.
2. Capture and include recent log lines in email body.
3. Add regression test proving notifier path executes safely when SMTP is absent.

### 7b) Shift-left
1. Keep notifier behavior in regression suite.
2. Document required SMTP env vars in README.
3. Add remote + GitHub issue automation when repo remote is configured.

## 8) Intervention
- Updated `Install-Brother-MFCL9570CDW-Launcher.ps1`:
  - Added params: `-NotifyOnFailure`, `-NotifyTo` (default `henry@supercivil.com.au`).
  - Added `Get-RecentLogLines` helper.
  - Added `Send-FailureNotification` helper using `.NET` SMTP client and env-based config.
  - Wired notifier to all launcher failure paths:
    - missing installer script
    - elevated child non-zero exit
    - elevation launch exception
    - direct installer non-zero exit
    - launcher catch
- Updated `tests/Installer.Regression.Tests.ps1`:
  - Added launcher helper invocation function.
  - Added regression test for notifier-skip path when SMTP config is missing.
- Updated `README-Install-Brother-MFCL9570CDW.md`:
  - Added "Failure email notification (optional)" section and env var contract.

## 9) Evaluation
- Command: `npm test`
- Result: `Passed: 14 Failed: 0`
- Evidence artifact: `tests/artifacts/pester-results.xml`
- New test confirms failure path logs notification attempt and safe skip without SMTP config.

## 10) Review
- DONE for requested feature scope.
- Merge conflict check against `origin/main` cannot be executed because no `origin` remote exists.

## 11) Documentation-as-code
- This issue note + SOAPIER record (separate file) provide reproducible session evidence.

## 12) Git hygiene
- Dedicated issue branch created.
- Changes isolated to launcher, tests, and README/docs.

## 13) Pre-finish checks
- Issue doc: present.
- Branch: present.
- Testing: green.
- SOAPIER: present.

## 14) Finish
- Ready for commit/push to remote once a GitHub remote is configured.
