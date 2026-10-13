#requires -Version 5.1
<#
.SYNOPSIS
GoldScalperM15 console: live status, event journal and commands for the EA.

.DESCRIPTION
The EA (InpConsole = true, live or demo chart) writes to MT5's common Files folder:
  GS15_<symbol>_<magic>_status.txt   current state, rewritten every second
  GS15_<symbol>_<magic>_log.txt      events (opened, closed, skipped, news, warnings)
and reads one command from GS15_<symbol>_<magic>_cmd.txt (MODE1, MODE2, PAUSE, RESUME, CLOSEALL).

Start it with GS15_Console.bat (double-click), or:
  powershell -ExecutionPolicy Bypass -File tools\GS15_Console.ps1 [-Symbol GOLD] [-Magic 20261013] [-NoColor]

Keys: 1 / 2 switch mode (both explained, then y/n), P pause / resume, C close all (type CLOSE),
L longer journal, O full log in Notepad, Q quit. Best in Windows Terminal, at least 80 x 24.
#>
[CmdletBinding()]
param(
    [string]$Symbol = '',
    [string]$Magic  = '',
    [string]$Dir    = "$env:APPDATA\MetaQuotes\Terminal\Common\Files",
    [switch]$NoColor
)

$ErrorActionPreference = 'Stop'
$script:Esc     = [string][char]27
$script:Inv     = [Globalization.CultureInfo]::InvariantCulture
$script:Rows    = New-Object 'System.Collections.Generic.List[string]'
$script:Width   = 100
$script:Height  = 30
$script:LongLog = $false
$script:Feedback = ''
$script:Palette = @{
    Text  = '232;238;248'; Muted = '154;171;196'; Accent = '112;170;255'; Amber = '239;188;99'
    Red   = '255;131;146'; Green = '120;214;150'; Blue = '145;186;255';   Line  = '34;54;83'
}
$script:Bg = '6;10;18'

# Windows PowerShell 5.1 in the old console host needs VT processing switched on for colours.
function Enable-Vt {
    try {
        Add-Type -Namespace GS15 -Name Vt -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int h);
[DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr h, out uint m);
[DllImport("kernel32.dll")] public static extern bool SetConsoleMode(IntPtr h, uint m);
'@
        $h = [GS15.Vt]::GetStdHandle(-11)
        $m = [uint32]0
        if (-not [GS15.Vt]::GetConsoleMode($h, [ref]$m)) { return $false }
        return [GS15.Vt]::SetConsoleMode($h, $m -bor 4)
    } catch { return $false }
}
$script:UseAnsi = (-not $NoColor) -and (-not [Console]::IsOutputRedirected) -and (Enable-Vt)

#--- files -----------------------------------------------------------
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

function Send-Command([string]$cmd) {
    [IO.File]::WriteAllText("$($script:Base)_cmd.txt", $cmd, [Text.Encoding]::ASCII)
}

function Read-Status {
    $st = @{}
    $file = "$($script:Base)_status.txt"
    if (-not (Test-Path $file)) { $script:Age = 999; return $st }
    $raw = Read-Shared $file
    if ($raw) {
        foreach ($line in ($raw -split "`r?`n")) {
            $i = $line.IndexOf('=')
            if ($i -gt 0) { $st[$line.Substring(0, $i)] = $line.Substring($i + 1) }
        }
    }
    $script:Age = ((Get-Date) - (Get-Item $file).LastWriteTime).TotalSeconds
    return $st
}

$script:LogCache = @()
$script:LogStamp = [datetime]::MinValue
function Read-Log {
    $file = "$($script:Base)_log.txt"
    if (-not (Test-Path $file)) { return }
    $stamp = (Get-Item $file).LastWriteTime
    if ($stamp -eq $script:LogStamp) { return }
    $text = Read-Shared $file
    if ($text) { $script:LogCache = @($text -split "`r?`n" | Where-Object { $_ -ne '' }) }
    $script:LogStamp = $stamp
}

#--- drawing ---------------------------------------------------------
function Format-Text([object]$Value, [int]$Length) {
    if ($Length -le 0) { return '' }
    $t = [regex]::Replace([string]$Value, '[\x00-\x1f\x7f]', ' ')
    if ($t.Length -gt $Length) {
        if ($Length -lt 4) { return $t.Substring(0, $Length) }
        return $t.Substring(0, $Length - 3) + '...'
    }
    return $t.PadRight($Length)
}

function Add-Line([string]$Text = '', [string]$Tone = 'Text') {
    $line = Format-Text $Text $script:Width
    if ($script:UseAnsi) {
        $rgb = $script:Palette[$Tone]; if (-not $rgb) { $rgb = $script:Palette.Text }
        $bg = if ($Tone -eq 'Accent' -or $Tone -eq 'Blue') { '13;27;50' } else { $script:Bg }
        $line = "$($script:Esc)[48;2;$($bg)m$($script:Esc)[38;2;$($rgb)m$line$($script:Esc)[K"
    }
    [void]$script:Rows.Add($line)
}

# One line made of cells, each with its own colour: @(@(text, tone, width), ...)
function Add-Cells($cells) {
    $line = ''
    foreach ($c in $cells) {
        $t = Format-Text $c[0] $c[2]
        if ($script:UseAnsi) { $t = "$($script:Esc)[48;2;$($script:Bg)m$($script:Esc)[38;2;$($script:Palette[$c[1]])m$t" }
        $line += $t
    }
    if ($script:UseAnsi) { $line += "$($script:Esc)[K" }
    [void]$script:Rows.Add($line)
}

function Add-Pair([string]$Left, [string]$Right, [string]$Tone = 'Text') {
    $col = [int][math]::Floor(($script:Width - 8) / 2)
    Add-Line ('  ' + (Format-Text $Left $col) + '    ' + $Right) $Tone
}

function Num([string]$v, [string]$fmt = 'N2') {
    $d = 0.0
    if ([double]::TryParse($v, [Globalization.NumberStyles]::Float, $script:Inv, [ref]$d)) { return $d.ToString($fmt, $script:Inv) }
    if ($v) { return $v }
    return '--'
}

function Get-Number([string]$v) {
    $d = 0.0
    if ([double]::TryParse($v, [Globalization.NumberStyles]::Float, $script:Inv, [ref]$d)) { return $d }
    return [double]::NaN
}

function Show-Frame {
    $frame = $script:Rows -join [Environment]::NewLine
    if ($script:UseAnsi) {
        [Console]::Write("$($script:Esc)[H$frame$($script:Esc)[48;2;$($script:Bg)m$($script:Esc)[J")
    } else {
        [Console]::SetCursorPosition(0, 0)
        [Console]::Write($frame)
        $blank = ' ' * $script:Width
        for ($i = $script:Rows.Count; $i -lt $script:Height; $i++) { [Console]::Write([Environment]::NewLine + $blank) }
    }
}

function Measure-Window {
    try {
        $script:Width  = [math]::Min(128, [Console]::WindowWidth - 1)
        $script:Height = [Console]::WindowHeight - 1
    } catch {}
}

$script:Tones = @{ OPEN = 'Blue'; WIN = 'Green'; LOSS = 'Red'; SKIP = 'Amber'; WARN = 'Amber'; NEWS = 'Accent'; INFO = 'Text' }

function Render-Frame($st) {
    $script:Rows.Clear()
    Measure-Window
    $rule = '  ' + ('-' * ($script:Width - 4))

    if ($script:Width -lt 79 -or $script:Height -lt 22) {
        Add-Line ' GoldScalper console' 'Accent'
        Add-Line ' Make this window at least 80 columns x 24 rows.' 'Amber'
        Add-Line ' Q = quit.' 'Muted'
        return
    }

    $ccy  = $st['ccy']
    $real = $st['accttype'] -eq 'REAL'
    $ver  = ($st['version'] -replace '^\S+\s+', '')
    $acct = ($st['account'] -replace '\s*\(.*\)$', '')
    Add-Pair "GOLDSCALPER / v$ver" ("LIVE EA | " + $(if ($real) { 'REAL MONEY' } else { 'DEMO' })) $(if ($real) { 'Red' } else { 'Accent' })
    Add-Pair "ASIAN RANGE BREAKOUT | $($st['symbol']) / $($st['tf'])" "Account $acct | $ccy" 'Muted'
    Add-Line $rule 'Line'

    # Status
    if ($script:Age -gt 10) {
        Add-Line ("  DATA STALE - EA not updating for {0:N0} s" -f $script:Age) 'Red'
        Add-Line '  MT5 closed, EA removed from the chart, or no connection. Values below are old.' 'Muted'
    } else {
        $state = $st['state']
        $tone = switch ($state) { 'READY' { 'Green' } 'IN TRADE' { 'Blue' } 'HALTED' { 'Red' } default { 'Amber' } }
        Add-Line ('  ' + $state) $tone
        Add-Line ('  ' + $st['reason']) 'Muted'
    }
    Add-Line

    # Account
    $cell = [int][math]::Floor(($script:Width - 6) / 3)
    Add-Line ('  ' + (Format-Text 'ACCOUNT EQUITY' $cell) + (Format-Text "TODAY P/L ($ccy)" $cell) + 'OPEN TRADE P/L') 'Muted'
    $pl = Get-Number $st['plv']
    $plTone = if ($pl -lt 0) { 'Red' } elseif ($pl -gt 0) { 'Green' } else { 'Text' }
    # position = "BUY 0.03 @ 4123.45 | SL 4091.20 | P/L -12.40 USD" or "none"
    $posText = $st['position']
    $hasPos = $posText -match '^(BUY|SELL)'
    $float = '--'; $floatTone = 'Text'
    if ($hasPos -and $posText -match 'P/L (-?[\d.]+)') {
        $float = Num $Matches[1]
        $floatTone = if ([double]::Parse($Matches[1], $script:Inv) -lt 0) { 'Red' } else { 'Green' }
    }
    Add-Cells @(
        @('  ', 'Text', 2),
        @(((Num $st['eqv']) + " $ccy"), 'Text', $cell),
        @((Num $st['plv']), $plTone, $cell),
        @($float, $floatTone, ($script:Width - 2 - 2 * $cell)))
    if ($hasPos) { Add-Line ('  Position  ' + ($posText -replace '\s*\|\s*P/L.*$', '')) 'Blue' }
    else { Add-Line '  Position  none' 'Muted' }
    Add-Line $rule 'Line'

    # 01 / 02
    Add-Pair '01  TRADE CONFIGURATION' '02  MARKET CONDITIONS' 'Accent'
    $modeName = if ($st['mode'] -eq '2') { '02 / Multiple entries' } else { '01 / Single entry' }
    $cap = if ($st['maxtrades'] -eq '0') { 'not limited' } else { $st['maxtrades'] }
    $ra = Get-Number $st['riskactual']
    $actual = if ($ra -ge 0) { $ra.ToString('N2', $script:Inv) + '%' } else { '-- / no position' }
    $target = if ((Get-Number $st['risktarget']) -gt 0) { (Num $st['risktarget']) + '%' } else { 'fixed lot' }
    $news = if ($st['news'] -and $st['news'] -ne '-') { $st['news'] } else { 'none in 24 h' }
    Add-Pair ("Active mode      $modeName") ("Spread / limit   " + (Num $st['spreadv']) + ' / ' + (Num $st['spreadmax']))
    Add-Pair ("Target risk      $target")    ("ATR (M15)        " + (Num $st['atrv']))
    Add-Pair ("Actual risk      $actual")    ("Next news        $news")
    Add-Pair ("Entries / cap    $($st['trades']) / $cap") ("Server time      " + $st['servertime'])
    $dd = "{0}% / halt at {1}%" -f (Num $st['ddv']), (Num $st['ddmax'] 'N0')
    $streak = "$($st['streak']) / halt at $($st['streakmax'])"
    if ($st['ddmax'] -match '^0(\.0+)?$') { $dd = (Num $st['ddv']) + '% / no halt' }
    if ($st['streakmax'] -eq '0') { $streak = "$($st['streak']) / no halt" }
    Add-Pair ("Losses in a row  $streak") ("Drawdown         $dd")
    Add-Line $rule 'Line'

    # 03 journal, newest first
    Add-Pair '03  EVENT JOURNAL' 'Newest first' 'Accent'
    $room = [math]::Max(1, $script:Height - $script:Rows.Count - 4)
    if (-not $script:LongLog) { $room = [math]::Min($room, 8) }
    $tail = @(if ($script:LogCache.Count -gt $room) { $script:LogCache[($script:LogCache.Count - $room)..($script:LogCache.Count - 1)] } else { $script:LogCache })
    [array]::Reverse($tail)
    foreach ($entry in $tail) {
        $parts = $entry -split "`t", 3
        if ($parts.Count -lt 3) { Add-Line ('  ' + $entry) 'Muted'; continue }
        $time = $parts[0]; if ($time.Length -ge 16) { $time = $time.Substring(5) }   # MM.DD HH:MM:SS
        $kind = $parts[1].Trim()
        $tone = if ($script:Tones.ContainsKey($kind)) { $script:Tones[$kind] } else { 'Text' }
        Add-Line ('  ' + (Format-Text $time 16) + (Format-Text $kind 6) + $parts[2]) $tone
    }
    if ($tail.Count -eq 0) { Add-Line '  No events yet.' 'Muted' }
    Add-Line
    Add-Line $rule 'Line'
    $pauseKey = if ($st['paused'] -eq '1') { '[P] Resume' } else { '[P] Pause' }
    $logKey = if ($script:LongLog) { '[L] Short log' } else { '[L] Long log' }
    Add-Line "  [1] Mode 01  [2] Mode 02  $pauseKey  [C] Close all  $logKey  [O] Open log  [Q] Quit" 'Blue'
    if ($script:Feedback) { Add-Line ('  ' + $script:Feedback) 'Muted' }
}

function Render-Waiting {
    $script:Rows.Clear()
    Measure-Window
    Add-Line ' GOLDSCALPER / console' 'Accent'
    Add-Line
    Add-Line ' Waiting for the EA...' 'Amber'
    Add-Line ' - Attach GoldScalperM15 v1.40+ to a chart on a live or demo account' 'Muted'
    Add-Line ' - Keep InpConsole = true (default)' 'Muted'
    Add-Line " - Looking in: $Dir" 'Muted'
    Add-Line
    Add-Line ' [Q] Quit' 'Blue'
}

# Full-screen question in the console's own style. Returns the typed text (or the key for single-key answers).
function Ask-Dialog([string[]]$lines, [string]$prompt, [switch]$Line) {
    $script:Rows.Clear()
    Measure-Window
    foreach ($l in $lines) {
        $tone = if ($l -match '^(Mode \d|CLOSE)') { 'Accent' } elseif ($l -match '^Current') { 'Amber' } else { 'Text' }
        Add-Line ('  ' + $l) $tone
    }
    Add-Line
    Add-Line ('  ' + $prompt) 'Blue'
    Show-Frame
    if (-not $Line) { return [Console]::ReadKey($true).KeyChar.ToString() }
    try { [Console]::CursorVisible = $true } catch {}
    [Console]::SetCursorPosition([math]::Min($script:Width - 2, $prompt.Length + 3), $script:Rows.Count - 1)
    $answer = [Console]::ReadLine()
    try { [Console]::CursorVisible = $false } catch {}
    return $answer
}

$script:ModeText = @(
    'Mode 1: one bigger trade a day'
    '  - Only the first range breakout of the day, 1% risk per trade (InpRiskPct)'
    '  - Tested 2018-2026 ($3,000): +89%, PF 1.45, max DD 14.8%'
    '  - For: maximum profit, accepting 15-20% drawdowns'
    ''
    'Mode 2: several smaller trades'
    '  - Every breakout that meets the rules, no daily limit, 0.5% risk per trade (InpMultiRiskPct)'
    '  - Needs about twice the balance of mode 1, or most signals are skipped'
    '  - For: a steadier account, with less profit'
    ''
    'The 2nd-3rd trades of a day lose more often; mode 2 is steadier because each trade is smaller.'
    ''
)

function Invoke-Key([string]$key, $st) {
    switch ($key) {
        { $_ -in '1', '2' } {
            $lines = $script:ModeText + @("Current: $($st['modetext'])")
            if ($st['mode'] -eq $key) {
                [void](Ask-Dialog $lines "Mode $key is already active - press any key")
            } elseif ((Ask-Dialog $lines "Switch to mode $key ? [Y] yes  [N] no") -match '^[yY]') {
                Send-Command "MODE$key"; $script:Feedback = "Sent: switch to mode $key"
            } else { $script:Feedback = 'Mode not changed.' }
        }
        'P' {
            if ($st['paused'] -eq '1') { Send-Command 'RESUME'; $script:Feedback = 'Sent: resume' }
            else { Send-Command 'PAUSE'; $script:Feedback = 'Sent: pause (open trades keep their SL)' }
        }
        'C' {
            $lines = @('CLOSE ALL TRADES OF THIS EA', '', "Open trade: $($st['position'])", 'Manual trades and other EAs are not touched.')
            if ((Ask-Dialog $lines 'Type CLOSE and press Enter (anything else cancels):' -Line) -ceq 'CLOSE') {
                Send-Command 'CLOSEALL'; $script:Feedback = 'Sent: close all'
            } else { $script:Feedback = 'Close all cancelled.' }
        }
        'L' { $script:LongLog = -not $script:LongLog }
        'O' { $f = "$($script:Base)_log.txt"; if (Test-Path $f) { Start-Process notepad.exe $f } }
    }
}

#--- main loop -------------------------------------------------------
$oldTitle = ''
try {
    try { $oldTitle = $Host.UI.RawUI.WindowTitle; $Host.UI.RawUI.WindowTitle = 'GoldScalper console' } catch {}
    try { [Console]::CursorVisible = $false } catch {}
    [Console]::OutputEncoding = [Text.Encoding]::UTF8
    if ($script:UseAnsi) { [Console]::Write("$($script:Esc)[?1049h$($script:Esc)[48;2;$($script:Bg)m$($script:Esc)[2J") } else { [Console]::Clear() }

    $script:Base = $null
    while ($true) {
        if (-not $script:Base) { $script:Base = Find-Base }
        $st = @{}
        if ($script:Base) {
            $st = Read-Status
            if (-not $st.ContainsKey('state')) {   # EA older than v1.41
                $st['state'] = $st['status']; $st['reason'] = 'Update the EA to v1.41+ for the full view'
            }
            Read-Log
            Render-Frame $st
        } else { Render-Waiting }
        Show-Frame

        $until = (Get-Date).AddSeconds(1)
        $quit = $false
        while ((Get-Date) -lt $until) {
            if (-not [Console]::KeyAvailable) { Start-Sleep -Milliseconds 70; continue }
            $key = [Console]::ReadKey($true).KeyChar.ToString().ToUpper()
            if ($key -eq 'Q' -or $key -eq [string][char]27) { $quit = $true }
            elseif ($script:Base) { Invoke-Key $key $st }
            break
        }
        if ($quit) { break }
    }
} finally {
    if ($script:UseAnsi) { [Console]::Write("$($script:Esc)[0m$($script:Esc)[?1049l") }
    try { [Console]::CursorVisible = $true; $Host.UI.RawUI.WindowTitle = $oldTitle } catch {}
}
