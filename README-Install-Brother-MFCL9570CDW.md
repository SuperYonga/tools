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

Enable diagnostic email/draft on successful runs too (dev/internal):
```bat
INSTALL.bat -NotifyAlways
```

Validation-only (no changes made):
```bat
INSTALL.bat -ValidateOnly
```

Validation-only with custom IP:
```bat
INSTALL.bat -PrinterIP 192.168.0.120 -ValidateOnly
```

Skip setting configured queue as default printer:
```bat
INSTALL.bat -NoSetDefaultPrinter
```

## Logging
A log file is written on every run to `.\logs\` unless `-LogPath` is provided.

Filename pattern:
- `install-YYYYMMDD-HHMMSS.log`

Example:
- `logs\install-20260210-153045.log`

The log contains BAT + PowerShell output, including:
- URL/signature validation
- driver staging status
- printer/port checks
- postcondition pass/fail details
- reachability diagnostics with timeout + elapsed milliseconds
- explicit warning if TCP/9100 is unreachable
- degraded verification handling: if test-page evidence is queue-only while TCP/9100 is unreachable, installer exits non-zero to trigger failure comms and queues retry
- degraded verification handling: if no test-page queue evidence is observed, installer exits non-zero, queues retry, and triggers failure comms
- PrintService(Admin) "no events found" recorded as informational evidence, not failure
- default-printer set attempt and postcondition evidence for the configured queue (unless `-NoSetDefaultPrinter` is specified)

## Runtime visibility and window behavior
- The launcher shows a live terminal spinner while waiting for installer completion.
- Every 15 seconds it also writes a heartbeat line to the log (`Still waiting for process PID=...`).
- Disable spinner output with `SC_SHOW_PROGRESS=0` (heartbeats remain in logs).
- `cmd` stays open on failures by default so error output is visible.
- Keep `cmd` open for every run: set `SC_PAUSE=1`.

## Failure email notification
On failure (non-zero exit or launcher exception), the launcher performs a single failure email action per run:
- If SMTP is configured, SMTP send is attempted first.
- If SMTP send is not configured or fails, a prefilled default mail-client draft is opened instead.

Optional diagnostics mode:
- `-NotifyAlways` (or environment `SC_NOTIFY_ALWAYS=1`) also sends a success diagnostic email/draft on exit code `0`.

Optional recipient override:
- `-NotifyTo "henry@supercivil.com.au"` (default is already `henry@supercivil.com.au`)

Required SMTP environment variables:
- `SC_SMTP_HOST` (or `SC_SMTP_SERVER`)
- `SC_SMTP_FROM`

Optional SMTP environment variables:
- `SC_SMTP_PORT` (default `587`)
- `SC_SMTP_SSL` (`1` default, set `0` to disable TLS)
- `SC_SMTP_USER`
- `SC_SMTP_PASS`

Email content includes:
- host/user/time
- exit code + failure reason
- log path
- `User Action Required` next-step checklist
- full log content from the run

## Outlook draft on failure (Windows desktop)
The launcher uses a prefilled draft in the default Windows mail client as the primary failure path when SMTP is not configured, and as fallback if SMTP send fails.

Draft mode:
- Default: uses system default mail client first (`default`) so the currently configured Outlook/mail app is respected
- Fallback: opens Notepad instructions + the run log when default-client launch fails

Behavior:
- On failure, it creates an Outlook mail item addressed to `henry@supercivil.com.au` (or `-NotifyTo` override).
- Subject is prefilled with host + exit code.
- Body includes failure context, `User Action Required` steps, and full log content.
- If draft open fails, Notepad opens with manual instructions and asks the user to email `henry@supercivil.com.au` with the run log attached.

## Release packaging
Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Pack-Release.ps1
```

Default output location:
- sibling directory to repo root: `..\builds\Install-Brother-MFCL9570CDW\`

## Exit behavior
- Exit code `0` = success
- Exit code `2` = degraded verification (test-page verification failed or queue-only evidence while endpoint was unreachable); launcher treats this as failure for comms
- Non-zero exit = failed (see log for root cause)

## Notes
- Install mode requires Administrator privileges.
- ValidateOnly mode does not install or change printer state.
- Keep `INSTALL.bat`, `Install-Brother-MFCL9570CDW-Launcher.ps1`, and `Install-Brother-MFCL9570CDW.ps1` in the same folder.
- `INSTALL.bat` pauses on non-zero exit by default.
- Set `SC_PAUSE=1` to always pause at the end.
- Test-page request handling is automatic:
  - The installer sends one test-page invocation per run (to avoid duplicate paper output) and then observes queue/event evidence.
  - If no queued job evidence is observed, the request is persisted to `C:\ProgramData\SuperCivil\PrinterInstall\pending-test-pages.json`.
  - A scheduled task (`SuperCivil-PrinterTestPageRetry`) retries pending requests every 5 minutes and removes itself when the queue is empty.

## Regression tests
Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\run-regression-tests.ps1
```

Or via npm entrypoint:

```powershell
npm test
```

Artifacts:
- `tests\artifacts\pester-results.xml`
- per-test logs in `tests\artifacts\*.log`

## CI
- GitHub Actions workflow: `.github/workflows/regression-tests.yml`
- Trigger: push to `main` or `issue-*`, and pull requests into `main`.
- Runner: `windows-latest` with PowerShell + Pester regression execution via `npm test`.
