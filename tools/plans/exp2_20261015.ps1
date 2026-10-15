# Experiment 2 (15 Oct 2026). Deposit 10,000, risk 0.5 %, random execution delay, news filter at its default (high impact +/-30 min).
# REG: the R1 / R6 settings of suite_20261015 must still give identical results (probes off).
# U0-U2: trades per day and loss cooldown, with probes on (signals skipped because a position was open, MFE/MAE).
# M3P: mode 3 baseline with probes on (MFE/MAE after every M5 confirmation). Probes never trade.
$periods = @(
    @{ Tag = 'DEV';   From = '2018.01.01'; To = '2023.12.31'; Model = 1 },
    @{ Tag = 'VAL';   From = '2024.01.01'; To = '2026.10.12'; Model = 1 },
    @{ Tag = 'VALRT'; From = '2024.10.14'; To = '2026.10.12'; Model = 4 }
)
@{ Name = 'REG_R1_mode1_nonews_1min_3k'; From = '2018.01.01'; To = '2026.10.12'; Model = 1; Deposit = 3000; Delay = 0; Inputs = @{ InpNewsInTester = 'false' } }
@{ Name = 'REG_R6_smc_1min_2018_2026_3k'; From = '2018.01.01'; To = '2026.10.12'; Model = 1; Deposit = 3000; Delay = 0; Inputs = @{ InpTradeStyle = 3 } }
$configs = [ordered]@{
    'U0_mode1_cd20'      = @{ InpTradeStyle = 1; InpRiskPct = 0.5; InpLossCooldownMin = 20; InpProbeLog = 'true' }
    'U1_mode2_cd20'      = @{ InpTradeStyle = 2; InpMultiRiskPct = 0.5; InpLossCooldownMin = 20; InpProbeLog = 'true' }
    'U2_mode2_cd0'       = @{ InpTradeStyle = 2; InpMultiRiskPct = 0.5; InpLossCooldownMin = 0; InpProbeLog = 'true' }
    'M3P_base_probes'    = @{ InpTradeStyle = 3; InpProbeLog = 'true' }
}
foreach ($c in $configs.Keys) {
    foreach ($p in $periods) {
        @{ Name = "$($c)_$($p.Tag)"; From = $p.From; To = $p.To; Model = $p.Model; Deposit = 10000; Delay = -1; Inputs = $configs[$c] }
    }
}
