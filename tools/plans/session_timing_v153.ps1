# Session timing on v1.53 (planned for Saturday 24 Oct 2026). User wish: entries from 08:00 Thai (= 04:00 server until 1 Nov), close 23:00 Thai (= 19:00 server).
# The range must finish before entries start, so earlier entries need a shorter range. Choose on DEV, confirm on VAL / VALRT.
$p = @(
    @{ Tag = 'DEV';   From = '2018.01.01'; To = '2023.12.31'; Model = 1 },
    @{ Tag = 'VAL';   From = '2024.01.01'; To = '2026.10.12'; Model = 1 },
    @{ Tag = 'VALRT'; From = '2024.10.14'; To = '2026.10.12'; Model = 4 }
)
$cfg = [ordered]@{
    'R0408_close20' = @{ InpRangeStartHour = 0; InpRangeEndHour = 4 }                              # range 04-08 Thai, entries from 08:00 Thai
    'R0408_close19' = @{ InpRangeStartHour = 0; InpRangeEndHour = 4; InpDailyCloseHour = 19 }      # + close 23:00 Thai
    'R0206_close20' = @{ InpRangeStartHour = 0; InpRangeEndHour = 6 }                              # range 04-10 Thai, entries from 10:00 Thai
    'R0008_close19' = @{ InpDailyCloseHour = 19 }                                                  # current range, close 23:00 Thai
    'R0008_close22' = @{ InpDailyCloseHour = 22 }                                                  # current range, close 02:00 Thai (guard closes before the rollover)
}
foreach ($c in $cfg.Keys) { foreach ($x in $p) { @{ Name = "$($c)_$($x.Tag)"; From = $x.From; To = $x.To; Model = $x.Model; Deposit = 10000; Delay = 0; Inputs = $cfg[$c] } } }
