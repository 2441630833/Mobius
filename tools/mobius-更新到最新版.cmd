@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0.."
echo ==========================================================
echo  Mobius - update this machine to the latest GitHub release
echo  (uses api.github.com, works when github.com is blocked)
echo ==========================================================
echo.
tasklist /fi "imagename eq Mobius.exe" | find /i "Mobius.exe" >nul
if not errorlevel 1 (
  echo Mobius is still running. Quit it from the tray icon first.
  echo.
  pause
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\update-mobius-local.ps1" %*
echo.
pause