# SMC / ICT models round 1 (21 Oct 2026): GS_SMC_Lab, each model alone, regime logged per trade (filter off). $10,000, 0.5 % risk, TP 2R.
$p = @(
    @{ Tag = 'DEV';   From = '2018.01.01'; To = '2023.12.31'; Model = 1 },
    @{ Tag = 'VAL';   From = '2024.01.01'; To = '2026.10.12'; Model = 1 },
    @{ Tag = 'VALRT'; From = '2024.10.14'; To = '2026.10.12'; Model = 4 }
)
$names = @{ 1 = 'M1_sweep_mss_fvg'; 2 = 'M2_turtle_soup'; 3 = 'M3_silver_bullet'; 4 = 'M4_ob_retest'; 5 = 'M5_range_fade' }
foreach ($m in 1..5) { foreach ($x in $p) { @{ Name = "$($names[$m])_$($x.Tag)"; From = $x.From; To = $x.To; Model = $x.Model; Deposit = 10000; Delay = 0; Inputs = @{ InpModel = $m } } } }
