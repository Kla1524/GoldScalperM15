# v1.51 (17 Oct 2026): bot care (daily summary, start/stop notices, duplicate guard, losing-days halt, default off).
# REG151: the defaults must give exactly the v1.50 results (suite_20261017_reg150), trade by trade.
# LD2: the clip's rule "stop after 2 losing days", paused like live and resumed after 7 days (assumption), and stay paused.
$p = @(
    @{ Tag = 'DEV';   From = '2018.01.01'; To = '2023.12.31'; Model = 1 },
    @{ Tag = 'VAL';   From = '2024.01.01'; To = '2026.10.12'; Model = 1 },
    @{ Tag = 'VALRT'; From = '2024.10.14'; To = '2026.10.12'; Model = 4 }
)
@{ Name = 'REG151_R1_1pct_nonews_1min_3k'; From = '2018.01.01'; To = '2026.10.12'; Model = 1; Deposit = 3000; Delay = 0; Inputs = @{ InpRiskPct = 1.0; InpNewsInTester = 'false' } }
foreach ($x in $p) { @{ Name = "REG151_D0_$($x.Tag)"; From = $x.From; To = $x.To; Model = $x.Model; Deposit = 10000; Delay = 0; Inputs = @{} } }
foreach ($x in $p) { @{ Name = "LD2_resume7_$($x.Tag)"; From = $x.From; To = $x.To; Model = $x.Model; Deposit = 10000; Delay = 0; Inputs = @{ InpMaxLosingDays = 2; InpTesterHaltDays = 7 } } }
foreach ($x in $p) { @{ Name = "LD3_resume7_$($x.Tag)"; From = $x.From; To = $x.To; Model = $x.Model; Deposit = 10000; Delay = 0; Inputs = @{ InpMaxLosingDays = 3; InpTesterHaltDays = 7 } } }
