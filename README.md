# GoldScalperM15

**MetaTrader 5 Expert Advisor for XAUUSD (Gold) — M15 intraday Asian-range breakout**
with a volatility filter, per-trade risk guard, news filter, on-chart control panel and mobile push notifications.

> ⚠️ **Disclaimer** — This project is for educational purposes only and is not financial advice. Backtest results do not guarantee future performance. Gold is highly volatile: always run on a demo account first. You are solely responsible for your trading results.

---

## 📊 Backtest results (v1.30 defaults, XM Global `GOLD`, fixed 0.01 lot)

| Period | Data | Deposit | Net profit | Profit factor | Max equity DD | Trades |
|---|---|---|---|---|---|---|
| 2018 – 2026 | 1-minute OHLC | $3,000 | +$2,332 | **1.56** | **9.8%** | 538 |
| Oct 2024 – Oct 2026 | **real ticks (99%)** | $3,000 | +$1,962 | **1.65** | **10.8%** | 268 |
| Oct 2024 – Oct 2026 | real ticks | $1,000 | +$1,598 | 1.55 | 24.4% | 260 |

Net profit by year (2018–2026, $3,000): 2018: no trades · 2019: +48 · 2020: +162 · 2021: −46 · 2022: +86 · 2023: +27 · 2024: +51 · 2025: +446 · 2026: +1,559

**How it was validated**
- Parameters were chosen on **2020–2023 only**, then checked on periods the optimizer never saw: **2024–2026** (forward) and **2018–2019**.
- Neighbouring settings (stop 3–6 × ATR, exit 18:00–22:00) are also profitable, so the result is not a single lucky parameter set.
- Confirmed on real tick data, including spreads.

**Honest caveats**
- Most of the profit comes from 2025–2026, when gold was unusually volatile. In quiet years the EA mostly sits out (by design) and earns little.
- Fixed 0.01 lot means risk per trade grows with gold's volatility; the largest single loss in 2026 was about $230.
- The news filter cannot run in the Strategy Tester, so it was not part of these results.

## 💰 Capital requirements

With a standard account (0.01 lot = 1 oz of gold), one stop-loss typically costs **$15–$100+**.

| Balance | Behaviour |
|---|---|
| **$3,000+** | Recommended — drawdown ~10% in tests |
| $1,000 | Works, but drawdown ~25% |
| $100 | The risk guard **refuses every trade** (one loss would exceed 5% of the account). Use a **cent/micro account** instead |

## ✨ Strategy (default)

1. **Range:** record the high/low of the Asian session, 00:00–08:00 server time.
2. **Volatility filter:** trade only on days when daily ATR(14) ≥ 1.6% of price; breakouts fail in quiet markets.
3. **Entry:** the first M15 candle that closes above the range high (buy) or below the range low (sell). Maximum one trade per day.
4. **Stop:** 4 × ATR(14, M15). No take-profit, breakeven or trailing stop: winners run.
5. **Exit:** all positions are closed at **20:00 server time**, so no overnight swap. XM's gold swap was the main reason holding strategies failed in testing.
6. **Position size:** fixed lot (default 0.01) or **risk-based**: Lot = Balance × Risk% ÷ SL points (`InpLotMode`, `InpRiskPct`). In tests at $3,000, 1% risk gave PF 1.66 / DD 10.8% and 2% risk PF 1.55 / DD 17.9% (real ticks, Oct 2024 – Oct 2026).
7. **Risk guard:** skip any trade whose stop would lose more than 5% of balance.

Other selectable strategies (`InpStrategy`): EMA pullback (v1.x, not profitable in tests), Donchian breakout, RSI(2) pullback.

## 🖥️ Other features

| | |
|---|---|
| 🚦 **Filters** | Trading hours · max spread · trades per day · daily loss limit · Friday close · daily close |
| 📰 **News filter** | MT5 economic calendar — pauses entries around high-impact USD events (live trading only) |
| 🖥️ **Control panel** | Live status (incl. "low volatility"), position P/L, today's stats, spread/ATR, next news · **Pause** / **Close all** buttons |
| 📱 **Notifications** | MT5 mobile push on open/close, news windows, daily-loss stop, skipped trades (max once a day) |

## 🚀 Installation

**Windows (one click):** run `install_to_MT5.bat`. It compiles the EA, shows the target folder and — after you confirm with **Y** — copies it to `MQL5\Experts\MyEA` and the preset to `MQL5\Presets`.

**Manual:** copy `GoldScalperM15.mq5` into `MQL5\Experts` (*File → Open Data Folder*), open it in MetaEditor and press **F7**.

Attach the EA to a **GOLD/XAUUSD** chart, enable **Allow Algo Trading**. The defaults are the validated settings (`presets/GoldScalperM15_v130_Default.set` is the same).

> Times are **broker server time**. The defaults were validated on XM Global (GMT+2/+3). Other brokers may need the hours adjusted.

📖 Full guide: [USER_GUIDE.md](USER_GUIDE.md) · Thai: [คู่มือ_GoldScalperM15.md](คู่มือ_GoldScalperM15.md)

## 🧪 Reproducing the backtests

`tools/backtest.ps1` drives the MT5 Strategy Tester from PowerShell (compile, single backtests, grid/genetic optimization with a forward period, report parsing):

```powershell
. .\tools\backtest.ps1
Build-Dev
Invoke-Backtest -Name check -From 2024.10.13 -To 2026.10.12 -Model 4 -Deposit 3000
```

Paths at the top of the script point to the author's MT5 installation; adjust them for yours.

## 📁 Repository contents

```
GoldScalperM15.mq5          EA source code (MQL5)
install_to_MT5.bat          One-click compile + install helper (Windows)
presets/                    Validated default preset
tools/backtest.ps1          Backtest / optimization automation
USER_GUIDE.md               User guide (English)
คู่มือ_GoldScalperM15.md      User guide (Thai)
```

## 🗺️ Roadmap

- [ ] Telegram notifications & remote control
- [ ] Trade journal export (CSV)
- [ ] English / Thai language switch for the panel and alerts
