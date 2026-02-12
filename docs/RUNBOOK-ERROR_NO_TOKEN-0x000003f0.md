# RUNBOOK: `ERROR_NO_TOKEN` (`0x000003f0`)

## Scope
- Installer/runtime triage for token-context failures around:
  - `Add-Printer`
  - `Win32_Printer.SetDefaultPrinter`
  - `PrintUIEntry /y`

## Fast Facts
- Win32 code: `1008`
- Hex: `0x000003f0`
- Symbol: `ERROR_NO_TOKEN`
- Meaning: missing or invalid security token for the attempted operation.

## Triage Steps
1. Open latest installer log under `logs/`.
2. Locate security context evidence line:
   - `Security context: User='...', SID='...', IsSystem=..., UserInteractive=..., SessionId=...`
3. Check for default-printer guard evidence:
   - `Skipping default-printer set due to non-interactive/system context...`
4. Check operation-specific failures:
   - `Add-Printer failed for ...`
   - `Default printer CIM set failed for ...`
5. Confirm classifier hints:
   - `...appears token-related (0x000003f0)...`
6. Validate queue/default postconditions and final exit code.

## Expected Behavior After Hardening
- Token errors are detected via shared helper (`HResult` Win32 extraction + fallback signatures).
- Default-printer mutation is skipped for SYSTEM/non-interactive contexts.
- Security identity/session details are logged every run to support incident triage.

## Operator Actions
1. If `IsSystem=True` or `UserInteractive=False`, rerun interactively as the target user when default-printer mutation is required.
2. If queue creation fails and token hints appear, verify elevation context and retry from an elevated interactive session.
3. Attach the full log to issue updates for reproducibility.

## Source Anchors
- `Install-Brother-MFCL9570CDW.ps1:47`
- `Install-Brother-MFCL9570CDW.ps1:89`
- `Install-Brother-MFCL9570CDW.ps1:108`
- `Install-Brother-MFCL9570CDW.ps1:836`
- `Install-Brother-MFCL9570CDW.ps1:932`
