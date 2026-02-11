# ISSUE-91 SOAPIER Session (2026-02-11)

## (1) Git Hygiene + Issue/Branch Alignment
- GitHub issue created: `#91` (`Printer install reports success on queue-only test-page evidence; no failure comms triggered`).
- Working branch created from current codebase: `issue-91-test-page-strict-failure-comms`.
- Branch now maps to the issue scope.

## (2) Presenting Issue
- User ran `INSTALL.bat`.
- Log showed:
  - `Reachability to 192.168.0.120:9100 ... => False`
  - `Test page postcondition: queue job observed.`
  - `Install completed successfully.`
  - launcher exit code `0`
- Observed outcome: no physical paper output and no Outlook/failure email.

## (3) Past History
- Related prior issue chain in this installer package:
  - `#1` through `#9` (driver input, notifications, Outlook fallback, full-log body, runtime UX, comms behavior).
  - `#88` (single failure email action/channel selection).
  - `#89` (reachability timeout evidence and warning semantics).
- Related docs:
  - `docs/ISSUE-89-SOAPIER-2026-02-11.md`
  - `docs/issues/ISSUE-9-full-log-body-on-email-trigger.md`
- Existing regression harness already wired: `npm test` -> `tests/run-regression-tests.ps1`.

## (4) Subjective Assessment
- Installer behavior looked logically consistent with existing code but operationally misleading:
  - Queue-only evidence was treated as full success even while endpoint reachability failed.
  - Because exit stayed `0`, failure comms logic correctly did nothing, which clashed with operator expectation.

## (5) Objective Assessment (Source + Testing)
- Source review findings:
  - `Install-Brother-MFCL9570CDW.ps1` considered `Invoke-TestPageWithEvidence` success as sufficient completion (`queue job observed`).
  - Launcher only triggers failure comms on non-zero exit (`Install-Brother-MFCL9570CDW-Launcher.ps1`).
- Test execution:
  - Command: `npm test`
  - Result: `Passed: 21 Failed: 0`
  - Artifact: `tests/artifacts/pester-results.xml`

## (6) Analysis (Gap vs Best Practice)
### (a) Current Codebase Gaps
- Gap 1: install completion state did not distinguish "fully verified" from "degraded verification."
- Gap 2: failure comms were coupled only to non-zero exit, so degraded-but-zero runs never alerted operators.

### (b) Best-Practice References
- Fail-safe and explicit operational signaling:
  - OWASP Design Principles - Fail Safe: https://devguide.owasp.org/en/02-foundations/03-security-principles/
- Logging and investigation quality:
  - OWASP Logging Cheat Sheet: https://cheatsheetseries.owasp.org/cheatsheets/Logging_Cheat_Sheet.html
  - NIST SP 800-92 (log management): https://csrc.nist.gov/pubs/sp/800/92/final
- Windows printing command semantics/context:
  - Microsoft `rundll32 printui.dll,PrintUIEntry` reference: https://learn.microsoft.com/windows-server/administration/windows-commands/rundll32-printui

## (7) Prioritized Problem List
### (a) Immediate Fix
1. Treat queue-only test-page evidence as degraded when endpoint reachability is false.
2. Return non-zero so launcher comms path activates and the user gets escalation support.
3. Keep retry queue entry for degraded verification instead of marking run clean.

### (b) Shift-Left Prevention
1. Add regression assertions that lock degraded verification behavior and exit code semantics.
2. Document explicit exit code contract for degraded state (`2`) in README.

## (8) Intervention
- Updated `Install-Brother-MFCL9570CDW.ps1`:
  - Added degraded tracking state (`$degradedReasons`) and reachability flag (`$printerReachable`).
  - On test-page queue success with unreachable endpoint:
    - log degraded verification as `ERROR`
    - add pending retry request (instead of clearing pending state)
    - exit `2` at end of run to trigger launcher failure comms.
- Updated `tests/Installer.Regression.Tests.ps1`:
  - Added assertions that the script contains degraded verification path, reachability flagging, and `exit 2` contract.
- Updated `README-Install-Brother-MFCL9570CDW.md`:
  - Documented degraded verification behavior and exit code `2`.

## (9) Evaluation (Evidence)
- Re-ran regression suite after changes:
  - `npm test`
  - `Passed: 21 Failed: 0`
- Evidence of implemented behavior in source:
  - `Install-Brother-MFCL9570CDW.ps1:777`
  - `Install-Brother-MFCL9570CDW.ps1:781`
  - `Install-Brother-MFCL9570CDW.ps1:885`
  - `Install-Brother-MFCL9570CDW.ps1:903`
  - `tests/Installer.Regression.Tests.ps1:129`
  - `tests/Installer.Regression.Tests.ps1:137`

## (10) Review
- Issue scope status: DONE locally for this defect.
- Merge-conflict check vs `origin/main`:
  - `git fetch origin --prune` completed.
  - `git merge-base HEAD origin/main` returned no merge-base in this clone topology, so direct conflict simulation with `origin/main` is not reliable here.

## (11) Documentation-as-Code
- Session recorded in this SOAPIER doc.
- Issue-level SOAPIER summary posted to GitHub Issue `#91`.

## (12) Git Hygiene
- Confirmed clean branch start and scoped changes only to:
  - `Install-Brother-MFCL9570CDW.ps1`
  - `tests/Installer.Regression.Tests.ps1`
  - `README-Install-Brother-MFCL9570CDW.md`
  - `docs/ISSUE-91-SOAPIER-2026-02-11.md`

## (13) Pre-Commit Checks
- GitHub issue exists: `#91`.
- Branch exists and aligned: `issue-91-test-page-strict-failure-comms`.
- Documentation attached: this SOAPIER doc + issue comment.
- Testing completed and green: `npm test` passed.

## (14) Finish
- Issue judged complete for this iteration.
- Ready to commit and push branch for CI and PR workflow.

---

# ISSUE-91 SOAPIER Addendum (2026-02-11, scheduled retry task regression)

## (1) Git Hygiene + Issue/Branch Alignment
- Verified branch: `issue-91-test-page-strict-failure-comms`.
- Verified issue exists and remains open: `#91`.
- Verified this branch is the active tracking branch for issue scope.

## (2) Presenting Issue
- New log evidence from install run (`2026-02-11 13:16:20`) shows:
  - `Could not ensure scheduled retry task 'SuperCivil-PrinterTestPageRetry': Exception setting "RepetitionInterval": "The property 'RepetitionInterval' cannot be found on this object..."`
- Impact: pending retry queue is persisted but retry task scheduling degrades, reducing automatic recovery reliability.

## (3) Past History
- Related issue/branch lineage:
  - `#88` / `issue-88-single-failure-email-per-run`
  - `#89` / `issue-89-reachability-probe-logging-timeout`
  - `#91` / `issue-91-test-page-strict-failure-comms` (current)
- Related code and tests:
  - `Install-Brother-MFCL9570CDW.ps1` retry task orchestration.
  - `tests/Installer.Regression.Tests.ps1` retry and launcher regression suite.
  - CI entrypoint already enforced by `.github/workflows/regression-tests.yml` via `npm test`.

## (4) Subjective Assessment
- Installation path is mostly healthy (driver + queue + printer creation pass), but the retry scheduler warning indicates a concrete implementation mismatch with ScheduledTasks trigger object semantics on this host.

## (5) Objective Assessment (Testing + Logs + Source)
- Reproduced object model behavior in-shell:
  - `New-ScheduledTaskTrigger -Once -At ...` returns `MSFT_TaskTimeTrigger` with property `Repetition` (nested), not top-level `RepetitionInterval`.
- Source root-cause confirmed:
  - `Install-Brother-MFCL9570CDW.ps1` used:
    - `$trigger.RepetitionInterval = ...`
    - `$trigger.RepetitionDuration = ...`
- Prescribed tests executed after fix:
  - `npm test`
  - Result: `Passed: 22 Failed: 0`
  - Artifact: `tests/artifacts/pester-results.xml`

## (6) Analysis (Gap vs Best Practice)
### (a) Current Codebase Gap
1. Scheduled trigger repetition was configured via unsupported direct property assignment on the trigger object.

### (b) Best-Practice References
1. Microsoft ScheduledTasks cmdlet contract:
   - `New-ScheduledTaskTrigger` supports `-RepetitionInterval` and `-RepetitionDuration` parameters (preferred over ad-hoc object mutation).
2. Reliability/logging guidance:
   - Keep deterministic, machine-parseable failure logs and avoid warnings caused by avoidable API misuse.
   - NIST log management baseline: https://csrc.nist.gov/pubs/sp/800/92/final
   - OWASP logging guidance: https://cheatsheetseries.owasp.org/cheatsheets/Logging_Cheat_Sheet.html

## (7) Prioritized Problem List
### (a) Immediate Fix
1. Replace unsupported `trigger` property assignment with native `New-ScheduledTaskTrigger` repetition parameters.
2. Add regression assertions to prevent reintroduction.

### (b) Shift-Left Strategy
1. Keep static source guardrails in Pester for scheduler API usage.
2. Keep runtime regression assertion that logs do not include the known `RepetitionInterval` property error text.

## (8) Intervention
- Updated `Install-Brother-MFCL9570CDW.ps1`:
  - Replaced trigger mutation with:
    - `New-ScheduledTaskTrigger -Once -At ... -RepetitionInterval ... -RepetitionDuration ...`
- Updated `tests/Installer.Regression.Tests.ps1`:
  - Added test: `installer uses supported ScheduledTasks repetition trigger parameters`.
  - Added runtime assertion in retry-path test ensuring log does not contain:
    - `property 'RepetitionInterval' cannot be found`.

## (9) Evaluation (Evidence)
- Test run:
  - Command: `npm test`
  - Result: `Passed: 22 Failed: 0`
- Code evidence:
  - `Install-Brother-MFCL9570CDW.ps1` now uses `New-ScheduledTaskTrigger` repetition parameters directly.
  - `tests/Installer.Regression.Tests.ps1` includes static and runtime regression guards for this exact error signature.

## (10) Review
- Issue scope status for this addendum: DONE for the scheduled retry task defect.
- Merge-conflict check with `origin/main`:
  - `git fetch origin --prune` executed.
  - `git merge-base HEAD origin/main` still returns no merge-base in current clone topology, so direct conflict simulation with `origin/main` remains unavailable here.

## (11) Documentation-as-Code
- This addendum records the second evidence cycle under issue `#91`.
- A matching SOAPIER progress comment was posted to issue `#91`.

## (12) Git Hygiene
- Local changes scoped to:
  - `Install-Brother-MFCL9570CDW.ps1`
  - `tests/Installer.Regression.Tests.ps1`
  - `docs/ISSUE-91-SOAPIER-2026-02-11.md`

## (13) Pre-Commit Checks
- Issue exists: `#91`.
- Branch aligned: `issue-91-test-page-strict-failure-comms`.
- Documentation updated: this SOAPIER addendum.
- Tests green: `npm test` (`22/22` passed).

## (14) Finish
- Ready to commit and push this fix branch for CI and PR processing.
