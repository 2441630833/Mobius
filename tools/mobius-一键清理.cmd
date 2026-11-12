@echo off
rem Real cleanup: archive old sessions, rotate logs, compact state.vscdb
rem Recommend: fully quit Mobius first so state.vscdb can be compacted
setlocal
echo ================================================================
echo  Mobius session cleanup
echo  - old sessions are zipped to %%USERPROFILE%%\MobiusArchive first
echo  - originals are deleted only after the zip is verified
echo  - quit Mobius first if you want state.vscdb compaction
echo ================================================================
echo.
set /p GO=Proceed? [y/N]
if /i not "%GO%"=="y" goto :cancel
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0mobius-auto-maintain.ps1" -Mode Clean
echo.
echo Exit code: %ERRORLEVEL%   (0=healthy 1=watch 2=risk 3=cleaned 4=error)
echo.
pause
exit /b 0
:cancel
echo Cancelled.
pause
exit /b 0