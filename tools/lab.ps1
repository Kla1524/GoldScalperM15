# Lab backtests on a separate, portable MT5 (D:\EA_Trade_lab\mt5) that is NOT the terminal
# running the demo account. Every run gets a run ID and a folder under reports\experiments\runs
# with the ini, the inputs, the HTML report, the tester log excerpt and a meta.json.
#
#   . D:\EA_Trade_lab\repo\tools\lab.ps1
#   Build-Lab                       # compile the worktree source with the lab MetaEditor
#   Invoke-LabRun -Tag base -From 2018.01.01 -To 2026.10.12 -Model 1 -Deposit 3000 -Inputs @{}
#
# Results are appended to reports\experiments\runs.csv.

$script:LabRoot  = 'D:\EA_Trade_lab'
$script:Repo     = "$script:LabRoot\repo"
$script:Mt5      = "$script:LabRoot\mt5"
$script:Term     = "$script:Mt5\terminal64.exe"
$script:Editor   = "$script:Mt5\MetaEditor64.exe"
$script:ExpDir   = "$script:Repo\reports\experiments"
$script:RunsDir  = "$script:ExpDir\runs"
$script:EaRel    = 'Lab\GS15_lab.ex5'
$script:LabLogin  = $env:GS15_LAB_LOGIN  # account number of the account logged in on the lab terminal (set it in your session)
$script:LabServer = 'XMGlobal-MT5 2'

function Get-SourceHash {
    (Get-FileHash "$script:Repo\GoldScalperM15.mq5" -Algorithm SHA256).Hash.Substring(0, 12)
}

function Build-Lab {
    $src = "$script:Repo\GoldScalperM15.mq5"
    $ex5 = "$script:Repo\GoldScalperM15.ex5"
    $log = "$script:ExpDir\compile.log"
    New-Item -ItemType Directory -Force $script:ExpDir, "$script:Mt5\MQL5\Experts\Lab" | Out-Null
    if (Test-Path $ex5) { Remove-Item $ex5 }
    $p = Start-Process $script:Editor -ArgumentList '/portable', "/compile:`"$src`"", "/include:`"$script:Mt5\MQL5`"", "/log:`"$log`"" -Wait -PassThru
    $summary = Get-Content $log -Encoding Unicode | Where-Object { $_ -match '\d+ errors?, \d+ warnings?' -or ($_ -match ' error | warning ' -and $_ -notmatch 'information') }
    if (-not (Test-Path $ex5)) { $summary; throw 'compile failed' }
    Copy-Item $ex5 "$script:Mt5\MQL5\Experts\$script:EaRel" -Force
    [pscustomobject]@{ Exit = $p.ExitCode; Log = ($summary -join ' | '); SourceHash = Get-SourceHash }
}

function Invoke-LabRun {
    param(
        [Parameter(Mandatory)] [string]$Tag,
        [string]$From = '2018.01.01',
        [string]$To = '2026.10.12',
        [int]$Model = 1,                 # 0 every tick, 1 1-minute OHLC, 4 real ticks
        [double]$Deposit = 3000,
        [string]$Symbol = 'GOLD',
        [hashtable]$Inputs = @{},
        [int]$Delay = 0,                 # ExecutionMode: 0 = no delay, -1 = random delay, N = fixed ms
        [string]$Note = '',
        [int]$TimeoutMin = 60
    )
    if (Get-Process terminal64 -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $script:Term }) {
        throw 'lab terminal already running - one run at a time'
    }
    $hash  = Get-SourceHash
    $runId = '{0:yyyyMMdd-HHmmss}_{1}' -f (Get-Date), $Tag
    $dir   = "$script:RunsDir\$runId"
    New-Item -ItemType Directory -Force $dir, "$script:Mt5\reports" | Out-Null

    $all = [ordered]@{ InpNotifyPush = 'false'; InpShowPanel = 'false'; InpConsole = 'false' }
    foreach ($k in $Inputs.Keys) { $all[$k] = "$($Inputs[$k])".ToLower() }
    $setName = "lab_$runId.set"
    $setLines = [string[]]($all.Keys | ForEach-Object { "$_=$($all[$_])" })
    [IO.File]::WriteAllLines("$script:Mt5\MQL5\Profiles\Tester\$setName", $setLines, [Text.UnicodeEncoding]::new($false, $true))
    $setLines | Set-Content "$dir\inputs.set"

    $ini = "$dir\tester.ini"
    # The tester refuses to start without an account number. Only the number is given (no
    # password): the lab terminal cannot connect or trade and tests run on the copied history.
    @"
[Common]
Login=$script:LabLogin
Server=$script:LabServer
[Tester]
Expert=$script:EaRel
ExpertParameters=$setName
Symbol=$Symbol
Period=M15
Model=$Model
Optimization=0
ForwardMode=0
FromDate=$From
ToDate=$To
Deposit=$Deposit
Currency=USD
Leverage=100
ExecutionMode=$Delay
Visual=0
Report=reports\lab_$runId
ReplaceReport=1
ShutdownTerminal=1
"@ | Set-Content $ini -Encoding Unicode

    $started = Get-Date
    $proc = Start-Process $script:Term -ArgumentList '/portable', "/config:`"$ini`"" -PassThru
    if (-not $proc.WaitForExit($TimeoutMin * 60 * 1000)) {
        try { $proc.Kill() } catch {}
        throw "timeout after $TimeoutMin min: $runId"
    }
    $htm = "$script:Mt5\reports\lab_$runId.htm"
    if (-not (Test-Path $htm)) { throw "no report produced: $runId (see $script:Mt5\logs and Tester\logs)" }
    if ((Get-Item $htm).LastWriteTime -lt $started) { throw "stale report: $runId" }
    Copy-Item $htm "$dir\report.htm"
    Get-ChildItem "$script:Mt5\reports" -Filter "lab_$runId*.png" -ErrorAction SilentlyContinue | Copy-Item -Destination $dir

    # Tester agent log lines from this run (EA prints, guard counts, errors).
    $agentLog = Get-ChildItem "$script:Mt5\Tester" -Recurse -Filter '*.log' -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -match 'Agent.*\\logs' -and $_.LastWriteTime -ge $started } |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($agentLog) {
        Get-Content $agentLog.FullName -Encoding Unicode |
            Where-Object { $_ -match 'Risk guard|Skipped|error|failed|final balance|test passed|lot reduced|history|quality|ticks|bars' } |
            Select-Object -Last 400 | Set-Content "$dir\tester_excerpt.log" -Encoding UTF8
    }

    $s = Get-LabSummary "$dir\report.htm"
    $meta = [ordered]@{
        RunId = $runId; Tag = $Tag; Note = $Note; SourceHash = $hash
        Commit = (git -C $script:Repo rev-parse --short HEAD); Dirty = [bool](git -C $script:Repo status --porcelain GoldScalperM15.mq5)
        Symbol = $Symbol; Server = 'XM Global (lab copy of local history)'; From = $From; To = $To
        Model = $Model; Delay = $Delay; Deposit = $Deposit; Inputs = ($setLines -join ';')
        Seconds = [int]((Get-Date) - $started).TotalSeconds; ExitCode = $proc.ExitCode
    }
    foreach ($p in $s.PSObject.Properties) { $meta[$p.Name] = $p.Value }
    ([pscustomobject]$meta) | ConvertTo-Json -Depth 3 | Set-Content "$dir\meta.json" -Encoding UTF8
    ([pscustomobject]$meta) | Select-Object RunId, Tag, SourceHash, Commit, From, To, Model, Delay, Deposit, Net, PF, DDpct, Trades,
        WinPct, AvgWin, AvgLoss, Expectancy, MaxLossStreak, Recovery, Quality, Years, Inputs, Note |
        Export-Csv "$script:ExpDir\runs.csv" -Append -NoTypeInformation -Encoding UTF8
    [pscustomobject]$meta
}

# Parses the MT5 HTML report (same approach as tools\backtest.ps1) and writes the closing
# deals to deals.csv next to it.
function Get-LabSummary([string]$Path) {
    $h = [IO.File]::ReadAllText($Path)
    $cut = $h.IndexOf('<b>Orders</b>'); if ($cut -lt 0) { $cut = $h.Length }
    $t = $h.Substring(0, $cut) -replace '<[^>]+>', ' ' -replace '&nbsp;', ' ' -replace '\s+', ' '
    function num($pattern) { if ($t -match $pattern) { [double]($Matches[1] -replace ' ', '') } else { [double]::NaN } }
    function txt($pattern) { if ($t -match $pattern) { $Matches[1].Trim() } else { '' } }

    $deals = New-Object System.Collections.Generic.List[object]
    $di = $h.IndexOf('<b>Deals</b>')
    if ($di -ge 0) {
        foreach ($r in [regex]::Matches($h.Substring($di), '<tr[^>]*>(.*?)</tr>', 'Singleline')) {
            $c = @([regex]::Matches($r.Groups[1].Value, '<td[^>]*>(.*?)</td>', 'Singleline') | ForEach-Object { ($_.Groups[1].Value -replace '<[^>]+>', '').Trim() })
            if ($c.Count -ge 13 -and $c[4] -eq 'out') {
                $pl = [double]($c[10] -replace ' ', '') + [double]($c[9] -replace ' ', '') + [double]($c[8] -replace ' ', '')
                $deals.Add([pscustomobject]@{ Time = $c[0]; Type = $c[3]; Volume = $c[5]; Price = $c[6]; PL = $pl; Balance = ($c[11] -replace ' ', ''); Comment = $c[12] })
            }
        }
    }
    $deals | Export-Csv ([IO.Path]::Combine([IO.Path]::GetDirectoryName($Path), 'deals.csv')) -NoTypeInformation -Encoding UTF8
    $years = [ordered]@{}; $streak = 0; $maxStreak = 0
    foreach ($d in $deals) {
        $y = $d.Time.Substring(0, 4); $years[$y] = $years[$y] + $d.PL
        if ($d.PL -lt 0) { $streak++; if ($streak -gt $maxStreak) { $maxStreak = $streak } } elseif ($d.PL -gt 0) { $streak = 0 }
    }
    [pscustomobject]@{
        Net        = num 'Total Net Profit: (-?[\d ]+\.\d+)'
        PF         = num 'Profit Factor: (-?[\d ]+\.\d+)'
        DDpct      = num 'Equity Drawdown Relative: ([\d.]+)%'
        Trades     = num 'Total Trades: (\d+)'
        WinPct     = num 'Profit Trades \(% of total\): \d+ \(([\d.]+)%\)'
        AvgWin     = num 'Average profit trade: (-?[\d ]+\.\d+)'
        AvgLoss    = num 'Average loss trade: (-?[\d ]+\.\d+)'
        Expectancy = num 'Expected Payoff: (-?[\d ]+\.\d+)'
        Recovery   = num 'Recovery Factor: (-?[\d ]+\.\d+)'
        MaxLossStreak = $maxStreak
        Quality    = txt 'History Quality: ([\d.]+%)'
        Years      = ($years.Keys | ForEach-Object { '{0}:{1:N0}' -f $_, $years[$_] }) -join ' '
    }
}
