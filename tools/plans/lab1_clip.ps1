# Lab test 1 (17 Oct 2026): ideas from the "Claude trades for me" clip, GS15_Lab.mq5, tester only.
# $10,000, same periods as the live-system tests. News filter on (+/-15 min, high-impact USD) in every run.
$periods = @(
    @{ Tag = 'DEV';   From = '2018.01.01'; To = '2023.12.31'; Model = 1 },
    @{ Tag = 'VAL';   From = '2024.01.01'; To = '2026.10.12'; Model = 1 },
    @{ Tag = 'VALRT'; From = '2024.10.14'; To = '2026.10.12'; Model = 4 }
)
$configs = [ordered]@{
    'S1_atr'   = @{ InpStrategy = 1 }                                   # EMA20/50 + Stochastic, SL 1.5 ATR, TP 1R, 0.5 % risk
    'S1_clip'  = @{ InpStrategy = 1; InpSLPts = 1000; InpTPPts = 1000 } # same entries, SL = TP = 1,000 points as in the clip
    'G1_clip'  = @{ InpStrategy = 2 }                                   # RSI martingale: 0.50 lot x2, 4 levels, step 500 pts, basket stop 27.5 %
    'G2_wide'  = @{ InpStrategy = 2; InpGridStepPts = 1000 }            # wider steps
    'G3_sl10'  = @{ InpStrategy = 2; InpBasketSLPct = 10 }              # basket stop 10 % of equity
}
foreach ($c in $configs.Keys) {
    foreach ($p in $periods) {
        @{ Name = "$($c)_$($p.Tag)"; From = $p.From; To = $p.To; Model = $p.Model; Deposit = 10000; Delay = 0; Inputs = $configs[$c] }
    }
}
