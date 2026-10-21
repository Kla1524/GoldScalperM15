# Same strategy on other instruments (rules in reports\OTHER_SYMBOLS_RULES.txt).
$p = @(
    @{ Tag = 'DEV';   From = '2018.01.01'; To = '2023.12.31'; Model = 1 },
    @{ Tag = 'VAL';   From = '2024.01.01'; To = '2026.10.12'; Model = 1 },
    @{ Tag = 'VALRT'; From = '2024.10.14'; To = '2026.10.12'; Model = 4 }
)
$in = @{ InpDailyCloseHour = 19; InpRiskPct = 0.5; InpMinDailyATRPct = 0; InpMaxSpread = 1000000 }
foreach ($s in 'GOLD', 'SILVER', 'US100Cash', 'US30Cash', 'US500Cash', 'GER40Cash', 'JP225Cash', 'EURUSD', 'GBPUSD', 'USDJPY', 'BTCUSD') {
    foreach ($x in $p) { @{ Name = "SYM_$($s)_$($x.Tag)"; Symbol = $s; From = $x.From; To = $x.To; Model = $x.Model; Deposit = 10000; Delay = 0; Inputs = $in } }
}
