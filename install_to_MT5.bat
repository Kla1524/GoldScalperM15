@echo off
chcp 65001 >nul
setlocal
rem Compile GoldScalperM15 in this folder, then copy it (and presets) into MT5.

set "EA=GoldScalperM15"
set "SRC=%~dp0"
set "ME=C:\Program Files\MetaTrader 5\MetaEditor64.exe"

echo ==============================================
echo   ติดตั้ง / อัปเดต %EA% เข้า MetaTrader 5
echo ==============================================
echo.

if not exist "%ME%" (
  echo [ผิดพลาด] ไม่พบ MetaEditor ที่ "%ME%"
  goto :fail
)

rem Find the MT5 data folder that belongs to C:\Program Files\MetaTrader 5
set "DATA="
for /d %%D in ("%APPDATA%\MetaQuotes\Terminal\*") do (
  if exist "%%D\origin.txt" (
    type "%%D\origin.txt" | find /i "Program Files\MetaTrader 5" >nul && set "DATA=%%D\MQL5"
  )
)
if not defined DATA (
  echo [ผิดพลาด] หาโฟลเดอร์ข้อมูลของ MT5 ไม่เจอ - เปิด MT5 ให้ได้อย่างน้อย 1 ครั้งก่อน
  goto :fail
)

echo จะติดตั้งไปที่: %DATA%\Experts\MyEA
echo.
choice /c YN /m "ดำเนินการต่อ? (Y = ใช่, N = ยกเลิก)"
if errorlevel 2 goto :cancel

echo.
echo [1/3] คอมไพล์ %EA%.mq5 ...
if exist "%SRC%%EA%.ex5" del "%SRC%%EA%.ex5"
start "" /wait "%ME%" /compile:"%SRC%%EA%.mq5" /include:"%DATA%" /log:"%SRC%compile.log"
if not exist "%SRC%%EA%.ex5" (
  echo [ผิดพลาด] คอมไพล์ไม่ผ่าน - เปิดดูรายละเอียดใน compile.log
  goto :fail
)
echo       ผ่าน

echo [2/3] คัดลอก EA ไปที่ MT5 ...
if not exist "%DATA%\Experts\MyEA" mkdir "%DATA%\Experts\MyEA"
copy /y "%SRC%%EA%.ex5" "%DATA%\Experts\MyEA\" >nul || goto :fail
copy /y "%SRC%%EA%.mq5" "%DATA%\Experts\MyEA\" >nul || goto :fail
echo       เรียบร้อย

echo [3/3] คัดลอกไฟล์ตั้งค่า (.set) ...
if not exist "%DATA%\Presets" mkdir "%DATA%\Presets"
copy /y "%SRC%presets\*.set" "%DATA%\Presets\" >nul || goto :fail
echo       เรียบร้อย

echo.
echo ติดตั้งสำเร็จ! ใน MT5 กด Ctrl+N แล้วดูที่ Expert Advisors ^> MyEA ^> %EA%
echo (ถ้า EA ติดกราฟอยู่แล้ว MT5 จะโหลดเวอร์ชันใหม่ให้อัตโนมัติ)
goto :end

:cancel
echo ยกเลิกแล้ว ไม่ได้เปลี่ยนแปลงอะไรใน MT5
goto :end

:fail
echo.
echo ติดตั้งไม่สำเร็จ

:end
echo.
pause
