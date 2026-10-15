# Backtest helper for GoldScalperM15.
# Usage (PowerShell):
#   . D:\EA_Trade\tools\backtest.ps1
#   Build-Dev                                   # compile source -> MQL5\Experts\MyEA\Dev\GS15_dev.ex5
#   Invoke-Backtest -Name base -From 2018.01.01 -To 2023.12.31 -Inputs @{ InpSL_ATR = 1.5 }
# Results are appended to D:\EA_Trade\reports\results.csv; full reports go to reports\runs\.

$script:Root    = 'D:\EA_Trade'
$script:Data    = 'D:\MT5_GoldScalper'                  # portable MT5: program and data in one folder
$script:Term    = "$script:Data\terminal64.exe"
$script:Editor  = "$script:Data\MetaEditor64.exe"
$script:DevDir  = "$script:Data\MQL5\Experts\MyEA\Dev"
$script:RunsDir = "$script:Root\reports\runs"

function Build-Dev {
    $src = "$script:Root\GoldScalperM15.mq5"
    $ex5 = "$script:Root\GoldScalperM15.ex5"
    $log = "$script:Root\reports\compile.log"
    New-Item -ItemType Directory -Force "$script:Root\reports", $script:DevDir | Out-Null
    if (Test-Path $ex5) { Remove-Item $ex5 }
    Start-Process $script:Editor -ArgumentList '/portable', "/compile:`"$src`"", "/include:`"$script:Data\MQL5`"", "/log:`"$log`"" -Wait
    $result = (Get-Content $log -Encoding Unicode | Where-Object { $_ -match 'error|warning' -and $_ -notmatch 'information' })
    $result
    if (-not (Test-Path $ex5)) { throw 'compile failed' }
    Copy-Item $ex5 "$script:DevDir\GS15_dev.ex5" -Force
}

function Invoke-Backtest {
    param(
        [Parameter(Mandatory)] [string]$Name,
        [string]$From = '2018.01.01',
        [string]$To = '2023.12.31',
        [int]$Model = 1,                 # 0 every tick, 1 = 1-minute OHLC, 4 = real ticks
        [double]$Deposit = 1000,
        [string]$Period = 'M15',
        [string]$Symbol = 'GOLD',
        [hashtable]$Inputs = @{},
        [int]$TimeoutMin = 60
    )
    if (Get-Process terminal64 -ErrorAction SilentlyContinue) { throw 'MT5 is running - close it first' }
    New-Item -ItemType Directory -Force $script:RunsDir, "$script:Data\reports" | Out-Null

    # Inputs not listed fall back to the EA defaults. Alerts/panel are irrelevant in the tester.
    $all = @{ InpNotifyPush = 'false'; InpShowPanel = 'false' }
    foreach ($k in $Inputs.Keys) { $all[$k] = "$($Inputs[$k])".ToLower() }
    $setName = "GS15_bt_$Name.set"
    [IO.File]::WriteAllLines("$script:Data\MQL5\Profiles\Tester\$setName",
        [string[]]($all.Keys | Sort-Object | ForEach-Object { "$_=$($all[$_])" }), [Text.UnicodeEncoding]::new($false, $true))

    $ini = "$script:RunsDir\$Name.ini"
    @"
[Tester]
Expert=MyEA\Dev\GS15_dev.ex5
ExpertParameters=$setName
Symbol=$Symbol
Period=$Period
Model=$Model
Optimization=0
ForwardMode=0
FromDate=$From
ToDate=$To
Deposit=$Deposit
Currency=USD
Leverage=100
ExecutionMode=0
Visual=0
Report=reports\bt_$Name
ReplaceReport=1
ShutdownTerminal=1
"@ | Set-Content $ini -Encoding Unicode

    Get-ChildItem "$script:Data\reports" -Filter "bt_$Name.*" -ErrorAction SilentlyContinue | Remove-Item
    $proc = Start-Process $script:Term -ArgumentList '/portable', "/config:`"$ini`"" -WorkingDirectory $script:Data -PassThru
    if (-not $proc.WaitForExit($TimeoutMin * 60 * 1000)) {
        [void]$proc.CloseMainWindow(); Start-Sleep 15; if (-not $proc.HasExited) { $proc.Kill() }
        throw "timeout: $Name"
    }
    $htm = "$script:Data\reports\bt_$Name.htm"
    if (-not (Test-Path $htm)) { throw "no report produced: $Name" }
    Copy-Item $htm "$script:RunsDir\" -Force

    $s = Get-BacktestSummary "$script:RunsDir\bt_$Name.htm"
    $s | Add-Member -NotePropertyName Name -NotePropertyValue $Name -PassThru |
         Add-Member -NotePropertyName Range -NotePropertyValue "$From-$To" -PassThru |
         Add-Member -NotePropertyName Model -NotePropertyValue $Model -PassThru |
         Add-Member -NotePropertyName Inputs -NotePropertyValue (($Inputs.Keys | Sort-Object | ForEach-Object { "$_=$($Inputs[$_])" }) -join ';') -PassThru |
         Select-Object Name, Range, Model, Net, PF, DDpct, Trades, WinPct, AvgWin, AvgLoss, Years, Inputs |
         Export-Csv "$script:Root\reports\results.csv" -Append -NoTypeInformation -Encoding UTF8
    $s
}

# Genetic optimization with a built-in forward (out-of-sample) period.
# Ranges use MT5 syntax: @{ InpSL_ATR = '2||1||0.5||3||Y'; InpTF = 15 }  (fixed values are plain)
# Produces reports\runs\opt_<Name>.xml (in-sample) and opt_<Name>.forward.xml (forward).
function Invoke-Optimization {
    param(
        [Parameter(Mandatory)] [string]$Name,
        [string]$From = '2018.01.01',
        [string]$To = '2026.10.12',
        [string]$ForwardDate = '2024.01.01',
        [string]$Period = 'M15',
        [hashtable]$Inputs = @{},
        [int]$Mode = 2,                  # 1 = complete grid, 2 = genetic
        [int]$TimeoutMin = 240
    )
    if (Get-Process terminal64 -ErrorAction SilentlyContinue) { throw 'MT5 is running - close it first' }
    New-Item -ItemType Directory -Force $script:RunsDir, "$script:Data\reports" | Out-Null

    $all = @{ InpNotifyPush = 'false'; InpShowPanel = 'false'; InpNewsFilter = 'false' }
    foreach ($k in $Inputs.Keys) { $all[$k] = "$($Inputs[$k])".ToLower() -replace '\|\|y$', '||Y' -replace '\|\|n$', '||N' }
    $setName = "GS15_opt_$Name.set"
    [IO.File]::WriteAllLines("$script:Data\MQL5\Profiles\Tester\$setName",
        [string[]]($all.Keys | Sort-Object | ForEach-Object { "$_=$($all[$_])" }), [Text.UnicodeEncoding]::new($false, $true))

    $ini = "$script:RunsDir\opt_$Name.ini"
    @"
[Tester]
Expert=MyEA\Dev\GS15_dev.ex5
ExpertParameters=$setName
Symbol=GOLD
Period=$Period
Model=1
Optimization=$Mode
OptimizationCriterion=6
ForwardMode=4
ForwardDate=$ForwardDate
FromDate=$From
ToDate=$To
Deposit=1000
Currency=USD
Leverage=100
ExecutionMode=0
Visual=0
Report=reports\opt_$Name
ReplaceReport=1
ShutdownTerminal=1
"@ | Set-Content $ini -Encoding Unicode

    Get-ChildItem "$script:Data\reports" -Filter "opt_$Name*" -ErrorAction SilentlyContinue | Remove-Item
    $proc = Start-Process $script:Term -ArgumentList '/portable', "/config:`"$ini`"" -WorkingDirectory $script:Data -PassThru
    if (-not $proc.WaitForExit($TimeoutMin * 60 * 1000)) {
        [void]$proc.CloseMainWindow(); Start-Sleep 15; if (-not $proc.HasExited) { $proc.Kill() }
        throw "timeout: $Name"
    }
    Get-ChildItem "$script:Data\reports" -Filter "opt_$Name*.xml" | Copy-Item -Destination $script:RunsDir -Force
    Get-ChildItem $script:RunsDir -Filter "opt_$Name*.xml" | Select-Object Name, Length
}

# Reads an optimization XML report into objects (one per pass).
function Read-OptReport([string]$Path) {
    [xml]$x = Get-Content $Path -Raw
    $ns = New-Object Xml.XmlNamespaceManager $x.NameTable
    $ns.AddNamespace('ss', 'urn:schemas-microsoft-com:office:spreadsheet')
    $rows = $x.SelectNodes('//ss:Worksheet/ss:Table/ss:Row', $ns)
    $head = @($rows[0].SelectNodes('ss:Cell/ss:Data', $ns) | ForEach-Object { $_.InnerText })
    for ($i = 1; $i -lt $rows.Count; $i++) {
        $vals = @($rows[$i].SelectNodes('ss:Cell/ss:Data', $ns) | ForEach-Object { $_.InnerText })
        $o = [ordered]@{}
        for ($j = 0; $j -lt $head.Count; $j++) { $o[$head[$j]] = $vals[$j] }
        [pscustomobject]$o
    }
}

function Get-BacktestSummary([string]$Path) {
    $h = [IO.File]::ReadAllText($Path)
    $cut = $h.IndexOf('<b>Orders</b>'); if ($cut -lt 0) { $cut = $h.Length }
    $t = $h.Substring(0, $cut) -replace '<[^>]+>', ' ' -replace '&nbsp;', ' ' -replace '\s+', ' '
    function num($pattern) { if ($t -match $pattern) { [double]($Matches[1] -replace ' ', '') } else { [double]::NaN } }

    # yearly net from closing deals
    $years = @{}
    $di = $h.IndexOf('<b>Deals</b>')
    if ($di -ge 0) {
        foreach ($r in [regex]::Matches($h.Substring($di), '<tr[^>]*>(.*?)</tr>', 'Singleline')) {
            $c = @([regex]::Matches($r.Groups[1].Value, '<td[^>]*>(.*?)</td>', 'Singleline') | ForEach-Object { ($_.Groups[1].Value -replace '<[^>]+>', '').Trim() })
            if ($c.Count -ge 13 -and $c[4] -eq 'out') {
                $y = $c[0].Substring(0, 4)
                $pl = [double]($c[10] -replace ' ', '') + [double]($c[9] -replace ' ', '') + [double]($c[8] -replace ' ', '')
                $years[$y] = $years[$y] + $pl
            }
        }
    }
    [pscustomobject]@{
        Net     = num 'Total Net Profit: (-?[\d ]+\.\d+)'
        PF      = num 'Profit Factor: (-?[\d ]+\.\d+)'
        DDpct   = num 'Equity Drawdown Relative: ([\d.]+)%'
        Trades  = num 'Total Trades: (\d+)'
        WinPct  = num 'Profit Trades \(% of total\): \d+ \(([\d.]+)%\)'
        AvgWin  = num 'Average profit trade: (-?[\d ]+\.\d+)'
        AvgLoss = num 'Average loss trade: (-?[\d ]+\.\d+)'
        Years   = ($years.Keys | Sort-Object | ForEach-Object { '{0}:{1:N0}' -f $_, $years[$_] }) -join ' '
    }
}
