# Swap options (17 Oct 2026): close just before the rollover (23:00 server = 03:00 Thai) instead of 20:00.
$periods = @(
    @{ Tag = 'DEV';   From = '2018.01.01'; To = '2023.12.31'; Model = 1 },
    @{ Tag = 'VAL';   From = '2024.01.01'; To = '2026.10.12'; Model = 1 },
    @{ Tag = 'VALRT'; From = '2024.10.14'; To = '2026.10.12'; Model = 4 }
)
$configs = [ordered]@{
    'W1_24h_close23'      = @{ InpEndHour = 23; InpDailyCloseHour = 23 }                    # one trade a day, entries to 23:00, close 23:00, no TP
    'W2_tp4_24h_close23'  = @{ InpEndHour = 23; InpDailyCloseHour = 23; InpTP_ATR = 4 }     # same with TP 4 ATR
}
foreach ($c in $configs.Keys) { foreach ($p in $periods) { @{ Name = "$($c)_$($p.Tag)"; From = $p.From; To = $p.To; Model = $p.Model; Deposit = 10000; Delay = 0; Inputs = $configs[$c] } } }
