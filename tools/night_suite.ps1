# Overnight backtest suite on the MAIN MT5 terminal (the one that runs the demo), as agreed:
# start after the daily close, run one backtest at a time, restart MT5 at the end.
# The main terminal is the portable MT5 in D:\MT5_GoldScalper (started with /portable).
#
# Start it from your own Windows session (double-click), so it sees the live EA's status file:
#   tools\Run-Backtests-Now.cmd        weekend / market closed: start at once
#   tools\Run-Backtests-Tonight.cmd    weekday: wait until 00:15, no new run after 07:30
# or: powershell -ExecutionPolicy Bypass -File tools\night_suite.ps1 -StartAt '00:15' -StopAt '07:30' [-Now]
#
# Safety:
#  - waits for StartAt; refuses to stop MT5 while this EA has an open position (status file);
#  - STOP file (D:\EA_Trade_lab\STOP) ends the suite before the next run;
#  - no new run after StopAt; each run has a timeout;
#  - MT5 is always started again at the end (finally block), even after an error (not with -NoRestart).
#  - Test-only copy, while the live MT5 keeps trading: -Terminal D:\MT5_Tester -NoRestart -Now
# Output: reports\experiments\suite_<date>\<run>\ (ini, inputs, report.htm, deals.csv, journals, tester log)
#         reports\experiments\suite_<date>\summary.csv and suite.log; DONE file when finished.
param(
    [string]$StartAt = '00:15',
    [string]$StopAt  = '07:30',
    [switch]$Now,
    [string]$Terminal = 'D:\MT5_GoldScalper',   # portable MT5 to test on; e.g. D:\MT5_Tester (a copy with no EA on its charts)
    [switch]$NoRestart,                       # do not start the terminal again at the end (use with a test-only copy)
    [string]$Plan = '',                       # .ps1 that returns the list of runs (same fields as $runs below)
    [string]$Tag  = '',                       # suffix for the result folder, e.g. 'exp1'
    [string]$SuiteName = '',                  # exact result folder name (continue an earlier suite), e.g. suite_20261016_exp3
    [switch]$SkipDone                         # skip runs that already have a report in the result folder
)
$ErrorActionPreference = 'Stop'
# Only Get-LabSummary is needed from lab.ps1. Dot-source it FIRST: it sets $Term/$Editor for the
# portable lab terminal, and the values below must win.
. 'D:\EA_Trade_lab\repo\tools\lab.ps1'
$Repo   = Split-Path $PSScriptRoot -Parent          # the repo / worktree this script belongs to
$Mt5    = $Terminal                         # portable: program and data in one folder
$Term   = "$Mt5\terminal64.exe"
$Editor = "$Mt5\MetaEditor64.exe"
$Data   = $Mt5
$Common = "$env:APPDATA\MetaQuotes\Terminal\Common\Files"
$Agents = "$Mt5\Tester"
$StopFile = 'D:\EA_Trade_lab\STOP'
$Suite  = "$Repo\reports\experiments\suite_{0:yyyyMMdd}" -f (Get-Date).AddHours(6)
if ($Tag) { $Suite += "_$Tag" }
if ($SuiteName) { $Suite = "$Repo\reports\experiments\$SuiteName" }
New-Item -ItemType Directory -Force $Suite | Out-Null
New-Item -ItemType Directory -Force "$Terminal\reports" | Out-Null   # MT5 does not create the report folder itself
$Log = "$Suite\suite.log"
function Log([string]$m) {
    $line = '{0:yyyy-MM-dd HH:mm:ss}  {1}' -f (Get-Date), $m
    Write-Host $line
    # Someone may be reading the log (a viewer, a monitor): retry, and never let logging stop the suite.
    for ($i = 0; $i -lt 20; $i++) { try { [IO.File]::AppendAllText($Log, "$line
"); return } catch { Start-Sleep -Milliseconds 250 } }
}

$runs = @(
    @{ Name = 'R0_smc_smoke_1min_2026Q3';     From = '2026.08.01'; To = '2026.10.12'; Model = 1; Deposit = 3000;  Delay = 0;  Inputs = @{ InpTradeStyle = 3 } },
    @{ Name = 'R1_regression_mode1_1min_3k';  From = '2018.01.01'; To = '2026.10.12'; Model = 1; Deposit = 3000;  Delay = 0;  Inputs = @{ InpNewsInTester = 'false' } },
    @{ Name = 'R1n_mode1_news_1min_3k';       From = '2018.01.01'; To = '2026.10.12'; Model = 1; Deposit = 3000;  Delay = 0;  Inputs = @{} },
    @{ Name = 'R2_smc_realticks_3k';          From = '2024.10.14'; To = '2026.10.12'; Model = 4; Deposit = 3000;  Delay = 0;  Inputs = @{ InpTradeStyle = 3 } },
    @{ Name = 'R3_orb_0.5pct_realticks_3k';   From = '2024.10.14'; To = '2026.10.12'; Model = 4; Deposit = 3000;  Delay = 0;  Inputs = @{ InpRiskPct = 0.5 } },
    @{ Name = 'R4_smc_realticks_1k';          From = '2024.10.14'; To = '2026.10.12'; Model = 4; Deposit = 1000;  Delay = 0;  Inputs = @{ InpTradeStyle = 3 } },
    @{ Name = 'R5_smc_realticks_10k';         From = '2024.10.14'; To = '2026.10.12'; Model = 4; Deposit = 10000; Delay = 0;  Inputs = @{ InpTradeStyle = 3 } },
    @{ Name = 'R6_smc_1min_2018_2026_3k';     From = '2018.01.01'; To = '2026.10.12'; Model = 1; Deposit = 3000;  Delay = 0;  Inputs = @{ InpTradeStyle = 3 } },
    @{ Name = 'R7_orb_0.5pct_1min_2018_2026_3k'; From = '2018.01.01'; To = '2026.10.12'; Model = 1; Deposit = 3000; Delay = 0; Inputs = @{ InpRiskPct = 0.5 } },
    @{ Name = 'R8_smc_realticks_3k_randomdelay'; From = '2024.10.14'; To = '2026.10.12'; Model = 4; Deposit = 3000; Delay = -1; Inputs = @{ InpTradeStyle = 3 } }
)

if ($Plan) { $runs = @(& $Plan) }

function Wait-Until([string]$hhmm) {
    $t = [datetime]::ParseExact($hhmm, 'HH:mm', $null)
    if ($t -lt (Get-Date)) { $t = $t.AddDays(1) }
    Log "waiting until $t"
    while ((Get-Date) -lt $t) {
        if (Test-Path $StopFile) { throw 'STOP file present - suite cancelled before start' }
        Start-Sleep 30
    }
}

function Get-MainTerminal { Get-Process terminal64 -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $Term } }

# Every MT5 terminal with its folder and process id, and whether the live (demo) terminal still runs.
$LiveTerm = 'D:\MT5_GoldScalper\terminal64.exe'
function Log-Terminals([string]$when) {
    $t = @(Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'" -ErrorAction SilentlyContinue)
    $list = ($t | ForEach-Object { '{0} pid {1}' -f $_.ExecutablePath, $_.ProcessId }) -join '; '
    $live = @($t | Where-Object { $_.ExecutablePath -eq $LiveTerm }).Count -gt 0
    Log ("terminals {0}: {1} | live terminal {2}" -f $when, $(if ($list) { $list } else { 'none' }), $(if ($live) { 'RUNNING' } else { 'NOT RUNNING' }))
}
function Run-One($r) {
    $dir = "$Suite\$($r.Name)"
    New-Item -ItemType Directory -Force $dir | Out-Null
    $all = [ordered]@{ InpNotifyPush = 'false'; InpShowPanel = 'false'; InpConsole = 'false' }
    foreach ($k in $r.Inputs.Keys) { $all[$k] = "$($r.Inputs[$k])".ToLower() }
    $set = "night_$($r.Name).set"
    $lines = [string[]]($all.Keys | ForEach-Object { "$_=$($all[$_])" })
    [IO.File]::WriteAllLines("$Data\MQL5\Profiles\Tester\$set", $lines, [Text.UnicodeEncoding]::new($false, $true))
    $lines | Set-Content "$dir\inputs.set"
    $ini = "$dir\tester.ini"
    @"
[Tester]
Expert=MyEA\Dev\GS15_dev.ex5
ExpertParameters=$set
Symbol=GOLD
Period=M15
Model=$($r.Model)
Optimization=0
ForwardMode=0
FromDate=$($r.From)
ToDate=$($r.To)
Deposit=$($r.Deposit)
Currency=USD
Leverage=100
ExecutionMode=$($r.Delay)
Visual=0
Report=reports\night_$($r.Name)
ReplaceReport=1
ShutdownTerminal=1
"@ | Set-Content $ini -Encoding Unicode
    foreach ($j in "GS15_journal_GOLD_20261013_tester.csv", "GS15_smc_journal_GOLD_20261013_tester.csv", "GS15_probe_GOLD_20261013_tester.csv", "GS15_stress_GOLD_20261013_tester.csv") { if (Test-Path "$Common\$j") { [IO.File]::Delete("$Common\$j") } }
    Log-Terminals 'before'
    $start = Get-Date
    # Minimised, so the test window is not mistaken for the live terminal.
    $p = Start-Process $Term -ArgumentList '/portable', "/config:`"$ini`"" -WorkingDirectory $Mt5 -WindowStyle Minimized -PassThru
    $timeout = if ($r.Model -eq 4) { 120 } else { 75 }
    if (-not $p.WaitForExit($timeout * 60000)) { try { $p.Kill() } catch {}; throw "timeout after $timeout min" }
    Log-Terminals 'after'
    $htm = "$Data\reports\night_$($r.Name).htm"
    if (-not (Test-Path $htm) -or (Get-Item $htm).LastWriteTime -lt $start) { throw 'no fresh report' }
    Copy-Item $htm "$dir\report.htm" -Force
    foreach ($j in "GS15_journal_GOLD_20261013_tester.csv", "GS15_smc_journal_GOLD_20261013_tester.csv", "GS15_probe_GOLD_20261013_tester.csv", "GS15_stress_GOLD_20261013_tester.csv") { if (Test-Path "$Common\$j") { Copy-Item "$Common\$j" "$dir\" -Force } }
    $agentLog = Get-ChildItem $Agents -Recurse -Filter '*.log' | Where-Object { $_.FullName -match '\\logs\\' -and $_.LastWriteTime -ge $start } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($agentLog) {
        Get-Content $agentLog.FullName -Encoding Unicode | Where-Object { $_ -match 'Risk guard|error|range|critical|failed|final balance|history|quality|ticks|bars|SMC|generated|test passed|stopped' } |
            Select-Object -Last 600 | Set-Content "$dir\tester_excerpt.log" -Encoding UTF8
    }
    $s = Get-LabSummary "$dir\report.htm"
    $row = [ordered]@{ Run = $r.Name; From = $r.From; To = $r.To; Model = $r.Model; Delay = $r.Delay; Deposit = $r.Deposit; Inputs = ($lines -join ';'); Minutes = [int]((Get-Date) - $start).TotalMinutes }
    foreach ($pp in $s.PSObject.Properties) { $row[$pp.Name] = $pp.Value }
    [pscustomobject]$row | Export-Csv "$Suite\summary.csv" -Append -NoTypeInformation -Encoding UTF8
    Log ("done {0}: net {1} PF {2} DD {3}% trades {4} ({5} min)" -f $r.Name, $s.Net, $s.PF, $s.DDpct, $s.Trades, $row.Minutes)
}

$stopped = $false
try {
    if (-not $Now) { Wait-Until $StartAt }
    $stopTime = [datetime]::ParseExact($StopAt, 'HH:mm', $null); if ($stopTime -lt (Get-Date)) { $stopTime = $stopTime.AddDays(1) }

    # The status file must be live: a copy that is not updating (MT5 not running, or this script
    # started where it cannot see MT5's files) cannot tell whether a position is open.
    if (Get-MainTerminal) {
        $sf = "$Common\GS15_GOLD_20261013_status.txt"
        $age = if (Test-Path $sf) { ((Get-Date) - (Get-Item $sf).LastWriteTime).TotalMinutes } else { 999 }
        if ($age -gt 3) { throw ("EA status file is {0:N0} min old - cannot check for open positions; start the suite with tools\Run-Backtests-*.cmd" -f $age) }
    }

    # Do not stop MT5 while this EA holds a position.
    for ($i = 0; $i -lt 60; $i++) {
        $st = Get-Content "$Common\GS15_GOLD_20261013_status.txt" -Encoding Unicode -ErrorAction SilentlyContinue
        if (-not $st -or ($st -match '^position=none$')) { break }
        Log 'EA has an open position - waiting'; Start-Sleep 60
    }
    if ($st -and -not ($st -match '^position=none$')) { throw 'position still open after 60 min - suite cancelled' }

    $mt = Get-MainTerminal
    if ($mt) {
        Log 'closing MT5 (demo terminal) gracefully'
        [void]$mt.CloseMainWindow()
        if (-not $mt.WaitForExit(60000)) { throw 'MT5 did not close' }
        $stopped = $true
    }

    # Compile the experimental source into the tester slot (Experts\MyEA\Dev), not the live EA.
    $clog = "$Suite\compile.log"
    New-Item -ItemType Directory -Force "$Data\MQL5\Experts\MyEA\Dev" | Out-Null
    Start-Process $Editor -ArgumentList '/portable', "/compile:`"$Repo\GoldScalperM15.mq5`"", "/include:`"$Data\MQL5`"", "/log:`"$clog`"" -Wait
    $res = Get-Content $clog -Encoding Unicode | Select-String 'Result:' | Select-Object -Last 1
    Log "compile: $res"
    if (-not (Test-Path "$Repo\GoldScalperM15.ex5")) { throw 'compile failed' }
    Copy-Item "$Repo\GoldScalperM15.ex5" "$Data\MQL5\Experts\MyEA\Dev\GS15_dev.ex5" -Force
    Log ('source sha256 ' + (Get-FileHash "$Repo\GoldScalperM15.mq5").Hash.Substring(0, 12) + ', commit ' + (git -C $Repo rev-parse --short HEAD))

    foreach ($r in $runs) {
        if (Test-Path $StopFile) { Log 'STOP file - ending suite'; break }
        if ((Get-Date) -gt $stopTime) { Log "past $StopAt - no new runs"; break }
        if ($SkipDone -and (Test-Path "$Suite\$($r.Name)\report.htm")) { Log "skip $($r.Name) (already done)"; continue }
        Log "start $($r.Name)"
        try { Run-One $r } catch { Log "FAILED $($r.Name): $($_.Exception.Message)" }
    }
} catch {
    Log "suite error: $($_.Exception.Message)"
} finally {
    if (-not $NoRestart -and ($stopped -or -not (Get-MainTerminal))) {
        Log 'starting MT5 again (demo terminal)'
        Start-Process $Term -ArgumentList '/portable' -WorkingDirectory $Mt5
    }
    Log 'suite finished'
    Set-Content "$Suite\DONE" (Get-Date).ToString('s')
}
