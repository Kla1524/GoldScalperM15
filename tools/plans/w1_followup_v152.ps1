# W1 follow-up (18 Oct 2026, v1.52 = v1.51 + no entries at/after the daily close hour). $10,000, news +/-15.
# REG152: defaults must equal v1.51 trade by trade. W1 split: later close only / entries to 20:00 / entries to 23:00.
# T6: TP 6 ATR = R:R 1:1.5. S1fix: Scalp S1 without the trades that opened after the daily close.
# Delay: random (-1) and 500 ms on real ticks for the base, W1a and W1.
$periods = @(
    @{ Tag = 'DEV';   From = '2018.01.01'; To = '2023.12.31'; Model = 1 },
    @{ Tag = 'VAL';   From = '2024.01.01'; To = '2026.10.12'; Model = 1 },
    @{ Tag = 'VALRT'; From = '2024.10.14'; To = '2026.10.12'; Model = 4 }
)
$configs = [ordered]@{
    'REG152'        = @{}
    'W1a_close23'   = @{ InpDailyCloseHour = 23 }
    'W1b_entry20_close23' = @{ InpEndHour = 20; InpDailyCloseHour = 23 }
    'W1_entry23_close23'  = @{ InpEndHour = 23; InpDailyCloseHour = 23 }
    'T6_tp6'        = @{ InpTP_ATR = 6 }
    'S1fix_sl2tp2_trend_close' = @{ InpMaxTradesPerDay = 0; InpSL_ATR = 2; InpTP_ATR = 2; InpUseTrend = 'true'; InpEndHour = 24 }
}
@{ Name = 'REG152_R1_1pct_nonews_1min_3k'; From = '2018.01.01'; To = '2026.10.12'; Model = 1; Deposit = 3000; Delay = 0; Inputs = @{ InpRiskPct = 1.0; InpNewsInTester = 'false' } }
foreach ($c in $configs.Keys) { foreach ($p in $periods) { @{ Name = "$($c)_$($p.Tag)"; From = $p.From; To = $p.To; Model = $p.Model; Deposit = 10000; Delay = 0; Inputs = $configs[$c] } } }
foreach ($c in 'REG152', 'W1a_close23', 'W1_entry23_close23') {
    foreach ($d in @(@{ T = 'rnd'; V = -1 }, @{ T = '500ms'; V = 500 })) {
        @{ Name = "$($c)_VALRT_delay$($d.T)"; From = '2024.10.14'; To = '2026.10.12'; Model = 4; Deposit = 10000; Delay = $d.V; Inputs = $configs[$c] }
    }
}
