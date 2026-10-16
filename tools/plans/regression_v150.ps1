# Regression for v1.50 (one strategy): the same settings must give exactly the v1.44 results.
# R1: 1 % risk, news filter off, $3,000 (suite_20261015 R1: +2,670.83, 473 trades).
# D0: the candidate = the v1.50 defaults, $10,000, delay 0 (suite_20261016_exp3 D0: DEV +1,022.15 / 209,
#     VAL +2,222.58 / 262, VALRT +1,638.34 / 227).
@(
    @{ Name = 'REG150_R1_1pct_nonews_1min_3k'; From = '2018.01.01'; To = '2026.10.12'; Model = 1; Deposit = 3000;  Delay = 0; Inputs = @{ InpRiskPct = 1.0; InpNewsInTester = 'false' } },
    @{ Name = 'REG150_D0_DEV';   From = '2018.01.01'; To = '2023.12.31'; Model = 1; Deposit = 10000; Delay = 0; Inputs = @{} },
    @{ Name = 'REG150_D0_VAL';   From = '2024.01.01'; To = '2026.10.12'; Model = 1; Deposit = 10000; Delay = 0; Inputs = @{} },
    @{ Name = 'REG150_D0_VALRT'; From = '2024.10.14'; To = '2026.10.12'; Model = 4; Deposit = 10000; Delay = 0; Inputs = @{} }
)
