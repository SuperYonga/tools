param(
  [string]$OutputDir = (Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) "builds") "Install-Brother-MFCL9570CDW")
)

$ErrorActionPreference = "Stop"

$requiredFiles = @(
  "INSTALL.bat",
  "Install-Brother-MFCL9570CDW-Launcher.ps1",
  "Install-Brother-MFCL9570CDW.ps1",
  "README-Install-Brother-MFCL9570CDW.md"
)
$optionalFiles = @(
  "Y16E_C1-hostm-K1.EXE"
)

foreach ($file in $requiredFiles) {
  $path = Join-Path $PSScriptRoot $file
  if (-not (Test-Path $path)) {
    throw "Missing required file: $path"
  }
}

if (-not (Test-Path $OutputDir)) {
  New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$zipPath = Join-Path $OutputDir ("Brother-MFCL9570CDW-Installer-{0}.zip" -f $stamp)

$stageDir = Join-Path $env:TEMP ("brother-release-{0}" -f ([guid]::NewGuid().ToString("N")))
New-Item -ItemType Directory -Path $stageDir -Force | Out-Null

try {
  foreach ($file in $requiredFiles) {
    Copy-Item -Path (Join-Path $PSScriptRoot $file) -Destination (Join-Path $stageDir $file) -Force
  }
  foreach ($file in $optionalFiles) {
    $source = Join-Path $PSScriptRoot $file
    if (Test-Path $source) {
      Copy-Item -Path $source -Destination (Join-Path $stageDir $file) -Force
      Write-Host ("Included optional offline file: {0}" -f $file)
    }
  }

  Compress-Archive -Path (Join-Path $stageDir "*") -DestinationPath $zipPath -CompressionLevel Optimal -Force
  Write-Host ("Created release zip: {0}" -f $zipPath)
}
finally {
  if (Test-Path $stageDir) {
    Remove-Item -Path $stageDir -Recurse -Force
  }
}
