@echo off
rem Opens the GoldScalperM15 PowerShell console (live status, colour event log, commands).
rem Optional: GS15_Console.bat -Symbol GOLD -Magic 20261013
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\GS15_Console.ps1" %*
