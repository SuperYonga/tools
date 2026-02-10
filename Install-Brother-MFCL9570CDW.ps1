<#
.SYNOPSIS
  Install or validate Brother MFC-L9570CDW network printer configuration.

.DESCRIPTION
  - BAT owns elevation.
  - Install path expects Windows PowerShell 5.1 with PrintManagement.
  - ValidateOnly does no printer/port creation.
#>

param(
  [string]$PrinterIP = "192.168.0.120",
  [string]$PrinterName,
  [string]$DriverUrl,
  [switch]$ValidateOnly,
  [switch]$SkipSignatureCheck,
  [switch]$NoTestPage,
  [switch]$RetryPendingOnly,
  [string]$LogPath
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$DefaultDriverUrl = "https://download.brother.com/welcome/dlf106550/Y16E_C1-hostm-K1.EXE"
if ([string]::IsNullOrWhiteSpace($DriverUrl)) {
  $DriverUrl = $DefaultDriverUrl
}
$AllowedDriverHosts = @("download.brother.com","brother.com","welcome.brother.com")
$PublisherAllowlist = @("*Brother Industries*","*Brother International*","*Brother*")
$ExpectedPrintUiModel = "Brother MFC-L9570CDW series"
$WorkRoot = if ([string]::IsNullOrWhiteSpace($env:SC_PRINTER_WORK_ROOT)) {
  Join-Path $env:ProgramData "SuperCivil\PrinterInstall"
} else {
  $env:SC_PRINTER_WORK_ROOT
}
$CacheRoot = Join-Path $WorkRoot "cache"
$PendingTestPagePath = Join-Path $WorkRoot "pending-test-pages.json"
$PendingRetryTaskName = "SuperCivil-PrinterTestPageRetry"
$RetryWorkerLogPath = Join-Path $WorkRoot "retry-worker.log"
$PendingRetryMaxAttempts = 96
$PendingRetryBaseMinutes = 5
$PendingRetryMaxBackoffMinutes = 240
$PendingRetryTtlDays = 7
$DefaultDriverFileName = "Y16E_C1-hostm-K1.EXE"
$driverUriForPath = $null
try { $driverUriForPath = [Uri]$DriverUrl } catch { $driverUriForPath = $null }
$DriverFileName = $DefaultDriverFileName
if ($driverUriForPath -and -not [string]::IsNullOrWhiteSpace($driverUriForPath.AbsolutePath)) {
  $candidateName = [System.IO.Path]::GetFileName($driverUriForPath.AbsolutePath)
  if (-not [string]::IsNullOrWhiteSpace($candidateName)) {
    $DriverFileName = $candidateName
  }
}
$DriverExePath = Join-Path $CacheRoot $DriverFileName
$BundledDriverExePath = Join-Path $PSScriptRoot $DriverFileName
$DriverHashPath = Join-Path $CacheRoot ($DriverFileName + ".sha256")

function Write-Log {
  param(
    [Parameter(Mandatory = $true)][string]$Message,
    [ValidateSet("INFO","WARN","ERROR")][string]$Level = "INFO"
  )
  $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
  $line = "[{0}] [{1}] {2}" -f $ts, $Level, $Message
  Write-Host $line
  if ($script:LogPath) {
    try { Add-Content -Path $script:LogPath -Value $line } catch { Write-Host "[LOGGING-FAIL] $($_.Exception.Message)" }
  }
}

function Fail {
  param([string]$Message)
  Write-Log -Message $Message -Level "ERROR"
  throw $Message
}

function Test-IsAdmin {
  $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
  return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-HostAllowed {
  param([string]$HostName)
  foreach ($hostEntry in $AllowedDriverHosts) {
    if ($HostName -ieq $hostEntry -or $HostName -like ("*." + $hostEntry)) { return $true }
  }
  return $false
}

function Test-Tcp9100 {
  param([string]$Ip)
  $tnc = Get-Command Test-NetConnection -ErrorAction SilentlyContinue
  if ($tnc) {
    try {
      $r = Test-NetConnection -ComputerName $Ip -Port 9100 -WarningAction SilentlyContinue
      return [PSCustomObject]@{ Method = "Test-NetConnection"; Reachable = [bool]$r.TcpTestSucceeded }
    } catch {
      return [PSCustomObject]@{ Method = "Test-NetConnection"; Reachable = $false }
    }
  }

  $client = $null
  try {
    $client = New-Object System.Net.Sockets.TcpClient
    $iar = $client.BeginConnect($Ip, 9100, $null, $null)
    $ok = $iar.AsyncWaitHandle.WaitOne(2500, $false)
    if (-not $ok) { return [PSCustomObject]@{ Method = "TcpClient"; Reachable = $false } }
    $client.EndConnect($iar) | Out-Null
    return [PSCustomObject]@{ Method = "TcpClient"; Reachable = $true }
  } catch {
    return [PSCustomObject]@{ Method = "TcpClient"; Reachable = $false }
  } finally {
    if ($client) { $client.Close() }
  }
}

function Get-FileSha256 {
  param([Parameter(Mandatory = $true)][string]$Path)
  $gfh = Get-Command Get-FileHash -ErrorAction SilentlyContinue
  if ($gfh) {
    return (Get-FileHash -Path $Path -Algorithm SHA256).Hash
  }

  $out = certutil -hashfile "$Path" SHA256 2>$null
  if ($LASTEXITCODE -ne 0 -or -not $out) {
    Fail ("Could not compute SHA256 for '{0}'." -f $Path)
  }
  foreach ($line in $out) {
    if ($line -match '^[0-9A-Fa-f ]{32,}$') {
      return ($line -replace ' ', '').Trim().ToUpperInvariant()
    }
  }
  Fail ("Could not parse SHA256 output for '{0}'." -f $Path)
}

function Find-InfPath {
  if (-not (Test-Path $CacheRoot)) { return $null }
  $known = @(
    (Join-Path $CacheRoot "gdi\BRPRC16A.INF"),
    (Join-Path $CacheRoot "Y16E_C1-hostm-K1\gdi\BRPRC16A.INF"),
    (Join-Path $CacheRoot "extracted\gdi\BRPRC16A.INF")
  )
  foreach ($k in $known) {
    if (Test-Path $k) { return $k }
  }
  $found = Get-ChildItem -Path $CacheRoot -Recurse -Filter "BRPRC16A.INF" -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($found) { return $found.FullName }
  return $null
}

function Log-InfDiagnostics {
  Write-Log "INF was not found. Directory diagnostics follow." "ERROR"
  foreach ($path in @($CacheRoot,(Join-Path $CacheRoot "gdi"),(Join-Path $CacheRoot "extracted"))) {
    if (Test-Path $path) {
      Write-Log ("Listing path: {0}" -f $path)
      Get-ChildItem -Path $path -Force -ErrorAction SilentlyContinue | Select-Object Name,Length,LastWriteTime,FullName |
        Format-Table -AutoSize | Out-String | ForEach-Object { Write-Log $_.TrimEnd() }
    } else {
      Write-Log ("Path missing: {0}" -f $path) "WARN"
    }
  }
}

function Ensure-DriverAndInf {
  param(
    [switch]$AllowExtraction,
    [switch]$ReadOnly
  )

  $uri = $null
  try {
    $uri = [Uri]$DriverUrl
  }
  catch {
    Fail ("Driver URL is not a valid absolute URI: {0}" -f $DriverUrl)
  }
  if (-not $uri.IsAbsoluteUri) {
    Fail ("Driver URL must be absolute: {0}" -f $DriverUrl)
  }
  if ($uri.Scheme -ne "https" -or -not (Test-HostAllowed -HostName $uri.Host)) {
    Fail ("Driver URL policy failed: {0}" -f $DriverUrl)
  }

  if (-not (Test-Path $CacheRoot)) {
    if ($ReadOnly) {
      Write-Log ("ReadOnly driver probe: cache directory not found: {0}" -f $CacheRoot)
      return $null
    }
    New-Item -ItemType Directory -Force -Path $CacheRoot | Out-Null
  }

  if (-not (Test-Path $DriverExePath)) {
    if ($ReadOnly) {
      Write-Log ("ReadOnly driver probe: driver EXE not found at '{0}'." -f $DriverExePath)
      return (Find-InfPath)
    }
    if (Test-Path $BundledDriverExePath) {
      Write-Log ("Using bundled driver EXE from script folder: {0}" -f $BundledDriverExePath)
      Copy-Item -Path $BundledDriverExePath -Destination $DriverExePath -Force
    }
    else {
      Write-Log ("Downloading driver EXE: {0}" -f $DriverUrl)
      Write-Log ("Download target path: {0}" -f $DriverExePath)
      $resp = Invoke-WebRequest -Uri $DriverUrl -OutFile $DriverExePath -PassThru
      $resolved = $DriverUrl
      if ($resp -and $resp.BaseResponse -and $resp.BaseResponse.ResponseUri) {
        $resolved = $resp.BaseResponse.ResponseUri.AbsoluteUri
      }
      Write-Log ("Resolved driver URL: {0}" -f $resolved)
    }
  } else {
    Write-Log ("Using cached driver EXE: {0}" -f $DriverExePath)
  }

  $exe = Get-Item $DriverExePath
  $exeHash = Get-FileSha256 -Path $DriverExePath
  Write-Log ("Driver EXE size={0} bytes sha256={1}" -f $exe.Length, $exeHash)
  if ($exe.Length -lt 5MB) { Fail "Driver EXE file is unexpectedly small." }

  $sigCmd = Get-Command Get-AuthenticodeSignature -ErrorAction SilentlyContinue
  if (-not $sigCmd) {
    try {
      Import-Module Microsoft.PowerShell.Security -ErrorAction Stop
    }
    catch {
      Write-Log ("Could not import Microsoft.PowerShell.Security: {0}" -f $_.Exception.Message) "WARN"
    }
    $sigCmd = Get-Command Get-AuthenticodeSignature -ErrorAction SilentlyContinue
  }

  if (-not $sigCmd) {
    if ($SkipSignatureCheck) {
      Write-Log "SkipSignatureCheck is ENABLED and signature cmdlet is unavailable." "WARN"
    }
    else {
      Fail "Get-AuthenticodeSignature is unavailable. Install/enable Microsoft.PowerShell.Security or run with -SkipSignatureCheck for emergency use."
    }
  }
  else {
    $sig = & $sigCmd -FilePath $DriverExePath
    $subject = if ($sig.SignerCertificate) { $sig.SignerCertificate.Subject } else { "<none>" }
    $issuer = if ($sig.SignerCertificate) { $sig.SignerCertificate.Issuer } else { "<none>" }
    Write-Log ("Signature status='{0}', subject='{1}', issuer='{2}'" -f $sig.Status, $subject, $issuer)
    if (-not $SkipSignatureCheck) {
      if ($sig.Status -ne "Valid") { Fail ("Signature must be Valid. Actual={0}" -f $sig.Status) }
      $allowed = $false
      foreach ($p in $PublisherAllowlist) { if ($subject -like $p) { $allowed = $true; break } }
      if (-not $allowed) { Fail ("Signer subject not allowlisted: {0}" -f $subject) }
    } else {
      Write-Log "SkipSignatureCheck is ENABLED. Signature policy bypassed for this run." "WARN"
    }
  }

  $inf = Find-InfPath
  $needExtract = $false
  $storedHash = $null
  if (Test-Path $DriverHashPath) {
    $storedHash = (Get-Content -Path $DriverHashPath -ErrorAction SilentlyContinue | Select-Object -First 1)
  }
  if (-not $inf) { $needExtract = $true }
  if ($storedHash -and ($storedHash -ne $exeHash)) { $needExtract = $true }
  if (-not $storedHash -and $inf -and (Test-Path $inf)) {
    Write-Log "Driver hash marker missing but INF exists. Will reuse INF and write current hash marker."
  }
  if ($inf -and (Test-Path $inf)) {
    $infItem = Get-Item $inf
    Write-Log ("Current INF path: {0}" -f $inf)
    Write-Log ("Current INF mtime: {0}" -f $infItem.LastWriteTime.ToString("s"))
    if ($infItem.LastWriteTime -lt $exe.LastWriteTime) {
      Write-Log "INF mtime is older than EXE. This is expected for vendor-packed files; using hash marker to decide staleness."
    }
  }

  Write-Log ("Driver hash file: {0}" -f $(if ($storedHash) { $storedHash } else { "<none>" }))
  Write-Log ("Extraction required: {0}" -f $needExtract)

  if ($needExtract) {
    if ($ReadOnly) {
      Write-Log "ReadOnly driver probe: extraction required but disabled in ValidateOnly mode." "WARN"
      return $inf
    }
    if (-not $AllowExtraction) { return $null }
    Write-Log "Running extractor because cache is stale or missing."
    $p = Start-Process -FilePath $DriverExePath -WorkingDirectory $CacheRoot -Wait -PassThru
    Write-Log ("Extractor exit code: {0}" -f $p.ExitCode)
    $inf = Find-InfPath
    if (-not $inf) {
      Log-InfDiagnostics
      Fail "BRPRC16A.INF not found after extraction."
    }
  }

  if (-not $inf) { return $null }

  if (-not $ReadOnly) {
    Set-Content -Path $DriverHashPath -Value $exeHash -Encoding ascii
  }
  $infItem2 = Get-Item $inf
  Write-Log ("Using INF: {0}" -f $inf)
  Write-Log ("INF mtime: {0}" -f $infItem2.LastWriteTime.ToString("s"))
  return $inf
}

function Import-PrintManagementOrFail {
  $mod = Get-Module -ListAvailable -Name PrintManagement | Select-Object -First 1
  Write-Log ("PrintManagement available: {0}" -f ([bool]$mod))
  if ($mod) { Write-Log ("PrintManagement module path: {0}" -f $mod.Path) }
  if (-not $mod) { Fail "PrintManagement module is not available." }
  Import-Module PrintManagement -ErrorAction Stop
  $gp = Get-Command Get-Printer -ErrorAction SilentlyContinue
  if (-not $gp) { Fail "Get-Printer command unavailable after module import." }
  Write-Log ("Get-Printer source: Name={0}, Module={1}, Source={2}" -f $gp.Name, $gp.ModuleName, $gp.Source)
}

function Get-PrintJobsSafe {
  param([Parameter(Mandatory = $true)][string]$QueueName)
  try {
    return @(Get-PrintJob -PrinterName $QueueName -ErrorAction Stop)
  }
  catch {
    Write-Log ("Get-PrintJob failed for '{0}': {1}" -f $QueueName, $_.Exception.Message) "WARN"
    return @()
  }
}

function Log-RecentPrintServiceEvents {
  param(
    [Parameter(Mandatory = $true)][datetime]$Since,
    [int]$MaxEvents = 20
  )
  try {
    $events = Get-WinEvent -FilterHashtable @{
      LogName   = "Microsoft-Windows-PrintService/Admin"
      StartTime = $Since
    } -ErrorAction Stop | Select-Object -First $MaxEvents

    if (-not $events -or $events.Count -eq 0) {
      Write-Log "PrintService(Admin) evidence: no events captured after test page invoke."
      return
    }

    foreach ($ev in $events) {
      $msg = if ($ev.Message) { ($ev.Message -replace '\r?\n', ' ').Trim() } else { "<no message>" }
      if ($msg.Length -gt 240) { $msg = $msg.Substring(0, 240) + "..." }
      Write-Log ("PrintService(Admin) EventId={0}, Level={1}, Time={2}, Message='{3}'" -f $ev.Id, $ev.LevelDisplayName, $ev.TimeCreated.ToString("s"), $msg)
    }
  }
  catch {
    Write-Log ("Could not read PrintService(Admin) log: {0}" -f $_.Exception.Message) "WARN"
  }
}

function Get-PendingTestPageRequests {
  return (Invoke-WithPendingQueueLock -ScriptBlock {
    if (-not (Test-Path $PendingTestPagePath)) { return @() }
    try {
      $raw = Get-Content -Path $PendingTestPagePath -Raw -ErrorAction Stop
      if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
      $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
      if ($null -eq $parsed) { return @() }
      if ($parsed -is [System.Array]) { return @($parsed) }
      return @($parsed)
    }
    catch {
      Write-Log ("Could not read pending test page queue '{0}': {1}" -f $PendingTestPagePath, $_.Exception.Message) "WARN"
      return @()
    }
  })
}

function Save-PendingTestPageRequests {
  param([Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Requests)
  Invoke-WithPendingQueueLock -ScriptBlock {
    try {
      $pendingDir = Split-Path -Path $PendingTestPagePath -Parent
      if (-not (Test-Path $pendingDir)) { New-Item -ItemType Directory -Force -Path $pendingDir | Out-Null }
      if ($Requests.Count -eq 0) {
        if (Test-Path $PendingTestPagePath) { Remove-Item -Path $PendingTestPagePath -Force -ErrorAction SilentlyContinue }
        Write-Log "Pending test page queue is now empty."
        return
      }

      $tempPath = "{0}.tmp.{1}.{2}" -f $PendingTestPagePath, $PID, ([guid]::NewGuid().ToString("N"))
      ($Requests | ConvertTo-Json -Depth 5) | Set-Content -Path $tempPath -Encoding ascii
      Move-Item -Path $tempPath -Destination $PendingTestPagePath -Force
      Write-Log ("Pending test page queue saved. Path='{0}', Count={1}" -f $PendingTestPagePath, $Requests.Count)
    }
    catch {
      Write-Log ("Could not save pending test page queue '{0}': {1}" -f $PendingTestPagePath, $_.Exception.Message) "WARN"
    }
  } | Out-Null
}

function Invoke-WithPendingQueueLock {
  param(
    [Parameter(Mandatory = $true)][scriptblock]$ScriptBlock,
    [int]$TimeoutSeconds = 30
  )

  $mutex = $null
  $hasHandle = $false
  try {
    $pathBytes = [System.Text.Encoding]::UTF8.GetBytes($PendingTestPagePath.ToLowerInvariant())
    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    $hash = [System.BitConverter]::ToString($sha1.ComputeHash($pathBytes)).Replace("-", "")
    $sha1.Dispose()
    $mutexName = "Global\SuperCivilPrinterPendingQueue_{0}" -f $hash
    $mutex = New-Object System.Threading.Mutex($false, $mutexName)
    try {
      $hasHandle = $mutex.WaitOne([TimeSpan]::FromSeconds($TimeoutSeconds))
    }
    catch [System.Threading.AbandonedMutexException] {
      $hasHandle = $true
    }
    if (-not $hasHandle) {
      Fail ("Timed out acquiring pending queue lock. Mutex='{0}'" -f $mutexName)
    }
    return (& $ScriptBlock)
  }
  finally {
    if ($mutex) {
      if ($hasHandle) {
        try { $mutex.ReleaseMutex() | Out-Null } catch {}
      }
      $mutex.Dispose()
    }
  }
}

function Get-PendingRequestAttemptCount {
  param([Parameter(Mandatory = $true)][object]$Request)
  if ($Request.AttemptCount) { return [int]$Request.AttemptCount }
  return 0
}

function Get-PendingRequestTimestampUtc {
  param(
    [Parameter(Mandatory = $false)][string]$Timestamp,
    [datetime]$FallbackUtc
  )
  if ([string]::IsNullOrWhiteSpace($Timestamp)) { return $FallbackUtc }
  $parsed = [datetime]::MinValue
  if ([datetime]::TryParse($Timestamp, [ref]$parsed)) {
    return $parsed.ToUniversalTime()
  }
  return $FallbackUtc
}

function Get-PendingRequestNextAttemptUtc {
  param([Parameter(Mandatory = $true)][object]$Request)
  return (Get-PendingRequestTimestampUtc -Timestamp ([string]$Request.NextAttemptAt) -FallbackUtc ((Get-Date).ToUniversalTime()))
}

function Get-PendingRequestExpiresUtc {
  param([Parameter(Mandatory = $true)][object]$Request)
  return (Get-PendingRequestTimestampUtc -Timestamp ([string]$Request.ExpiresAt) -FallbackUtc (((Get-Date).ToUniversalTime()).AddDays($PendingRetryTtlDays)))
}

function Get-NextRetryDelayMinutes {
  param([int]$AttemptCount)
  $attempt = if ($AttemptCount -lt 1) { 1 } else { $AttemptCount }
  $power = [Math]::Min(6, $attempt - 1)
  $delay = [int]($PendingRetryBaseMinutes * [Math]::Pow(2, $power))
  return [Math]::Min($PendingRetryMaxBackoffMinutes, $delay)
}

function New-PendingTestPageRequestRecord {
  param(
    [Parameter(Mandatory = $true)][string]$QueueName,
    [Parameter(Mandatory = $true)][string]$QueueIp,
    [string]$Reason,
    [int]$PreviousAttemptCount = 0,
    [string]$RequestedAt,
    [string]$ExistingExpiresAt
  )
  $nowUtc = (Get-Date).ToUniversalTime()
  $attemptCount = $PreviousAttemptCount + 1
  $delay = Get-NextRetryDelayMinutes -AttemptCount $attemptCount
  $reqAt = Get-PendingRequestTimestampUtc -Timestamp $RequestedAt -FallbackUtc $nowUtc
  $expAt = Get-PendingRequestTimestampUtc -Timestamp $ExistingExpiresAt -FallbackUtc ($nowUtc.AddDays($PendingRetryTtlDays))
  return [PSCustomObject]@{
    PrinterName       = $QueueName
    PrinterIP         = $QueueIp
    RequestedAt       = $reqAt.ToString("o")
    LastAttemptAt     = $nowUtc.ToString("o")
    AttemptCount      = $attemptCount
    NextAttemptAt     = $nowUtc.AddMinutes($delay).ToString("o")
    ExpiresAt         = $expAt.ToString("o")
    LastFailureReason = [string]$Reason
  }
}

function Remove-PendingTestPageRequest {
  param(
    [Parameter(Mandatory = $true)][string]$QueueName,
    [Parameter(Mandatory = $true)][string]$QueueIp
  )
  $pending = @(Get-PendingTestPageRequests)
  if ($pending.Count -eq 0) { return }
  $remaining = @($pending | Where-Object { -not ($_.PrinterName -eq $QueueName -and $_.PrinterIP -eq $QueueIp) })
  if ($remaining.Count -ne $pending.Count) {
    Write-Log ("Clearing pending test page request for PrinterName='{0}', PrinterIP='{1}'." -f $QueueName, $QueueIp)
    Save-PendingTestPageRequests -Requests $remaining
  }
}

function Add-PendingTestPageRequest {
  param(
    [Parameter(Mandatory = $true)][string]$QueueName,
    [Parameter(Mandatory = $true)][string]$QueueIp,
    [Parameter(Mandatory = $true)][string]$Reason
  )
  $pending = @(Get-PendingTestPageRequests)
  $updated = @()
  $matched = $false
  foreach ($item in $pending) {
    if ($item.PrinterName -eq $QueueName -and $item.PrinterIP -eq $QueueIp) {
      $attemptCount = Get-PendingRequestAttemptCount -Request $item
      $updated += New-PendingTestPageRequestRecord -QueueName $QueueName -QueueIp $QueueIp -Reason $Reason -PreviousAttemptCount $attemptCount -RequestedAt ([string]$item.RequestedAt) -ExistingExpiresAt ([string]$item.ExpiresAt)
      $matched = $true
    }
    else {
      $updated += $item
    }
  }
  if (-not $matched) {
    $updated += New-PendingTestPageRequestRecord -QueueName $QueueName -QueueIp $QueueIp -Reason $Reason -PreviousAttemptCount 0
  }
  Write-Log ("Queued persistent test page retry for PrinterName='{0}', PrinterIP='{1}'. Reason='{2}'" -f $QueueName, $QueueIp, $Reason) "WARN"
  Save-PendingTestPageRequests -Requests $updated
}

function Invoke-TestPageWithEvidence {
  param(
    [Parameter(Mandatory = $true)][string]$QueueName,
    [int]$InvokeAttempts = 3,
    [int]$ObserveSeconds = 20
  )

  $rundll32 = Join-Path $env:WINDIR "System32\rundll32.exe"
  $args = 'printui.dll,PrintUIEntry /k /n "{0}"' -f ($QueueName -replace '"', '""')
  $lastFailure = $null

  for ($attempt = 1; $attempt -le $InvokeAttempts; $attempt++) {
    $testStart = Get-Date
    $beforeJobs = Get-PrintJobsSafe -QueueName $QueueName
    Write-Log ("Test page attempt {0}/{1}: pre-state queue job count={2}" -f $attempt, $InvokeAttempts, $beforeJobs.Count)

    try {
      $tp = Start-Process -FilePath $rundll32 -ArgumentList $args -PassThru -Wait -ErrorAction Stop
      Write-Log ("Test page command invoked. attempt={0}, rundll32 exit code={1}" -f $attempt, $tp.ExitCode)
      if ($tp.ExitCode -ne 0) {
        $lastFailure = ("rundll32 exited with code {0}" -f $tp.ExitCode)
      }
    }
    catch {
      $lastFailure = ("invoke failed: {0}" -f $_.Exception.Message)
      Write-Log ("Test page invocation failed on attempt {0}: {1}" -f $attempt, $_.Exception.Message) "WARN"
      Start-Sleep -Seconds 2
      continue
    }

    $seenNewJob = $false
    for ($i = 1; $i -le $ObserveSeconds; $i++) {
      Start-Sleep -Seconds 1
      $afterJobs = Get-PrintJobsSafe -QueueName $QueueName
      $newJobs = @($afterJobs | Where-Object { $_.SubmittedTime -ge $testStart.AddSeconds(-2) })
      if ($newJobs.Count -gt 0) {
        $seenNewJob = $true
        foreach ($job in $newJobs) {
          Write-Log ("Test page job evidence: Id={0}, Status='{1}', Submitted='{2}', Document='{3}', Size={4}" -f $job.ID, $job.JobStatus, $job.SubmittedTime.ToString("s"), $job.DocumentName, $job.Size)
        }
        break
      }
    }

    Log-RecentPrintServiceEvents -Since $testStart

    if ($seenNewJob) {
      return [PSCustomObject]@{
        Success = $true
        Reason  = "Queue job observed."
      }
    }

    $lastFailure = "No queue job observed after invocation."
    Write-Log ("Test page attempt {0}/{1} did not show a new queue job." -f $attempt, $InvokeAttempts) "WARN"
    Start-Sleep -Seconds 2
  }

  return [PSCustomObject]@{
    Success = $false
    Reason  = if ($lastFailure) { $lastFailure } else { "Unknown test page failure." }
  }
}

function Process-PendingTestPageRequests {
  $pending = @(Get-PendingTestPageRequests)
  if ($pending.Count -eq 0) {
    Write-Log "Pending test page queue: none."
    return
  }

  Write-Log ("Pending test page queue found. Count={0}" -f $pending.Count)
  $remaining = @()
  foreach ($req in $pending) {
    if (-not $req.PrinterName -or -not $req.PrinterIP) {
      Write-Log "Skipping malformed pending test page queue item." "WARN"
      continue
    }

    $queueName = [string]$req.PrinterName
    $queueIp = [string]$req.PrinterIP
    $attemptCount = Get-PendingRequestAttemptCount -Request $req
    $nowUtc = (Get-Date).ToUniversalTime()
    $nextAttemptUtc = Get-PendingRequestNextAttemptUtc -Request $req
    $expiresUtc = Get-PendingRequestExpiresUtc -Request $req
    Write-Log ("Processing pending test page request for PrinterName='{0}', PrinterIP='{1}'." -f $queueName, $queueIp)

    if ($expiresUtc -le $nowUtc) {
      Write-Log ("Pending request expired and dropped. PrinterName='{0}', ExpiresAt='{1}', Attempts={2}" -f $queueName, $expiresUtc.ToString("o"), $attemptCount) "WARN"
      continue
    }

    if ($attemptCount -ge $PendingRetryMaxAttempts) {
      Write-Log ("Pending request dropped after max attempts. PrinterName='{0}', Attempts={1}, Max={2}, LastReason='{3}'" -f $queueName, $attemptCount, $PendingRetryMaxAttempts, [string]$req.LastFailureReason) "ERROR"
      continue
    }

    if ($nextAttemptUtc -gt $nowUtc) {
      Write-Log ("Pending request deferred by backoff policy. PrinterName='{0}', NextAttemptAt='{1}'." -f $queueName, $nextAttemptUtc.ToString("o"))
      $remaining += $req
      continue
    }

    $printerExists = Get-Printer -Name $queueName -ErrorAction SilentlyContinue
    if (-not $printerExists) {
      Write-Log ("Pending request deferred: printer '{0}' not found." -f $queueName) "WARN"
      $remaining += New-PendingTestPageRequestRecord -QueueName $queueName -QueueIp $queueIp -Reason ("Printer '{0}' not found." -f $queueName) -PreviousAttemptCount $attemptCount -RequestedAt ([string]$req.RequestedAt) -ExistingExpiresAt ([string]$req.ExpiresAt)
      continue
    }

    $reach = Test-Tcp9100 -Ip $queueIp
    Write-Log ("Pending request reachability {0}:9100 via {1} => {2}" -f $queueIp, $reach.Method, $reach.Reachable)
    if (-not $reach.Reachable) {
      Write-Log ("Pending request deferred: printer network endpoint is not reachable for '{0}'." -f $queueIp) "WARN"
      $remaining += New-PendingTestPageRequestRecord -QueueName $queueName -QueueIp $queueIp -Reason ("Printer endpoint '{0}:9100' unreachable." -f $queueIp) -PreviousAttemptCount $attemptCount -RequestedAt ([string]$req.RequestedAt) -ExistingExpiresAt ([string]$req.ExpiresAt)
      continue
    }

    $result = Invoke-TestPageWithEvidence -QueueName $queueName -InvokeAttempts 2 -ObserveSeconds 20
    if ($result.Success) {
      Write-Log ("Pending request completed for PrinterName='{0}'." -f $queueName)
      continue
    }

    Write-Log ("Pending request failed again for PrinterName='{0}'. Reason='{1}'" -f $queueName, $result.Reason) "WARN"
    $remaining += New-PendingTestPageRequestRecord -QueueName $queueName -QueueIp $queueIp -Reason ([string]$result.Reason) -PreviousAttemptCount $attemptCount -RequestedAt ([string]$req.RequestedAt) -ExistingExpiresAt ([string]$req.ExpiresAt)
  }

  Save-PendingTestPageRequests -Requests @($remaining)
}

function Ensure-PendingRetryScheduledTask {
  try {
    if (-not (Get-Command Register-ScheduledTask -ErrorAction SilentlyContinue)) {
      Write-Log "ScheduledTasks cmdlets are unavailable; cannot ensure retry task." "WARN"
      return
    }
    $psExe = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
    if (-not (Test-Path $psExe)) { $psExe = "powershell.exe" }

    $taskArgs = ('-NoProfile -ExecutionPolicy Bypass -File "{0}" -RetryPendingOnly -NoTestPage -LogPath "{1}"' -f $PSCommandPath, $RetryWorkerLogPath)
    $action = New-ScheduledTaskAction -Execute $psExe -Argument $taskArgs
    $trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(1))
    $trigger.RepetitionInterval = (New-TimeSpan -Minutes $PendingRetryBaseMinutes)
    $trigger.RepetitionDuration = (New-TimeSpan -Days 3650)
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName $PendingRetryTaskName -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null
    Write-Log ("Scheduled retry task ensured. Name='{0}', IntervalMinutes={1}" -f $PendingRetryTaskName, $PendingRetryBaseMinutes)
  }
  catch {
    Write-Log ("Could not ensure scheduled retry task '{0}': {1}" -f $PendingRetryTaskName, $_.Exception.Message) "WARN"
  }
}

function Remove-PendingRetryScheduledTask {
  try {
    if (-not (Get-Command Unregister-ScheduledTask -ErrorAction SilentlyContinue)) {
      Write-Log "ScheduledTasks cmdlets are unavailable; cannot remove retry task." "WARN"
      return
    }
    Unregister-ScheduledTask -TaskName $PendingRetryTaskName -Confirm:$false -ErrorAction Stop
    Write-Log ("Scheduled retry task removed. Name='{0}'" -f $PendingRetryTaskName)
  }
  catch {
    if ($_.Exception.Message -match "cannot find the file specified|No MSFT_ScheduledTask objects found|The system cannot find the file specified") {
      Write-Log ("Scheduled retry task remove skipped; task absent. Name='{0}'" -f $PendingRetryTaskName)
    }
    else {
      Write-Log ("Could not remove scheduled retry task '{0}': {1}" -f $PendingRetryTaskName, $_.Exception.Message) "WARN"
    }
  }
}

function Update-PendingRetryTaskState {
  $pending = @(Get-PendingTestPageRequests)
  if ($pending.Count -gt 0) {
    Ensure-PendingRetryScheduledTask
  }
  else {
    Remove-PendingRetryScheduledTask
  }
}

try {
  if ([string]::IsNullOrWhiteSpace($PrinterName)) {
    $PrinterName = "Brother MFC-L9570CDW ($PrinterIP)"
  }

  if ([string]::IsNullOrWhiteSpace($LogPath)) {
    $LogPath = Join-Path (Join-Path $PSScriptRoot "logs") ("install-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
  }
  $script:LogPath = $LogPath
  $logDir = Split-Path -Path $script:LogPath -Parent
  if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }
  if (-not (Test-Path $script:LogPath)) { New-Item -ItemType File -Path $script:LogPath | Out-Null }
}
catch {
  Write-Error "Failed to initialize logging: $($_.Exception.Message)"
  exit 1
}

try {
  Write-Log ("WorkRoot: {0}" -f $WorkRoot)
  Write-Log "Starting Install-Brother-MFCL9570CDW.ps1"
  $mode = "Install"
  if ($ValidateOnly) { $mode = "ValidateOnly" }
  if ($RetryPendingOnly) { $mode = "RetryPendingOnly" }
  Write-Log ("Mode: {0}" -f $mode)
  Write-Log ("PS host: Edition={0}, Version={1}, Home={2}" -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $PSHOME)
  Write-Log ("Parameters: PrinterIP='{0}', PrinterName='{1}', DriverUrl='{2}', ValidateOnly={3}, SkipSignatureCheck={4}, NoTestPage={5}, RetryPendingOnly={6}" -f $PrinterIP, $PrinterName, $DriverUrl, $ValidateOnly, $SkipSignatureCheck, $NoTestPage, $RetryPendingOnly)
  Write-Log ("Driver cache artifacts: DriverExePath='{0}', DriverHashPath='{1}'" -f $DriverExePath, $DriverHashPath)

  if (-not $RetryPendingOnly -and -not ($PrinterIP -match '^(?:(?:25[0-5]|2[0-4][0-9]|1?[0-9]{1,2})\.){3}(?:25[0-5]|2[0-4][0-9]|1?[0-9]{1,2})$')) {
    Fail ("Invalid IP argument: {0}" -f $PrinterIP)
  }

  $isAdmin = Test-IsAdmin
  Write-Log ("Admin status: {0}" -f $isAdmin)
  if (-not $isAdmin -and -not $ValidateOnly -and -not $RetryPendingOnly) {
    Write-Log "Not admin. BAT must launch install elevated." "ERROR"
    exit 1
  }

  if ($RetryPendingOnly) {
    Import-PrintManagementOrFail
    Process-PendingTestPageRequests
    Update-PendingRetryTaskState
    Write-Log "RetryPendingOnly completed."
    exit 0
  }

  if (-not $ValidateOnly -and $PSVersionTable.PSEdition -ne "Desktop") {
    Fail "Install path requires Windows PowerShell 5.1 (Desktop edition)."
  }

  $reach = Test-Tcp9100 -Ip $PrinterIP
  Write-Log ("Reachability to {0}:9100 via {1} => {2}" -f $PrinterIP, $reach.Method, $reach.Reachable)

  Import-PrintManagementOrFail

  if ($ValidateOnly) {
    $infPath = Ensure-DriverAndInf -AllowExtraction:$false -ReadOnly
    $infDiscoverable = $false
    if (-not [string]::IsNullOrWhiteSpace([string]$infPath)) {
      $infDiscoverable = [bool](Test-Path $infPath)
    }
    Write-Log ("ValidateOnly evidence: INF discoverable={0}" -f $infDiscoverable)
    $port = Get-PrinterPort -ErrorAction SilentlyContinue | Where-Object Name -eq $PrinterIP
    $printer = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue
    Write-Log ("ValidateOnly evidence: PortExists={0}" -f ([bool]$port))
    Write-Log ("ValidateOnly evidence: PrinterExists={0}" -f ([bool]$printer))
    if ($printer) {
      Write-Log ("ValidateOnly evidence: Printer PortName='{0}', DriverName='{1}'" -f $printer.PortName, $printer.DriverName)
    }
    Write-Log "ValidateOnly completed. No printer objects or queue state were modified."
    exit 0
  }

  $infPath = Ensure-DriverAndInf -AllowExtraction

  if (-not $infPath -or -not (Test-Path $infPath)) { Fail "INF path is missing before install stage." }

  Write-Log ("Stage: pnputil /add-driver '{0}'" -f $infPath)
  $pnpOut = pnputil /add-driver "$infPath" 2>&1
  $pnpOut | ForEach-Object { Write-Log ("pnputil: {0}" -f $_.ToString()) }
  $pnpRc = $LASTEXITCODE
  Write-Log ("pnputil exit code: {0}" -f $pnpRc)
  if ($pnpRc -ne 0) { Fail ("pnputil failed with exit code {0}" -f $pnpRc) }

  $enumOut = pnputil /enum-drivers 2>&1 | Out-String
  if ($enumOut -match "BRPRC16A\.INF" -or $enumOut -match "MFC-L9570CDW") {
    Write-Log "Postcondition: driver appears in pnputil /enum-drivers output."
  } else {
    Write-Log "Postcondition warning: driver not clearly found in enum output." "WARN"
  }

  $port = Get-PrinterPort -ErrorAction SilentlyContinue | Where-Object Name -eq $PrinterIP
  if (-not $port) {
    Write-Log ("Stage: creating printer port '{0}'" -f $PrinterIP)
    Add-PrinterPort -Name $PrinterIP -PrinterHostAddress $PrinterIP
  } else {
    Write-Log ("Stage: printer port '{0}' already exists." -f $PrinterIP)
  }
  $port = Get-PrinterPort -Name $PrinterIP -ErrorAction SilentlyContinue
  if (-not $port) { Fail ("Postcondition failed: port '{0}' not found." -f $PrinterIP) }
  Write-Log ("Postcondition: Get-PrinterPort Name='{0}', HostAddress='{1}'" -f $port.Name, $port.PrinterHostAddress)

  $printer = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue
  if (-not $printer) {
    Write-Log ("Stage: creating printer '{0}' with model '{1}'" -f $PrinterName, $ExpectedPrintUiModel)
    & printui.exe /if /b "$PrinterName" /f "$infPath" /r "$PrinterIP" /m "$ExpectedPrintUiModel"
    Write-Log ("printui exit code: {0}" -f $LASTEXITCODE)
  } else {
    Write-Log ("Stage: printer '{0}' already exists." -f $PrinterName)
  }

  $printer = $null
  for ($i = 1; $i -le 15; $i++) {
    $printer = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue
    if ($printer) { break }
    Start-Sleep -Seconds 1
  }
  if (-not $printer) { Fail ("Postcondition failed: printer '{0}' not found after retry." -f $PrinterName) }

  $actualPortName = $printer.PortName
  Write-Log ("Postcondition: printer exists Name='{0}', DriverName='{1}', PortName='{2}'" -f $printer.Name, $printer.DriverName, $actualPortName)

  $actualPort = Get-PrinterPort -Name $actualPortName -ErrorAction SilentlyContinue
  if (-not $actualPort) { Fail ("Postcondition failed: printer's bound port '{0}' not found." -f $actualPortName) }
  Write-Log ("Postcondition: bound port evidence Name='{0}', HostAddress='{1}'" -f $actualPort.Name, $actualPort.PrinterHostAddress)

  $regBase = "HKLM:\SYSTEM\CurrentControlSet\Control\Print\Monitors\Standard TCP/IP Port\Ports\$actualPortName"
  if (-not (Test-Path $regBase)) { Fail ("Port registry key not found for bound port: {0}" -f $regBase) }
  Set-ItemProperty -Path $regBase -Name "Protocol" -Value 1
  Set-ItemProperty -Path $regBase -Name "PortNumber" -Value 9100
  Set-ItemProperty -Path $regBase -Name "SNMP Enabled" -Value 0

  $protocol = (Get-ItemProperty -Path $regBase -Name "Protocol").Protocol
  $portNum = (Get-ItemProperty -Path $regBase -Name "PortNumber").PortNumber
  $snmp = (Get-ItemProperty -Path $regBase -Name "SNMP Enabled")."SNMP Enabled"
  Write-Log ("Postcondition: registry Protocol={0}, PortNumber={1}, SNMP Enabled={2}" -f $protocol, $portNum, $snmp)
  if ($protocol -ne 1 -or $portNum -ne 9100 -or $snmp -ne 0) {
    Fail "Postcondition failed: RAW 9100 / SNMP OFF registry values are incorrect."
  }

  if (-not $NoTestPage) {
    Process-PendingTestPageRequests

    $tpResult = Invoke-TestPageWithEvidence -QueueName $PrinterName -InvokeAttempts 3 -ObserveSeconds 20
    if ($tpResult.Success) {
      Write-Log "Test page postcondition: queue job observed."
      Write-Log "Test page evidence confirms queue submission only; physical paper output is device-dependent."
      Remove-PendingTestPageRequest -QueueName $PrinterName -QueueIp $PrinterIP
      Update-PendingRetryTaskState
    }
    else {
      Write-Log ("Test page postcondition: no queue job evidence. Reason='{0}'" -f $tpResult.Reason) "WARN"
      Add-PendingTestPageRequest -QueueName $PrinterName -QueueIp $PrinterIP -Reason $tpResult.Reason
      Update-PendingRetryTaskState
    }
  }
  else {
    Write-Log "NoTestPage specified. Skipping test page invocation."
  }

  Write-Log "Install completed successfully."
  exit 0
}
catch {
  Write-Log ("Unhandled failure: {0}" -f $_.Exception.Message) "ERROR"
  if ($_.InvocationInfo) {
    Write-Log ("At: {0}" -f $_.InvocationInfo.PositionMessage) "ERROR"
  }
  Write-Log ("Stack: {0}" -f $_.ScriptStackTrace) "ERROR"
  exit 1
}
