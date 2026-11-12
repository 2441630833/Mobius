@echo off
rem Dry run: show what would be archived, change nothing
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0mobius-auto-maintain.ps1" -Mode Clean -DryRun
echo.
pause