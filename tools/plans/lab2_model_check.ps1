# Lab test 2 (17 Oct 2026): is the martingale profit in the 1-minute-OHLC runs real?
# Same window as the real-tick runs (VALRT) but 1-minute OHLC, and DEV with generated every-tick data.
$w = @{ From = '2024.10.14'; To = '2026.10.12' }
@(
    @{ Name = 'G1_clip_RTwindow_1min'; From = $w.From; To = $w.To; Model = 1; Deposit = 10000; Delay = 0; Inputs = @{ InpStrategy = 2 } },
    @{ Name = 'G3_sl10_RTwindow_1min'; From = $w.From; To = $w.To; Model = 1; Deposit = 10000; Delay = 0; Inputs = @{ InpStrategy = 2; InpBasketSLPct = 10 } },
    @{ Name = 'G3_sl10_DEV_everytick'; From = '2018.01.01'; To = '2023.12.31'; Model = 0; Deposit = 10000; Delay = 0; Inputs = @{ InpStrategy = 2; InpBasketSLPct = 10 } },
    @{ Name = 'G1_clip_DEV_everytick'; From = '2018.01.01'; To = '2023.12.31'; Model = 0; Deposit = 10000; Delay = 0; Inputs = @{ InpStrategy = 2 } }
)
