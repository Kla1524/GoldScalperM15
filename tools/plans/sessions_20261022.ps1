# Session range breakout (rules fixed in SESSION_RULES.txt). GS_Sessions_Lab, $10,000, 0.5 % risk per system.
$p = @(
    @{ Tag = 'DEV';   From = '2018.01.01'; To = '2023.12.31'; Model = 1 },
    @{ Tag = 'VAL';   From = '2024.01.01'; To = '2026.10.12'; Model = 1 },
    @{ Tag = 'VALRT'; From = '2024.10.14'; To = '2026.10.12'; Model = 4 }
)
$sets = [ordered]@{ 'S1_ASIA' = 1; 'S2_LONDON' = 2; 'S4_NEWYORK' = 4; 'S3_ASIA_LONDON' = 3; 'S5_ASIA_NEWYORK' = 5; 'S7_ALL' = 7 }
foreach ($k in $sets.Keys) { foreach ($x in $p) { @{ Name = "$($k)_$($x.Tag)"; From = $x.From; To = $x.To; Model = $x.Model; Deposit = 10000; Delay = 0; Inputs = @{ InpSessions = $sets[$k] } } } }
foreach ($k in 'S1_ASIA', 'S7_ALL') { @{ Name = "$($k)_VALRT_delayrnd"; From = '2024.10.14'; To = '2026.10.12'; Model = 4; Deposit = 10000; Delay = -1; Inputs = @{ InpSessions = $sets[$k] } } }
