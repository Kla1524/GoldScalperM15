# Experiment 3 (15 Oct 2026): robustness of the candidate before closing the work.
# Candidate = mode 1, 1 trade/day, risk 0.5 %, 20-min loss cooldown, high-impact news +/-15 min. Deposit 10,000.
# DLY: execution delay fixed 0 / 100 / 250 / 500 ms, and random (-1) five times.
# SPR: spread stress x1.5 and x2.0 (x1.0 = D0), delay 0.
# HALT: risk-guard halts like live - paused 7 days then a simulated Resume (main case, 7 days is an assumption),
#       and paused to the end of the test (comparison); the default (count and carry on) = D0. Delay 0.
# REG: the R1 / R6 settings of suite_20261015 must still give identical results.
$periods = @(
    @{ Tag = 'DEV';   From = '2018.01.01'; To = '2023.12.31'; Model = 1 },
    @{ Tag = 'VAL';   From = '2024.01.01'; To = '2026.10.12'; Model = 1 },
    @{ Tag = 'VALRT'; From = '2024.10.14'; To = '2026.10.12'; Model = 4 }
)
$cand = @{ InpTradeStyle = 1; InpRiskPct = 0.5; InpLossCooldownMin = 20; InpNewsMinsBefore = 15; InpNewsMinsAfter = 15 }
function With($extra) { $h = @{}; foreach ($k in $cand.Keys) { $h[$k] = $cand[$k] }; foreach ($k in $extra.Keys) { $h[$k] = $extra[$k] }; $h }
@{ Name = 'REG_R1_mode1_nonews_1min_3k'; From = '2018.01.01'; To = '2026.10.12'; Model = 1; Deposit = 3000; Delay = 0; Inputs = @{ InpNewsInTester = 'false' } }
@{ Name = 'REG_R6_smc_1min_2018_2026_3k'; From = '2018.01.01'; To = '2026.10.12'; Model = 1; Deposit = 3000; Delay = 0; Inputs = @{ InpTradeStyle = 3 } }
$configs = [ordered]@{
    'D0'    = @{ Delay = 0;   Inputs = (With @{}) }
    'D100'  = @{ Delay = 100; Inputs = (With @{}) }
    'D250'  = @{ Delay = 250; Inputs = (With @{}) }
    'D500'  = @{ Delay = 500; Inputs = (With @{}) }
    'RND1'  = @{ Delay = -1;  Inputs = (With @{}) }
    'RND2'  = @{ Delay = -1;  Inputs = (With @{}) }
    'RND3'  = @{ Delay = -1;  Inputs = (With @{}) }
    'RND4'  = @{ Delay = -1;  Inputs = (With @{}) }
    'RND5'  = @{ Delay = -1;  Inputs = (With @{}) }
    'S15'   = @{ Delay = 0;   Inputs = (With @{ InpTesterSpreadMult = 1.5 }) }
    'S20'   = @{ Delay = 0;   Inputs = (With @{ InpTesterSpreadMult = 2.0 }) }
    'H7'    = @{ Delay = 0;   Inputs = (With @{ InpTesterHaltDays = 7 }) }
    'HSTOP' = @{ Delay = 0;   Inputs = (With @{ InpTesterHaltDays = -1 }) }
}
foreach ($c in $configs.Keys) {
    foreach ($p in $periods) {
        @{ Name = "$($c)_$($p.Tag)"; From = $p.From; To = $p.To; Model = $p.Model; Deposit = 10000; Delay = $configs[$c].Delay; Inputs = $configs[$c].Inputs }
    }
}
