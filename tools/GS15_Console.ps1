#requires -Version 5.1
<#
.SYNOPSIS
GoldScalperM15 console: live status, controls and event journal for the EA.

.DESCRIPTION
Compact control panel in the terminal. Dark / blue / navy theme following Gravity UI principles
(semantic status colours, primary / outlined / danger button views, a visible selected state,
4-8-12-16-24 spacing scale). All values come from the EA; nothing is invented.

The EA (InpConsole = true, live or demo chart) writes to MT5's common Files folder:
  GS15_<symbol>_<magic>_status.txt    current state, rewritten every second
  GS15_<symbol>_<magic>_log.txt       events (opened, closed, skipped, news, warnings)
  GS15_<symbol>_<magic>_account.txt   last account check (after the ACCOUNT command)
and reads one command from GS15_<symbol>_<magic>_cmd.txt:
  PAUSE, RESUME, CLOSEALL, TEST, ACCOUNT (v1.50 has one strategy - no trade modes).

Start: GS15_Console.bat (double-click), or
  powershell -ExecutionPolicy Bypass -File tools\GS15_Console.ps1 [-Symbol GOLD] [-Magic 20261013] [-NoColor]

Keys: P pause/resume - A account check - T system test - C close all
      L longer journal - O full log in Notepad - Q quit
Best in Windows Terminal with Cascadia Mono / Consolas, window at least 54 x 22.
#>
[CmdletBinding()]
param(
    [string]$Symbol = '',
    [string]$Magic  = '',
    [string]$Dir    = "$env:APPDATA\MetaQuotes\Terminal\Common\Files",
    [switch]$NoColor,
    [string]$Snapshot = '',      # test aid: render one frame (with colour codes) into this file and exit
    [int]$SnapWidth = 80,
    [int]$SnapHeight = 46
)

$ErrorActionPreference = 'Stop'

#==================================================================
# Theme - the only place colours are defined.
#==================================================================
$script:Theme = @{
    ScreenBg  = '#080C14'   # main background
    PanelBg   = '#0D1728'   # panel surface
    DataBg    = '#13213A'   # data surface, unselected controls
    Border    = '#263750'   # dividers and frame
    Primary   = '#2563EB'   # primary action, selected mode
    Accent    = '#79ADFF'   # headings, highlights
    Text      = '#E8EEF7'   # main text
    Muted     = '#9AAAC1'   # labels, secondary text
    Positive  = '#42C995'   # running / profit
    Warning   = '#E5AD52'   # waiting / caution
    Negative  = '#F07886'   # error / loss / danger
    OnPrimary = '#FFFFFF'
}
# Layout in characters (2 columns ~ 16 px padding). The panel width follows the window, within limits.
$script:Layout = @{ MinWidth = 52; MaxWidth = 68; LabelWidth = 16; MinHeight = 22 }

# Headline feeds (RSS the publishers offer for this purpose). Information for you only:
# the EA never trades on headlines. Add or remove feeds here.
$script:Feeds = @(
    @{ Src = 'BBC';  Url = 'https://feeds.bbci.co.uk/news/world/rss.xml' },
    @{ Src = 'BBC';  Url = 'https://feeds.bbci.co.uk/news/business/rss.xml' },
    @{ Src = 'CNBC'; Url = 'https://www.cnbc.com/id/100727362/device/rss/rss.html' },
    @{ Src = 'CNBC'; Url = 'https://www.cnbc.com/id/15839069/device/rss/rss.html' },
    @{ Src = 'IQ';   Url = 'https://www.infoquest.co.th/feed' }
)
$script:HeadlineMinutes = 10

#==================================================================
# Terminal setup
#==================================================================
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
$script:Ansi = if ($Snapshot) { -not $NoColor } else { (-not $NoColor) -and (-not [Console]::IsOutputRedirected) -and (Enable-Vt) }
$script:E    = [string][char]27
$script:Inv  = [Globalization.CultureInfo]::InvariantCulture

$script:RgbCache = @{}
function Rgb([string]$token) {
    if (-not $script:RgbCache.ContainsKey($token)) {
        $h = $script:Theme[$token].TrimStart('#')
        $script:RgbCache[$token] = '{0};{1};{2}' -f [Convert]::ToInt32($h.Substring(0, 2), 16), [Convert]::ToInt32($h.Substring(2, 2), 16), [Convert]::ToInt32($h.Substring(4, 2), 16)
    }
    return $script:RgbCache[$token]
}
function Sgr([string]$fg, [string]$bg, [bool]$bold = $false) {
    if (-not $script:Ansi) { return '' }
    $b = if ($bold) { '1' } else { '22' }
    return "$($script:E)[0;$b;38;2;$(Rgb $fg);48;2;$(Rgb $bg)m"
}

#==================================================================
# Files
#==================================================================
function Read-Shared([string]$path) {
    for ($i = 0; $i -lt 3; $i++) {
        try {
            $fs = [IO.File]::Open($path, 'Open', 'Read', 'ReadWrite, Delete')
            try { return (New-Object IO.StreamReader($fs, [Text.Encoding]::Unicode, $true)).ReadToEnd() }
            finally { $fs.Dispose() }
        } catch { Start-Sleep -Milliseconds 80 }
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

function Read-KeyValues([string]$file) {
    $kv = @{}
    if (-not (Test-Path $file)) { return $kv }
    $raw = Read-Shared $file
    if ($raw) {
        foreach ($line in ($raw -split "`r?`n")) {
            $i = $line.IndexOf('=')
            if ($i -gt 0) { $kv[$line.Substring(0, $i)] = $line.Substring($i + 1) }
        }
    }
    return $kv
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

#==================================================================
# Commands: one at a time; the result shown is the EA's own reply
#==================================================================
$script:Pending  = $null
$script:Feedback = $null      # @{ Text; Tone }

function Send-Command([string]$cmd, [string]$label) {
    if ($script:Pending) { $script:Feedback = @{ Text = 'Wait - the previous command is still being processed'; Tone = 'Warning' }; return }
    [IO.File]::WriteAllText("$($script:Base)_cmd.txt", $cmd, [Text.Encoding]::ASCII)
    $script:Pending  = @{ Cmd = $cmd; Label = $label; Sent = Get-Date; LogCount = $script:LogCache.Count }
    $script:Feedback = @{ Text = "Sending: $label - waiting for the EA..."; Tone = 'Warning' }
}

function Update-Pending {
    $p = $script:Pending
    if (-not $p) { return }
    $file = "$($script:Base)_cmd.txt"
    $age  = ((Get-Date) - $p.Sent).TotalSeconds
    if (Test-Path $file) {
        if ($age -gt 10) {
            Remove-Item $file -ErrorAction SilentlyContinue   # never let a stale command run later
            $script:Feedback = @{ Text = "Not done: the EA did not pick up '$($p.Label)' within 10 s (MT5 closed or EA not running)"; Tone = 'Negative' }
            $script:Pending = $null
        }
        return
    }
    if ($script:LogCache.Count -gt $p.LogCount) {
        $parts = $script:LogCache[$script:LogCache.Count - 1] -split "`t", 3
        $kind  = if ($parts.Count -ge 3) { $parts[1].Trim() } else { 'INFO' }
        $msg   = if ($parts.Count -ge 3) { $parts[2] } else { $parts[0] }
        $tone  = if ($kind -in 'WARN', 'LOSS') { 'Negative' } else { 'Positive' }
        $script:Feedback = @{ Text = "EA: $msg"; Tone = $tone }
        if ($p.Cmd -eq 'ACCOUNT') { $script:View = 'account' }
        $script:Pending = $null
    } elseif ($age -gt 15) {
        $script:Feedback = @{ Text = "The EA read '$($p.Label)' but sent no reply - check the log (O)"; Tone = 'Warning' }
        $script:Pending = $null
    }
}

#==================================================================
# Headlines: fetched in a background job so the panel never waits on the network
#==================================================================
$script:Headlines   = @()
$script:HeadJob     = $null
$script:HeadNext    = [datetime]::MinValue
$script:HeadStatus  = 'loading...'
$script:ShowHeads   = $true

function Update-Headlines {
    if ($script:HeadJob -and $script:HeadJob.State -ne 'Running') {
        $items = @(Receive-Job $script:HeadJob -ErrorAction SilentlyContinue)
        Remove-Job $script:HeadJob -Force -ErrorAction SilentlyContinue
        $script:HeadJob = $null
        $ok = @($items | Where-Object { $_.Title })
        if ($ok.Count -gt 0) {
            $seen = @{}
            $script:Headlines = @($ok | Sort-Object Time -Descending | Where-Object { if ($seen[$_.Title]) { $false } else { $seen[$_.Title] = 1; $true } } | Select-Object -First 40)
            $script:HeadStatus = 'updated {0:HH:mm}' -f (Get-Date)
        } else { $script:HeadStatus = 'not available (no connection?)' }
    }
    if (-not $script:HeadJob -and (Get-Date) -ge $script:HeadNext) {
        $script:HeadNext = (Get-Date).AddMinutes($script:HeadlineMinutes)
        $script:HeadJob = Start-Job -ArgumentList (, $script:Feeds) -ScriptBlock {
            param($feeds)
            [Net.ServicePointManager]::SecurityProtocol = 'Tls12'
            foreach ($f in $feeds) {
                try {
                    $r = Invoke-WebRequest -Uri $f.Url -UseBasicParsing -TimeoutSec 15 -UserAgent 'GoldScalperM15-console'
                    [xml]$x = [Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray())
                    foreach ($it in @($x.rss.channel.item | Select-Object -First 12)) {
                        $title = if ($it.title -is [string]) { $it.title } else { $it.title.InnerText }
                        $when = [datetime]::MinValue
                        try { $when = ([DateTimeOffset]::Parse([string]$it.pubDate, [Globalization.CultureInfo]::InvariantCulture)).LocalDateTime } catch {}
                        [pscustomobject]@{ Src = $f.Src; Time = $when; Title = ($title -replace '\s+', ' ').Trim() }
                    }
                } catch {}
            }
        }
    }
}

#==================================================================
# Frame building
#==================================================================
$script:Rows = New-Object 'System.Collections.Generic.List[string]'
$script:Ell  = [string][char]0x2026

function Fit([string]$t, [int]$n) {
    if ($n -le 0) { return '' }
    $t = [regex]::Replace([string]$t, '[\x00-\x1f\x7f]', ' ')
    if ($t.Length -gt $n) { return $t.Substring(0, [Math]::Max(0, $n - 1)) + $script:Ell }
    return $t.PadRight($n)
}

# Wraps text into at most $max lines of width $n; the last line ends with an ellipsis when cut.
function Wrap([string]$t, [int]$n, [int]$max = 2) {
    $out = New-Object 'System.Collections.Generic.List[string]'
    $line = ''
    foreach ($w in ([string]$t -split ' ')) {
        if (($line + ' ' + $w).Trim().Length -le $n) { $line = ($line + ' ' + $w).Trim() }
        else { $out.Add($line); $line = $w }
    }
    $out.Add($line)
    if ($out.Count -gt $max) {
        $keep = @($out[0..($max - 1)])
        $keep[$max - 1] = (Fit ($keep[$max - 1] + ' ' + $script:Ell + '   ') $n).TrimEnd()
        return $keep
    }
    return @($out)
}

# A row inside the frame: segments are @(text, fg, bg, bold).
function Add-Row($segs) {
    # PowerShell flattens @(@(a, b, c)) into one array: re-wrap a single segment.
    if ($segs.Count -gt 0 -and -not ($segs[0] -is [array])) { $segs = @(, $segs) }
    $iw = $script:W - 4
    $s = ''; $len = 0
    foreach ($seg in $segs) {
        $t = [string]$seg[0]
        if ($len + $t.Length -gt $iw) { $t = Fit $t ($iw - $len) }
        $bold = $false; if ($seg.Count -gt 3) { $bold = [bool]$seg[3] }
        $s += (Sgr $seg[1] $seg[2] $bold) + $t
        $len += $t.Length
        if ($len -ge $iw) { break }
    }
    $s += (Sgr 'Text' 'PanelBg') + (' ' * [Math]::Max(0, $iw - $len))
    $bar = [string][char]0x2502
    [void]$script:Rows.Add((Sgr 'Border' 'ScreenBg') + ' ' + (Sgr 'Border' 'PanelBg') + $bar + (Sgr 'Text' 'PanelBg') + ' ' + $s + ' ' + (Sgr 'Border' 'PanelBg') + $bar + (Sgr 'Text' 'ScreenBg'))
}

function Add-Blank { Add-Row @() }

function Add-Edge([string]$kind, [string]$title = '') {
    $w = $script:W
    $l = @{ top = [char]0x256D; mid = [char]0x251C; bot = [char]0x2570 }[$kind]
    $r = @{ top = [char]0x256E; mid = [char]0x2524; bot = [char]0x256F }[$kind]
    $h = [string][char]0x2500
    if ($title) {
        $fill = [Math]::Max(0, $w - 5 - $title.Length)
        $line = (Sgr 'Border' 'PanelBg') + $l + $h + ' ' + (Sgr 'Accent' 'PanelBg' $true) + $title + (Sgr 'Border' 'PanelBg') + ' ' + ($h * $fill) + $r
    } else {
        $line = (Sgr 'Border' 'PanelBg') + $l + ($h * ($w - 2)) + $r
    }
    [void]$script:Rows.Add((Sgr 'Border' 'ScreenBg') + ' ' + $line + (Sgr 'Text' 'ScreenBg'))
}

function Add-KeyValue([string]$label, [string]$value, [string]$tone = 'Text', [bool]$bold = $false) {
    Add-Row @(@((Fit $label $script:Layout.LabelWidth), 'Muted', 'PanelBg'), @($value, $tone, 'PanelBg', $bold))
}

# Button views: primary (filled blue), normal (navy surface), selected (filled blue + tick),
# danger (red text on navy), disabled (dim).
function Button([string]$key, [string]$text, [string]$view = 'normal') {
    switch ($view) {
        'primary'  { return @(" $key  $text ", 'OnPrimary', 'Primary', $true) }
        'selected' { return @(" $([char]0x2713) $text ", 'OnPrimary', 'Primary', $true) }
        'danger'   { return @(" $key  $text ", 'Negative', 'DataBg', $true) }
        'disabled' { return @(" $key  $text ", 'Border', 'DataBg') }
        default    { return @(" $key  $text ", 'Text', 'DataBg') }
    }
}
function Gap([int]$n = 1) { return @((' ' * [Math]::Max(0, $n)), 'Text', 'PanelBg') }

function Num([string]$v, [string]$fmt = 'N2') {
    $d = 0.0
    if ([double]::TryParse($v, [Globalization.NumberStyles]::Float, $script:Inv, [ref]$d)) { return $d.ToString($fmt, $script:Inv) }
    return '--'
}
function Dbl([string]$v) {
    $d = 0.0
    if ([double]::TryParse($v, [Globalization.NumberStyles]::Float, $script:Inv, [ref]$d)) { return $d }
    return [double]::NaN
}
function Money([double]$v, [string]$ccy) {
    if ([double]::IsNaN($v)) { return 'not available' }
    $sign = if ($v -gt 0) { '+' } else { '' }
    return '{0}{1} {2}' -f $sign, $v.ToString('N2', $script:Inv), $ccy
}

# "15:30 USD CPI m/m" + server time -> "in 1 h 12 min". The EA lists only events from now on
# (re-checked every minute), so an event up to 2 minutes in the past shows as "now".
function News-Eta([string]$news, [string]$serverTime) {
    if ($news -notmatch '^(\d{2}):(\d{2})\s') { return '' }
    $now = [datetime]::MinValue
    if (-not [datetime]::TryParseExact($serverTime, 'yyyy.MM.dd HH:mm:ss', $script:Inv, 'None', [ref]$now)) { return '' }
    $t = $now.Date.AddHours([int]$Matches[1]).AddMinutes([int]$Matches[2])
    if ($t -lt $now.AddMinutes(-2)) { $t = $t.AddDays(1) }
    $m = [int][Math]::Round(($t - $now).TotalMinutes)
    if ($m -le 0) { return 'now' }
    if ($m -lt 60) { return "in $m min" }
    return 'in {0} h {1:00} min' -f [int][Math]::Floor($m / 60), ($m % 60)
}

#==================================================================
# Views
#==================================================================
$script:View    = 'main'
$script:LongLog = $false
$script:Tones   = @{ OPEN = 'Accent'; WIN = 'Positive'; LOSS = 'Negative'; SKIP = 'Warning'; WARN = 'Warning'; NEWS = 'Accent'; INFO = 'Muted' }

function Measure-Window {
    if ($Snapshot) { $script:WinW = $SnapWidth; $script:WinH = $SnapHeight }
    else { try { $script:WinW = [Console]::WindowWidth; $script:WinH = [Console]::WindowHeight } catch { $script:WinW = 80; $script:WinH = 30 } }
    $script:W = [Math]::Max($script:Layout.MinWidth, [Math]::Min($script:Layout.MaxWidth, $script:WinW - 3))
    $script:Compact = $script:WinH -lt 40   # no blank spacer rows, no server time
    $script:Dense   = $script:WinH -lt 32   # also pair related values on one row
}

function Get-StatusChip($st) {
    if ($script:Age -gt 10) {
        return @{ Label = 'ERROR'; Tone = 'Negative'; Reason = ('No data from the EA for {0:N0} s - MT5 closed, EA removed or no connection. Values below are the last known.' -f $script:Age) }
    }
    $reason = ([string]$st['reason']) -replace ' - ', (' ' + [char]0x2014 + ' ')
    switch ($st['state']) {
        'HALTED'   { return @{ Label = 'HALTED';   Tone = 'Negative'; Reason = $reason } }
        'PAUSED'   { return @{ Label = 'PAUSED';   Tone = 'Warning';  Reason = 'New entries paused by you. Open trades keep their SL.' } }
        'IN TRADE' { return @{ Label = 'IN TRADE'; Tone = 'Positive'; Reason = $reason } }
        'READY'    { return @{ Label = 'RUNNING';  Tone = 'Positive'; Reason = $reason } }
    }
    if ($st['reason'] -match 'News')       { return @{ Label = 'NEWS WINDOW'; Tone = 'Warning';  Reason = 'News window ' + [char]0x2014 + ' entries paused' } }
    if ($st['reason'] -match 'Daily loss') { return @{ Label = 'DAILY LIMIT'; Tone = 'Negative'; Reason = $reason } }
    return @{ Label = 'WAITING'; Tone = 'Warning'; Reason = $reason }
}

function Render-Main($st) {
    $iw = $script:W - 4
    $ccy = $st['ccy']; if (-not $ccy) { $ccy = 'USD' }
    $real = $st['accttype'] -eq 'REAL'
    $ver = ($st['version'] -replace '^\S+\s+', '')

    # Header: name, version, symbol / timeframe, account type badge (only when the EA reports it)
    Add-Edge 'top'
    $badge = if ($real) { @(' LIVE ', 'OnPrimary', 'Negative', $true) } elseif ($st['accttype'] -eq 'Demo') { @(' DEMO ', 'Accent', 'DataBg', $true) } else { @('', 'Text', 'PanelBg') }
    $title = 'GoldScalper M15'
    Add-Row @(@($title, 'Text', 'PanelBg', $true), @("  v$ver", 'Muted', 'PanelBg'), (Gap ($iw - $title.Length - 3 - $ver.Length - $badge[0].Length)), $badge)
    Add-Row @(@("$($st['symbol']) $([char]0x00B7) $($st['tf'])   Account $(($st['account'] -replace '\s*\(.*\)$', ''))", 'Muted', 'PanelBg'))

    # Status: label with colour AND text, reason on its own line(s)
    Add-Edge 'mid' 'STATUS'
    $chip = Get-StatusChip $st
    Add-Row @(@("$([char]0x25CF) ", $chip.Tone, 'PanelBg'), @($chip.Label, $chip.Tone, 'PanelBg', $true))
    foreach ($l in (Wrap $chip.Reason $iw 2)) { Add-Row @(@($l, 'Text', 'PanelBg')) }

    # Today
    Add-Edge 'mid' 'TODAY'
    $pl = Dbl $st['plv']
    $plTone = if ($pl -gt 0) { 'Positive' } elseif ($pl -lt 0) { 'Negative' } else { 'Text' }
    Add-KeyValue 'Daily P/L' (Money $pl $ccy) $plTone $true
    $cap = if ($st['maxtrades'] -eq '0') { 'no limit' } else { $st['maxtrades'] }
    Add-KeyValue 'Trades' ("{0} / {1}" -f $st['trades'], $cap)
    $pos = [string]$st['position']
    if ($pos -match '^(BUY|SELL)') {
        $float = if ($pos -match 'P/L (-?[\d.]+)') { Dbl $Matches[1] } else { [double]::NaN }
        $ft = if ($float -lt 0) { 'Negative' } elseif ($float -gt 0) { 'Positive' } else { 'Text' }
        Add-KeyValue 'Position' ($pos -replace '\s*\|\s*P/L.*$', '')
        Add-KeyValue 'Open P/L' (Money $float $ccy) $ft
    } else { Add-KeyValue 'Position' 'No open position' 'Muted' }

    # Strategy & risk (v1.50: one strategy, no modes)
    Add-Edge 'mid' 'STRATEGY & RISK'
    Add-KeyValue 'Strategy' $(if ($st['modetext']) { $st['modetext'] } else { 'Asian-range breakout, one trade a day' })
    $tr = Dbl $st['risktarget']
    Add-KeyValue 'Target risk' $(if ($tr -gt 0) { '{0}% of equity per trade' -f $tr.ToString('N2', $script:Inv) } else { 'fixed lot (no risk target)' })
    $ra = Dbl $st['riskactual']
    if ($ra -ge 0) {
        $raTone = if ($tr -gt 0 -and $ra -gt $tr * 1.0001) { 'Negative' } else { 'Text' }
        Add-KeyValue 'Actual risk' ('{0}% of equity at the SL' -f $ra.ToString('N2', $script:Inv)) $raTone
    } else { Add-KeyValue 'Actual risk' 'no open position' 'Muted' }
    $guard = if ($st['ddmax'] -match '^0(\.0+)?$') { "$(Num $st['ddv'])% (no halt)" } else { "$(Num $st['ddv'])% of $(Num $st['ddmax'] 'N0')% halt" }
    $streak = if ($st['streakmax'] -eq '0') { "$($st['streak']) (no halt)" } else { "$($st['streak']) of $($st['streakmax'])" }
    if ($script:Dense) { Add-KeyValue 'Guards' ("DD $guard $([char]0x00B7) losses $streak") }
    else { Add-KeyValue 'Drawdown' $guard; Add-KeyValue 'Losses in a row' $streak }

    # Market & news
    Add-Edge 'mid' 'MARKET & NEWS'
    $sp = Dbl $st['spreadv']; $spMax = Dbl $st['spreadmax']
    $spTone = if ($sp -gt $spMax) { 'Warning' } else { 'Text' }
    if ($script:Dense) { Add-KeyValue 'Spread / ATR' ('{0} / {1} limit {2} ATR {3}' -f (Num $st['spreadv']), (Num $st['spreadmax']), [char]0x00B7, (Num $st['atrv'])) $spTone }
    else { Add-KeyValue 'Spread / limit' ('{0} / {1}' -f (Num $st['spreadv']), (Num $st['spreadmax'])) $spTone; Add-KeyValue 'ATR (M15)' ('{0} (price units)' -f (Num $st['atrv'])) }
    $news = [string]$st['news']
    if (-not $st.ContainsKey('news')) { Add-KeyValue 'News' 'not available' 'Muted' }
    elseif (-not $news -or $news -eq '-') { Add-KeyValue 'News' 'none in the next 24 h' 'Muted' }
    else {
        $eta = News-Eta $news $st['servertime']
        Add-KeyValue 'Upcoming news' $(if ($eta) { "$news $([char]0x00B7) $eta" } else { $news })
    }
    if (-not $script:Compact) { Add-KeyValue 'Server time' $st['servertime'] 'Muted' }

    # Controls: frequent actions on one row; Close all alone on the right, in red.
    Add-Edge 'mid' 'CONTROLS'
    $busy = [bool]$script:Pending
    $pauseText = if ($st['paused'] -eq '1') { 'Resume' } else { 'Pause' }
    $pauseView = if ($busy) { 'disabled' } elseif ($st['paused'] -eq '1') { 'primary' } else { 'normal' }
    $other = if ($busy) { 'disabled' } else { 'normal' }
    Add-Row @((Button 'P' $pauseText $pauseView), (Gap 1), (Button 'A' 'Account check' $other), (Gap 1), (Button 'T' 'Test order' $other))
    if (-not $script:Compact) { Add-Blank }
    $close = Button 'C' ('Close all' + $script:Ell) $(if ($busy) { 'disabled' } else { 'danger' })
    $hint = 'closes this EA''s trades only'
    Add-Row @(@($hint, 'Muted', 'PanelBg'), (Gap ($iw - $hint.Length - $close[0].Length)), $close)
    if ($script:Feedback) {
        Add-Edge 'mid'
        foreach ($l in (Wrap $script:Feedback.Text $iw 2)) { Add-Row @(@($l, $script:Feedback.Tone, 'PanelBg')) }
    }
    Add-Edge 'bot'

    # Event journal, newest first, in the remaining height.
    $room = $script:WinH - $script:Rows.Count - 4
    if (-not $script:LongLog) { $room = [Math]::Min($room, $(if ($script:ShowHeads) { 6 } else { 8 })) }
    if ($room -ge 2) {
        Add-Edge 'top' 'EVENTS  newest first'
        $tail = @(if ($script:LogCache.Count -gt $room) { $script:LogCache[($script:LogCache.Count - $room)..($script:LogCache.Count - 1)] } else { $script:LogCache })
        [array]::Reverse($tail)
        foreach ($entry in $tail) {
            $parts = $entry -split "`t", 3
            if ($parts.Count -lt 3) { Add-Row @(@($entry, 'Muted', 'PanelBg')); continue }
            $time = $parts[0]; if ($time.Length -ge 16) { $time = $time.Substring(11, 5) }
            $kind = $parts[1].Trim()
            $tone = if ($script:Tones.ContainsKey($kind)) { $script:Tones[$kind] } else { 'Muted' }
            Add-Row @(@("$time  ", 'Muted', 'PanelBg'), @(((Fit $kind 5) + ' '), $tone, 'PanelBg', $true), @($parts[2], 'Text', 'PanelBg'))
        }
        if ($tail.Count -eq 0) { Add-Row @(@('No events yet.', 'Muted', 'PanelBg')) }
        Add-Edge 'bot'
    }
    if ($script:ShowHeads) {
        $hroom = $script:WinH - $script:Rows.Count - 4
        if ($hroom -ge 2) {
            Add-Edge 'top' ('HEADLINES  info only, not used for trading  ' + [char]0x00B7 + ' ' + $script:HeadStatus)
            $n = 0
            foreach ($h in $script:Headlines) {
                if ($n -ge $hroom) { break }
                $t = if ($h.Time -gt [datetime]::MinValue) { $h.Time.ToString('HH:mm') } else { '--:--' }
                Add-Row @(@("$t  ", 'Muted', 'PanelBg'), @(((Fit $h.Src 4) + ' '), 'Accent', 'PanelBg', $true), @($h.Title, 'Text', 'PanelBg'))
                $n++
            }
            if ($n -eq 0) { Add-Row @(@('No headlines yet.', 'Muted', 'PanelBg')) }
            Add-Edge 'bot'
        }
    }
    $logWord = if ($script:LongLog) { 'short' } else { 'long' }
    # The action keys are on the buttons above; the footer only lists the view keys.
    [void]$script:Rows.Add((Sgr 'Muted' 'ScreenBg') + '  ' + (Fit "L $logWord journal   H headlines   O full log   Q quit" ($script:W - 2)))
}

function Render-Account {
    $iw = $script:W - 4
    $kv = @{}; $lines = @()
    $file = "$($script:Base)_account.txt"
    if (Test-Path $file) {
        foreach ($l in ((Read-Shared $file) -split "`r?`n")) {
            if ($l -match '^(updated|title)=(.*)$') { $kv[$Matches[1]] = $Matches[2] } else { $lines += $l }
        }
    }
    Add-Edge 'top' 'ACCOUNT CHECK'
    if (-not $kv['updated']) { Add-Row @(@('No account check yet. Press A on the main view.', 'Muted', 'PanelBg')) }
    else {
        Add-Row @(@($kv['title'], 'Text', 'PanelBg', $true))
        Add-Row @(@("checked $($kv['updated']) (server time)", 'Muted', 'PanelBg'))
        Add-Blank
        $max = $script:WinH - 8
        $n = 0
        foreach ($l in $lines) {
            foreach ($w in (Wrap $l $iw 3)) { if ($n -lt $max) { Add-Row @(@($w, 'Text', 'PanelBg')); $n++ } }
        }
    }
    Add-Edge 'bot'
    [void]$script:Rows.Add((Sgr 'Muted' 'ScreenBg') + '  Any key: back')
}

function Render-Dialog([string]$title, [string[]]$lines, [string]$prompt) {
    $script:Rows.Clear()
    Measure-Window
    $iw = $script:W - 4
    Add-Edge 'top' $title
    foreach ($l in $lines) {
        if ($l -eq '') { Add-Blank; continue }
        foreach ($w in (Wrap $l $iw 4)) { Add-Row @(@($w, 'Text', 'PanelBg')) }
    }
    Add-Blank
    Add-Row @(@($prompt, 'Accent', 'PanelBg', $true))
    Add-Edge 'bot'
    Show-Frame -Force
}

function Render-Waiting {
    Add-Edge 'top' 'GOLDSCALPER CONSOLE'
    Add-Row @(@("$([char]0x25CF) WAITING FOR THE EA", 'Warning', 'PanelBg', $true))
    Add-Row @(@('Attach GoldScalperM15 v1.40+ to a chart on a live or demo', 'Text', 'PanelBg'))
    Add-Row @(@('account and keep InpConsole = true (default).', 'Text', 'PanelBg'))
    Add-Row @(@("Looking in: $Dir", 'Muted', 'PanelBg'))
    Add-Edge 'bot'
    [void]$script:Rows.Add((Sgr 'Muted' 'ScreenBg') + '  Q quit')
}

$script:LastFrame = ''
function Show-Frame([switch]$Force) {
    $frame = ($script:Rows -join "`n")
    if (-not $Force -and $frame -eq $script:LastFrame) { return }   # nothing changed: no redraw, no flicker
    $script:LastFrame = $frame
    if ($script:Ansi) {
        $clr = "$($script:E)[K"
        [Console]::Write("$($script:E)[H" + ($frame -replace "`n", "$clr`r`n") + $clr + (Sgr 'Text' 'ScreenBg') + "$($script:E)[J")
    } else {
        [Console]::Clear()
        [Console]::Write($frame -replace "`n", "`r`n")
    }
}

function Read-Answer([switch]$Line) {
    if (-not $Line) { return [Console]::ReadKey($true).KeyChar.ToString() }
    try { [Console]::CursorVisible = $true } catch {}
    [Console]::Write((Sgr 'Text' 'ScreenBg') + "`r`n  > ")
    $a = [Console]::ReadLine()
    try { [Console]::CursorVisible = $false } catch {}
    return $a
}

#==================================================================
# Keys
#==================================================================
function Invoke-Key([string]$key, $st) {
    if ($script:View -eq 'account') { $script:View = 'main'; return }
    $isCommand = $key -in 'P', 'A', 'T', 'C'
    if ($isCommand -and $script:Pending) { $script:Feedback = @{ Text = 'Wait - the previous command is still being processed'; Tone = 'Warning' }; return }
    if ($isCommand -and $script:Age -gt 10) { $script:Feedback = @{ Text = 'Not sent: the EA is not updating (MT5 closed or EA removed)'; Tone = 'Negative' }; return }
    switch ($key) {
        'P' { if ($st['paused'] -eq '1') { Send-Command 'RESUME' 'resume' } else { Send-Command 'PAUSE' 'pause' } }
        'A' { Send-Command 'ACCOUNT' 'account check' }
        'T' {
            Render-Dialog 'SYSTEM TEST' @('Opens a real BUY of the minimum lot with an SL, holds it about 0.1 s (InpQuickTestHoldMs), closes it and reports how long the open and the close took.', 'Costs only the spread. Not counted as a trade of the day. Demo accounts only, unless InpQuickTestReal = true.') 'Start the test?   Y yes   N no'
            if ((Read-Answer) -match '^[yY]') { Send-Command 'TEST' 'system test' } else { $script:Feedback = @{ Text = 'Test cancelled'; Tone = 'Muted' } }
        }
        'C' {
            $mg = ($script:Base -split '_')[-1]
            Render-Dialog 'CLOSE ALL TRADES OF THIS EA' @("Closes only positions of this EA: symbol $($st['symbol']), magic $mg.", 'Manual trades and other EAs are not touched.', '', "Open now: $($st['position'])") 'Type CLOSE and press Enter (anything else cancels):'
            if ((Read-Answer -Line) -ceq 'CLOSE') { Send-Command 'CLOSEALL' 'close all' } else { $script:Feedback = @{ Text = 'Close all cancelled'; Tone = 'Muted' } }
        }
        'L' { $script:LongLog = -not $script:LongLog }
        'H' { $script:ShowHeads = -not $script:ShowHeads }
        'O' { $f = "$($script:Base)_log.txt"; if (Test-Path $f) { Start-Process notepad.exe $f } }
    }
}

#==================================================================
# Main loop
#==================================================================
if ($Snapshot) {
    $script:Base = Find-Base
    $script:Age = 0
    $st = Read-KeyValues "$($script:Base)_status.txt"
    Read-Log
    Measure-Window
    Render-Main $st
    [IO.File]::WriteAllText($Snapshot, ($script:Rows -join "`n"), [Text.Encoding]::UTF8)
    return
}

$oldTitle = ''
$pidFile = Join-Path $Dir 'GS15_console_pid.txt'   # lets the launcher (chart button) find and close this window
try {
    try { [IO.File]::WriteAllText($pidFile, "$PID", [Text.Encoding]::ASCII) } catch {}
    try { $oldTitle = $Host.UI.RawUI.WindowTitle; $Host.UI.RawUI.WindowTitle = 'GoldScalper console' } catch {}
    try { [Console]::CursorVisible = $false } catch {}
    [Console]::OutputEncoding = [Text.Encoding]::UTF8
    if ($script:Ansi) { [Console]::Write("$($script:E)[?1049h" + (Sgr 'Text' 'ScreenBg') + "$($script:E)[2J") } else { [Console]::Clear() }

    $script:Base = $null
    $script:Age  = 999
    while ($true) {
        if (-not $script:Base) { $script:Base = Find-Base }
        $script:Rows.Clear()
        Measure-Window
        $st = @{}
        if ($script:WinW -lt $script:Layout.MinWidth + 2 -or $script:WinH -lt $script:Layout.MinHeight) {
            [void]$script:Rows.Add((Sgr 'Warning' 'ScreenBg') + " Window too small: make it at least $($script:Layout.MinWidth + 2) x $($script:Layout.MinHeight). Q quit")
        } elseif ($script:Base) {
            $sf = "$($script:Base)_status.txt"
            $st = Read-KeyValues $sf
            $script:Age = if (Test-Path $sf) { ((Get-Date) - (Get-Item $sf).LastWriteTime).TotalSeconds } else { 999 }
            if (-not $st.ContainsKey('state')) { $st['state'] = $st['status']; $st['reason'] = 'Update the EA to v1.41+ for the full view' }
            Read-Log
            Update-Pending
            Update-Headlines
            if ($script:View -eq 'account') { Render-Account } else { Render-Main $st }
        } else { Render-Waiting }
        Show-Frame

        $until = (Get-Date).AddSeconds(1)
        $quit = $false
        while ((Get-Date) -lt $until) {
            if (-not [Console]::KeyAvailable) { Start-Sleep -Milliseconds 60; continue }
            $key = [Console]::ReadKey($true).KeyChar.ToString().ToUpper()
            if ($key -eq 'Q' -or $key -eq [string][char]27) { if ($script:View -ne 'main') { $script:View = 'main' } else { $quit = $true } }
            elseif ($script:Base) { Invoke-Key $key $st }
            $script:LastFrame = ''   # redraw after any key
            break
        }
        if ($quit) { break }
    }
} finally {
    if ($script:HeadJob) { Remove-Job $script:HeadJob -Force -ErrorAction SilentlyContinue }
    try { if ((Get-Content $pidFile -ErrorAction SilentlyContinue) -eq "$PID") { Remove-Item $pidFile -ErrorAction SilentlyContinue } } catch {}
    if ($script:Ansi) { [Console]::Write("$($script:E)[0m$($script:E)[?1049l") }
    try { [Console]::CursorVisible = $true; $Host.UI.RawUI.WindowTitle = $oldTitle } catch {}
}
