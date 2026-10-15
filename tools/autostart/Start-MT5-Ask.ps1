# Runs at Windows logon (Startup shortcut "MT5 GoldScalper Ask"): asks Yes / No, then starts the
# trading MT5 (D:\MT5_GoldScalper, portable) if it is not running yet. Does nothing to any other MT5.
#   Install / remove: Install-Autostart.cmd / Remove-Autostart.cmd in this folder.
param([switch]$Test)   # -Test: show the question only, start nothing
$exe = 'D:\MT5_GoldScalper\terminal64.exe'
$log = Join-Path $PSScriptRoot 'autostart_log.txt'
function Say($t) { Add-Content $log ("{0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $t) }

if (-not $Test -and (Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.ExecutablePath -eq $exe })) {
    Say 'already running - not asked'
    return
}

Add-Type -AssemblyName System.Windows.Forms
$owner = New-Object System.Windows.Forms.Form -Property @{ TopMost = $true; ShowInTaskbar = $false; WindowState = 'Minimized' }
$owner.Show(); $owner.Hide()
$answer = [System.Windows.Forms.MessageBox]::Show($owner,
    "เปิด MT5 GoldScalper (บัญชี Demo + EA) ตอนนี้เลยไหม?`n`nYes = เปิดและให้ EA เริ่มทำงาน`nNo = ยังไม่เปิด (เปิดเองทีหลังได้จากไอคอน MT5 GoldScalper)",
    'GoldScalper - เปิดเครื่องแล้ว', 'YesNo', 'Question')
$owner.Dispose()

if ($Test) { Say "test - answer $answer (nothing started)"; return }
if ($answer -eq 'Yes') {
    Start-Process $exe -ArgumentList '/portable' -WorkingDirectory (Split-Path $exe)
    Say 'answer Yes - MT5 GoldScalper started'
} else {
    Say 'answer No - not started'
}
