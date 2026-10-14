# Code review (v1.42 source) — time, signals, risk, orders

| Area | Finding | Status |
|---|---|---|
| Asian range | High/low of M15 bars opening 00:00–07:45 server time (`CopyHigh(rs, re)`, `re = 08:00 - 1 s`). | OK |
| DST | Everything uses server time. XM server time follows the New York close (GMT+2 winter / GMT+3 summer), so the range stays aligned with the market. Only the Thai clock time shifts by 1 h around early Nov and mid Mar. | OK (documented) |
| Signal bar | Evaluated once on the first tick of a new M15 bar, using bar 1 (closed) and bar 2. No look-ahead. | OK |
| Indicator bars | ATR M15, ATR D1, EMA50 D1, EMA200 H1, ADX H1 and RSI M15 all read shift 1 (`GetBuf`), i.e. the last closed bar. | OK |
| One signal per bar | If a filter blocks at that first tick (spread, cooldown, news), the breakout is not re-checked later in the bar. | By design (noted) |
| Trades per day / restart | Counted from today's deal history (magic + symbol), so restarts and mode switches cannot reset the count. Test-button trades use magic + 1 and are not counted. | OK |
| SL distance and risk | Buy: entry at ask, SL hit at bid. Sell: entry at bid, SL hit at ask. Loss = SL distance exactly; risk adds 30 pts slippage + commission. Uses `TICK_VALUE_LOSS` / tick size. | OK |
| Lot rounding | Rounded down to the volume step with an epsilon. Min lot is never forced: strict risk skips the trade. Baseline: all 473 trades ≤ 1.000%, mean 0.79%. | OK, verified on data |
| **Unknown tick value** | If the tick value was 0 (just after connecting), the lot fell back to `InpLots` and every risk check passed (risk = 0). | **Fixed:** skip and warn |
| **Requote / price changed** | The order failed once and the breakout was lost for the day. | **Fixed:** one retry at the new price, same lot and SL distance, spread re-checked |
| **Withdrawal vs DD halt** | A withdrawal lowered equity below the peak and could trigger the 20% drawdown halt. A deposit could hide a real drawdown. | **Fixed:** the peak moves with balance deals |
| **Daily loss start balance** | `balance − (realized + floating)` overstated the start balance while a trade was open. | **Fixed:** realized only |
| Daily loss budget | Checked before each entry with realized P/L. A trade whose stop exceeds the remaining budget is skipped (1 skip in 2018–2026). | OK |
| Cooldown | Set after any losing close; survives restarts (live). | OK |
| News filter | Live only. The calendar is not available in the tester, so **no backtest includes it**. | Limitation |
| Holiday early close | 2 trades held past midnight (US holidays: no tick between 20:00 and the early close). | Open (Q3) |
| Duplicates / other EAs | A terminal-wide 10 s order lock plus a position re-check. Only own magic + symbol is managed. | OK |
| Closing | Verified and retried 3× per tick, with a throttled alert. | OK |

All fixes compile (0 errors, 0 warnings). The tester regression is pending (blocker B1). None of the fixes should change tester results: the tester has no requotes, no zero tick value and no deposits.
