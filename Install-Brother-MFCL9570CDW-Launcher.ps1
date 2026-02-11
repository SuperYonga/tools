param(
  [switch]$Elevated,
  [string]$PrinterIP,
  [string]$PrinterName,
  [string]$DriverUrl,
  [switch]$ValidateOnly,
  [switch]$SkipSignatureCheck,
  [switch]$NoTestPage,
  [switch]$NoSetDefaultPrinter,
  [string]$LogPath,
  [switch]$NotifyOnFailure,
  [string]$NotifyTo = "henry@supercivil.com.au",
  [switch]$PrepareOutlookMailOnFailure,
  [switch]$NotifyAlways
)

$ErrorActionPreference = "Stop"
$script:FailureCommsTriggered = $false

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$installerPs1 = Join-Path $scriptDir "Install-Brother-MFCL9570CDW.ps1"

function Write-LauncherLog {
  param([string]$Message, [string]$Level = "INFO")
  $line = "[{0}] [{1}] [LAUNCHER] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"), $Level, $Message
  Write-Host $line
  if ($script:LogPath) {
    try {
      Add-Content -Path $script:LogPath -Value $line
    }
    catch {
      Write-Host ("[LAUNCHER-LOG-WARN] Failed to write log file '{0}': {1}" -f $script:LogPath, $_.Exception.Message)
    }
  }
}

function New-InstallerInvokeArgs {
  $invokeArgs = @{
    LogPath = $script:LogPath
  }
  if (-not [string]::IsNullOrWhiteSpace($PrinterIP)) { $invokeArgs.PrinterIP = $PrinterIP }
  if (-not [string]::IsNullOrWhiteSpace($PrinterName)) { $invokeArgs.PrinterName = $PrinterName }
  if (-not [string]::IsNullOrWhiteSpace($DriverUrl)) { $invokeArgs.DriverUrl = $DriverUrl }
  if ($ValidateOnly) { $invokeArgs.ValidateOnly = $true }
  if ($SkipSignatureCheck) { $invokeArgs.SkipSignatureCheck = $true }
  if ($NoTestPage) { $invokeArgs.NoTestPage = $true }
  if ($NoSetDefaultPrinter) { $invokeArgs.NoSetDefaultPrinter = $true }
  return $invokeArgs
}

function Quote-Arg {
  param([Parameter(Mandatory = $true)][string]$Value)
  return '"' + ($Value -replace '"', '\"') + '"'
}

function Get-InstallerPowerShellPath {
  $powershellExe = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
  if (-not (Test-Path $powershellExe)) { $powershellExe = "powershell.exe" }
  return $powershellExe
}

function New-InstallerArgumentLine {
  $childArgs = @(
    "-NoProfile",
    "-ExecutionPolicy Bypass",
    "-File " + (Quote-Arg -Value $installerPs1),
    "-LogPath " + (Quote-Arg -Value $script:LogPath)
  )
  if ($ValidateOnly) { $childArgs += "-ValidateOnly" }
  if ($SkipSignatureCheck) { $childArgs += "-SkipSignatureCheck" }
  if ($NoTestPage) { $childArgs += "-NoTestPage" }
  if ($NoSetDefaultPrinter) { $childArgs += "-NoSetDefaultPrinter" }
  if (-not [string]::IsNullOrWhiteSpace($PrinterIP)) { $childArgs += "-PrinterIP " + (Quote-Arg -Value $PrinterIP) }
  if (-not [string]::IsNullOrWhiteSpace($PrinterName)) { $childArgs += "-PrinterName " + (Quote-Arg -Value $PrinterName) }
  if (-not [string]::IsNullOrWhiteSpace($DriverUrl)) { $childArgs += "-DriverUrl " + (Quote-Arg -Value $DriverUrl) }
  return ($childArgs -join " ")
}

function Wait-InstallerProcess {
  param(
    [Parameter(Mandatory = $true)]
    [System.Diagnostics.Process]$Process,
    [string]$Activity = "Installer is running"
  )

  $spinnerEnabled = -not [Console]::IsOutputRedirected
  if (-not [string]::IsNullOrWhiteSpace($env:SC_SHOW_PROGRESS) -and $env:SC_SHOW_PROGRESS -eq "0") {
    $spinnerEnabled = $false
  }

  $frames = @("|", "/", "-", "\")
  $frameIndex = 0
  $start = Get-Date
  $lastHeartbeatSec = -1

  while (-not $Process.WaitForExit(250)) {
    $elapsedSec = [int]((Get-Date) - $start).TotalSeconds
    if ($spinnerEnabled) {
      $frame = $frames[$frameIndex % $frames.Count]
      $frameIndex++
      Write-Host -NoNewline ("`r[{0}] {1} ({2}s elapsed)" -f $frame, $Activity, $elapsedSec)
    }
    if ($elapsedSec -gt 0 -and ($elapsedSec % 15) -eq 0 -and $elapsedSec -ne $lastHeartbeatSec) {
      Write-LauncherLog ("Still waiting for process PID={0} ({1}s elapsed)." -f $Process.Id, $elapsedSec)
      $lastHeartbeatSec = $elapsedSec
    }
  }

  if ($spinnerEnabled) {
    Write-Host ("`r[OK] {0} (completed in {1}s){2}" -f $Activity, [int]((Get-Date) - $start).TotalSeconds, (' ' * 20))
  }
}

function Get-LogContent {
  param(
    [int]$MaxLines = 120,
    [switch]$Full
  )
  if ([string]::IsNullOrWhiteSpace($script:LogPath) -or -not (Test-Path $script:LogPath)) {
    return "<No log file available>"
  }
  try {
    if ($Full) {
      $lines = Get-Content -Path $script:LogPath -ErrorAction Stop
    }
    else {
      $lines = Get-Content -Path $script:LogPath -Tail $MaxLines -ErrorAction Stop
    }
    if (-not $lines) {
      return "<Log file exists but is empty>"
    }
    return ($lines -join [Environment]::NewLine)
  }
  catch {
    return ("<Could not read log file '{0}': {1}>" -f $script:LogPath, $_.Exception.Message)
  }
}

function New-FailureMessageBody {
  param(
    [int]$ExitCode,
    [string]$FailureMessage,
    [string]$LogContent
  )

  if ([string]::IsNullOrWhiteSpace($LogContent)) {
    $LogContent = "<No log content available>"
  }

  return @(
    ("Time (UTC): {0}" -f (Get-Date).ToUniversalTime().ToString("o"))
    ("Computer: {0}" -f $env:COMPUTERNAME)
    ("User: {0}" -f [Environment]::UserName)
    ("ExitCode: {0}" -f $ExitCode)
    ("Failure: {0}" -f $FailureMessage)
    ("LogPath: {0}" -f $script:LogPath)
    ""
    "User Action Required:"
    "1) Open the log file at LogPath and review the final ERROR/WARN entries."
    "2) Re-run in validation mode: INSTALL.bat -ValidateOnly (or launcher -ValidateOnly)."
    "3) If validation still fails, escalate with this message and the full log attached."
    ""
    "Auto-attempted:"
    "- Installer launch/elevation orchestration"
    "- Failure notification and/or mail draft generation"
    ""
    "Full log content:"
    $LogContent
  ) -join [Environment]::NewLine
}

function Send-FailureNotification {
  param(
    [int]$ExitCode,
    [string]$FailureMessage
  )

  $smtpHost = $env:SC_SMTP_HOST
  if ([string]::IsNullOrWhiteSpace($smtpHost)) {
    $smtpHost = $env:SC_SMTP_SERVER
  }
  $smtpFrom = $env:SC_SMTP_FROM
  $smtpUser = $env:SC_SMTP_USER
  $smtpPass = $env:SC_SMTP_PASS

  if ([string]::IsNullOrWhiteSpace($smtpHost) -or [string]::IsNullOrWhiteSpace($smtpFrom)) {
    Write-LauncherLog "Failure notification requested but skipped: missing SC_SMTP_HOST/SC_SMTP_SERVER or SC_SMTP_FROM." "WARN"
    return [PSCustomObject]@{ Attempted = $false; Succeeded = $false }
  }

  $smtpPort = 587
  if (-not [string]::IsNullOrWhiteSpace($env:SC_SMTP_PORT)) {
    $parsedPort = 0
    if ([int]::TryParse($env:SC_SMTP_PORT, [ref]$parsedPort) -and $parsedPort -gt 0) {
      $smtpPort = $parsedPort
    }
  }
  $smtpUseSsl = $true
  if ($env:SC_SMTP_SSL -eq "0") {
    $smtpUseSsl = $false
  }

  $subject = ("[Printer Installer] Failure on {0} (exit={1})" -f $env:COMPUTERNAME, $ExitCode)
  $logContent = Get-LogContent -Full
  $body = New-FailureMessageBody -ExitCode $ExitCode -FailureMessage $FailureMessage -LogContent $logContent

  try {
    $mail = New-Object System.Net.Mail.MailMessage
    $mail.From = $smtpFrom
    $mail.To.Add($NotifyTo)
    $mail.Subject = $subject
    $mail.Body = $body

    $smtp = New-Object System.Net.Mail.SmtpClient($smtpHost, $smtpPort)
    $smtp.EnableSsl = $smtpUseSsl
    if (-not [string]::IsNullOrWhiteSpace($smtpUser)) {
      $smtp.Credentials = New-Object System.Net.NetworkCredential($smtpUser, $smtpPass)
    }
    else {
      $smtp.UseDefaultCredentials = $true
    }

    $smtp.Send($mail)
    Write-LauncherLog ("Failure notification email sent to '{0}' via '{1}:{2}'." -f $NotifyTo, $smtpHost, $smtpPort)
    return [PSCustomObject]@{ Attempted = $true; Succeeded = $true }
  }
  catch {
    Write-LauncherLog ("Failure notification send failed: {0}" -f $_.Exception.Message) "WARN"
    return [PSCustomObject]@{ Attempted = $true; Succeeded = $false }
  }
}

function Prepare-OutlookFailureDraft {
  param(
    [int]$ExitCode,
    [string]$FailureMessage
  )

  if ([string]::IsNullOrWhiteSpace($NotifyTo)) {
    Write-LauncherLog "Outlook draft requested but skipped: NotifyTo is empty." "WARN"
    return
  }

  $subject = ("[Printer Installer] Failure on {0} (exit={1})" -f $env:COMPUTERNAME, $ExitCode)
  $logContent = Get-LogContent -Full
  $fullBody = New-FailureMessageBody -ExitCode $ExitCode -FailureMessage $FailureMessage -LogContent $logContent

  try {
    $mailToUri = ("mailto:{0}?subject={1}&body={2}" -f
      [Uri]::EscapeDataString($NotifyTo),
      [Uri]::EscapeDataString($subject),
      [Uri]::EscapeDataString($fullBody))
    Start-Process $mailToUri | Out-Null
    Write-LauncherLog ("Default mail client draft opened for '{0}' (mode=default, body=full-log)." -f $NotifyTo)
    return
  }
  catch {
    Write-LauncherLog ("Default mail client draft failed: {0}" -f $_.Exception.Message) "WARN"
  }

  try {
    $manualNotePath = Join-Path $env:TEMP ("printer-install-failure-email-{0}.txt" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
    $manualNote = @(
      "Failure notification draft could not be opened automatically."
      ""
      "User Action Required:"
      "1) Email all details below to henry@supercivil.com.au."
      "2) Include this run log as an attachment: $script:LogPath"
      "3) Include any screenshots or printer panel error codes."
      ""
      "Suggested subject:"
      $subject
      ""
      "Suggested recipient:"
      "henry@supercivil.com.au"
      ""
      "Failure body:"
      $fullBody
    ) -join [Environment]::NewLine
    Set-Content -Path $manualNotePath -Value $manualNote -Encoding UTF8
    Start-Process notepad.exe -ArgumentList ('"{0}"' -f $manualNotePath) | Out-Null
    Write-LauncherLog ("Manual fallback opened in Notepad: '{0}'" -f $manualNotePath) "WARN"
    if (-not [string]::IsNullOrWhiteSpace($script:LogPath) -and (Test-Path $script:LogPath)) {
      Start-Process notepad.exe -ArgumentList ('"{0}"' -f $script:LogPath) | Out-Null
      Write-LauncherLog ("Run log opened in Notepad: '{0}'" -f $script:LogPath) "WARN"
    }
  }
  catch {
    Write-LauncherLog ("Manual Notepad fallback failed: {0}" -f $_.Exception.Message) "WARN"
  }
}

function Invoke-FailureComms {
  param(
    [int]$ExitCode,
    [string]$FailureMessage
  )

  if ($ExitCode -eq 0) {
    Write-LauncherLog "Failure comms skipped because exit code is zero."
    return
  }
  if ($script:FailureCommsTriggered) {
    Write-LauncherLog ("Failure comms already handled for this run. Skipping duplicate trigger. ExitCode={0}" -f $ExitCode) "WARN"
    return
  }
  $script:FailureCommsTriggered = $true

  Write-LauncherLog ("Failure handler triggered. ExitCode={0}, Reason='{1}'" -f $ExitCode, $FailureMessage) "ERROR"
  $smtpHost = $env:SC_SMTP_HOST
  if ([string]::IsNullOrWhiteSpace($smtpHost)) { $smtpHost = $env:SC_SMTP_SERVER }
  $smtpFrom = $env:SC_SMTP_FROM
  $smtpConfigured = -not [string]::IsNullOrWhiteSpace($smtpHost) -and -not [string]::IsNullOrWhiteSpace($smtpFrom)

  if ($smtpConfigured) {
    Write-LauncherLog "Failure comms channel selected: smtp-primary (single email action per run)."
    $smtpResult = Send-FailureNotification -ExitCode $ExitCode -FailureMessage $FailureMessage
    if (-not $smtpResult.Succeeded) {
      Write-LauncherLog "SMTP send did not complete; falling back to default mail draft path." "WARN"
      Prepare-OutlookFailureDraft -ExitCode $ExitCode -FailureMessage $FailureMessage
    }
    return
  }

  Write-LauncherLog "Failure comms channel selected: mail-draft-primary (single email action per run)."
  Prepare-OutlookFailureDraft -ExitCode $ExitCode -FailureMessage $FailureMessage
}

function Get-DiagnosticCommsEnabled {
  if ($NotifyAlways) { return $true }
  if ($env:SC_NOTIFY_ALWAYS -eq "1") { return $true }
  return $false
}

function Invoke-SuccessDiagnosticComms {
  param([int]$ExitCode, [string]$Summary)

  if ($ExitCode -ne 0) { return }
  if (-not (Get-DiagnosticCommsEnabled)) { return }
  if ($script:FailureCommsTriggered) {
    Write-LauncherLog "Success diagnostic comms skipped: failure comms already handled for this run." "WARN"
    return
  }

  Write-LauncherLog "Success diagnostic comms mode enabled. Sending diagnostic success message."

  $smtpHost = $env:SC_SMTP_HOST
  if ([string]::IsNullOrWhiteSpace($smtpHost)) { $smtpHost = $env:SC_SMTP_SERVER }
  $smtpFrom = $env:SC_SMTP_FROM
  $smtpConfigured = -not [string]::IsNullOrWhiteSpace($smtpHost) -and -not [string]::IsNullOrWhiteSpace($smtpFrom)

  if ($smtpConfigured) {
    $subject = ("[Printer Installer] SUCCESS on {0} (exit={1})" -f $env:COMPUTERNAME, $ExitCode)
    $logContent = Get-LogContent -Full
    $body = @(
      ("Time (UTC): {0}" -f (Get-Date).ToUniversalTime().ToString("o"))
      ("Computer: {0}" -f $env:COMPUTERNAME)
      ("User: {0}" -f [Environment]::UserName)
      ("ExitCode: {0}" -f $ExitCode)
      ("Summary: {0}" -f $Summary)
      ("LogPath: {0}" -f $script:LogPath)
      ""
      "Full log content:"
      $logContent
    ) -join [Environment]::NewLine

    try {
      $smtpPort = 587
      if (-not [string]::IsNullOrWhiteSpace($env:SC_SMTP_PORT)) {
        $parsedPort = 0
        if ([int]::TryParse($env:SC_SMTP_PORT, [ref]$parsedPort) -and $parsedPort -gt 0) { $smtpPort = $parsedPort }
      }
      $smtpUseSsl = $true
      if ($env:SC_SMTP_SSL -eq "0") { $smtpUseSsl = $false }
      $smtpUser = $env:SC_SMTP_USER
      $smtpPass = $env:SC_SMTP_PASS

      $mail = New-Object System.Net.Mail.MailMessage
      $mail.From = $smtpFrom
      $mail.To.Add($NotifyTo)
      $mail.Subject = $subject
      $mail.Body = $body

      $smtp = New-Object System.Net.Mail.SmtpClient($smtpHost, $smtpPort)
      $smtp.EnableSsl = $smtpUseSsl
      if (-not [string]::IsNullOrWhiteSpace($smtpUser)) {
        $smtp.Credentials = New-Object System.Net.NetworkCredential($smtpUser, $smtpPass)
      }
      else {
        $smtp.UseDefaultCredentials = $true
      }
      $smtp.Send($mail)
      Write-LauncherLog ("Diagnostic success notification email sent to '{0}' via '{1}:{2}'." -f $NotifyTo, $smtpHost, $smtpPort)
      return
    }
    catch {
      Write-LauncherLog ("Diagnostic success SMTP send failed: {0}" -f $_.Exception.Message) "WARN"
    }
  }

  try {
    $subject = ("[Printer Installer] SUCCESS on {0} (exit={1})" -f $env:COMPUTERNAME, $ExitCode)
    $logContent = Get-LogContent -Full
    $body = @(
      ("Summary: {0}" -f $Summary)
      ("LogPath: {0}" -f $script:LogPath)
      ""
      "Full log content:"
      $logContent
    ) -join [Environment]::NewLine
    $mailToUri = ("mailto:{0}?subject={1}&body={2}" -f
      [Uri]::EscapeDataString($NotifyTo),
      [Uri]::EscapeDataString($subject),
      [Uri]::EscapeDataString($body))
    Start-Process $mailToUri | Out-Null
    Write-LauncherLog ("Diagnostic success mail draft opened for '{0}' (mode=default, body=full-log)." -f $NotifyTo)
  }
  catch {
    Write-LauncherLog ("Diagnostic success mail draft failed: {0}" -f $_.Exception.Message) "WARN"
  }
}

if (-not (Test-Path $installerPs1)) {
  Write-Error "Missing installer script: $installerPs1"
  Invoke-FailureComms -ExitCode 1 -FailureMessage ("Missing installer script: {0}" -f $installerPs1)
  exit 1
}

if ([string]::IsNullOrWhiteSpace($LogPath)) {
  $LogPath = Join-Path (Join-Path $scriptDir "logs") ("install-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
}
$script:LogPath = $LogPath

$logDir = Split-Path -Parent $script:LogPath
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
if (-not (Test-Path $script:LogPath)) { New-Item -ItemType File -Path $script:LogPath | Out-Null }

Write-LauncherLog "Start launcher."
Write-LauncherLog ("Installer path: {0}" -f $installerPs1)
Write-LauncherLog ("Invocation: Elevated={0}, ValidateOnly={1}, SkipSignatureCheck={2}, NoTestPage={3}, NoSetDefaultPrinter={4}, NotifyOnFailure={5}, PrepareOutlookMailOnFailure={6}, NotifyAlways={7}" -f $Elevated, $ValidateOnly, $SkipSignatureCheck, $NoTestPage, $NoSetDefaultPrinter, $NotifyOnFailure, $PrepareOutlookMailOnFailure, $NotifyAlways)
Write-LauncherLog ("Parameters: PrinterIP='{0}', PrinterName='{1}', DriverUrl='{2}', LogPath='{3}'" -f $PrinterIP, $PrinterName, $DriverUrl, $script:LogPath)
Write-LauncherLog ("Failure notification mode: always-on. NotifyTo='{0}'" -f $NotifyTo)
Write-LauncherLog ("Outlook failure draft mode: always-on (default mode=default-client, fallback=notepad instructions). NotifyTo='{0}'" -f $NotifyTo)
$successDiagMode = "disabled"
if (Get-DiagnosticCommsEnabled) { $successDiagMode = "enabled" }
Write-LauncherLog ("Success diagnostic comms mode: {0} (enable via -NotifyAlways or SC_NOTIFY_ALWAYS=1)." -f $successDiagMode)

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Write-LauncherLog ("Admin status: {0}" -f $isAdmin)

if (-not $isAdmin -and -not $ValidateOnly) {
  Write-LauncherLog "Elevation required. Launching elevated installer and waiting."
  $powershellExe = Get-InstallerPowerShellPath
  $argLine = New-InstallerArgumentLine
  Write-LauncherLog ("Elevated target: {0}" -f $installerPs1)
  Write-LauncherLog ("Elevated arg line: {0}" -f $argLine)

  try {
    $p = Start-Process -FilePath $powershellExe -ArgumentList $argLine -Verb RunAs -PassThru
    Write-LauncherLog ("Elevated PID={0}" -f $p.Id)
    Write-LauncherLog "Waiting for elevated process to complete."
    Wait-InstallerProcess -Process $p -Activity "Elevated installer is running"
    Write-LauncherLog ("Elevated process exit code={0}" -f $p.ExitCode)
    if ($p.ExitCode -ne 0) {
      Write-LauncherLog "Elevated process failed. Check installer logs after the last LAUNCHER line for root cause." "ERROR"
      Invoke-FailureComms -ExitCode $p.ExitCode -FailureMessage "Elevated installer process exited non-zero."
    }
    else {
      Invoke-SuccessDiagnosticComms -ExitCode $p.ExitCode -Summary "Elevated installer process completed successfully."
    }
    Write-LauncherLog "Launcher exiting after elevated child."
    exit $p.ExitCode
  }
  catch {
    Write-LauncherLog ("Elevation launch failed: {0}" -f $_.Exception.Message) "ERROR"
    Invoke-FailureComms -ExitCode 1 -FailureMessage ("Elevation launch failed: {0}" -f $_.Exception.Message)
    exit 1
  }
}

try {
  $powershellExe = Get-InstallerPowerShellPath
  $argLine = New-InstallerArgumentLine
  Write-LauncherLog ("Installer process target: {0}" -f $installerPs1)
  Write-LauncherLog ("Installer process arg line: {0}" -f $argLine)
  $p = Start-Process -FilePath $powershellExe -ArgumentList $argLine -PassThru
  Write-LauncherLog ("Installer PID={0}" -f $p.Id)
  Wait-InstallerProcess -Process $p -Activity "Installer is running"
  $rc = $p.ExitCode
  Write-LauncherLog ("Installer exit code={0}" -f $rc)
  if ($rc -ne 0) {
    Invoke-FailureComms -ExitCode $rc -FailureMessage "Installer exited non-zero."
  }
  else {
    Invoke-SuccessDiagnosticComms -ExitCode $rc -Summary "Installer process completed successfully."
  }
  Write-LauncherLog "Launcher complete."
  Write-Host ("Log file: {0}" -f $script:LogPath)
  exit $rc
}
catch {
  Write-LauncherLog ("Launcher failure: {0}" -f $_.Exception.Message) "ERROR"
  Write-LauncherLog ("Stack: {0}" -f $_.ScriptStackTrace) "ERROR"
  Invoke-FailureComms -ExitCode 1 -FailureMessage ("Launcher failure: {0}" -f $_.Exception.Message)
  exit 1
}
