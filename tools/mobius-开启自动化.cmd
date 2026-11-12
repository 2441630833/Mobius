@echo off
rem Register the scheduled maintenance tasks (and run one health check now)
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-MobiusAutoMaintain.ps1" -Install -RunNow
echo.
echo Done. Use  -Status  to inspect tasks,  -Uninstall  to remove them.
echo.
pause