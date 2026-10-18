# Diagnostics (18 Oct 2026): (a) daily close at 22:00 instead of 23:00 (no ticks after 22:59 in DST-mismatch weeks);
# (b) periods without trades: same defaults with the volatility filter off, to see whether it was the filter.
$p = @(
    @{ Tag = 'DEV';   From = '2018.01.01'; To = '2023.12.31'; Model = 1 },
    @{ Tag = 'VAL';   From = '2024.01.01'; To = '2026.10.12'; Model = 1 },
    @{ Tag = 'VALRT'; From = '2024.10.14'; To = '2026.10.12'; Model = 4 }
)
foreach ($x in $p) { @{ Name = "W1c_close22_$($x.Tag)"; From = $x.From; To = $x.To; Model = $x.Model; Deposit = 10000; Delay = 0; Inputs = @{ InpDailyCloseHour = 22 } } }
@{ Name = 'GAP_2018_2019H1_noATRfilter'; From = '2018.01.01'; To = '2019.07.03'; Model = 1; Deposit = 10000; Delay = 0; Inputs = @{ InpMinDailyATRPct = 0 } }
@{ Name = 'GAP_2018_2019H1_default';     From = '2018.01.01'; To = '2019.07.03'; Model = 1; Deposit = 10000; Delay = 0; Inputs = @{} }
@{ Name = 'GAP_2025Q1_noATRfilter';      From = '2025.01.01'; To = '2025.03.31'; Model = 4; Deposit = 10000; Delay = 0; Inputs = @{ InpMinDailyATRPct = 0 } }
@{ Name = 'GAP_2025Q3_noATRfilter';      From = '2025.07.01'; To = '2025.09.30'; Model = 4; Deposit = 10000; Delay = 0; Inputs = @{ InpMinDailyATRPct = 0 } }
