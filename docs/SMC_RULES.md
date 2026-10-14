# Mode 3 — SMC: FVG + CHoCH + OB (experimental)

Every rule below is implemented in `GS15_SMC.mqh` (pure signal functions) and in the mode-3 block of `GoldScalperM15.mq5` (state machine, risk, execution). `tools/SMC_Tests.mq5` checks the signal rules on synthetic bars (`reports/experiments/smc_unit_tests.txt`).

**All defaults are starting hypotheses for testing, not optimised or proven values.** Support/resistance zones come from price rules; they do not guarantee that price will react there.

## 1. Scope
- **Modes 1 and 2 (Asian-range breakout) are unchanged.** Mode 3 is selected with `InpTradeStyle = 3`, the console key `3`, or the `MODE3` command.
- **Mode 3 does not use:**
  - the Asian range;
  - the 08:00–18:00 entry window;
  - the daily-ATR ≥ 1.6 % filter;
  - the confidence score.
- **Mode 3 still uses:**
  - the news filter, spread limit and margin check;
  - the risk caps (strict risk, `InpMaxRiskPct`, lot cap);
  - the 3 % daily loss limit;
  - pause, the drawdown / losing-streak halts and the 20-minute loss cooldown.
- **Trade count:** no daily trade count, but only one position at a time. Each setup can be traded once.

## 2. Timeframes and data
| Role | Input | Default |
|---|---|---|
| Bias, support/resistance | `InpSmcTfBias` | H1 |
| CHoCH, order block, FVG | `InpSmcTfStructure` | M15 |
| Confirmation candle | `InpSmcTfEntry` | M5 |
| ATR period | `InpSmcAtrPeriod` | 14 |

- **Closed bars only.** Every decision uses closed bars (`CopyRates` from shift 1).
- **ATR timing.** "ATR known before bar i" means the ATR value of bar i−1.

## 3. Swings (pivots)
- **Swing high at bar i:** `high[i]` is strictly higher than the `L` bars before it, and ≥ the `R` bars after it. Swing lows are the same, mirrored.
  - Defaults: `L = InpSmcPivotLeft = 2`, `R = InpSmcPivotRight = 2`.
  - Equal highs: only the earliest bar is a pivot (deterministic).
- **When a pivot can be used.** A pivot exists only after bar i+R has closed. The engine records both:
  - `time`: the pivot bar;
  - `confirmTime`: the close of bar i+R.

## 4. H1 bias
| Bias | Condition |
|---|---|
| Bullish | latest confirmed swing high > the previous one, and latest swing low > the previous one |
| Bearish | both lower |
| Neutral | anything else, or fewer than two of each |

With `InpSmcBiasFilter = true` (default), BUY needs a bullish bias and SELL a bearish bias, and neutral means no trade.

## 5. Support / resistance (H1)
1. Collect the confirmed swing highs and lows of the last `InpSmcSRLookback = 100` H1 bars.
2. Sort the levels and merge neighbours within `InpSmcSRTolAtr × ATR(H1) = 0.2 ATR` into zones `[lo, hi]`.
3. **Resistance** for a BUY is the nearest zone whose top is above the entry. If price is inside a zone, that zone counts: there is no room, so RR fails.
4. **Support** for a SELL is the mirror.
5. If no zone is found, the trade is skipped. No target is invented.

## 6. CHoCH (M15)
- **Bullish CHoCH at bar k:** all three conditions hold.
  - The swings confirmed before bar k closed form a bearish structure: lower high and lower low.
  - `close[k]` > latest swing high + buffer, where buffer = `InpSmcBreakBufAtr` × ATR of bar k−1 (0.1).
  - `close[k−1]` ≤ the same level, so it is a new close through the level. A wick alone does not count.
- **Bearish CHoCH:** the mirror (bullish structure, close below the latest higher low).
- **BOS is not a CHoCH.** A close through a level in the direction of the existing structure is a BOS and is not traded.
- **One CHoCH per swing level.**
- **Opposite CHoCH** cancels an untraded setup.

## 7. Impulse, displacement, order block
- **Impulse:** the run of candles in the break direction that ends at bar k.
- **Displacement:** at least one impulse candle has a body ≥ `InpSmcDispAtr` × ATR known before that candle (1.0).
- **Order block:**
  - BUY: the last bearish candle before the impulse.
  - SELL: the last bullish candle before the impulse.
  - It must lie within `InpSmcObMaxBack = 10` bars of bar k.
  - The zone is the OB candle's high–low.
- **No displacement or no OB:** no setup. The console log says which.

## 8. FVG
- **Pattern:** three consecutive closed candles A, B, C.
  - Bullish FVG: `Low(C) > High(A)`, zone `High(A)–Low(C)`.
  - Bearish FVG: `High(C) < Low(A)`, zone `High(C)–Low(A)`.
- **Linked to the same impulse:**
  - A must be at or after the OB.
  - B must be in the impulse or within `InpSmcFvgWindow = 3` bars after the break.
  - Only bars that have closed are searched.
- **Minimum width:** `InpSmcFvgMinAtr` × ATR before the break (0.1).
- **Role:** the FVG confirms the impulse. The entry zone is the OB.
  - `InpSmcRequireOverlap = true` uses only the OB/FVG overlap, and skips the setup if they do not overlap.
- **Ready time:** the setup is *ready* at the close of the later of the break bar and bar C.

## 9. State machine
`DETECTED` (CHoCH + OB) → `READY` (FVG found) → `RETESTED` (an M5 candle after the ready time touched the zone) → `CONFIRMED` → `SUBMITTED` → `TRADED`. Two end states: `INVALIDATED` and `EXPIRED`.

- **Confirmation (BUY):** an M5 candle that opens at or after the ready time, whose range touches the zone, is bullish, and closes above the zone top. SELL is the mirror.
  - Price action before the ready time is never used.
- **Entry:** at the first tick after the confirmation candle closes. Entry, SL, TP, RR and risk are recalculated from the current Ask (BUY) or Bid (SELL).
  - If RR or risk no longer passes, the setup is skipped. The EA never chases price.
- **Expiry:** `InpSmcExpiryBars = 16` M15 bars after the ready time.
- **Invalidation:**
  - an M15 close below the OB low (BUY) or above the OB high (SELL);
  - the H1 bias flips or becomes neutral;
  - an opposite CHoCH;
  - a newer CHoCH;
  - no FVG within the window;
  - any skip at entry time.
- **Duplicate prevention:**
  - `SUBMITTED` blocks re-sending while the result is unknown.
  - Only a requote or price change gets a retry (at most 2, each with fresh prices).
  - The CHoCH time of the last traded setup is stored in a global variable, and recovered from the deal history (comment `SMC …`) after a restart.
- **Setup ID:** `<symbol>-<structure TF>-<B|S>-<CHoCH time>`, e.g. `GOLD-M15-B-20261014T1545`. The order comment is `SMC M15-B-20261014T1545`.
- **Restart:** setups are rebuilt from closed bars. A confirmation that happened while the EA was off is not traded late.

## 10. SL, TP, size
| Item | Rule (BUY; SELL mirrored) |
|---|---|
| SL | min(OB low, lowest low from OB to break) − `InpSmcSlBufAtr` × ATR M15 (0.2) |
| TP | nearest H1 resistance zone low − `InpSmcTpBufAtr` × ATR M15 (0.1) |
| Money per lot | `OrderCalcProfit` to SL and to TP, plus the slippage allowance (`InpSlippagePts`) and commission (`InpCommissionLot`) |
| RR | reward per lot ÷ risk per lot, after costs; must be ≥ `InpSmcMinRR` = 1.5 |
| Lot | equity × `InpSmcRiskPct` (0.5 %) ÷ risk per lot, rounded down to the volume step, then the lot cap |
| Strict risk | if the rounded lot (or the minimum lot) risks more than the target, skip |
| Daily budget | start-of-day balance × 3 % − today's net loss; profits today do not enlarge it; skip if the trade's risk is larger |
| Broker checks | trade mode, stops level for SL/TP, `OrderCheck` (margin, volume, prices), retcode of the real send |

SL and TP are sent with the order, so they live on the server. Partial close, breakeven and trailing are off in mode 3.

## 11. Time policy (mode 3 only)
- **Sessions:** mode 3 scans every session in which the symbol trades (`SymbolInfoSessionTrade`).
- **Rollover:** `InpSmcRolloverHour = 0` server time.
  - This is an assumption: XM charges swap at 00:00 server time. **Verify this with the broker.**
  - No entries in the 60 minutes before and the 60 minutes after the rollover.
  - Mode-3 positions are closed 15 minutes before it.
- **Other mode 3 policies:**
  - The 20:00 daily close of modes 1/2 does **not** apply to mode-3 trades. They are recognised by the `SMC` comment.
  - The Friday close (21:00) applies to every trade.
  - No entries when quotes are older than 120 s (live).
- **Server time only.** No Thai-time conversion is used anywhere, so the GMT+2/+3 changes need no code.
- **Real accounts:** mode 3 is refused until `InpSmcAllowReal = true`, because the rollover time and the strategy are not yet validated.

## 12. Console, chart and journal
- **Console (mode 3):**
  - H1 bias and the nearest support/resistance zones;
  - the last CHoCH (direction and time);
  - setup state, ID and M15 bars left;
  - OB and FVG zones;
  - what is still missing ("Next: …");
  - the planned entry, SL, TP, RR and risk.
- **Chart (live or visual tester):** objects named `GS15_smc_*`. They show the nearest support/resistance, the OB, the FVG and the CHoCH line. User drawings are never touched.
- **Journal:** `Common\Files\GS15_smc_journal_<symbol>_<magic>[_tester].csv` logs every event:
  - `DETECTED`, `READY`, `CONFIRMED`, `OPEN` and `CLOSE`;
  - `INVALIDATED` and `EXPIRED`, with the reason (for example `RR 1.12 < 1.50 after costs`, `M15 closed below the order block`, `blocked: News window`).

## 13. Known limits
- **Indicator and tester limits:**
  - ATR is MT5's `iATR`.
  - The tester has no news calendar, so news blocks are not part of backtests.
  - Results with 1-minute OHLC data only approximate the M5 confirmation inside each minute; real-tick tests are the reference.
- **Not used in this version** (deliberately, for a clear baseline):
  - several setups at the same time;
  - BOS continuation entries;
  - partial / breakeven / trailing;
  - news-based exits.
