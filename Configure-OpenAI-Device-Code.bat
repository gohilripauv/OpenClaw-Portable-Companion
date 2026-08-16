@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Configure-OpenAI.ps1" -DeviceCode
set "OPENCLAW_PORTABLE_EXIT=%ERRORLEVEL%"
echo.
if not "%OPENCLAW_PORTABLE_EXIT%"=="0" echo Configuration failed with code %OPENCLAW_PORTABLE_EXIT%.
pause
exit /b %OPENCLAW_PORTABLE_EXIT%
