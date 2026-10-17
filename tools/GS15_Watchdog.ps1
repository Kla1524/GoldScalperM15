# GS15_Watchdog.ps1 - looks after the live MT5 while the PC is on (v1.51).
# Every 2 minutes during market hours (Mon 04:05 - Sat 03:50 Thai time) it checks:
#   - the live MT5 (D:\MT5_GoldScalper\terminal64.exe) is running;
#   - the EA status file was written in the last 3 minutes (EA attached and running).
# On a problem it shows a Windows notification once per incident and writes _watchdog\watchdog_log.txt.
# It never starts, stops or trades anything. (A PC that is off cannot warn; the EA then reports the gap
# on the phone when it starts again.)
# Pause it: create D:\MT5_GoldScalper\_watchdog\PAUSE  (delete the file to resume).
param([int]$EveryMin = 2, [switch]$Once)
$Live   = 'D:\MT5_GoldScalper\terminal64.exe'
$Status = "$env:APPDATA\MetaQuotes\Terminal\Common\Files\GS15_GOLD_20261013_status.txt"
$Dir    = 'D:\MT5_GoldScalper\_watchdog'
New-Item -ItemType Directory -Force $Dir | Out-Null
$Log = "$Dir\watchdog_log.txt"
function Log([string]$m) { Add-Content $Log ('{0:yyyy-MM-dd HH:mm:ss}  {1}' -f (Get-Date), $m) -Encoding UTF8 }

function MarketOpen {
    $n = Get-Date
    switch ($n.DayOfWeek) {
        'Sunday'   { return $false }
        'Monday'   { return $n.TimeOfDay -ge [timespan]'04:05' }
        'Saturday' { return $n.TimeOfDay -lt [timespan]'03:50' }
        default    { return $true }
    }
}

function Toast([string]$title, [string]$text) {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    $n = New-Object System.Windows.Forms.NotifyIcon
    $n.Icon = [System.Drawing.SystemIcons]::Warning
    $n.Visible = $true
    $n.ShowBalloonTip(15000, $title, $text, [System.Windows.Forms.ToolTipIcon]::Warning)
    Start-Sleep 16
    $n.Dispose()
}

function Check {
    if (Test-Path "$Dir\PAUSE") { return 'paused' }
    if (-not (MarketOpen)) { return 'market closed' }
    $p = Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.ExecutablePath -eq $Live }
    if (-not $p) { return 'PROBLEM: MT5 GoldScalper is not running' }
    if (-not (Test-Path $Status)) { return 'PROBLEM: no EA status file - is the EA on the chart?' }
    $age = ((Get-Date) - (Get-Item $Status).LastWriteTime).TotalMinutes
    if ($age -gt 3) { return ('PROBLEM: EA status not updated for {0:N0} min - EA removed, AutoTrading off or MT5 frozen' -f $age) }
    return 'ok'
}

Log "watchdog started (every $EveryMin min)"
$last = ''
do {
    $r = Check
    if ($r -ne $last) {
        Log $r
        if ($r -like 'PROBLEM*') { Toast 'GoldScalper watchdog' ($r.Substring(9) + ' (' + (Get-Date -Format 'HH:mm') + ')') }
        elseif ($last -like 'PROBLEM*' -and $r -eq 'ok') { Toast 'GoldScalper watchdog' 'Back to normal: MT5 and the EA are running' }
        $last = $r
    }
    if (-not $Once) { Start-Sleep ($EveryMin * 60) }
} while (-not $Once)
