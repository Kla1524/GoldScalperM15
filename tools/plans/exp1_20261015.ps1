# Experiment 1 (15 Oct 2026). One change at a time against the baseline, same costs for every run.
# Deposit 10,000, risk 0.5 % per trade, random execution delay (ExecutionMode -1) everywhere.
# Development 2018-2023 (1-min OHLC); validation 2024-2026 (1-min OHLC) and Oct 2024 - Oct 2026 (real ticks).
$periods = @(
    @{ Tag = 'DEV';   From = '2018.01.01'; To = '2023.12.31'; Model = 1 },
    @{ Tag = 'VAL';   From = '2024.01.01'; To = '2026.10.12'; Model = 1 },
    @{ Tag = 'VALRT'; From = '2024.10.14'; To = '2026.10.12'; Model = 4 }
)
$configs = [ordered]@{
    # Mode 1, news filter variants (everything else identical)
    'N0_nonews'      = @{ InpRiskPct = 0.5; InpNewsInTester = 'false' }
    'N30_high'       = @{ InpRiskPct = 0.5 }                                                   # current default: high impact +/-30 min
    'N15_high'       = @{ InpRiskPct = 0.5; InpNewsMinsBefore = 15; InpNewsMinsAfter = 15 }
    'NKEY_nfp_cpi_fomc' = @{ InpRiskPct = 0.5; InpNewsOnlyEvents = 'Nonfarm Payrolls,CPI,FOMC,Fed Interest Rate Decision' }
    # Mode 3, one variable at a time
    'M3_base'        = @{ InpTradeStyle = 3 }
    'M3A_tp2R'       = @{ InpTradeStyle = 3; InpSmcTpMode = 1; InpSmcTpR = 2.0 }
    'M3B_skipnear1atr' = @{ InpTradeStyle = 3; InpSmcTpMinDistAtr = 1.0 }
    'M3C_loosebias'  = @{ InpTradeStyle = 3; InpSmcBiasLoose = 'true' }
    'M3D_expiry32'   = @{ InpTradeStyle = 3; InpSmcExpiryBars = 32 }
}
foreach ($c in $configs.Keys) {
    foreach ($p in $periods) {
        @{ Name = "$($c)_$($p.Tag)"; From = $p.From; To = $p.To; Model = $p.Model; Deposit = 10000; Delay = -1; Inputs = $configs[$c] }
    }
}
