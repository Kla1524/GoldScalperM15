# Night of 21-22 Oct 2026 (v1.54 build, all new options off by default). Runs after midnight Thai, demo idle.
$p = @(
    @{ Tag = 'DEV';   From = '2018.01.01'; To = '2023.12.31'; Model = 1 },
    @{ Tag = 'VAL';   From = '2024.01.01'; To = '2026.10.12'; Model = 1 },
    @{ Tag = 'VALRT'; From = '2024.10.14'; To = '2026.10.12'; Model = 4 }
)
function Grid($cfg) { foreach ($c in $cfg.Keys) { foreach ($x in $p) { @{ Name = "$($c)_$($x.Tag)"; From = $x.From; To = $x.To; Model = $x.Model; Deposit = 10000; Delay = 0; Inputs = $cfg[$c] } } } }
# 0. regression: v1.54 defaults = v1.53 (suite_20261018_final BASE153_*)
Grid ([ordered]@{ 'REG154' = @{} })
# 1. the clip ideas
Grid ([ordered]@{
    'SAL_unlimited_stopafterloss' = @{ InpMaxTradesPerDay = 0; InpStopDayAfterLoss = 'true' }
    'MON_skip'                    = @{ InpSkipMonday = 'true' }
    'RT8_retest'                  = @{ InpRetestEntry = 'true'; InpRetestMaxBars = 8 }
    'RT4_retest'                  = @{ InpRetestEntry = 'true'; InpRetestMaxBars = 4 }
})
# 2. trades per day, session timing, profit lock (plans written 20-21 Oct)
& "$PSScriptRoot\trades_per_day_v153.ps1"
& "$PSScriptRoot\session_timing_v153.ps1"
& "$PSScriptRoot\profit_lock_v153.ps1"
# 3. risk per trade (cap 1 %; DD cap 20 % checked with Monte Carlo afterwards)
Grid ([ordered]@{ 'RISK075' = @{ InpRiskPct = 0.75 }; 'RISK100' = @{ InpRiskPct = 1.0 } })
# 4. demo outages 19-21 Oct: did the live settings (unlimited trades) have signals?
@{ Name = 'GAPCHECK_live_settings_RT'; From = '2026.10.12'; To = '2026.10.21'; Model = 4; Deposit = 10000; Delay = 0; Inputs = @{ InpMaxTradesPerDay = 0 } }
