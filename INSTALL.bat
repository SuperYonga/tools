@echo off
setlocal EnableExtensions DisableDelayedExpansion

set "POWERSHELL_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%POWERSHELL_EXE%" set "POWERSHELL_EXE=powershell"

set "SCRIPT_DIR=%~dp0"
set "LAUNCHER=%SCRIPT_DIR%Install-Brother-MFCL9570CDW-Launcher.ps1"

if not exist "%LAUNCHER%" (
  echo ERROR: Missing launcher script:
  echo   %LAUNCHER%
  if defined SC_PAUSE pause
  exit /b 1
)

"%POWERSHELL_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%LAUNCHER%" %*
set "RC=%errorlevel%"

if not "%RC%"=="0" pause
if defined SC_PAUSE pause
exit /b %RC%
