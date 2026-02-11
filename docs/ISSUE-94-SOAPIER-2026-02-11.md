# ISSUE-94 SOAPIER Session (2026-02-11)

## (1) Git Hygiene + Issue/Branch Alignment
- Created GitHub issue: `#94`
  - https://github.com/SuperYonga/superyonga/issues/94
- Created and switched to branch:
  - `issue-94-printer-retry-comms-default-printer`
- Confirmed local repo and branch alignment before edits.

## (2) Presenting Issue
- Operator-reported problems from installer runs:
  1. Multiple printed test pages per run due to repeated invocation attempts.
  2. Test-page verification failure could still complete with exit code `0`, so launcher failure comms were not triggered.
  3. Need internal/dev diagnostics mode to send email/draft for successful runs too.
  4. Intermittent printer error `0x000003f0` (`token does not exist`).
  5. Need configured queue set as default printer.

## (3) Past History
- Related issue chain:
  - `#88` comms channel behavior
  - `#89` reachability evidence
  - `#91` degraded queue-only signaling
- Existing regression framework already wired:
  - `npm test` -> `tests/run-regression-tests.ps1`
  - CI workflow: `.github/workflows/regression-tests.yml`

## (4) Subjective Assessment
- Installer operational behavior was mostly successful (driver/port/queue), but reliability and operator-feedback semantics were inconsistent with expected internal diagnostics workflows.

## (5) Objective Assessment (Logs + Source + Tests)
- Source findings:
  - Test page invocation used multiple sends per run (`InvokeAttempts=3` for install, `2` for pending retry).
  - `no queue job evidence` path queued retry but did not mark degraded/exit non-zero.
  - Launcher comms was failure-only (non-zero exits), no success diagnostics mode.
  - Queue creation used `printui` only; no fallback strategy for token-related failures.
  - No explicit default-printer setting postcondition.
- Test run after intervention:
  - Command: `npm test`
  - Result: `Passed: 25 Failed: 0`
  - Artifact: `tests/artifacts/pester-results.xml`

## (6) Analysis (Gap vs Best Practice)
### (a) Current Codebase Gaps
1. Repeated print-send attempts can cause duplicate physical output.
2. Failure evidence path lacked non-zero signaling, suppressing failure comms.
3. Diagnostics comms lacked explicit dev/internal success mode.
4. Queue creation had single-path dependency (`printui`) with weaker resilience.
5. Default-printer outcome was not explicitly enforced/logged.

### (b) Best-Practice References
1. Microsoft Scheduled Tasks + print cmdlet contracts:
   - `New-ScheduledTaskTrigger` and supported parameters:
     https://learn.microsoft.com/powershell/module/scheduledtasks/new-scheduledtasktrigger
   - `Add-Printer`:
     https://learn.microsoft.com/powershell/module/printmanagement/add-printer
2. Windows print UI invocation behavior (`PrintUIEntry`):
   - https://learn.microsoft.com/windows-server/administration/windows-commands/rundll32-printui
3. Logging/operability guidance:
   - NIST SP 800-92: https://csrc.nist.gov/pubs/sp/800/92/final
   - OWASP Logging Cheat Sheet: https://cheatsheetseries.owasp.org/cheatsheets/Logging_Cheat_Sheet.html

## (7) Prioritized Problem List
### (a) Immediate Fix
1. Single-send test-page behavior per run.
2. Non-zero degraded exit for no-evidence test-page failures.
3. Optional success diagnostics comms mode.
4. Printer queue creation fallback strategy to mitigate token-related failures.
5. Best-effort default-printer set with postcondition logging.

### (b) Shift-Left Prevention
1. Add regression assertions for new behaviors and guard old failure patterns.
2. Keep launcher logging explicit for comms mode, status, and channel.
3. Document new operator flags and exit semantics in README.

## (8) Intervention
- `Install-Brother-MFCL9570CDW.ps1`
  - Added `-NoSetDefaultPrinter`.
  - Added constants:
    - `$TestPageInvokeAttemptsInstall = 1`
    - `$TestPageInvokeAttemptsRetry = 1`
  - Added `Ensure-PrinterQueueExists`:
    - prefers `Add-Printer`, falls back to `printui`.
    - logs token-related (`0x000003f0`) failure hints.
  - Added `Set-DefaultPrinterBestEffort`:
    - CIM `SetDefaultPrinter` attempt, `printui /y` fallback, postcondition logging.
  - Changed test-page no-evidence path to degraded failure:
    - records reason, queues retry, appends degraded reason, exits `2`.

- `Install-Brother-MFCL9570CDW-Launcher.ps1`
  - Added `-NotifyAlways` + `SC_NOTIFY_ALWAYS=1` support.
  - Added `Invoke-SuccessDiagnosticComms` for success-run diagnostic email/draft.
  - Forwarded `-NoSetDefaultPrinter` to installer.
  - Added explicit mode logging: success diagnostics enabled/disabled.

- `tests/Installer.Regression.Tests.ps1`
  - Added static assertions for:
    - single-send attempt constants and invocation wiring.
    - new degraded no-evidence logging.
    - printer creation fallback/default-printer functions.
    - launcher success diagnostics mode and knobs.
  - Added runtime test:
    - launcher success diagnostics with `-NotifyAlways`.
  - Kept existing regression and scheduled-task safeguards.

- `README-Install-Brother-MFCL9570CDW.md`
  - Added flags and behavior:
    - `-NotifyAlways`
    - `-NoSetDefaultPrinter`
    - degraded semantics for no test-page evidence
    - single-send test-page strategy

## (9) Evaluation (Evidence)
- Executed:
  - `npm test`
- Observed:
  - `Passed: 25 Failed: 0`
  - XML artifact generated at:
    - `tests/artifacts/pester-results.xml`
- Key code evidence:
  - `Install-Brother-MFCL9570CDW.ps1:47`
  - `Install-Brother-MFCL9570CDW.ps1:731`
  - `Install-Brother-MFCL9570CDW.ps1:769`
  - `Install-Brother-MFCL9570CDW.ps1:996`
  - `Install-Brother-MFCL9570CDW-Launcher.ps1:335`
  - `Install-Brother-MFCL9570CDW-Launcher.ps1:446`
  - `tests/Installer.Regression.Tests.ps1:137`
  - `tests/Installer.Regression.Tests.ps1:184`
  - `tests/Installer.Regression.Tests.ps1:235`

## (10) Review
- Status: DONE for issue scope in this session.
- Merge-conflict check:
  - `git fetch origin --prune` completed.
  - `git merge-base HEAD origin/main` returns no merge-base in this clone topology, so direct conflict simulation with `origin/main` is not available in this workspace.

## (11) Documentation-as-Code
- This full SOAPIER record is committed in:
  - `docs/ISSUE-94-SOAPIER-2026-02-11.md`
- Issue update comment posted to:
  - https://github.com/SuperYonga/superyonga/issues/94

## (12) Git Hygiene (Local)
- Changes were scoped to:
  - `Install-Brother-MFCL9570CDW.ps1`
  - `Install-Brother-MFCL9570CDW-Launcher.ps1`
  - `tests/Installer.Regression.Tests.ps1`
  - `README-Install-Brother-MFCL9570CDW.md`
  - `docs/ISSUE-94-SOAPIER-2026-02-11.md`

## (13) Pre-Commit Checks
- GitHub issue exists: `#94`.
- Branch exists and aligned: `issue-94-printer-retry-comms-default-printer`.
- Documentation attached: this SOAPIER doc + issue comment.
- Tests green via npm/CI entrypoint: `npm test`.

## (14) Finish
- Ready to commit and push branch for CI and manual PR workflow.

---

## Addendum (2026-02-11 13:55 local) - Validation Against Operator Log

### Presenting log snapshot
- Operator log reviewed:
  - `F:\Install-Brother-MFCL9570CDW\logs\install-20260211-131406.log`
- Observed in that run:
  1. test page attempts were `1/3`, `2/3`, `3/3`
  2. scheduled task warning included `"RepetitionInterval" cannot be found`
  3. run completed with installer `exit code=0`, so launcher failure comms did not trigger

### Assessment
- The `F:\...` run behavior maps to pre-fix script behavior (older packaged copy), not the current `issue-94` branch head.
- Current branch evidence:
  - single invoke for install/retry: `Install-Brother-MFCL9570CDW.ps1:47`, `Install-Brother-MFCL9570CDW.ps1:48`
  - degraded test-page evidence exits non-zero (`exit 2`): `Install-Brother-MFCL9570CDW.ps1:1008`, `Install-Brother-MFCL9570CDW.ps1:1009`
  - success diagnostics mode available: `Install-Brother-MFCL9570CDW-Launcher.ps1:335`, `Install-Brother-MFCL9570CDW-Launcher.ps1:446`
  - token error mitigation and default-printer handling present: `Install-Brother-MFCL9570CDW.ps1:755`, `Install-Brother-MFCL9570CDW.ps1:772`

### Objective re-validation
- Re-ran full test entrypoint:
  - `npm test`
  - Result: `Passed: 25, Failed: 0`
  - XML evidence: `tests/artifacts/pester-results.xml`

### Operator guidance
- To observe fixed behavior on device, run the latest script/package built from branch `issue-94-printer-retry-comms-default-printer` rather than the older `F:\...` copy.
