@echo off
rem ================================================================
rem  d-kimi.bat - switch Claude Code to the Kimi K3 config (kimi-settings)
rem  Runs from PATH or double-click; all logic lives in deploy.ps1.
rem  API key comes from the KIMI_API_KEY environment variable.
rem ================================================================
setlocal
set "PSCMD=powershell"
where pwsh >nul 2>nul && set "PSCMD=pwsh"

"%PSCMD%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy.ps1" -KeyEnvName KIMI_API_KEY -ProfileLabel "Kimi K3 (kimi)" -AgentAction deploy
set "EXITCODE=%ERRORLEVEL%"

rem Pause only when double-clicked (launched via explorer), not from a terminal
echo %cmdcmdline% | find /i "%~f0" >nul 2>nul && pause
exit /b %EXITCODE%
