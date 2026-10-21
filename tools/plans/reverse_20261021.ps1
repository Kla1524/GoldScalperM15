# Stop and reverse (21 Oct 2026, user's idea): on the live set (close 19, risk 0.75 %, 1 trade a day) + InpReverseOnOpposite.
# REG = live set without reverse, must equal suite_20261021_candidate trade by trade.
$p = @(
    @{ Tag = 'DEV';   From = '2018.01.01'; To = '2023.12.31'; Model = 1 },
    @{ Tag = 'VAL';   From = '2024.01.01'; To = '2026.10.12'; Model = 1 },
    @{ Tag = 'VALRT'; From = '2024.10.14'; To = '2026.10.12'; Model = 4 }
)
$live = @{ InpDailyCloseHour = 19; InpRiskPct = 0.75 }
$rev  = @{ InpDailyCloseHour = 19; InpRiskPct = 0.75; InpReverseOnOpposite = 'true' }
foreach ($x in $p) { @{ Name = "LIVESET_$($x.Tag)"; From = $x.From; To = $x.To; Model = $x.Model; Deposit = 10000; Delay = 0; Inputs = $live } }
foreach ($x in $p) { @{ Name = "REVERSE_$($x.Tag)"; From = $x.From; To = $x.To; Model = $x.Model; Deposit = 10000; Delay = 0; Inputs = $rev } }
@{ Name = 'REVERSE_VALRT_delayrnd'; From = '2024.10.14'; To = '2026.10.12'; Model = 4; Deposit = 10000; Delay = -1; Inputs = $rev }
