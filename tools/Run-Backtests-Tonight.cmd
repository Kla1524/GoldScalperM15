@echo off
rem Backtest suite on the portable MT5 (D:\MT5_GoldScalper): waits until 00:15, no new run after 07:30.
rem Leave the PC on. Closes MT5 only when the EA has no open position, and starts it again at the end.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0night_suite.ps1" -StartAt 00:15 -StopAt 07:30
pause
