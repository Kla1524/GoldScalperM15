# Big-run profit lock (user's question 21 Oct 2026): leave normal trades alone, trail only after a large gain.
# InpTrailStart_ATR = gain that switches the trailing stop on; InpTrail_ATR = distance behind price. Compare with BASE153_* (no lock).
$p = @(
    @{ Tag = 'DEV';   From = '2018.01.01'; To = '2023.12.31'; Model = 1 },
    @{ Tag = 'VAL';   From = '2024.01.01'; To = '2026.10.12'; Model = 1 },
    @{ Tag = 'VALRT'; From = '2024.10.14'; To = '2026.10.12'; Model = 4 }
)
$cfg = [ordered]@{
    'LOCK6_trail3'  = @{ InpTrailStart_ATR = 6;  InpTrail_ATR = 3 }
    'LOCK6_trail4'  = @{ InpTrailStart_ATR = 6;  InpTrail_ATR = 4 }
    'LOCK8_trail3'  = @{ InpTrailStart_ATR = 8;  InpTrail_ATR = 3 }
    'LOCK8_trail4'  = @{ InpTrailStart_ATR = 8;  InpTrail_ATR = 4 }
    'LOCK10_trail4' = @{ InpTrailStart_ATR = 10; InpTrail_ATR = 4 }
}
foreach ($c in $cfg.Keys) { foreach ($x in $p) { @{ Name = "$($c)_$($x.Tag)"; From = $x.From; To = $x.To; Model = $x.Model; Deposit = 10000; Delay = 0; Inputs = $cfg[$c] } } }
