# Regression after the v1.44 option changes: the same settings as R1 / R6 of suite_20261015 must give identical results.
@(
    @{ Name = 'REG_R1_mode1_nonews_1min_3k'; From = '2018.01.01'; To = '2026.10.12'; Model = 1; Deposit = 3000; Delay = 0; Inputs = @{ InpNewsInTester = 'false' } },
    @{ Name = 'REG_R6_smc_1min_2018_2026_3k'; From = '2018.01.01'; To = '2026.10.12'; Model = 1; Deposit = 3000; Delay = 0; Inputs = @{ InpTradeStyle = 3 } }
)
