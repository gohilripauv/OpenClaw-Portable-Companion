@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Start-OpenClaw.ps1"
set "OPENCLAW_PORTABLE_EXIT=%ERRORLEVEL%"
if not "%OPENCLAW_PORTABLE_EXIT%"=="0" (
  echo.
  echo OpenClaw Portable Companion exited with code %OPENCLAW_PORTABLE_EXIT%.
  pause
)
exit /b %OPENCLAW_PORTABLE_EXIT%
