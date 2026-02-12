# ISSUE-1 SOAPIER Session (2026-02-12) - Startup Printer Selection Menu

## Presenting Issue
Launcher starts directly into the Brother install flow with no startup choice. Requested change: at script start, allow users to select:
1) Brother setup,
2) Epson setup (to be configured later),
3) Custom setup where user enters driver URL, printer IP, and printer name.

## Past History
- Related issue documentation exists for launcher/install behavior hardening:
  - `docs/ISSUE-1-SOAPIER-2026-02-11.md`
  - `docs/ISSUE-2-SOAPIER-2026-02-11.md`
  - `docs/ISSUE-3-SOAPIER-2026-02-11.md`
  - `docs/ISSUE-4-SOAPIER-2026-02-11.md`
  - `docs/ISSUE-5-SOAPIER-2026-02-11.md`
  - `docs/ISSUE-6-SOAPIER-2026-02-11.md`
  - `docs/ISSUE-7-SOAPIER-2026-02-11.md`
  - `docs/ISSUE-8-SOAPIER-2026-02-11.md`
  - `docs/ISSUE-9-SOAPIER-2026-02-11.md`
  - `docs/ISSUE-89-SOAPIER-2026-02-11.md`
  - `docs/ISSUE-91-SOAPIER-2026-02-11.md`
  - `docs/ISSUE-94-SOAPIER-2026-02-11.md`
- Existing launcher/install architecture already supports command-line parameter overrides and regression testing via `npm test`.

## Subjective Assessment
The launcher was functionally correct for Brother defaults but had no operator-time branching for printer profile selection. This made onboarding of future non-Brother profiles cumbersome and error-prone.

## Objective Assessment (Testing + Review)
- Source review findings:
  - `Install-Brother-MFCL9570CDW-Launcher.ps1` accepted direct params only and always launched installer with default flow.
  - No startup menu existed.
- Baseline test framework:
  - Pester regression suite invoked by `npm test` via `tests/run-regression-tests.ps1`.
- Post-change test execution:
  - Command: `npm test`
  - Result: Passed `26`, Failed `0`
  - Evidence file: `tests/artifacts/pester-results.xml`

## Analysis
### Current implementation gap
- No interactive profile chooser at launcher start.
- No explicit placeholder path for Epson.
- No guided prompt path for custom printer metadata.

### Best-practice alignment
- Preserve non-interactive automation by providing explicit bypass controls and avoiding forced prompts in CI/scripted runs.
- Validate user input early (IP format, HTTPS URL presence) before elevation/install attempts.
- Keep behavior observable through structured logs and regression tests.

## Plan
1. Add startup selection capability in launcher only (minimal blast radius).
2. Keep existing CLI-first behavior when parameters are already supplied.
3. Add explicit bypass controls for automation/non-interactive runs.
4. Add regression checks for the new menu capability.
5. Update README usage docs.

## Intervention
- Updated `Install-Brother-MFCL9570CDW-Launcher.ps1`:
  - Added params: `-PrinterSelection` (`Brother|Epson|Custom`) and `-SkipStartupMenu`.
  - Added startup menu resolver with options 1/2/3.
  - Option 1 sets Brother defaults.
  - Option 2 logs and exits with clear "not configured yet" behavior.
  - Option 3 prompts for `PrinterIP`, `DriverUrl`, `PrinterName`.
  - Added input validation helper for required fields and IPv4/HTTPS checks.
  - Added non-interactive bypass guard (`SC_DISABLE_STARTUP_MENU=1`) and automatic skip when parameters already provided or `-ValidateOnly` is used.
  - Expanded invocation logging to include startup-menu-related flags and selection.
- Updated tests in `tests/Installer.Regression.Tests.ps1`:
  - Added regression test to assert startup menu capability and bypass controls are present.
- Updated docs in `README-Install-Brother-MFCL9570CDW.md`:
  - Added end-user startup menu behavior.
  - Added `-SkipStartupMenu` usage.
  - Added `SC_DISABLE_STARTUP_MENU=1` runtime note.

## Evaluation
- Validation command: `npm test`
- Outcome: PASS (`26`/`26`).
- New behavior is now covered by regression assertion and does not break ValidateOnly/non-interactive test runs.

## Review
- Issue objective is complete for requested launcher UX behavior.
- Epson remains intentionally non-implemented and now fails clearly with guidance.
- Branch is ready for push and PR creation.

## Git Hygiene
- Started from clean `main` tip.
- Created/used dedicated issue branch: `issue-1-startup-printer-selection-menu`.
- Maintained non-destructive workflow; no unrelated files reverted.

## Checks Before Finish
- GitHub Issue: `https://github.com/SuperYonga/tools/issues/1`
- Branch: `issue-1-startup-printer-selection-menu`
- Documentation: this SOAPIER file + issue comment
- Testing: `npm test` green, NUnit XML artifact generated.
