# GoldScalperM15 v1.31 — User Guide

XAUUSD (Gold) intraday EA for MetaTrader 5 (M15). Default strategy: **Asian-range breakout on volatile days**, wide ATR stop, all positions closed at 20:00 server time. Includes a per-trade risk guard, news filter, on-chart control panel and mobile push notifications.

> ⚠️ Backtests (2018–2026, PF 1.56, max DD ~10% on $3,000) do not guarantee future results. Always run on a demo account first.

## Capital

One stop-loss at 0.01 lot usually costs **$15–$100+**. Recommended balance: **$3,000+** ($1,000 works with ~25% drawdown). Below that the risk guard (`InpMaxRiskPct`, default 5%) skips trades — with $100 on a standard account it skips **all** of them. For small balances use a cent/micro account.

---

## Files

| File | Purpose |
|---|---|
| `GoldScalperM15.mq5` | Source code (edit in MetaEditor) |
| `install_to_MT5.bat` | Double-click to compile and install/update the EA in MT5 |
| `presets\*.set` | Validated default preset (same as the EA defaults) |
| `compile.log` | Created during installation — compiler output, safe to delete |

## 1. Install / update the EA

1. Double-click **`install_to_MT5.bat`**.
2. It shows where it will install → press **Y** to confirm (**N** cancels without touching MT5).
3. It then compiles the EA → copies it to `MQL5\Experts\MyEA` → copies the `.set` files to `MQL5\Presets`.

Run it again whenever you change `GoldScalperM15.mq5`.

## 2. Attach the EA to a chart

1. Open an **XAUUSD** chart (the name may differ by broker, e.g. `XAUUSDm`, `GOLD`). Any chart timeframe works — the EA always uses M15 for signals.
2. Press **Ctrl+N** → Expert Advisors → MyEA → drag **GoldScalperM15** onto the chart.
3. **Common** tab → tick **Allow Algo Trading**.
4. **Inputs** tab → the defaults are the validated settings (optionally **Load** `GoldScalperM15_v130_Default.set`) → OK.
5. Make sure the **Algo Trading** button in the top toolbar is green.

## 3. On-chart control panel

The panel (top-left of the chart) shows:

- **Status** — whether the EA can trade right now, or why not (see table below)
- **Position** — the EA's open trade and its floating P/L
- **Today** — trades taken vs. daily limit, and today's P/L
- **Spread / ATR** — current spread vs. the limit, and current M15 ATR
- **Next news** — the next filtered economic event within 24 hours

| Status | Meaning |
|---|---|
| 🟢 Ready - waiting for signal | All filters pass; waiting for a qualifying M15 candle |
| 🔵 Holding position | A trade is open; the EA is managing SL/TP/trailing |
| 🟠 Paused | You pressed the pause button |
| 🟠 News window | Inside the window before/after a high-impact event |
| 🟠 Daily loss limit reached | Today's loss hit the configured % — wait for tomorrow |
| 🟠 Max trades reached | Daily trade limit reached |
| 🟠 Outside trading hours | Outside the configured session |
| 🟠 Spread too wide | Spread is above the configured maximum |
| 🟠 Low volatility | Daily ATR is below `InpMinDailyATRPct` — the EA waits for a volatile day (normal in quiet markets) |

**Buttons**
- **Pause / Resume** — stops opening new trades (open trades are still managed). The setting is remembered across MT5 restarts.
- **Close all** — closes only this EA's positions, after a confirmation dialog. Your manual trades are not affected.

> The panel text in v1.20 is in Thai.

## 4. Strategy and key settings

| Setting | Default | Meaning |
|---|---|---|
| `InpStrategy` | ORB | Asian-range breakout (other modes are kept for research) |
| `InpRangeStartHour` / `InpRangeEndHour` | 0 / 8 | Range window, server time |
| `InpMinDailyATRPct` | 1.6 | Trade only when daily ATR ≥ 1.6% of price |
| `InpSL_ATR` | 4.0 | Stop-loss = 4 × M15 ATR; no TP / breakeven / trailing |
| `InpMaxTradesPerDay` | 1 | One breakout trade per day |
| `InpDailyCloseHour` | 20 | Close everything at 20:00 (avoids swap) |
| `InpLotMode` | Fixed lot | **Fixed lot** (`InpLots`) or **Risk %**: Lot = Balance × `InpRiskPct` ÷ SL points (XM GOLD: 1 point = $1 per lot), rounded down to 0.01 |
| `InpRiskPct` | 1.0 | Risk per trade when Risk % mode is on (must not exceed `InpMaxRiskPct`) |
| `InpMaxRiskPct` | 5.0 | Skip a trade if its stop would lose > 5% of balance |
| `InpMaxSpread` | 1.00 | Maximum spread in price units |

Times are **broker server time** and were validated on XM Global (GMT+2/+3).
## 5. Mobile push notifications

1. Install the **MetaTrader 5** app on your phone → **Settings** (or Messages) → note your **MetaQuotes ID** (8 characters).
2. In desktop MT5: **Tools → Options → Notifications**.
3. Tick **Enable Push Notifications** → enter the MetaQuotes ID → click **Test** (your phone should receive a test message) → OK.

**The EA notifies you when:**
- a trade opens (with SL/TP) or closes (TP hit, SL hit or manual close, with P/L)
- the stop is moved to breakeven
- a news window starts or ends
- the daily loss limit is reached
- positions are closed before the Friday market close

Individual notification types can be turned off in the **Notifications** input group. (Telegram support is planned.)

## 6. Backtesting

1. Press **Ctrl+R** to open the Strategy Tester.
2. Expert: `MyEA\GoldScalperM15` | Symbol: XAUUSD | Timeframe: M15.
3. Modelling: **Every tick based on real ticks** | Period: at least one year.
4. Inputs tab → **Load** a preset → **Start**.
5. Review Profit Factor (aim for > 1.3), Maximum Drawdown and number of trades.

> The news filter **does not work in the Strategy Tester** (an MT5 limitation), so results include trades taken around news.
> Tick **Visualization** if you want to see the control panel during the test.

## 7. Troubleshooting

| Problem | Fix |
|---|---|
| The EA never opens trades | Check the panel status / make sure the Algo Trading button is green / check the Experts tab (Ctrl+T) |
| Status is always "Spread too wide" | Some brokers have wide gold spreads → raise `InpMaxSpread` |
| "Outside trading hours" when you expect to trade | Hours are in **broker server time** (shown in Market Watch), not local time |
| No push notifications | Follow section 5 / look for "push failed" messages in the Experts tab |
| Next news always shows "none in 24h" | Open the **Calendar** tab in the Toolbox (Ctrl+T) so MT5 downloads events / check your internet connection |
| Installation fails | Open `compile.log` to see the error |
