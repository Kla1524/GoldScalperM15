# News straddle (TikTok clip, 18 Oct 2026): GS15_Lab strategy 3, tester only. $10,000, 0.5% risk at the SL.
# Real ticks Oct 2024 - Oct 2026 (NFP, CPI, Fed decisions), plus delays, other distances, trailing, all high-impact events,
# and 2018-2023 with generated every-tick data for reference only (news spikes are not modelled well there).
$rt = @{ From = '2024.10.14'; To = '2026.10.12'; Model = 4; Deposit = 10000 }
$base = @{ InpStrategy = 3 }
function Run($name, $inputs, $delay = 0, $p = $rt) { $i = $base.Clone(); foreach ($k in $inputs.Keys) { $i[$k] = $inputs[$k] }; @{ Name = $name; From = $p.From; To = $p.To; Model = $p.Model; Deposit = $p.Deposit; Delay = $delay; Inputs = $i } }
Run 'N1_d300_sl500_tp1000_RT' @{}
Run 'N1_RT_delayrnd' @{} -1
Run 'N1_RT_delay500ms' @{} 500
Run 'N2_d500_sl500_tp1500_RT' @{ InpNDistPts = 500; InpNTPPts = 1500 }
Run 'N3_d200_sl300_tp600_RT' @{ InpNDistPts = 200; InpNSLPts = 300; InpNTPPts = 600 }
Run 'N4_trail500_noTP_RT' @{ InpNTPPts = 0; InpNTrailPts = 500 }
Run 'N5_allhigh_RT' @{ InpNEvents = '' }
Run 'N1_DEV_everytick' @{} 0 @{ From = '2018.01.01'; To = '2023.12.31'; Model = 0; Deposit = 10000 }
