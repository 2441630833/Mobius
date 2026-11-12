@echo off
rem Mobius session health check (read-only)
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0mobius-auto-maintain.ps1" -Mode Check
set CODE=%ERRORLEVEL%
echo.
echo Exit code: %CODE%   (0=healthy 1=watch 2=risk 4=error)
echo.
pause
exit /b %CODE%