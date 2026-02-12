# ISSUE-95 SOAPIER Session (2026-02-12)

## (1) Git Hygiene + Issue/Branch Alignment
- Started on mismatched branch: `issue-1-startup-printer-selection-menu`.
- Created dedicated branch for this session:
  - `issue-95-token-context-hardening-default-printer`
- Created linked GitHub issue:
  - `#2` https://github.com/SuperYonga/tools/issues/2
  - Title includes `Issue 95` to preserve branch/traceability convention.

## (2) Presenting Issue
- Intermittent installer failures around printer operations with `0x000003f0` (`ERROR_NO_TOKEN`), especially during queue creation and default-printer assignment.

## (3) Past History
- Prior related branch/doc lineage:
  - `origin/issue-94-printer-retry-comms-default-printer`
  - `docs/ISSUE-94-SOAPIER-2026-02-11.md`
- Existing regression wiring already in place:
  - `package.json` -> `npm test` -> `tests/run-regression-tests.ps1`
  - CI workflow: `.github/workflows/regression-tests.yml`

## (4) Subjective Assessment
- Current code changes on disk were directionally correct but sitting on the wrong branch and not yet tied to a dedicated GitHub issue in this repository.

## (5) Objective Assessment (Logs + Source + Tests)
- Log checks (no token-signature matches in newer runs):
  - `logs/install-20260211-101115.log`
  - `logs/install-20260211-114900.log`
  - `logs/install-20260211-120322.log`
- Source evidence of hardening:
  - Constant: `Install-Brother-MFCL9570CDW.ps1:47`
  - Win32 extractor: `Install-Brother-MFCL9570CDW.ps1:89`
  - Shared token detector: `Install-Brother-MFCL9570CDW.ps1:108`
  - Add-Printer classification callsite: `Install-Brother-MFCL9570CDW.ps1:813`
  - Default-printer SYSTEM/non-interactive guard: `Install-Brother-MFCL9570CDW.ps1:836`
  - Default-printer classification callsite: `Install-Brother-MFCL9570CDW.ps1:856`
  - Security context runtime evidence: `Install-Brother-MFCL9570CDW.ps1:932`
- Regression assertions updated:
  - `tests/Installer.Regression.Tests.ps1:260`
- Test execution:
  - Command: `npm test`
  - Result: `Passed: 26 Failed: 0`
  - Artifact: `tests/artifacts/pester-results.xml`

## (6) Analysis (Gap vs Best Practice)
### (a) Current Codebase Gaps (pre-hardening)
1. Token error handling depended on exception string parsing.
2. Security context evidence was insufficient for reliable triage.
3. Default-printer mutation was attempted even in known-unreliable contexts.
4. Traceability drift between active branch and session scope.

### (b) Best-Practice Alignment
1. Prefer structured code-based error handling over message parsing (`Exception.HResult`).
2. Use canonical Win32 code (`1008`, `ERROR_NO_TOKEN`) for classification.
3. Avoid user-context operations from SYSTEM/non-interactive sessions.
4. Preserve explicit issue-branch linkage and auditable test evidence.

References:
- Win32 system error codes: https://learn.microsoft.com/windows/win32/debug/system-error-codes--1000-1299-
- Add-Printer: https://learn.microsoft.com/powershell/module/printmanagement/add-printer
- PrintUIEntry: https://learn.microsoft.com/windows-server/administration/windows-commands/rundll32-printui
- Win32_Printer.SetDefaultPrinter: https://learn.microsoft.com/windows/win32/cimwin32prov/setdefaultprinter-method-in-class-win32-printer
- Exception.HResult: https://learn.microsoft.com/dotnet/api/system.exception.hresult
- NIST SP 800-92 (logging): https://csrc.nist.gov/pubs/sp/800/92/final

## (7) Prioritized Problem List
### (a) Immediate Fix
1. Replace brittle token-error string matching with shared helper and Win32 code extraction.
2. Add execution identity/session evidence each run.
3. Skip default-printer set in SYSTEM/non-interactive contexts.
4. Lock in with regression checks.
5. Re-establish issue/branch hygiene for this session.

### (b) Shift-Left Prevention
1. Keep test coverage for helper presence/callsite usage.
2. Keep CI artifact publication for every run.
3. Add runbook for `0x000003f0` triage and operator workflow.
4. Add future integration test for non-interactive execution path.

## (8) Intervention
- Applied/retained code interventions:
  - `Install-Brother-MFCL9570CDW.ps1`
  - `tests/Installer.Regression.Tests.ps1`
- Added runbook:
  - `docs/RUNBOOK-ERROR_NO_TOKEN-0x000003f0.md`
- Confirmed test/CI integration already enforced through:
  - `package.json` `npm test`
  - `.github/workflows/regression-tests.yml`

## (9) Evaluation
- Re-ran objective checks and regression test entrypoint.
- Evidence:
  - `npm test` output: `Passed: 26 Failed: 0`
  - `tests/artifacts/pester-results.xml` updated on 2026-02-12.
  - No `0x000003f0`/`ERROR_NO_TOKEN` signatures in the three latest Feb 11 logs.

## (10) Review
- Status: complete for this issue scope (token-context hardening + traceability/documentation).
- Merge-conflict check:
  - Compared against `origin/main`; no conflict indicators in touched files.

## (11) Documentation-as-Code
- Session SOAPIER document:
  - `docs/ISSUE-95-SOAPIER-2026-02-12.md`
- Runbook document:
  - `docs/RUNBOOK-ERROR_NO_TOKEN-0x000003f0.md`
- GitHub issue updated with SOAPIER summary:
  - https://github.com/SuperYonga/tools/issues/2

## (12) Git Hygiene (Local)
- Work scoped to:
  - `Install-Brother-MFCL9570CDW.ps1`
  - `tests/Installer.Regression.Tests.ps1`
  - `docs/ISSUE-95-SOAPIER-2026-02-12.md`
  - `docs/RUNBOOK-ERROR_NO_TOKEN-0x000003f0.md`

## (13) Pre-Commit Checks
- GitHub issue exists: yes (`#2`).
- Dedicated branch exists: yes (`issue-95-token-context-hardening-default-printer`).
- Documentation attached: yes (SOAPIER + runbook + issue update).
- Tests attached: yes (`npm test`, `pester-results.xml`).

## (14) Finish
- Ready to commit and push this branch for CI and manual PR flow.
