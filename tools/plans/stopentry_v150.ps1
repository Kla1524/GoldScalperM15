# Stop-entry test (v1.50, 16 Oct 2026). One change against the candidate (v1.50 defaults, $10,000):
# InpStopEntry = true - BUY STOP / SELL STOP at the range edges instead of waiting for an M15 close.
# D0 rows re-run the default entry with the stop-entry code present: must stay identical to suite_20261016_exp3 D0.
$periods = @(
    @{ Tag = 'DEV';   From = '2018.01.01'; To = '2023.12.31'; Model = 1 },
    @{ Tag = 'VAL';   From = '2024.01.01'; To = '2026.10.12'; Model = 1 },
    @{ Tag = 'VALRT'; From = '2024.10.14'; To = '2026.10.12'; Model = 4 }
)
$configs = [ordered]@{
    'D0_close'     = @{ Delay = 0;  Inputs = @{} }
    'SE_stop'      = @{ Delay = 0;  Inputs = @{ InpStopEntry = 'true' } }
    'SE_stop_rnd'  = @{ Delay = -1; Inputs = @{ InpStopEntry = 'true' } }
}
foreach ($c in $configs.Keys) {
    foreach ($p in $periods) {
        @{ Name = "$($c)_$($p.Tag)"; From = $p.From; To = $p.To; Model = $p.Model; Deposit = 10000; Delay = $configs[$c].Delay; Inputs = $configs[$c].Inputs }
    }
}
