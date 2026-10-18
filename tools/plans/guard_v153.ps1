# v1.53 session guard (18 Oct 2026). REG153off: guard off must equal v1.52 trade by trade.
# BASE153 / T6g / W1ag: guard on (default). Delay checks on real ticks for the base and T6.
$p = @(
    @{ Tag = 'DEV';   From = '2018.01.01'; To = '2023.12.31'; Model = 1 },
    @{ Tag = 'VAL';   From = '2024.01.01'; To = '2026.10.12'; Model = 1 },
    @{ Tag = 'VALRT'; From = '2024.10.14'; To = '2026.10.12'; Model = 4 }
)
@{ Name = 'REG153off_R1_1pct_nonews_1min_3k'; From = '2018.01.01'; To = '2026.10.12'; Model = 1; Deposit = 3000; Delay = 0; Inputs = @{ InpRiskPct = 1.0; InpNewsInTester = 'false'; InpSessionGuard = 'false' } }
$cfg = [ordered]@{ 'REG153off' = @{ InpSessionGuard = 'false' }; 'BASE153' = @{}; 'T6g' = @{ InpTP_ATR = 6 }; 'W1ag' = @{ InpDailyCloseHour = 23 } }
foreach ($c in $cfg.Keys) { foreach ($x in $p) { @{ Name = "$($c)_$($x.Tag)"; From = $x.From; To = $x.To; Model = $x.Model; Deposit = 10000; Delay = 0; Inputs = $cfg[$c] } } }
foreach ($c in 'BASE153', 'T6g') { @{ Name = "$($c)_VALRT_delayrnd"; From = '2024.10.14'; To = '2026.10.12'; Model = 4; Deposit = 10000; Delay = -1; Inputs = $cfg[$c] } }
