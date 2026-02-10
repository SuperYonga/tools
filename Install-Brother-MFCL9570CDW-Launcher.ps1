param(
  [switch]$Elevated,
  [string]$PrinterIP,
  [string]$PrinterName,
  [string]$DriverUrl,
  [switch]$ValidateOnly,
  [switch]$SkipSignatureCheck,
  [switch]$NoTestPage,
  [string]$LogPath
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

if (-not (Test-Path $installerPs1)) {
  Write-Error "Missing installer script: $installerPs1"
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
Write-LauncherLog ("Invocation: Elevated={0}, ValidateOnly={1}, SkipSignatureCheck={2}, NoTestPage={3}" -f $Elevated, $ValidateOnly, $SkipSignatureCheck, $NoTestPage)
Write-LauncherLog ("Parameters: PrinterIP='{0}', PrinterName='{1}', DriverUrl='{2}', LogPath='{3}'" -f $PrinterIP, $PrinterName, $DriverUrl, $script:LogPath)

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Write-LauncherLog ("Admin status: {0}" -f $isAdmin)

if (-not $isAdmin -and -not $ValidateOnly) {
  Write-LauncherLog "Elevation required. Launching elevated installer and waiting."

  $powershellExe = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
  if (-not (Test-Path $powershellExe)) { $powershellExe = "powershell.exe" }

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

  $argLine = ($childArgs -join " ")
  Write-LauncherLog ("Elevated target: {0}" -f $installerPs1)
  Write-LauncherLog ("Elevated arg line: {0}" -f $argLine)

  try {
    $p = Start-Process -FilePath $powershellExe -ArgumentList $argLine -Verb RunAs -PassThru
    Write-LauncherLog ("Elevated PID={0}" -f $p.Id)
    Write-LauncherLog "Waiting for elevated process to complete..."
    $p.WaitForExit()
    Write-LauncherLog ("Elevated process exit code={0}" -f $p.ExitCode)
    if ($p.ExitCode -ne 0) {
      Write-LauncherLog "Elevated process failed. Check installer logs after the last LAUNCHER line for root cause." "ERROR"
    }
    Write-LauncherLog "Launcher exiting after elevated child."
    exit $p.ExitCode
  }
  catch {
    Write-LauncherLog ("Elevation launch failed: {0}" -f $_.Exception.Message) "ERROR"
    exit 1
  }
}

try {
  Write-LauncherLog "Invoking installer script."
  $invokeArgs = New-InstallerInvokeArgs
  & $installerPs1 @invokeArgs
  $rc = $LASTEXITCODE
  Write-LauncherLog ("Installer exit code={0}" -f $rc)
  Write-LauncherLog "Launcher complete."
  Write-Host ("Log file: {0}" -f $script:LogPath)
  exit $rc
}
catch {
  Write-LauncherLog ("Launcher failure: {0}" -f $_.Exception.Message) "ERROR"
  Write-LauncherLog ("Stack: {0}" -f $_.ScriptStackTrace) "ERROR"
  exit 1
}
