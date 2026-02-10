# Brother MFC-L9570CDW Installer (Windows 10/11)

This package installs a Brother MFC-L9570CDW network printer using:
- Standard TCP/IP Port = printer IPv4
- RAW 9100
- SNMP OFF

Files included:
- `INSTALL.bat` (launcher, auto-elevates)
- `Install-Brother-MFCL9570CDW.ps1` (installer logic)
- `Install-Brother-MFCL9570CDW-Launcher.ps1` (elevation/orchestration)

## End-user usage (recommended)
1. Unzip all files to one folder.
2. Double-click `INSTALL.bat`.
3. Approve the UAC prompt when asked.

Default printer IP used by BAT:
- `192.168.0.120`

Default printer name created by PS1:
- `Brother MFC-L9570CDW (<PrinterIP>)`
- Example: `Brother MFC-L9570CDW (192.168.0.120)`

## Command-line usage examples
From `cmd` in the same folder:

Install using default IP:
```bat
INSTALL.bat
```

Install using a custom IP:
```bat
INSTALL.bat -PrinterIP 192.168.0.120
```

Install using a custom driver URL:
```bat
INSTALL.bat -DriverUrl "https://download.brother.com/welcome/dlf106550/Y16E_C1-hostm-K1.EXE"
```

Install using custom IP + driver URL:
```bat
INSTALL.bat -PrinterIP 192.168.0.120 -DriverUrl "https://download.brother.com/welcome/dlf106550/Y16E_C1-hostm-K1.EXE"
```

Validation-only (no changes made):
```bat
INSTALL.bat -ValidateOnly
```

Validation-only with custom IP:
```bat
INSTALL.bat -PrinterIP 192.168.0.120 -ValidateOnly
```

## Logging
A log file is written on every run in the same folder as `INSTALL.bat` unless `-LogPath` is provided.

Filename pattern:
- `install-YYYYMMDD-HHMMSS.log`

Example:
- `install-20260210-153045.log`

The log contains BAT + PowerShell output, including:
- URL/signature validation
- driver staging status
- printer/port checks
- postcondition pass/fail details

## Exit behavior
- Exit code `0` = success
- Non-zero exit = failed (see log for root cause)

## Notes
- Install mode requires Administrator privileges.
- ValidateOnly mode does not install or change printer state.
- Keep `INSTALL.bat`, `Install-Brother-MFCL9570CDW-Launcher.ps1`, and `Install-Brother-MFCL9570CDW.ps1` in the same folder.
- `INSTALL.bat` is non-interactive by default (no auto-pause). Set env var `SC_PAUSE=1` before launch if you want it to pause at the end.
- Test-page request handling is automatic:
  - The installer invokes the test page without user input.
  - If no queued job evidence is observed, the request is persisted to `C:\ProgramData\SuperCivil\PrinterInstall\pending-test-pages.json`.
  - A scheduled task (`SuperCivil-PrinterTestPageRetry`) retries pending requests every 5 minutes and removes itself when the queue is empty.

## Regression tests
Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\run-regression-tests.ps1
```

Artifacts:
- `tests\artifacts\pester-results.xml`
- per-test logs in `tests\artifacts\*.log`
