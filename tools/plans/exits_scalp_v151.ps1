# Exit rules and the Scalp variant (17 Oct 2026, v1.51, $10,000, news +/-15). Every run has an SL; most also a TP.
# Baseline = v1.51 defaults (suite_20261017_v151 REG151_D0_*): one trade a day, SL 4 ATR, no TP, entries 08-18 server, close 20:00.
$periods = @(
    @{ Tag = 'DEV';   From = '2018.01.01'; To = '2023.12.31'; Model = 1 },
    @{ Tag = 'VAL';   From = '2024.01.01'; To = '2026.10.12'; Model = 1 },
    @{ Tag = 'VALRT'; From = '2024.10.14'; To = '2026.10.12'; Model = 4 }
)
$configs = [ordered]@{
    'A_be1'      = @{ InpBE_ATR = 1 }                                          # SL to entry at +1 ATR
    'B_trail2'   = @{ InpTrailStart_ATR = 2; InpTrail_ATR = 2 }                # trailing SL 2 ATR behind, from +2 ATR
    'B_trail3'   = @{ InpTrailStart_ATR = 3; InpTrail_ATR = 3 }
    'T_tp4'      = @{ InpTP_ATR = 4 }                                          # TP 4 ATR = 1:1 with the 4 ATR SL
    'N0_24h'     = @{ InpEndHour = 24 }                                        # no 18:00 entry stop (one trade a day, no TP)
    'S1_sl2tp2_trend_close'   = @{ InpMaxTradesPerDay = 0; InpSL_ATR = 2; InpTP_ATR = 2; InpUseTrend = 'true'; InpEndHour = 24 }
    'S2_sl2tp2_trend_noclose' = @{ InpMaxTradesPerDay = 0; InpSL_ATR = 2; InpTP_ATR = 2; InpUseTrend = 'true'; InpEndHour = 24; InpDailyCloseHour = -1 }
    'S3_sl15tp15_trend_noclose' = @{ InpMaxTradesPerDay = 0; InpSL_ATR = 1.5; InpTP_ATR = 1.5; InpUseTrend = 'true'; InpEndHour = 24; InpDailyCloseHour = -1 }
    'S4_sl2tp2_notrend_noclose' = @{ InpMaxTradesPerDay = 0; InpSL_ATR = 2; InpTP_ATR = 2; InpEndHour = 24; InpDailyCloseHour = -1 }
    'S5_sl4tp4_trend_noclose' = @{ InpMaxTradesPerDay = 0; InpSL_ATR = 4; InpTP_ATR = 4; InpUseTrend = 'true'; InpEndHour = 24; InpDailyCloseHour = -1 }
}
foreach ($c in $configs.Keys) {
    foreach ($p in $periods) {
        @{ Name = "$($c)_$($p.Tag)"; From = $p.From; To = $p.To; Model = $p.Model; Deposit = 10000; Delay = 0; Inputs = $configs[$c] }
    }
}
