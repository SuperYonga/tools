$ErrorActionPreference = "Stop"

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$resultsPath = Join-Path $here "artifacts\pester-results.xml"

if (-not (Get-Module -ListAvailable -Name Pester)) {
  Write-Error "Pester module is not installed."
  exit 1
}

Import-Module Pester -ErrorAction Stop

if (Test-Path $resultsPath) {
  Remove-Item -Path $resultsPath -Force -ErrorAction SilentlyContinue
}

$result = Invoke-Pester -Script (Join-Path $here "Installer.Regression.Tests.ps1") -OutputFormat NUnitXml -OutputFile $resultsPath -PassThru
if (-not $result) {
  Write-Error "Invoke-Pester returned no result object."
  exit 1
}

if ($result.FailedCount -gt 0) {
  Write-Error ("Regression tests failed. FailedCount={0}" -f $result.FailedCount)
  exit 1
}

Write-Host ("Regression tests passed. Total={0}, Failed={1}" -f $result.TotalCount, $result.FailedCount)
Write-Host ("Results XML: {0}" -f $resultsPath)
exit 0
