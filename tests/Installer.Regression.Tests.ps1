$ErrorActionPreference = "Stop"

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $here
$installerPs1 = Join-Path $projectRoot "Install-Brother-MFCL9570CDW.ps1"
$installBat = Join-Path $projectRoot "INSTALL.bat"
$codexTestRunner = Join-Path $projectRoot "_codex_test_runner.cmd"
$launcherPs1 = Join-Path $projectRoot "Install-Brother-MFCL9570CDW-Launcher.ps1"
$packReleasePs1 = Join-Path $projectRoot "Pack-Release.ps1"
$logDir = Join-Path $projectRoot "tests\artifacts"
$testWorkRoot = Join-Path $logDir "workroot"
$pendingQueuePath = Join-Path $testWorkRoot "pending-test-pages.json"

if (-not (Test-Path $logDir)) {
  New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

function New-TestLogPath {
  param([string]$Prefix)
  return (Join-Path $logDir ("{0}-{1}.log" -f $Prefix, (Get-Date -Format "yyyyMMdd-HHmmss-fff")))
}

function Invoke-InstallerPs1 {
  param(
    [Parameter(Mandatory = $true)][string[]]$Args,
    [Parameter(Mandatory = $true)][string]$LogPath,
    [string]$WorkRoot
  )

  $pwsh = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
  if (-not (Test-Path $pwsh)) { $pwsh = "powershell.exe" }

  $argList = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $installerPs1
  ) + $Args + @("-LogPath", $LogPath)

  $oldWorkRoot = $env:SC_PRINTER_WORK_ROOT
  try {
    if ($WorkRoot) { $env:SC_PRINTER_WORK_ROOT = $WorkRoot } else { Remove-Item Env:SC_PRINTER_WORK_ROOT -ErrorAction SilentlyContinue }
    & $pwsh @argList
    $exitCode = $LASTEXITCODE
    $logText = if (Test-Path $LogPath) { Get-Content -Path $LogPath -Raw } else { "" }
    return [PSCustomObject]@{
      ExitCode = $exitCode
      LogPath = $LogPath
      LogText = $logText
    }
  }
  finally {
    if ($null -eq $oldWorkRoot) { Remove-Item Env:SC_PRINTER_WORK_ROOT -ErrorAction SilentlyContinue } else { $env:SC_PRINTER_WORK_ROOT = $oldWorkRoot }
  }
}

function Invoke-LauncherPs1 {
  param(
    [Parameter(Mandatory = $true)][string[]]$Args,
    [Parameter(Mandatory = $true)][string]$LogPath
  )

  $pwsh = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
  if (-not (Test-Path $pwsh)) { $pwsh = "powershell.exe" }

  $argList = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $launcherPs1
  ) + $Args + @("-LogPath", $LogPath)

  & $pwsh @argList
  $exitCode = $LASTEXITCODE
  $logText = if (Test-Path $LogPath) { Get-Content -Path $LogPath -Raw } else { "" }
  return [PSCustomObject]@{
    ExitCode = $exitCode
    LogPath = $LogPath
    LogText = $logText
  }
}

function Invoke-Ps1File {
  param(
    [Parameter(Mandatory = $true)][string]$ScriptPath,
    [string[]]$Args = @()
  )

  $pwsh = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
  if (-not (Test-Path $pwsh)) { $pwsh = "powershell.exe" }

  $output = & $pwsh -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @Args 2>&1
  return [PSCustomObject]@{
    ExitCode = $LASTEXITCODE
    Output = ($output | Out-String)
  }
}

Describe "Brother installer regression tests" {
  BeforeEach {
    if (Test-Path $testWorkRoot) {
      Remove-Item -Path $testWorkRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $testWorkRoot -Force | Out-Null
  }

  It "launcher batch is non-interactive by default" {
    $content = Get-Content -Path $installBat -Raw
    ($content -match "if defined SC_PAUSE pause") | Should Be $true
    ($content -match 'if not "%RC%"=="0" pause') | Should Be $true
    ($content -match "SC_NO_PAUSE") | Should Be $false
  }

  It "codex test runner points to INSTALL.bat" {
    $content = Get-Content -Path $codexTestRunner -Raw
    ($content -match "INSTALL\.bat") | Should Be $true
    ($content -match "Install-Brother-MFCL9570CDW\.bat") | Should Be $false
  }

  It "installer and launcher default logs write to logs directory" {
    $installerContent = Get-Content -Path $installerPs1 -Raw
    $launcherContent = Get-Content -Path $launcherPs1 -Raw

    ($installerContent -match 'Join-Path \(Join-Path \$PSScriptRoot "logs"\)') | Should Be $true
    ($launcherContent -match 'Join-Path \(Join-Path \$scriptDir "logs"\)') | Should Be $true
  }

  It "installer reachability logging includes timeout and elapsed evidence in install and retry paths" {
    $installerContent = Get-Content -Path $installerPs1 -Raw
    ($installerContent -match '\$ReachabilityTimeoutMs\s*=\s*2500') | Should Be $true
    ($installerContent -match '\$degradedReasons\s*=\s*@\(\)') | Should Be $true
    ($installerContent -match '\$printerReachable\s*=\s*\[bool\]\$reach\.Reachable') | Should Be $true
    ($installerContent -match 'Stage: probing reachability to \{0\}:9100 with timeout=\{1\}ms') | Should Be $true
    ($installerContent -match 'Pending request stage: probing reachability to \{0\}:9100 with timeout=\{1\}ms') | Should Be $true
    ($installerContent -match 'Reachability to \{0\}:9100 via \{1\} => \{2\} \(elapsed=\{3\}ms\)') | Should Be $true
    ($installerContent -match 'Pending request reachability \{0\}:9100 via \{1\} => \{2\} \(elapsed=\{3\}ms\)') | Should Be $true
    ($installerContent -match 'Reachability warning: \{0\}:9100 was not reachable\. Continuing install for offline provisioning; verify printer power/network if test page evidence is absent\.') | Should Be $true
    ($installerContent -match "Test page verification degraded: \{0\}") | Should Be $true
    ($installerContent -match "Install completed with degraded verification\. Exiting non-zero to trigger failure comms\. Reasons='\{0\}'") | Should Be $true
    ($installerContent -match "exit 2") | Should Be $true
  }

  It "installer treats no matching PrintService admin events as informational evidence" {
    $installerContent = Get-Content -Path $installerPs1 -Raw
    ($installerContent -match 'PrintService\(Admin\) evidence: no matching events found since \{0\}\.') | Should Be $true
    ($installerContent -match 'NoMatchingEventsFound') | Should Be $true
  }

  It "launcher failure notifications include a user action guidance block" {
    $launcherContent = Get-Content -Path $launcherPs1 -Raw
    ($launcherContent -match "function New-FailureMessageBody") | Should Be $true
    ($launcherContent -match "User Action Required:") | Should Be $true
    ($launcherContent -match "Auto-attempted:") | Should Be $true
    ($launcherContent -match "INSTALL\.bat -ValidateOnly") | Should Be $true
    ($launcherContent -match "Full log content:") | Should Be $true
  }

  It "launcher exposes progress wait helper for long-running installer execution" {
    $launcherContent = Get-Content -Path $launcherPs1 -Raw
    ($launcherContent -match "function Wait-InstallerProcess") | Should Be $true
    ($launcherContent -match "SC_SHOW_PROGRESS") | Should Be $true
    ($launcherContent -match "Still waiting for process PID=") | Should Be $true
  }

  It "launcher failure flow centralizes full-log failure comms" {
    $launcherContent = Get-Content -Path $launcherPs1 -Raw
    ($launcherContent -match "function Invoke-FailureComms") | Should Be $true
    ($launcherContent -match "Failure handler triggered") | Should Be $true
    ($launcherContent -match "Get-LogContent -Full") | Should Be $true
  }

  It "launcher failure notification path uses a single mail-draft channel when SMTP is not configured" {
    $logPath = New-TestLogPath -Prefix "launcher-notify-failure"
    $oldHost = $env:SC_SMTP_HOST
    $oldServer = $env:SC_SMTP_SERVER
    $oldFrom = $env:SC_SMTP_FROM
    try {
      Remove-Item Env:SC_SMTP_HOST -ErrorAction SilentlyContinue
      Remove-Item Env:SC_SMTP_SERVER -ErrorAction SilentlyContinue
      Remove-Item Env:SC_SMTP_FROM -ErrorAction SilentlyContinue

      $result = Invoke-LauncherPs1 -Args @("-ValidateOnly","-PrinterIP","999.0.0.1") -LogPath $logPath

      $result.ExitCode | Should Not Be 0
      ($result.LogText -match "Failure handler triggered") | Should Be $true
      ($result.LogText -match "Failure notification mode: always-on") | Should Be $true
      ($result.LogText -match "Failure comms channel selected: mail-draft-primary \(single email action per run\)") | Should Be $true
      ($result.LogText -match "Failure notification requested but skipped") | Should Be $false
    }
    finally {
      if ($null -eq $oldHost) { Remove-Item Env:SC_SMTP_HOST -ErrorAction SilentlyContinue } else { $env:SC_SMTP_HOST = $oldHost }
      if ($null -eq $oldServer) { Remove-Item Env:SC_SMTP_SERVER -ErrorAction SilentlyContinue } else { $env:SC_SMTP_SERVER = $oldServer }
      if ($null -eq $oldFrom) { Remove-Item Env:SC_SMTP_FROM -ErrorAction SilentlyContinue } else { $env:SC_SMTP_FROM = $oldFrom }
    }
  }

  It "launcher mail-draft path logs enabled and uses full log body without truncation" {
    $logPath = New-TestLogPath -Prefix "launcher-outlook-failure"
    $result = Invoke-LauncherPs1 -Args @("-ValidateOnly","-PrinterIP","999.0.0.1") -LogPath $logPath

    $result.ExitCode | Should Not Be 0
    ($result.LogText -match "Failure handler triggered") | Should Be $true
    ($result.LogText -match "Outlook failure draft mode: always-on \(default mode=default-client, fallback=notepad instructions\)") | Should Be $true
    ($result.LogText -match "Failure comms channel selected: mail-draft-primary \(single email action per run\)") | Should Be $true
    ($result.LogText -match "Mailto body truncated") | Should Be $false
    ($result.LogText -match "Default mail client draft opened for '.*' \(mode=default, body=full-log\)|Default mail client draft failed|Manual fallback opened in Notepad|Manual Notepad fallback failed") | Should Be $true
  }

  It "launcher central failure comms guard prevents duplicate trigger handling in one run" {
    $launcherContent = Get-Content -Path $launcherPs1 -Raw
    ($launcherContent.Contains('$script:FailureCommsTriggered = $false')) | Should Be $true
    ($launcherContent -match "Failure comms already handled for this run\. Skipping duplicate trigger") | Should Be $true
  }

  It "ValidateOnly run succeeds and logs completion" {
    $logPath = New-TestLogPath -Prefix "validate-only"
    $result = Invoke-InstallerPs1 -Args @("-ValidateOnly","-SkipSignatureCheck") -LogPath $logPath -WorkRoot $testWorkRoot

    $result.ExitCode | Should Be 0
    ($result.LogText -match "Mode: ValidateOnly") | Should Be $true
    ($result.LogText -match "Stage: probing reachability to 192\.168\.0\.120:9100 with timeout=2500ms") | Should Be $true
    ($result.LogText -match "Reachability to 192\.168\.0\.120:9100 via TcpClient => (True|False) \(elapsed=\d+ms\)") | Should Be $true
    ($result.LogText -match "ValidateOnly completed\. No printer objects or queue state were modified\.") | Should Be $true
    ($result.LogText -match "Failure handler triggered") | Should Be $false
    ($result.LogText -match "Default mail client draft opened|Default mail client draft failed|Failure notification email sent") | Should Be $false
    (Test-Path (Join-Path $testWorkRoot "cache\Y16E_C1-hostm-K1.sha256")) | Should Be $false
  }

  It "RetryPendingOnly run succeeds and logs completion" {
    $logPath = New-TestLogPath -Prefix "retry-only"
    $result = Invoke-InstallerPs1 -Args @("-RetryPendingOnly","-NoTestPage") -LogPath $logPath -WorkRoot $testWorkRoot

    $result.ExitCode | Should Be 0
    ($result.LogText -match "Mode: RetryPendingOnly") | Should Be $true
    ($result.LogText -match "RetryPendingOnly completed\.") | Should Be $true
    ($result.LogText -match "Scheduled retry task") | Should Be $true
  }

  It "invalid PrinterIP fails fast with clear error" {
    $logPath = New-TestLogPath -Prefix "invalid-ip"
    $result = Invoke-InstallerPs1 -Args @("-ValidateOnly","-PrinterIP","999.0.0.1") -LogPath $logPath -WorkRoot $testWorkRoot

    $result.ExitCode | Should Not Be 0
    ($result.LogText -match "Invalid IP argument") | Should Be $true
  }

  It "ValidateOnly accepts custom allowed DriverUrl and logs derived cache artifact names" {
    $customDriverUrl = "https://download.brother.com/welcome/dlf106550/CustomDriver.EXE"
    $logPath = New-TestLogPath -Prefix "custom-driver-url"
    $result = Invoke-InstallerPs1 -Args @("-ValidateOnly","-SkipSignatureCheck","-DriverUrl",$customDriverUrl) -LogPath $logPath -WorkRoot $testWorkRoot

    $result.ExitCode | Should Be 0
    ($result.LogText -match [regex]::Escape("DriverUrl='$customDriverUrl'")) | Should Be $true
    ($result.LogText -match "CustomDriver\.EXE\.sha256") | Should Be $true
  }

  It "invalid DriverUrl host fails fast with clear error" {
    $logPath = New-TestLogPath -Prefix "invalid-driver-url"
    $result = Invoke-InstallerPs1 -Args @("-ValidateOnly","-SkipSignatureCheck","-DriverUrl","https://example.com/driver.exe") -LogPath $logPath -WorkRoot $testWorkRoot

    $result.ExitCode | Should Not Be 0
    ($result.LogText -match "Driver URL policy failed") | Should Be $true
  }

  It "RetryPendingOnly increments attempts on deferred printer-missing path" {
    @(
      [PSCustomObject]@{
        PrinterName       = "DoesNotExist-Queue"
        PrinterIP         = "192.168.0.120"
        RequestedAt       = (Get-Date).AddMinutes(-10).ToString("o")
        LastAttemptAt     = (Get-Date).AddMinutes(-10).ToString("o")
        AttemptCount      = 0
        NextAttemptAt     = (Get-Date).AddMinutes(-1).ToString("o")
        ExpiresAt         = (Get-Date).AddDays(2).ToString("o")
        LastFailureReason = "seed"
      }
    ) | ConvertTo-Json -Depth 5 | Set-Content -Path $pendingQueuePath -Encoding ascii

    $logPath = New-TestLogPath -Prefix "retry-deferred-increment"
    $result = Invoke-InstallerPs1 -Args @("-RetryPendingOnly","-NoTestPage") -LogPath $logPath -WorkRoot $testWorkRoot

    $result.ExitCode | Should Be 0
    $after = Get-Content -Path $pendingQueuePath -Raw | ConvertFrom-Json
    @($after).Count | Should Be 1
    ([int]$after.AttemptCount) | Should Be 1
    ([string]$after.NextAttemptAt).Length -gt 0 | Should Be $true
    ($result.LogText -match "Pending request deferred: printer 'DoesNotExist-Queue' not found") | Should Be $true
  }

  It "RetryPendingOnly drops request at max attempts" {
    @(
      [PSCustomObject]@{
        PrinterName       = "Maxed-Queue"
        PrinterIP         = "192.168.0.120"
        RequestedAt       = (Get-Date).AddMinutes(-20).ToString("o")
        LastAttemptAt     = (Get-Date).AddMinutes(-10).ToString("o")
        AttemptCount      = 96
        NextAttemptAt     = (Get-Date).AddMinutes(-1).ToString("o")
        ExpiresAt         = (Get-Date).AddDays(2).ToString("o")
        LastFailureReason = "seed"
      }
    ) | ConvertTo-Json -Depth 5 | Set-Content -Path $pendingQueuePath -Encoding ascii

    $logPath = New-TestLogPath -Prefix "retry-max-drop"
    $result = Invoke-InstallerPs1 -Args @("-RetryPendingOnly","-NoTestPage") -LogPath $logPath -WorkRoot $testWorkRoot

    $result.ExitCode | Should Be 0
    (Test-Path $pendingQueuePath) | Should Be $false
    ($result.LogText -match "Pending request dropped after max attempts") | Should Be $true
  }

  It "RetryPendingOnly drops expired request by TTL" {
    @(
      [PSCustomObject]@{
        PrinterName       = "Expired-Queue"
        PrinterIP         = "192.168.0.120"
        RequestedAt       = (Get-Date).AddDays(-10).ToString("o")
        LastAttemptAt     = (Get-Date).AddDays(-8).ToString("o")
        AttemptCount      = 2
        NextAttemptAt     = (Get-Date).AddMinutes(-1).ToString("o")
        ExpiresAt         = (Get-Date).AddMinutes(-2).ToString("o")
        LastFailureReason = "seed"
      }
    ) | ConvertTo-Json -Depth 5 | Set-Content -Path $pendingQueuePath -Encoding ascii

    $logPath = New-TestLogPath -Prefix "retry-ttl-drop"
    $result = Invoke-InstallerPs1 -Args @("-RetryPendingOnly","-NoTestPage") -LogPath $logPath -WorkRoot $testWorkRoot

    $result.ExitCode | Should Be 0
    (Test-Path $pendingQueuePath) | Should Be $false
    ($result.LogText -match "Pending request expired and dropped") | Should Be $true
  }

  It "RetryPendingOnly with non-empty queue attempts scheduled-task ensure path" {
    @(
      [PSCustomObject]@{
        PrinterName       = "Backoff-Queue"
        PrinterIP         = "192.168.0.120"
        RequestedAt       = (Get-Date).ToString("o")
        LastAttemptAt     = (Get-Date).ToString("o")
        AttemptCount      = 1
        NextAttemptAt     = (Get-Date).AddMinutes(120).ToString("o")
        ExpiresAt         = (Get-Date).AddDays(2).ToString("o")
        LastFailureReason = "seed"
      }
    ) | ConvertTo-Json -Depth 5 | Set-Content -Path $pendingQueuePath -Encoding ascii

    $logPath = New-TestLogPath -Prefix "retry-task-ensure"
    $result = Invoke-InstallerPs1 -Args @("-RetryPendingOnly","-NoTestPage") -LogPath $logPath -WorkRoot $testWorkRoot

    $result.ExitCode | Should Be 0
    ($result.LogText -match "Scheduled retry task ensured|Could not ensure scheduled retry task|ScheduledTasks cmdlets are unavailable; cannot ensure retry task") | Should Be $true
  }

  It "Pack-Release default output dir points to sibling builds folder and produces zip" {
    $expectedOutputDir = Join-Path (Join-Path (Split-Path -Parent $projectRoot) "builds") "Install-Brother-MFCL9570CDW"
    $before = @()
    if (Test-Path $expectedOutputDir) {
      $before = @(Get-ChildItem -Path $expectedOutputDir -Filter "Brother-MFCL9570CDW-Installer-*.zip" -File | Select-Object -ExpandProperty FullName)
    }

    $result = Invoke-Ps1File -ScriptPath $packReleasePs1
    $result.ExitCode | Should Be 0
    ($result.Output -match "Created release zip: ") | Should Be $true

    (Test-Path $expectedOutputDir) | Should Be $true
    $after = @(Get-ChildItem -Path $expectedOutputDir -Filter "Brother-MFCL9570CDW-Installer-*.zip" -File | Select-Object -ExpandProperty FullName)
    $new = @($after | Where-Object { $before -notcontains $_ })
    $new.Count -ge 1 | Should Be $true

    foreach ($path in $new) {
      if (Test-Path $path) { Remove-Item -Path $path -Force -ErrorAction SilentlyContinue }
    }
  }
}
