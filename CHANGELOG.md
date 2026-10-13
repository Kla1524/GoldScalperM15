# Changelog

All notable changes to GoldScalperM15. Backtests use XM Global `GOLD` unless noted. "1-min" = 1-minute OHLC model, "real ticks" = every tick based on real ticks.

## v1.38 — Demo system test mode
- **`InpTestMode`** (demo accounts only, refused on real accounts): opens `InpTestTrades` real trades one at a time, alternating BUY/SELL. Each is held `InpTestHoldMin` minutes and then closed, ignoring signals and trading hours. The trades go through the normal order path, so the test checks lot sizing, SL, phone alerts, loss diagnosis, the loss cooldown and the journal.
- Verified on an XM demo: 3 test trades opened and closed. Every step worked and the cooldown waited before each new trade.

## v1.37 — Trade mode buttons, non-blocking account check
- **Mode 1 / Mode 2 panel buttons** (`InpTradeStyle`):
  - Mode 1: one bigger trade a day at `InpRiskPct`, 1%.
  - Mode 2: several smaller trades with no daily limit, at `InpMultiRiskPct`, 0.5%.
  - A window explains both modes before you confirm. It shows tested results, who each mode suits, and the lot each would trade today.
  - The chosen mode is remembered across MT5 restarts.
- Results, 2018–2026, $3,000, 1-min:

  | Mode | Net | PF | Max DD |
  |---|---|---|---|
  | 1 | +105% | 1.46 | 16.3% |
  | 2 | +74% | 1.46 | 10.5% |

- Presets carry the mode. `Unlimited_0.5pct` starts in mode 2.

## v1.36 — Account check in the Experts tab (released with v1.37)
- The start-up account check prints to the **Experts** tab and needs no answer, so the EA keeps running when nobody is at the PC.
- `InpAccountPopup = true` restores the blocking popup. The panel button always opens the popup with choices.

## v1.35 — Optional unlimited trades per day
- `InpMaxTradesPerDay = 0` removes the daily limit. The panel shows the count as `x/∞`.
- The extra trades of a day come after a failed breakout and lose more often. They totalled −$102 over 85 trades in 2018–2026.
  - 1-min, 2018–2026: PF 1.63 → 1.51.
  - Real ticks, 2024–2026: PF 1.61 → 1.52.
- Use unlimited only with a smaller risk %.

## v1.34 — Small accounts ($10–$1,000)
- The default lot mode is now **risk-based, 1% per trade**, so lots follow the balance.
- The account check detects **Standard / Micro / Cent (USC)** accounts and recommends Micro/Cent for small balances.
- Presets `Default` (1%) and `Safe_0.5pct` (0.5%) replace the old fixed-lot preset.
- Tier results, 2018–2026, 1% risk. Micro $X behaves like Standard $X×100:

  | Balance | Net | PF | Max DD |
  |---|---|---|---|
  | $10 | +203% | 1.52 | 18.0% |
  | $20 | +120% | 1.47 | 14.8% |
  | $100 | +116% | 1.43 | 16.5% |
  | $100 at 0.5% | +41% | 1.40 | 8.2% |
  | $1,000 | +134% | 1.45 | 17.1% |

## v1.33 — Account-check popup (TH/EN)
- On start, and from a panel button, the EA analyses:
  - balance, leverage, contract size, min lot and margin
  - the money one stop-loss would cost today
- Verdict: too small, high risk, or reasonable.
- Choices: keep running, switch to 1% risk lots, pause, or remove the EA.
- New inputs: `InpLanguage` (Thai / English) and `InpAccountCheck`.
- `tools/CreateGoldMicro.mq5` builds a Micro-contract test symbol.
  - $10 on Micro, real ticks Aug–Oct 2026: +$1.79, PF 1.41.

## v1.32 — Loss diagnosis, journal, confidence filter, cooldown
- **Trade journal** (CSV in `Common\Files`) for every trade: entry conditions, MFE/MAE, exit reason and loss reasons.
- **Loss diagnosis** in phone alerts. Reasons include failed breakout, against the D1/H1 trend, weak candle, chased entry and gave back profit.
- **Confidence score 0–4**: D1 trend, H1 trend, ADX 20–30, strong RSI. Entries need ≥ 1.
- **Cooldown** of 20 minutes after a losing trade.
- Fix: on early-close holidays a position could stay open overnight. It is now closed.
- 2018–2026: PF 1.56 → **1.63**, DD 9.8% → **9.0%**.

## v1.31 — Risk-based lot sizing
- `InpLotMode`: fixed lot or Lot = Balance × Risk% ÷ SL. This follows the user's lot-size spreadsheet.
- Open alerts show the money and % at risk.
- Fix: floating-point lot rounding (0.10 became 0.09).
- Real ticks, 2024–2026, $3,000:
  - 1% risk: PF 1.66, DD 10.8%.
  - 2% risk: PF 1.55, DD 17.9%.

## v1.30 — New validated strategy
- Backtests showed that v1.20 (EMA pullback scalping) lost money every year, mainly because of the spread.
- Holding trades overnight failed because of XM's gold swap, about $0.84 per night per 0.01 lot.
- New default strategy, **Asian-range breakout**:
  - Range from 00:00 to 08:00 server time.
  - Trades only on volatile days (daily ATR ≥ 1.6%).
  - 4×ATR stop and no take-profit.
  - All trades closed by 20:00.
- Parameters were chosen on 2020–2023 and then checked on 2018–2019 and 2024–2026.
- Risk guard `InpMaxRiskPct`, margin check, failure alerts limited to once a day.
- Fix: `TP = 0` now means no take-profit.
- `tools/backtest.ps1`: automated backtests and optimization.

## v1.20 — First release
- EMA200 + EMA 9/21 + RSI pullback entries on M15, ATR stop/target, breakeven and trailing stop.
- Session, spread and daily-loss filters. Economic-calendar news filter.
- On-chart panel, mobile push notifications, presets, one-click installer, Thai and English guides.
