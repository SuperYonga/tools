# ISSUE-1: Make Brother installer pluggable for IP and driver URL

- Branch: `issue-1-pluggable-printer-driver-input`
- Date: 2026-02-10
- Status: DONE (local)

## 1) Session / branch hygiene
- No git repo existed initially in `Install-Brother-MFCL9570CDW`.
- Initialized local git repo and created branch `issue-1-pluggable-printer-driver-input`.
- GitHub issue creation is not possible from this local-only workspace (no remote configured).
- Local tracking issue created as `docs/issues/ISSUE-1-pluggable-printer-driver-input.md`.

## 2) Presenting issue
- Installer hardcoded driver URL in `Install-Brother-MFCL9570CDW.ps1` and did not expose a first-class `DriverUrl` parameter through launcher/elevated execution.
- User requested a pluggable workflow: provide printer IP and/or driver URL and let script complete the rest.

## 3) Past history
- Existing logs showed launcher/elevation behavior and prior failures (example: `install-20260210-132723.log` with elevated child non-zero).
- Existing regression suite in `tests/Installer.Regression.Tests.ps1` and runner `tests/run-regression-tests.ps1` already validated several installer invariants.

## 4) Subjective assessment
- Current code was close to desired behavior for `PrinterIP` but not for pluggable driver source.
- Hardcoded cache filenames also reduced flexibility when swapping driver package URLs.

## 5) Objective assessment (testing + source review)
- Reviewed:
  - `Install-Brother-MFCL9570CDW.ps1`
  - `Install-Brother-MFCL9570CDW-Launcher.ps1`
  - `README-Install-Brother-MFCL9570CDW.md`
  - `tests/Installer.Regression.Tests.ps1`
- Ran regression tests twice:
  1. Initial run: 10 passed / 1 failed (new DriverUrl policy test failed due early return path in ValidateOnly when cache absent).
  2. After fix: 11 passed / 0 failed.
- Evidence:
  - `tests/artifacts/pester-results.xml`

## 6) Analysis / gap analysis
### 6a) Current implementation gaps
- Driver URL fixed to one vendor path, not user-pluggable.
- Launcher did not pass `DriverUrl` to child process.
- Cache artifact names fixed to one filename regardless of URL.
- URL policy validation was not guaranteed to run in ValidateOnly when cache root was missing.

### 6b) Best-practice alignment
- Security baseline preserved: HTTPS + domain allowlist policy and signature checks remain enforced by default.
- Input validation moved earlier (fail-fast) for deterministic and testable behavior.
- Parameter plumbing across orchestrator + worker script aligns with robust CLI contract design.

## 7) Problem list
### 7a) Immediate fixes
1. Add `-DriverUrl` parameter end-to-end.
2. Derive cache file/hash names from provided driver URL filename.
3. Validate DriverUrl consistently in all modes (including ValidateOnly).
4. Extend regression coverage for custom/invalid driver URL inputs.

### 7b) Shift-left strategies
1. Keep regression tests as release gate before packaging zip artifacts.
2. Continue logging full parameter set + derived cache artifacts for traceability.
3. Add CI later once a remote is configured (local-only repo currently).

## 8) Intervention implemented
- Updated `Install-Brother-MFCL9570CDW-Launcher.ps1`:
  - Added `DriverUrl` parameter and forwarding in direct + elevated flows.
  - Added DriverUrl to launcher parameter logging.
- Updated `Install-Brother-MFCL9570CDW.ps1`:
  - Added `DriverUrl` parameter with default fallback.
  - Derived `DriverExePath`, bundled path, and hash marker from URL filename.
  - Added absolute URI validation + policy checks (HTTPS + allowlisted host).
  - Moved URL validation before cache-root early-return path.
  - Expanded parameter/cache logging for evidence.
- Updated docs:
  - `README-Install-Brother-MFCL9570CDW.md` with custom `-DriverUrl` usage examples.
- Updated tests:
  - Added regression case for allowed custom driver URL logging and derived artifact naming.
  - Added regression case for invalid driver host fail-fast behavior.

## 9) Evaluation (evidence)
- Command:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\run-regression-tests.ps1`
- Result:
  - `Passed: 11 Failed: 0`
- Evidence file:
  - `tests/artifacts/pester-results.xml`

## 10) Review
- DONE for local scope:
  - Pluggable IP + driver URL behavior implemented and regression-tested.
- Merge-conflict/origin-main check not applicable:
  - no remote `origin` configured in this local repository.

## 11) Documentation-as-code
- This file provides SOAPIER-style session documentation and evidence trail.
- README updated for end-user invocation patterns.

## 12) Git hygiene completed
- Local repo initialized.
- New branch created.
- `.gitignore` added to exclude logs/zips/test artifacts.

## 13) Pre-finish checks
- Local issue: present (this file).
- Branch: present (`issue-1-pluggable-printer-driver-input`).
- Documentation: present.
- Testing: green (11/11).

## 14) Finish status
- Complete for local repo workflow.
- Remote push/PR creation cannot be executed without a configured GitHub remote.
