# GoldScalperM15 console - live status, colour event log and commands for the EA.
#
# The EA (InpConsole = true, live/demo chart) writes to MT5's common Files folder:
#   GS15_<symbol>_<magic>_status.txt   current state, rewritten every second
#   GS15_<symbol>_<magic>_log.txt      events (opened, closed, skipped, news, warnings)
# and reads one command from GS15_<symbol>_<magic>_cmd.txt (MODE1, MODE2, PAUSE, RESUME, CLOSEALL).
#
# Start it with GS15_Console.bat (double-click), or:
#   powershell -ExecutionPolicy Bypass -File tools\GS15_Console.ps1 [-Symbol GOLD] [-Magic 20261013]

param(
    [string]$Symbol = '',
    [string]$Magic  = '',
    [string]$Dir    = "$env:APPDATA\MetaQuotes\Terminal\Common\Files"
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = 'GoldScalperM15 console'
try { [Console]::CursorVisible = $false } catch {}

$colors = @{
    INFO = 'Gray'; OPEN = 'Cyan'; WIN = 'Green'; LOSS = 'Red'
    SKIP = 'Yellow'; WARN = 'Magenta'; NEWS = 'DarkCyan'
}
$icons = @{
    INFO = '·'; OPEN = '▲'; WIN = '✔'; LOSS = '✖'; SKIP = '⊘'; WARN = '⚠'; NEWS = '»'
}

function Read-Shared([string]$path) {
    # The EA may be writing at the same moment: open with full sharing, retry briefly.
    for ($i = 0; $i -lt 3; $i++) {
        try {
            $fs = [IO.File]::Open($path, 'Open', 'Read', 'ReadWrite, Delete')
            try {
                $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::Unicode, $true)
                return $sr.ReadToEnd()
            } finally { $fs.Dispose() }
        } catch { Start-Sleep -Milliseconds 100 }
    }
    return $null
}

function Find-Base {
    $pattern = 'GS15_*_status.txt'
    if ($Symbol -and $Magic) { $pattern = "GS15_${Symbol}_${Magic}_status.txt" }
    elseif ($Symbol)         { $pattern = "GS15_${Symbol}_*_status.txt" }
    $f = Get-ChildItem -Path $Dir -Filter $pattern -ErrorAction SilentlyContinue |
         Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($f) { return $f.FullName -replace '_status\.txt$', '' }
    return $null
}

function Send-Command([string]$base, [string]$cmd) {
    [IO.File]::WriteAllText("${base}_cmd.txt", $cmd, [Text.Encoding]::ASCII)
}

function Write-Line([string]$text, [string]$color = 'Gray', [int]$width) {
    if ($text.Length -ge $width) { $text = $text.Substring(0, [Math]::Max(0, $width - 1)) }
    Write-Host ($text.PadRight($width - 1)) -ForegroundColor $color
}

function Ask([string]$question) {
    [Console]::CursorVisible = $true
    Write-Host ''
    $answer = Read-Host $question
    try { [Console]::CursorVisible = $false } catch {}
    return $answer
}

$modeText = @'
Mode 1: one bigger trade a day
  - Only the first range breakout of the day, 1% risk per trade (InpRiskPct)
  - Tested 2018-2026 ($3,000): +89%, PF 1.45, max DD 14.8%
  - For: maximum profit, accepting 15-20% drawdowns

Mode 2: several smaller trades
  - Every breakout that meets the rules, no daily limit, 0.5% risk per trade (InpMultiRiskPct)
  - Needs about twice the balance of mode 1, or most signals are skipped
  - For: a steadier account, with less profit

The 2nd-3rd trades of a day lose more often; mode 2 is steadier because each trade is smaller.
'@

$base = $null
$logCache = @()
$logStamp = [datetime]::MinValue
Clear-Host

while ($true) {
    if (-not $base) {
        $base = Find-Base
        if (-not $base) {
            [Console]::SetCursorPosition(0, 0)
            $w = [Console]::WindowWidth
            Write-Line 'GoldScalperM15 console' 'Yellow' $w
            Write-Line '' 'Gray' $w
            Write-Line 'Waiting for the EA...' 'Gray' $w
            Write-Line ' - Attach GoldScalperM15 v1.40+ to a chart on a live or demo account' 'Gray' $w
            Write-Line ' - Keep InpConsole = true (default)' 'Gray' $w
            Write-Line " - Looking in: $Dir" 'DarkGray' $w
            Write-Line '' 'Gray' $w
            Write-Line 'Press Q to quit.' 'DarkGray' $w
            if ([Console]::KeyAvailable -and ([Console]::ReadKey($true).Key -eq 'Q')) { break }
            Start-Sleep -Seconds 1
            continue
        }
        Clear-Host
    }

    # ---- read status
    $statusFile = "${base}_status.txt"
    $st = @{}
    $raw = if (Test-Path $statusFile) { Read-Shared $statusFile } else { $null }
    if ($raw) {
        foreach ($line in ($raw -split "`r?`n")) {
            $i = $line.IndexOf('=')
            if ($i -gt 0) { $st[$line.Substring(0, $i)] = $line.Substring($i + 1) }
        }
    }
    $age = if (Test-Path $statusFile) { ((Get-Date) - (Get-Item $statusFile).LastWriteTime).TotalSeconds } else { 999 }

    # ---- read log (only when it changed)
    $logFile = "${base}_log.txt"
    if (Test-Path $logFile) {
        $stamp = (Get-Item $logFile).LastWriteTime
        if ($stamp -ne $logStamp) {
            $text = Read-Shared $logFile
            if ($text) { $logCache = @($text -split "`r?`n" | Where-Object { $_ -ne '' }) }
            $logStamp = $stamp
        }
    }

    # ---- draw
    $w = [Console]::WindowWidth
    $h = [Console]::WindowHeight
    [Console]::SetCursorPosition(0, 0)
    $sep = '─' * ($w - 1)

    $acct = $st['account']
    $acctColor = if ($acct -match 'REAL') { 'Red' } else { 'White' }
    Write-Line ("{0} | {1} | {2} | Equity {3}" -f $st['version'], $st['symbol'], $acct, $st['equity']) $acctColor $w
    if ($acct -match 'REAL') { Write-Line '!! REAL MONEY ACCOUNT !!' 'Red' $w }
    if ($age -gt 10) {
        Write-Line ("EA not updating for {0:N0} s - MT5 closed, EA removed, or no connection" -f $age) 'Red' $w
    } else {
        $sColor = if ($st['paused'] -eq '1') { 'Yellow' } elseif ($st['status'] -match 'Ready|พร้อม') { 'Green' } elseif ($st['status'] -match 'In a trade|ถือ') { 'Cyan' } else { 'Yellow' }
        Write-Line ("Status:   {0}" -f $st['status']) $sColor $w
    }
    Write-Line ("Mode:     {0}" -f $st['modetext']) 'DarkYellow' $w
    $pColor = if ($st['position'] -match 'P/L -') { 'Red' } elseif ($st['position'] -match 'BUY|SELL') { 'Cyan' } else { 'Gray' }
    Write-Line ("Trade:    {0}" -f $st['position']) $pColor $w
    $tColor = if ($st['today'] -match 'P/L -') { 'Red' } else { 'Gray' }
    Write-Line ("Today:    {0}" -f $st['today']) $tColor $w
    Write-Line ("Market:   {0} | Next news: {1}" -f $st['market'], $st['news']) 'Gray' $w
    $pauseKey = if ($st['paused'] -eq '1') { '[P] Resume' } else { '[P] Pause' }
    Write-Line ("Keys:     [1] Mode 1   [2] Mode 2   {0}   [C] Close all   [L] Full log   [Q] Quit" -f $pauseKey) 'White' $w
    Write-Line ($sep.Substring(0, [Math]::Min($sep.Length, 20)) + ' events, newest first ' + $sep) 'DarkGray' $w

    # Newest first, so the latest event is always on screen whatever the window height.
    $headerRows = [Console]::CursorTop
    $room = [Math]::Max(3, $h - $headerRows - 2)
    $tail = @(if ($logCache.Count -gt $room) { $logCache[($logCache.Count - $room)..($logCache.Count - 1)] } else { $logCache })
    [array]::Reverse($tail)
    foreach ($entry in $tail) {
        $parts = $entry -split "`t", 3
        if ($parts.Count -lt 3) { Write-Line $entry 'Gray' $w; continue }
        $time = $parts[0]; if ($time.Length -ge 16) { $time = $time.Substring(5) }   # MM.DD HH:MM:SS
        $kind = $parts[1].Trim()
        $icon = if ($icons.ContainsKey($kind)) { $icons[$kind] } else { ' ' }
        $col  = if ($colors.ContainsKey($kind)) { $colors[$kind] } else { 'Gray' }
        Write-Line ("{0}  {1} {2}" -f $time, $icon, $parts[2]) $col $w
    }
    for ($i = $tail.Count; $i -lt $room; $i++) { Write-Line '' 'Gray' $w }

    # ---- keys
    $deadline = (Get-Date).AddSeconds(1)
    while ((Get-Date) -lt $deadline) {
        if (-not [Console]::KeyAvailable) { Start-Sleep -Milliseconds 100; continue }
        $key = [Console]::ReadKey($true).KeyChar.ToString().ToUpper()
        switch ($key) {
            { $_ -in '1', '2' } {
                Clear-Host
                Write-Host $modeText -ForegroundColor Gray
                Write-Host ("Current: {0}" -f $st['modetext']) -ForegroundColor DarkYellow
                if ($st['mode'] -eq $key) { [void](Ask "Mode $key is already active - press Enter") }
                elseif ((Ask "Switch to mode $key ? (y/n)") -match '^[yY]') { Send-Command $base "MODE$key" }
                Clear-Host
            }
            'P' {
                $cmd = if ($st['paused'] -eq '1') { 'RESUME' } else { 'PAUSE' }
                Send-Command $base $cmd
            }
            'C' {
                Clear-Host
                Write-Host ("Open trade: {0}" -f $st['position']) -ForegroundColor Cyan
                if ((Ask 'Type CLOSE to close all trades of this EA (anything else cancels)') -ceq 'CLOSE') { Send-Command $base 'CLOSEALL' }
                Clear-Host
            }
            'L' { if (Test-Path $logFile) { Start-Process notepad.exe $logFile } }
            'Q' { try { [Console]::CursorVisible = $true } catch {}; Clear-Host; exit }
        }
        break
    }
}
