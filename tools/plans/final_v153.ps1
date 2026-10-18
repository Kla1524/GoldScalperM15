# v1.53 final check (18 Oct 2026): Friday-close audit added; trades must equal the earlier v1.53 runs (suite_20261018_guard).
$p = @(
    @{ Tag = 'DEV';   From = '2018.01.01'; To = '2023.12.31'; Model = 1 },
    @{ Tag = 'VAL';   From = '2024.01.01'; To = '2026.10.12'; Model = 1 },
    @{ Tag = 'VALRT'; From = '2024.10.14'; To = '2026.10.12'; Model = 4 }
)
foreach ($x in $p) { @{ Name = "BASE153_$($x.Tag)"; From = $x.From; To = $x.To; Model = $x.Model; Deposit = 10000; Delay = 0; Inputs = @{} } }
foreach ($x in $p) { @{ Name = "W1ag_$($x.Tag)"; From = $x.From; To = $x.To; Model = $x.Model; Deposit = 10000; Delay = 0; Inputs = @{ InpDailyCloseHour = 23 } } }
