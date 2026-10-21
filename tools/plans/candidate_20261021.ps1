# Final candidate (21 Oct 2026): defaults (1 trade a day) + close 19:00 server (23:00 Thai until 1 Nov) + risk 0.75 %.
$p = @(
    @{ Tag = 'DEV';   From = '2018.01.01'; To = '2023.12.31'; Model = 1 },
    @{ Tag = 'VAL';   From = '2024.01.01'; To = '2026.10.12'; Model = 1 },
    @{ Tag = 'VALRT'; From = '2024.10.14'; To = '2026.10.12'; Model = 4 }
)
$in = @{ InpDailyCloseHour = 19; InpRiskPct = 0.75 }
foreach ($x in $p) { @{ Name = "CAND_close19_risk075_$($x.Tag)"; From = $x.From; To = $x.To; Model = $x.Model; Deposit = 10000; Delay = 0; Inputs = $in } }
@{ Name = 'CAND_close19_risk075_VALRT_delayrnd'; From = '2024.10.14'; To = '2026.10.12'; Model = 4; Deposit = 10000; Delay = -1; Inputs = $in }
