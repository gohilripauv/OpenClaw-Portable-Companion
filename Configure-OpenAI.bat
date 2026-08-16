@echo off
setlocal
set "OPENCLAW_PORTABLE_POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%OPENCLAW_PORTABLE_POWERSHELL%" (
  echo Trusted Windows PowerShell was not found at "%OPENCLAW_PORTABLE_POWERSHELL%".
  exit /b 1
)
cd /d "%~dp0"
"%OPENCLAW_PORTABLE_POWERSHELL%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Configure-OpenAI.ps1"
set "OPENCLAW_PORTABLE_EXIT=%ERRORLEVEL%"
echo.
if not "%OPENCLAW_PORTABLE_EXIT%"=="0" echo Configuration failed with code %OPENCLAW_PORTABLE_EXIT%.
pause
exit /b %OPENCLAW_PORTABLE_EXIT%
