@echo off
chcp 65001 >nul
setlocal
rem Compile GoldScalperM15 in this folder, then copy it (and presets) into MT5.

set "EA=GoldScalperM15"
set "SRC=%~dp0"
set "ME=C:\Program Files\MetaTrader 5\MetaEditor64.exe"
rem A portable MT5 (terminal64.exe /portable) keeps its data next to the program. Used when present.
set "PORTABLE=D:\MT5_GoldScalper"
set "PFLAG="
if exist "%PORTABLE%\MetaEditor64.exe" (
  set "ME=%PORTABLE%\MetaEditor64.exe"
  set "DATA=%PORTABLE%\MQL5"
  set "PFLAG=/portable"
)

echo ==============================================
echo   Install / update %EA% in MetaTrader 5
echo ==============================================
echo.

if not exist "%ME%" (
  echo [ERROR] MetaEditor not found at "%ME%"
  echo         Edit the ME= line in this file if MT5 is installed elsewhere.
  goto :fail
)

rem Find the MT5 data folder that belongs to C:\Program Files\MetaTrader 5
if defined PFLAG goto :found
set "DATA="
for /d %%D in ("%APPDATA%\MetaQuotes\Terminal\*") do (
  if exist "%%D\origin.txt" (
    type "%%D\origin.txt" | find /i "Program Files\MetaTrader 5" >nul && set "DATA=%%D\MQL5"
  )
)
if not defined DATA (
  echo [ERROR] MT5 data folder not found - start MT5 at least once first.
  goto :fail
)
:found

echo Install to: %DATA%\Experts\MyEA
echo.
choice /c YN /m "Continue? (Y = yes, N = cancel)"
if errorlevel 2 goto :cancel

echo.
echo [1/3] Compiling %EA%.mq5 ...
if exist "%SRC%%EA%.ex5" del "%SRC%%EA%.ex5"
start "" /wait "%ME%" %PFLAG% /compile:"%SRC%%EA%.mq5" /include:"%DATA%" /log:"%SRC%compile.log"
if not exist "%SRC%%EA%.ex5" (
  echo [ERROR] Compilation failed - see compile.log for details.
  goto :fail
)
echo       OK

echo [2/3] Copying the EA to MT5 ...
if not exist "%DATA%\Experts\MyEA" mkdir "%DATA%\Experts\MyEA"
copy /y "%SRC%%EA%.ex5" "%DATA%\Experts\MyEA\" >nul || goto :fail
copy /y "%SRC%%EA%.mq5" "%DATA%\Experts\MyEA\" >nul || goto :fail
echo       Done

echo [3/3] Copying presets (.set) ...
if not exist "%DATA%\Presets" mkdir "%DATA%\Presets"
copy /y "%SRC%presets\*.set" "%DATA%\Presets\" >nul || goto :fail
echo       Done

echo.
echo Installed! In MT5 press Ctrl+N and open Expert Advisors ^> MyEA ^> %EA%
echo (If the EA is already on a chart, MT5 reloads the new version automatically.)
goto :end

:cancel
echo Cancelled - nothing was changed in MT5.
goto :end

:fail
echo.
echo Installation failed.

:end
echo.
pause
