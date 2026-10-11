@echo off
setlocal EnableExtensions DisableDelayedExpansion
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Build-HelloWorld.ps1" %*
exit /b %ERRORLEVEL%
