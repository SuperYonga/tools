# ISSUE-89 SOAPIER Session (2026-02-11)

## Presenting Issue
- Install logs are technically rich, but operator-facing signals had two quality gaps:
- `Log-RecentPrintServiceEvents` logged a WARN when `Get-WinEvent` returned "No events were found", which is usually a non-failure condition.
- Reachability probe output (`TcpClient` to `:9100`) logged result metrics but did not explicitly tell the operator that install continues in offline-provisioning mode when probe is unreachable.

## Past History
- Active GitHub issue: `#89` (Stabilize printer reachability probe logging and timeout evidence).
- Active branch: `issue-89-reachability-probe-logging-timeout`.
- Related historical branches/docs in this package: `issue-5` (runtime feedback), `issue-6/7/8/9` (failure comms and log payload quality), `issue-88` (single failure email action).
- Existing CI regression pipeline already wired through npm entrypoint: `.github/workflows/regression-tests.yml` -> `npm test`.

## Subjective Assessment
- Current implementation is strong on instrumentation depth and deterministic postconditions.
- Operator UX was still slightly noisy/ambiguous in edge conditions:
- A normal empty PrintService(Admin) query looked like a warning.
- A failed reachability probe lacked explicit ?what happens next? guidance in the same stage.

## Objective Assessment (Testing + Source Review)
- Baseline test execution before changes:
- Command: `npm test`
- Result: `Passed: 20 Failed: 0`
- Source review highlights:
- `Install-Brother-MFCL9570CDW.ps1` catch block in `Log-RecentPrintServiceEvents` warned on any exception, including `NoMatchingEventsFound` behavior.
- Main install path logged probe metrics but did not emit explicit continuation guidance when `Reachable=False`.
- Implemented and re-tested:
- Added no-events classification path (informational evidence instead of warning) using `FullyQualifiedErrorId` / exception message detection.
- Added explicit reachability warning line that states install continues for offline provisioning and directs operator to verify printer power/network if test-page evidence is absent.
- Added two regression assertions to lock behavior.
- Post-change test execution:
- Command: `npm test`
- Result: `Passed: 21 Failed: 0`
- Test evidence artifact: `tests/artifacts/pester-results.xml`.

## Analysis
### Current Codebase Gap
- Severity semantics were slightly misaligned (normal no-event condition emitted as warning).
- Reachability branch lacked immediate operator action guidance despite detailed telemetry.

### Best-Practice Comparison
- OWASP Logging Cheat Sheet recommends correct event severity and useful operational context to avoid alert fatigue and improve investigations.
  - https://cheatsheetseries.owasp.org/cheatsheets/Logging_Cheat_Sheet.html
- NIST SP 800-92 emphasizes log quality/consistency for operational monitoring and incident handling.
  - https://csrc.nist.gov/pubs/sp/800/92/final
- Google Cloud logging guidance promotes structured severity discipline and noise reduction in operational logging.
  - https://cloud.google.com/logging/docs/audit/best-practices
- AWS Cloud Operations guidance emphasizes actionable alarms/signals and avoiding low-value noise for responders.
  - https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Best_Practice_Recommended_Alarms_AWS_Services.html
- Microsoft `Get-WinEvent` behavior context for event retrieval supports handling "no match" outcomes distinctly from true read failures.
  - https://learn.microsoft.com/powershell/module/microsoft.powershell.diagnostics/get-winevent

## Plan
1. Downgrade `NoMatchingEventsFound` PrintService(Admin) condition to informational log evidence.
2. Add explicit operator guidance log when TCP/9100 is unreachable but run continues.
3. Add regression tests to enforce both behaviors.
4. Update README logging semantics.

## Intervention
- Updated `Install-Brother-MFCL9570CDW.ps1`:
- In `Log-RecentPrintServiceEvents`, classify `NoMatchingEventsFound` / "No events were found" as info evidence (`PrintService(Admin) evidence: no matching events found since ...`).
- Added reachability UX warning after probe result when `Reachable=False`.
- Updated `tests/Installer.Regression.Tests.ps1`:
- Extended reachability logging test to assert explicit continuation warning string exists.
- Added regression for no-match PrintService(Admin) informational handling markers.
- Updated `README-Install-Brother-MFCL9570CDW.md`:
- Documented reachability warning semantics and no-events informational behavior.

## Evaluation
- Re-ran full regression suite via npm entrypoint after code changes.
- Result: `Passed: 21 Failed: 0 Skipped: 0`.
- Evidence captured in test output and `tests/artifacts/pester-results.xml`.
- No functional regressions observed in launcher/install regression coverage.

## Review
- Issue scope for this increment is DONE locally: logging severity/UX ambiguity addressed with tests and docs.
- Remote main conflict check:
- Command: `git fetch origin` + `git merge-tree $(git merge-base HEAD origin/main) HEAD origin/main`
- Result: unable to compute merge conflict status because git reported `refusing to merge unrelated histories` against `origin/main` in this local clone layout.

## Git Hygiene
- Verified branch/issue alignment: `issue-89-reachability-probe-logging-timeout` <-> GitHub Issue `#89`.
- Preserved existing unrelated work (none detected at start).
- Changes are limited to:
- `Install-Brother-MFCL9570CDW.ps1`
- `tests/Installer.Regression.Tests.ps1`
- `README-Install-Brother-MFCL9570CDW.md`
- `docs/ISSUE-89-SOAPIER-2026-02-11.md`
