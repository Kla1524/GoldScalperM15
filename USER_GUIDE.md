# GoldScalperM15 v1.38 — User Guide

XAUUSD (Gold) intraday EA for MetaTrader 5 (M15). Default strategy: **Asian-range breakout on volatile days**, wide ATR stop, all positions closed at 20:00 server time. Includes a per-trade risk guard, news filter, on-chart control panel and mobile push notifications.

> ⚠️ Backtests (2018–2026, PF 1.56, max DD ~10% on $3,000) do not guarantee future results. Always run on a demo account first.

## Capital and account type (from $10)

The default lot size is **1% risk per trade**, so the EA adapts to any balance. Pick the account type by balance:

| Balance | Account |
|---|---|
| $10 – $999 | **Micro** or **Cent** (lots 100× smaller than Standard) |
| $1,000+ | Standard, Micro or Cent |

On a Standard account one stop-loss at the minimum lot costs $15–$100+, so below ~$1,000 the risk guard (`InpMaxRiskPct`, 5%) skips trades. The **account check** at start-up (Experts tab, or a popup from the panel button) detects Standard / Micro / Cent and shows what you need.

**Opening a Micro demo at XM:** on the XM website choose *Open Demo Account* → account type **Micro**, then log in to it in MT5 (you do this yourself). Check in Market Watch that GOLD is available and its contract size is 1. Cent accounts at other brokers show the balance in **USC**; the popup converts it to USD.

**Presets:** `GoldScalperM15_Default.set` (1% risk) and `GoldScalperM15_Safe_0.5pct.set` (0.5% risk, about half the drawdown) and `GoldScalperM15_Unlimited_0.5pct.set` (starts in mode 2: several trades at 0.5% risk) — or just use the mode buttons on the panel.

| Micro / Cent balance | = Standard balance | Lot sizing | Net 2018–2026 | PF | Max DD |
|---|---|---|---|---|---|
| $10 | $1,000 | min lot (≈1–3% risk) | +203% | 1.52 | 18.0% |
| $20 | $2,000 | 1% risk | +120% | 1.47 | 14.8% |
| $50 | $5,000 | 1% risk | +108% | 1.43 | 16.1% |
| $100 | $10,000 | 1% risk | +116% | 1.43 | 16.5% |
| $100 | $10,000 | **0.5% risk (Safe preset)** | +41% | 1.40 | **8.2%** |
| $1,000 | $100,000 | 1% risk | +134% | 1.45 | 17.1% |

A Micro account is a Standard account scaled down 100× (contract 1 oz instead of 100 oz), and a Cent account counts the balance in US cents, so $10 on Micro/Cent behaves like $1,000 on Standard. That is how these 8.8-year tests were run (1-minute OHLC, XM GOLD). A direct real-tick test of $10 on a Micro contract (Aug–Oct 2026) gave +$1.79, PF 1.41, DD 12.2%.

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
4. **Inputs** tab → the defaults are the validated settings (optionally **Load** `GoldScalperM15_Default.set`) → OK.
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
- **Mode 1: 1 trade/day / Mode 2: multi** — opens a window describing both modes (tested results, who each suits, the lot each would trade today), then asks to confirm the switch. The green button is the active mode; the choice is remembered across MT5 restarts.
  - **Mode 1** one bigger trade a day (`InpRiskPct`, 1%): 2018–2026 +105%, PF 1.46, DD 16.3%
  - **Mode 2** several smaller trades, no daily limit (`InpMultiRiskPct`, 0.5%): +74%, PF 1.46, DD 10.5%

> The panel text is in Thai; the account-check and trade-mode windows follow `InpLanguage` (Thai / English).

**System test on demo** — set `InpTestMode = true` (demo accounts only; refused on a real account). The EA opens `InpTestTrades` real trades (default 3) one at a time, alternating BUY/SELL, holds each for `InpTestHoldMin` minutes and closes it, ignoring signals and trading hours. Use it to check order sending, SL, phone alerts, loss diagnosis, the loss cooldown and the journal. Set it back to false afterwards.

## 4. Strategy and key settings

| Setting | Default | Meaning |
|---|---|---|
| `InpStrategy` | ORB | Asian-range breakout (other modes are kept for research) |
| `InpRangeStartHour` / `InpRangeEndHour` | 0 / 8 | Range window, server time |
| `InpMinDailyATRPct` | 1.6 | Trade only when daily ATR ≥ 1.6% of price |
| `InpSL_ATR` | 4.0 | Stop-loss = 4 × M15 ATR; no TP / breakeven / trailing |
| `InpMaxTradesPerDay` | 1 | Trades per day (0 = unlimited: every breakout that meets the rules, still with the 20-min loss cooldown). Tested 2018–2026 at 1% risk: 1 trade PF 1.46 / DD 16.3%, unlimited PF 1.36 / DD 19.6%; unlimited at 0.5% risk: PF 1.46 / DD 10.5%. Second trades come after a failed breakout in a choppy day and lose more often, so use a smaller risk % with unlimited. |
| `InpDailyCloseHour` | 20 | Close everything at 20:00 (avoids swap) |
| `InpLotMode` | Risk % | **Fixed lot** (`InpLots`) or **Risk %**: Lot = Balance × `InpRiskPct` ÷ SL points (XM GOLD: 1 point = $1 per lot), rounded down to 0.01 |
| `InpRiskPct` | 1.0 | Risk per trade when Risk % mode is on (must not exceed `InpMaxRiskPct`) |
| `InpMaxRiskPct` | 5.0 | Skip a trade if its stop would lose > 5% of balance |
| `InpMaxSpread` | 1.00 | Maximum spread in price units |
| `InpMinConfidence` | 1 | Confidence score 0–4 required to enter: +1 each for D1 trend (EMA50), H1 trend (EMA200), ADX H1 20–30, RSI(14) ≥ 70 in trade direction. 0 = off |
| `InpLossCooldownMin` | 20 | Pause new entries for N minutes after a losing trade |
| `InpJournal` | true | Log every trade with entry conditions and loss reasons to `MQL5\..\Common\Files\GS15_journal_GOLD_20261013.csv` (opens in Excel) |
### Account check popup

When the EA starts (live/demo only), and whenever you press **Account check / advice** on the panel, a window analyses your account. It shows:
- balance, leverage, contract size, minimum lot and margin;
- what one stop-loss would cost right now (from today's ATR) at the minimum lot and with your current lot setting.

It then gives a verdict and lets you choose what to do:

| Verdict | Choices |
|---|---|
| Balance too small (EA would skip every trade) | Keep running · Pause · Remove the EA. Shows the balance needed, or the Micro/Cent alternative |
| High risk (> 2% per trade) | Switch to 1% risk lots · Keep settings · Pause |
| Reasonable risk | Optionally switch to 1% risk lots (grows with the account) |

`InpLanguage` selects **ไทย / English** for the popup; `InpAccountCheck` turns the start-up check on or off. At start-up the check is printed to the **Experts** tab and needs no answer, so the EA keeps running when nobody is at the PC; set `InpAccountPopup = true` to get the popup instead (the EA waits until you answer). The panel button always opens the popup with choices. A switch to 1% risk lots made in the popup lasts for the session only — set `InpLotMode` in Inputs to make it permanent.

### Loss diagnosis

After every losing trade the phone alert and the journal state *why* it lost (several reasons can apply):

| Code | Meaning |
|---|---|
| FALSE_BREAK | Price closed back inside the range — a failed breakout (≈95% of losses in backtests) |
| GAVE_BACK | Trade was ≥ 1 ATR in profit, then reversed |
| AGAINST_D1 / AGAINST_H1 | Entry against the daily / hourly trend |
| LOW_ADX | No trend on H1 (ADX < 20) |
| WEAK_CANDLE | Breakout candle with a small body / long wick |
| CHASED | Entry far beyond the range (> 1 ATR) |
| RSI_EXTREME | RSI already overbought/oversold at entry |
| NO_FOLLOW | No follow-through; closed at 20:00 with a loss |
| LATE_ENTRY | Entry at 15:00 or later (US session / news) |
| NORMAL | Nothing unusual — a statistically normal loss |

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
