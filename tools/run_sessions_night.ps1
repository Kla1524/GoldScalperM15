# Runs the session tests after midnight Thai (demo idle: no position, no entries until 12:00).
$log = 'D:\EA_Trade_lab\lab\sessions_night.out'
function L($m) { Add-Content $log ('{0:yyyy-MM-dd HH:mm:ss}  {1}' -f (Get-Date), $m) }
$start = (Get-Date).Date.AddDays(1).AddMinutes(10)
if ((Get-Date).Hour -lt 6) { $start = (Get-Date).Date.AddMinutes(10) }
L "waiting until $start"
while ((Get-Date) -lt $start) { Start-Sleep 30 }
for ($i = 0; $i -lt 30; $i++) {
    Start-Process explorer.exe 'D:\EA_Trade_lab\live_ops\snapshot.cmd'; Start-Sleep 10
    $pos = (Get-Content D:\EA_Trade_lab\live_ops\live_status.txt -Encoding Unicode | Select-String '^position=').Line
    if ($pos -eq 'position=none') { break }
    L "demo has a position ($pos) - waiting"; Start-Sleep 60
}
L 'starting the session suite'
& powershell -ExecutionPolicy Bypass -File D:\EA_Trade_lab\lab\tools\night_suite.ps1 -Terminal D:\MT5_Tester -NoRestart -Now -StopAt 11:00 -Source GS_Sessions_Lab -Plan D:\EA_Trade_lab\lab\tools\plans\sessions_20261022.ps1 -SuiteName suite_20261022_sessions *>> $log
$live = Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'" | Where-Object { $_.ExecutablePath -eq 'D:\MT5_GoldScalper\terminal64.exe' }
if (-not $live) { L 'demo MT5 not running - starting it'; Start-Process explorer.exe 'D:\EA_Trade_lab\live_ops\start_live.cmd'; Start-Sleep 45 }
Start-Process explorer.exe 'D:\EA_Trade_lab\live_ops\verify.cmd'; Start-Sleep 10
L ('verify: ' + (Get-Content D:\EA_Trade_lab\live_ops\live_ops_log.txt -Tail 1))
L 'night run finished'
