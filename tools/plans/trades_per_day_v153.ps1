# Trades per day on v1.53 (planned for Saturday 24 Oct 2026, market closed). Same defaults + session guard; only InpMaxTradesPerDay changes.
# Base (1 a day) = suite_20261018_final BASE153_*. Compare net, PF, equity DD, worst year, and the P/L of the 2nd+ trades of a day.
$p = @(
    @{ Tag = 'DEV';   From = '2018.01.01'; To = '2023.12.31'; Model = 1 },
    @{ Tag = 'VAL';   From = '2024.01.01'; To = '2026.10.12'; Model = 1 },
    @{ Tag = 'VALRT'; From = '2024.10.14'; To = '2026.10.12'; Model = 4 }
)
$cfg = [ordered]@{ 'TPD2' = @{ InpMaxTradesPerDay = 2 }; 'TPD3' = @{ InpMaxTradesPerDay = 3 }; 'TPD0_unlimited' = @{ InpMaxTradesPerDay = 0 } }
foreach ($c in $cfg.Keys) { foreach ($x in $p) { @{ Name = "$($c)_$($x.Tag)"; From = $x.From; To = $x.To; Model = $x.Model; Deposit = 10000; Delay = 0; Inputs = $cfg[$c] } } }
@{ Name = 'TPD0_unlimited_VALRT_delayrnd'; From = '2024.10.14'; To = '2026.10.12'; Model = 4; Deposit = 10000; Delay = -1; Inputs = @{ InpMaxTradesPerDay = 0 } }
