@echo off
rem Backtest suite on the portable MT5 (D:\MT5_GoldScalper), starting now. For weekends / market closed.
rem Closes MT5 only when the EA has no open position, and starts it again at the end.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0night_suite.ps1" -Now -StopAt 23:59
pause
