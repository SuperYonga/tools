param(
  [switch]$Elevated,
  [string]$PrinterIP,
  [string]$PrinterName,
  [string]$DriverUrl,
  [switch]$ValidateOnly,
  [switch]$SkipSignatureCheck,
  [switch]$NoTestPage,
  [string]$LogPath,
  [switch]$NotifyOnFailure,
  [string]$NotifyTo = "henry@supercivil.com.au",
  [switch]$PrepareOutlookMailOnFailure
)

$ErrorActionPreference = "Stop"

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

function Get-RecentLogLines {
  param([int]$MaxLines = 120)
  if ([string]::IsNullOrWhiteSpace($script:LogPath) -or -not (Test-Path $script:LogPath)) {
    return "<No log file available>"
  }
  try {
    $lines = Get-Content -Path $script:LogPath -Tail $MaxLines -ErrorAction Stop
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
    [string]$LogTail
  )

  if ([string]::IsNullOrWhiteSpace($LogTail)) {
    $LogTail = "<No log excerpt available>"
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
    "- Failure notification and/or mail draft generation (if enabled)"
    ""
    "Recent log lines:"
    $LogTail
  ) -join [Environment]::NewLine
}

function Send-FailureNotification {
  param(
    [int]$ExitCode,
    [string]$FailureMessage
  )

  $notifyRequested = $NotifyOnFailure -or ($env:SC_NOTIFY_ON_FAILURE -eq "1")
  if (-not $notifyRequested) {
    return
  }

  $smtpHost = $env:SC_SMTP_HOST
  if ([string]::IsNullOrWhiteSpace($smtpHost)) {
    $smtpHost = $env:SC_SMTP_SERVER
  }
  $smtpFrom = $env:SC_SMTP_FROM
  $smtpUser = $env:SC_SMTP_USER
  $smtpPass = $env:SC_SMTP_PASS

  if ([string]::IsNullOrWhiteSpace($smtpHost) -or [string]::IsNullOrWhiteSpace($smtpFrom)) {
    Write-LauncherLog "Failure notification requested but skipped: missing SC_SMTP_HOST/SC_SMTP_SERVER or SC_SMTP_FROM." "WARN"
    return
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
  $logTail = Get-RecentLogLines -MaxLines 120
  $body = New-FailureMessageBody -ExitCode $ExitCode -FailureMessage $FailureMessage -LogTail $logTail

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
  }
  catch {
    Write-LauncherLog ("Failure notification send failed: {0}" -f $_.Exception.Message) "WARN"
  }
}

function Prepare-OutlookFailureDraft {
  param(
    [int]$ExitCode,
    [string]$FailureMessage
  )

  $draftRequested = $PrepareOutlookMailOnFailure -or ($env:SC_OUTLOOK_DRAFT_ON_FAILURE -eq "1")
  if (-not $draftRequested) {
    return
  }

  if ([string]::IsNullOrWhiteSpace($NotifyTo)) {
    Write-LauncherLog "Outlook draft requested but skipped: NotifyTo is empty." "WARN"
    return
  }

  $subject = ("[Printer Installer] Failure on {0} (exit={1})" -f $env:COMPUTERNAME, $ExitCode)
  $logTail = Get-RecentLogLines -MaxLines 120
  $fullBody = New-FailureMessageBody -ExitCode $ExitCode -FailureMessage $FailureMessage -LogTail $logTail

  $draftMode = "default"
  if (-not [string]::IsNullOrWhiteSpace($env:SC_MAIL_DRAFT_MODE)) {
    $draftMode = $env:SC_MAIL_DRAFT_MODE.ToLowerInvariant()
  }

  if ($draftMode -ne "outlookcom") {
    try {
      $mailtoMaxBodyChars = 4500
      if (-not [string]::IsNullOrWhiteSpace($env:SC_MAILTO_MAX_BODY_CHARS)) {
        $parsedMax = 0
        if ([int]::TryParse($env:SC_MAILTO_MAX_BODY_CHARS, [ref]$parsedMax) -and $parsedMax -gt 512) {
          $mailtoMaxBodyChars = $parsedMax
        }
      }

      $mailtoBody = $fullBody
      if ($mailtoBody.Length -gt $mailtoMaxBodyChars) {
        $mailtoBody = $mailtoBody.Substring(0, $mailtoMaxBodyChars) + [Environment]::NewLine + "[TRUNCATED] Open log file for full details."
        Write-LauncherLog ("Mailto body truncated to {0} chars. Set SC_MAILTO_MAX_BODY_CHARS higher if needed." -f $mailtoMaxBodyChars) "WARN"
      }

      $mailToUri = ("mailto:{0}?subject={1}&body={2}" -f
        [Uri]::EscapeDataString($NotifyTo),
        [Uri]::EscapeDataString($subject),
        [Uri]::EscapeDataString($mailtoBody))
      Start-Process $mailToUri | Out-Null
      Write-LauncherLog ("Default mail client draft opened for '{0}' (mode=default)." -f $NotifyTo)
      return
    }
    catch {
      Write-LauncherLog ("Default mail client draft failed, falling back to Outlook COM: {0}" -f $_.Exception.Message) "WARN"
    }
  }

  try {
    $outlook = New-Object -ComObject Outlook.Application
    $mail = $outlook.CreateItem(0)
    $mail.To = $NotifyTo
    $mail.Subject = $subject
    $mail.Body = $fullBody
    if (-not [string]::IsNullOrWhiteSpace($script:LogPath) -and (Test-Path $script:LogPath)) {
      $mail.Attachments.Add($script:LogPath) | Out-Null
    }
    $mail.Save()
    $mail.Display()
    Write-LauncherLog ("Outlook COM failure draft prepared for '{0}' (mode=outlookcom)." -f $NotifyTo)
  }
  catch {
    Write-LauncherLog ("Outlook failure draft preparation failed: {0}" -f $_.Exception.Message) "WARN"
  }
}

if (-not (Test-Path $installerPs1)) {
  Write-Error "Missing installer script: $installerPs1"
  Prepare-OutlookFailureDraft -ExitCode 1 -FailureMessage ("Missing installer script: {0}" -f $installerPs1)
  Send-FailureNotification -ExitCode 1 -FailureMessage ("Missing installer script: {0}" -f $installerPs1)
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
Write-LauncherLog ("Invocation: Elevated={0}, ValidateOnly={1}, SkipSignatureCheck={2}, NoTestPage={3}, NotifyOnFailure={4}, PrepareOutlookMailOnFailure={5}" -f $Elevated, $ValidateOnly, $SkipSignatureCheck, $NoTestPage, $NotifyOnFailure, $PrepareOutlookMailOnFailure)
Write-LauncherLog ("Parameters: PrinterIP='{0}', PrinterName='{1}', DriverUrl='{2}', LogPath='{3}'" -f $PrinterIP, $PrinterName, $DriverUrl, $script:LogPath)
if ($NotifyOnFailure -or ($env:SC_NOTIFY_ON_FAILURE -eq "1")) {
  Write-LauncherLog ("Failure notification enabled. NotifyTo='{0}'" -f $NotifyTo)
}
if ($PrepareOutlookMailOnFailure -or ($env:SC_OUTLOOK_DRAFT_ON_FAILURE -eq "1")) {
  Write-LauncherLog ("Outlook failure draft enabled. NotifyTo='{0}'" -f $NotifyTo)
}

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
      Prepare-OutlookFailureDraft -ExitCode $p.ExitCode -FailureMessage "Elevated installer process exited non-zero."
      Send-FailureNotification -ExitCode $p.ExitCode -FailureMessage "Elevated installer process exited non-zero."
    }
    Write-LauncherLog "Launcher exiting after elevated child."
    exit $p.ExitCode
  }
  catch {
    Write-LauncherLog ("Elevation launch failed: {0}" -f $_.Exception.Message) "ERROR"
    Prepare-OutlookFailureDraft -ExitCode 1 -FailureMessage ("Elevation launch failed: {0}" -f $_.Exception.Message)
    Send-FailureNotification -ExitCode 1 -FailureMessage ("Elevation launch failed: {0}" -f $_.Exception.Message)
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
    Prepare-OutlookFailureDraft -ExitCode $rc -FailureMessage "Installer exited non-zero."
    Send-FailureNotification -ExitCode $rc -FailureMessage "Installer exited non-zero."
  }
  Write-LauncherLog "Launcher complete."
  Write-Host ("Log file: {0}" -f $script:LogPath)
  exit $rc
}
catch {
  Write-LauncherLog ("Launcher failure: {0}" -f $_.Exception.Message) "ERROR"
  Write-LauncherLog ("Stack: {0}" -f $_.ScriptStackTrace) "ERROR"
  Prepare-OutlookFailureDraft -ExitCode 1 -FailureMessage ("Launcher failure: {0}" -f $_.Exception.Message)
  Send-FailureNotification -ExitCode 1 -FailureMessage ("Launcher failure: {0}" -f $_.Exception.Message)
  exit 1
}
