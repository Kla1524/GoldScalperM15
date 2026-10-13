# GoldScalperM15

**MetaTrader 5 Expert Advisor for XAUUSD (Gold) — M15 trend-pullback scalper**
with ATR-based risk management, an economic-calendar news filter, an on-chart control panel and mobile push notifications.

> ⚠️ **Disclaimer** — This project is for educational purposes only and is not financial advice. Its profitability has not been proven. Gold is a highly volatile instrument: always backtest and run on a demo account before using real money. You are solely responsible for your trading results.

---

## ✨ Features

| | |
|---|---|
| 📈 **Strategy** | EMA200 trend filter + EMA 9/21 direction + pullback-to-EMA9 rejection candle + RSI confirmation |
| 🛡️ **Risk** | Fixed lot · SL/TP as ATR multiples · breakeven · ATR trailing stop · one position at a time · no martingale/grid |
| 🚦 **Filters** | Trading-hour window · max spread · max trades per day · daily loss limit (% of balance) · Friday close · minimum ATR |
| 📰 **News filter** | Uses the built-in MT5 economic calendar to pause entries around high-impact events (configurable currencies and time window) |
| 🖥️ **Control panel** | Live status, open P/L, today's stats, spread/ATR, next news event · **Pause/Resume** and **Close all** buttons |
| 📱 **Notifications** | MT5 mobile push on trade open/close (TP/SL + P/L), breakeven, news windows and daily-loss stop |
| ⚙️ **Presets** | Ready-made Safe / Normal / Active `.set` files |

## 📊 Entry logic

Signals are evaluated once per closed M15 candle:

| | BUY | SELL |
|---|---|---|
| Trend | Close > EMA200 and EMA9 > EMA21 | Close < EMA200 and EMA9 < EMA21 |
| Pullback | Low touches EMA9, candle closes back above it | High touches EMA9, candle closes back below it |
| Candle | Bullish | Bearish |
| Momentum | RSI between 50 and 70 | RSI between 30 and 50 |

**Exits:** SL = 1.2 × ATR, TP = 1.5 × ATR → stop moves to breakeven at +0.8 × ATR → trails at 1.0 × ATR (all configurable).

## 🖥️ On-chart panel

```
┌──────────────────────────────────────────┐
│ GoldScalper M15  v1.20                   │
│ Status: Ready - waiting for signal       │
│ Position: BUY 0.01 lot | P/L 3.20 USD     │
│ Today: 2/5 trades | P/L 5.40 USD          │
│ Spread: 0.25 / 0.40 | ATR: 6.85           │
│ Next news: 19:30 USD Nonfarm Payrolls     │
│ [ Pause ]                 [ Close all ]   │
└──────────────────────────────────────────┘
```
*Shown translated — the panel text in v1.20 is in Thai.*

| Status | Meaning |
|---|---|
| Ready - waiting for signal | All filters pass; waiting for a qualifying M15 candle |
| Holding position | A trade is open and being managed |
| Paused | New entries paused with the panel button (open trades are still managed) |
| News window | Inside the window before/after a high-impact event |
| Daily loss limit reached | No new trades until the next day |
| Max trades reached | Daily trade limit reached |
| Outside trading hours | Outside the configured session |
| Spread too wide | Current spread exceeds the limit |

## 🚀 Installation

**Windows (one click):** run `install_to_MT5.bat`. It compiles the EA with MetaEditor, shows the target folder and — after you confirm with **Y** — copies the EA to `MQL5\Experts\MyEA` and the presets to `MQL5\Presets`.

**Manual:** copy `GoldScalperM15.mq5` into your MT5 `MQL5\Experts` folder (*File → Open Data Folder*), open it in MetaEditor and press **F7** to compile.

Then drag the EA onto an XAUUSD chart, enable **Allow Algo Trading**, and load a preset from the **Inputs** tab.

📖 Full guide (setup, push notifications, backtesting, troubleshooting): [USER_GUIDE.md](USER_GUIDE.md) · Thai version: [คู่มือ_GoldScalperM15.md](คู่มือ_GoldScalperM15.md)

## ⚙️ Presets

| | Safe | Normal | Active |
|---|---|---|---|
| RSI Buy / Sell range | 52–65 / 35–48 | 50–70 / 30–50 | 50–75 / 25–50 |
| SL / TP (× ATR) | 1.5 / 1.5 | 1.2 / 1.5 | 1.0 / 1.3 |
| Trading hours (server) | 09–18 | 08–20 | 07–22 |
| Max trades per day | 3 | 5 | 8 |
| Daily loss limit | 2% | 3% | 4% |
| News filter | ±45 min, medium + high, closes positions | ±30 min, high | ±15 min, high |

All presets use a fixed 0.01 lot — change `InpLots` after loading.

## 📁 Repository contents

```
GoldScalperM15.mq5          EA source code (MQL5)
install_to_MT5.bat          One-click compile + install helper (Windows)
presets/*.set               Safe / Normal / Active input presets
USER_GUIDE.md               User guide (English)
คู่มือ_GoldScalperM15.md      User guide (Thai)
```

## 🗺️ Roadmap

- [ ] Telegram notifications & remote control
- [ ] Higher-timeframe (H1/H4) trend filter
- [ ] Trade journal export (CSV)
- [ ] Partial take-profit
- [ ] English / Thai language switch for the panel and alerts

## Notes

- The news filter relies on the MT5 economic calendar, which is **not available in the Strategy Tester** — backtest results include trades taken around news.
- Trading hours are in **broker server time**, not your local time.
- Symbol names vary by broker (`XAUUSD`, `XAUUSDm`, `GOLD`, …).
