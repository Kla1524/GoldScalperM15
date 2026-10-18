# GoldScalperM15

![Version](https://img.shields.io/badge/version-1.53-blue) ![Platform](https://img.shields.io/badge/platform-MetaTrader%205-0a7bbb) ![Language](https://img.shields.io/badge/language-MQL5-orange) ![Symbol](https://img.shields.io/badge/symbol-XAUUSD%20(Gold)-d4af37) ![Status](https://img.shields.io/badge/status-demo%20forward%20test-yellow) ![License](https://img.shields.io/badge/license-MIT-green)

**MetaTrader 5 Expert Advisor for XAUUSD (Gold) — M15 intraday Asian-range breakout, one trade a day**
with strict risk-based position sizing (0.5% per trade), a volatility filter, a news filter (live and in the Strategy Tester), risk guards, loss diagnosis, an on-chart panel, a PowerShell console and mobile push notifications.

**Current version: v1.53** · [Release notes](https://github.com/Kla1524/GoldScalperM15/releases) · [Changelog](CHANGELOG.md) · [User guide](docs/USER_GUIDE.md) · [คู่มือภาษาไทย](docs/USER_GUIDE_TH.md)

## ⚡ Quick start

1. Run **`install_to_MT5.bat`** (compiles the EA and copies it to `MQL5\Experts\MyEA`).
2. In MT5 open **one** GOLD / XAUUSD chart and drag **GoldScalperM15** onto it; tick *Allow Algo Trading*.
3. Keep the default inputs (or load `presets/GoldScalperM15_Default.set`). Test on a **demo account** first.
4. Optional: phone alerts (MetaQuotes ID in *Tools → Options → Notifications*) and the console (`GS15_Console.bat`).

> ⚠️ **Disclaimer — for education and research only.** This project is **not investment advice** and **not an invitation, recommendation or solicitation to invest** or to trade any financial product. It is shared as a learning resource on how an EA can be built and tested. Trading gold and other leveraged products carries a high risk of loss. Backtest results do not guarantee future performance. Always test on a demo account first. You are solely responsible for how you use it and for your trading results. Full text: [DISCLAIMER.md](DISCLAIMER.md).

---

## 📊 Backtest results (default settings, XM Global `GOLD`, $10,000, 0.5% risk, news filter ±15 min)

| Period | Data | Net profit | Profit factor | Max DD | Trades |
|---|---|---|---|---|---|
| 2018 – 2023 (development) | 1-minute OHLC | +$1,022 | 1.23 | 8.4% | 209 |
| 2024 – Oct 2026 (validation) | 1-minute OHLC | +$2,223 | 1.54 | 4.0% | 262 |
| Oct 2024 – Oct 2026 | **real ticks** | +$1,638 | 1.50 | 3.7% | 227 |

**Stress tests (v1.44 research, same settings)**
- Order delay: 500 ms cost about 1% of the profit; random delays (5 runs) 1–4% on real ticks.
- Spread ×1.5 and ×2: still profitable in every period.
- Risk guards paused like live (resumed after 7 days): profit −11% in 2018–2023, slightly higher in 2024–2026.
- Monte Carlo (trade order shuffled / resampled): 95% of runs stayed under about 10–12% drawdown; losing streaks up to 12 trades.

**Honest caveats**
- Most of the profit comes from 2024–2026, when gold was unusually volatile. In quiet years the EA mostly sits out (by design) and earns little.
- The live demo forward test (target 30–50 trades) started in October 2026; it is not finished.
- Other ideas were tested and rejected: more trades a day, a smart-money-concepts mode, an EMA/Stochastic scalper and a martingale grid (the grid blew the account with real-tick data — its big 1-minute-OHLC profits were a modelling artefact). Results are in the [`research`](https://github.com/Kla1524/GoldScalperM15/tree/research) and [`lab-clip-tests`](https://github.com/Kla1524/GoldScalperM15/tree/lab-clip-tests) branches.

## 💰 Account size: Standard, Micro and Cent accounts

The lot size is **risk-based**: 0.5% of equity per trade (`InpRiskPct`). The risk is **strict** (`InpStrictRisk`): real risk = SL from the actual entry price + slippage allowance + commission. If even the minimum lot (0.01) would risk more than 0.5%, the EA **skips the trade and says why**; it never forces it. On a Standard account 0.01 lot risks about $15–$100+ per stop, so:

| Balance | Use |
|---|---|
| under ~$6,000 | **Micro or Cent account** (lots 100× smaller), from ~$60 |
| ~$6,000+ | Standard, Micro or Cent |

The start-up **account check** (Experts tab, or a popup from the panel button) detects the account type (Standard / Micro / Cent) and tells you what balance or account you need. A Micro account is a Standard account scaled down 100× (contract 1 oz instead of 100 oz), and a Cent account counts the balance in US cents.

## ✨ Strategy

1. **Range:** record the high/low of the Asian session, 00:00–08:00 server time.
2. **Volatility filter:** trade only on days when daily ATR(14) ≥ 1.6% of price; breakouts fail in quiet markets.
3. **Entry:** the first M15 candle of the day that closes above the range high (buy) or below the range low (sell), from 08:00 until 18:00 server time. **One trade a day.** Optional: `InpStopEntry` places BUY STOP / SELL STOP orders at the range edges instead (off by default).
4. **Confidence score (0–4):** +1 each for trading with the D1 trend, with the H1 trend, ADX(H1) 20–30 and RSI ≥ 70 in the trade direction; entries need ≥ 1 (`InpMinConfidence`).
5. **Stop:** 4 × ATR(14, M15). No take-profit, breakeven or trailing stop: winners run.
6. **Exit:** everything is closed at **20:00 server time** (no overnight swap) and before the Friday close. Since v1.53 a **session guard** (`InpSessionGuard`) also closes before gold stops trading: 10 minutes before the end of the broker's session, at 22:50 in the weeks when US and EU summer time differ, and at 18:00 on US holidays with an early close — all from rules known in advance. Every close is logged with the intended time, the time sent and the confirmed close.
7. **Position size:** Lot = Equity × 0.5% ÷ (SL + slippage + commission per lot), rounded down; skipped if the minimum lot would exceed 0.5%.
8. **Risk guards:** daily loss limit 3% (`InpMaxDailyLossPct`), hard cap 5% per trade (`InpMaxRiskPct`), lot cap (`InpMaxExposure`, `InpMaxLot`), 20-minute pause after a loss, news filter ±15 min around high-impact USD events.
   **Halts** (the EA pauses itself and waits for you to review and press Resume; open trades keep their SL): equity 20% below its peak (`InpMaxDDPct`), 5 losing trades in a row (`InpMaxLossStreak`), and optionally N losing days in a row (`InpMaxLosingDays`, off by default).
9. **Loss diagnosis & journal:** every loss is tagged with reasons (failed breakout, against trend, gave back profit, …) in the phone alert and in a CSV journal.

## 🤖 Looking after the bot (v1.51)

| | |
|---|---|
| 📱 **Daily summary** | After the daily close a push message to your phone: trades, P/L, balance, drawdown, losing streaks, state |
| ⏯️ **Start / stop notices** | When the EA starts it reports how long it was not running (PC off, MT5 closed, power cut); when MT5 closes or the EA is removed it says so |
| 🧷 **Duplicate guard** | A second copy on another chart of the same symbol refuses to start, so trades are never doubled |
| 🛑 **Losing-days halt** | `InpMaxLosingDays` (0 = off). Tested: stopping after 2 losing days halved the profit, after 3 it was mixed, so it is off by default |
| 🐶 **PC watchdog** | `tools/GS15_Watchdog.ps1`: every 2 minutes during market hours, a Windows notification if MT5 is closed or the EA stopped updating. It never starts, stops or trades anything. Not installed automatically |

## 🖥️ Other features

| | |
|---|---|
| 🚦 **Filters** | Trading hours · max spread · one trade a day · daily loss limit · Friday close · daily close |
| 📰 **News filter** | MT5 economic calendar — pauses entries ±15 min around high-impact USD events. Also in the Strategy Tester: the live EA exports the USD calendar history (GMT) to `Common\Files\GS15_news_USD.csv`, and the tester converts it to server time with the US daylight-saving rule |
| 🖥️ **Control panel** | Status with the reason, position P/L, today's trades and P/L, spread/ATR, next news · **Pause** / **Close all** / **Account check** / **Test** (opens and closes a minimum-lot trade to prove orders go through, demo only) |
| 🧭 **Account check** | Balance, leverage, contract size and what one stop-loss costs, with a verdict (TH/EN) |
| 🖥️ **PowerShell console** | `GS15_Console.bat` or the chart's **Console** button (needs `tools/Install-ConsoleLauncher.ps1` once). Status, strategy & risk, guards (drawdown, losing streak, losing days), market and news, event journal, headlines. Keys: `P` pause/resume, `A` account check, `T` test order, `C` close all. The EA keeps running whether the console is open or not |
| 📱 **Notifications** | MT5 mobile push: open/close, news windows, daily-loss stop, halts, skipped trades, daily summary, start/stop |

## 🚀 Installation

**Windows (one click):** run `install_to_MT5.bat`. It compiles the EA, shows the target folder and — after you confirm with **Y** — copies it to `MQL5\Experts\MyEA` and the preset to `MQL5\Presets`. A portable MT5 in `D:\MT5_GoldScalper` is used when there is one.

**Manual:** copy `GoldScalperM15.mq5` into `MQL5\Experts` (*File → Open Data Folder*), open it in MetaEditor and press **F7**.

Attach the EA to **one** GOLD/XAUUSD chart and enable **Allow Algo Trading**. The defaults are the validated settings (`presets/GoldScalperM15_Default.set` is the same). For phone alerts enter your MetaQuotes ID in *Tools → Options → Notifications*.

> Times are **broker server time**. The defaults were validated on XM Global (GMT+2/+3). Other brokers may need the hours adjusted.

📖 Full guide: [docs/USER_GUIDE.md](docs/USER_GUIDE.md) · Thai: [docs/USER_GUIDE_TH.md](docs/USER_GUIDE_TH.md) · What changed in each version: [CHANGELOG.md](CHANGELOG.md)

## 🧪 Backtests and research

Every number in this README comes from MT5 Strategy Tester reports kept in the [`research`](https://github.com/Kla1524/GoldScalperM15/tree/research) branch (`reports/experiments/`), together with the scripts that ran them (`tools/night_suite.ps1`, `tools/plans/`) and the analysis tools (trade-by-trade regression, Monte Carlo, close audit). `tools/backtest.ps1` on this branch runs single backtests from PowerShell.

## 📁 Repository contents

```
GoldScalperM15.mq5      EA source code (MQL5)
install_to_MT5.bat      One-click compile + install (Windows)
GS15_Console.bat        Opens the PowerShell console
presets/                Default preset (= the EA defaults)
tools/                  Console, console launcher, watchdog, news export, backtest helper
docs/                   User guides (EN / TH), code review, MT5 self-close note
CHANGELOG.md            What changed in each version
LICENSE · DISCLAIMER.md MIT license · education-only disclaimer (EN + TH)
```

## 📄 License

[MIT](LICENSE) — free to use, modify and share, including commercially, as long as the copyright notice (credit to **Kla1524**) is kept. Provided as is, with no warranty. The [disclaimer](DISCLAIMER.md) applies to every use.

## 🗺️ Roadmap

- [ ] Demo forward test: 30–50 trades (set 1 = v1.53 defaults, from 19 Oct 2026)
- [ ] Exit-rule study (breakeven, shorter stop, partial exits) — tested before any change
- [x] Session guard: close before the market stops, close audit — v1.53
- [x] Bot care: daily summary, start/stop notices, duplicate guard, losing-days halt — v1.51
- [x] One strategy only (modes removed) — v1.50
- [x] News filter in the Strategy Tester — v1.43
- [x] English / Thai for the panel, alerts and windows — v1.39
- ~~Telegram control~~ — dropped; alerts use MT5 mobile push
