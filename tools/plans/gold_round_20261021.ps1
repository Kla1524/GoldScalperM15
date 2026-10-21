$p = @(
    @{ Tag = 'DEV';   From = '2018.01.01'; To = '2023.12.31'; Model = 1 },
    @{ Tag = 'VAL';   From = '2024.01.01'; To = '2026.10.12'; Model = 1 },
    @{ Tag = 'VALRT'; From = '2024.10.14'; To = '2026.10.12'; Model = 4 }
)
$base = @{ InpDailyCloseHour = 19; InpRiskPct = 0.75 }
function W($extra) { $h = $base.Clone(); foreach ($k in $extra.Keys) { $h[$k] = $extra[$k] }; $h }
$cfg = [ordered]@{ 'BASE155' = (W @{}); 'F1_judas' = (W @{ InpFilterJudas = 'true' }); 'F2_fvg' = (W @{ InpFilterFVG = 'true' }); 'F3_h1bias' = (W @{ InpFilterH1Bias = 'true' }); 'P1_pyramid' = (W @{ InpPyramid = 'true' }) }
foreach ($c in $cfg.Keys) { foreach ($x in $p) { @{ Name = "$($c)_$($x.Tag)"; From = $x.From; To = $x.To; Model = $x.Model; Deposit = 10000; Delay = 0; Inputs = $cfg[$c] } } }
