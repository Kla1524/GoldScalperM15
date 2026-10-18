# GoldScalperM15 v1.53 — User Guide

XAUUSD (Gold) intraday EA for MetaTrader 5 (M15). One strategy: **Asian-range breakout on volatile days, one trade a day**, wide ATR stop, all positions closed at 20:00 server time. Includes strict 0.5% risk sizing, risk guards, a news filter, an on-chart control panel, a PowerShell console and mobile push notifications (daily summary, start/stop notices).

> ⚠️ **For education and research only.** Not investment advice and not an invitation or solicitation to invest. Trading leveraged products carries a high risk of loss; backtests do not guarantee future results. Always test on a demo account first. You are solely responsible for your trading.
>
> **License:** [MIT](LICENSE) — free to use, modify and share, keeping the credit to **Kla1524**.

## Capital and account type

Lot size is **0.5% of equity per trade** (`InpRiskPct`), counting the SL, a slippage allowance and commission. With the default **strict risk** rule (`InpStrictRisk`), a trade is skipped, with the reason, when even the minimum lot would exceed that %. Pick the account type by balance:

| Balance | Account |
|---|---|
| under ~$6,000 | **Micro** or **Cent** (lots 100× smaller than Standard), from ~$60 |
| ~$6,000+ | Standard, Micro or Cent |

On a Standard account one stop-loss at the minimum lot costs $15–$100+, so below ~$6,000 most signals are skipped by the strict 0.5% rule. The **account check** at start-up (Experts tab, or a popup from the panel button) detects Standard / Micro / Cent and shows what you need. (Its recommendation text still quotes the balance for 1% risk; at 0.5% you need about twice that.)

**Opening a Micro demo at XM:** on the XM website choose *Open Demo Account* → account type **Micro**, then log in to it in MT5 (you do this yourself). Check in Market Watch that GOLD is available and its contract size is 1. Cent accounts at other brokers show the balance in **USC**; the popup converts it to USD.

**Preset:** `GoldScalperM15_Default.set` — the same as the EA defaults (0.5% risk, one trade a day, news ±15 min).

**Backtest results (defaults, $10,000, news filter on):** 2018–2023 +$1,022, PF 1.23, DD 8.4% (209 trades) · 2024–Oct 2026 +$2,223, PF 1.54, DD 4.0% (262) · real ticks Oct 2024–Oct 2026 +$1,638, PF 1.50, DD 3.7% (227).

## Files

| File | Purpose |
|---|---|
| `GoldScalperM15.mq5` | Source code (edit in MetaEditor) |
| `install_to_MT5.bat` | Double-click to compile and install/update the EA in MT5 |
| `presets\*.set` | Validated default preset (same as the EA defaults) |
| `GS15_Console.bat` | Opens the PowerShell console |
| `tools\Install-ConsoleLauncher.ps1` | Run once: lets the **Console** button on the chart open / close the console |
| `tools\GS15_Watchdog.ps1` | Optional PC watchdog: a Windows notification when MT5 or the EA stops during market hours |
| `compile.log` | Created during installation — compiler output, safe to delete |

## 1. Install / update the EA

1. Double-click **`install_to_MT5.bat`**.
2. It shows where it will install → press **Y** to confirm (**N** cancels without touching MT5).
3. It then compiles the EA → copies it to `MQL5\Experts\MyEA` → copies the `.set` files to `MQL5\Presets`.

Run it again whenever you change `GoldScalperM15.mq5`.

The installer uses a **portable MT5 in `D:\MT5_GoldScalper`** when there is one (started with `terminal64.exe /portable`; program and data in one folder), otherwise the MT5 in `C:\Program Files\MetaTrader 5`. Edit the `PORTABLE=` line if yours is elsewhere.

## 2. Attach the EA to a chart

1. Open an **XAUUSD** chart (the name may differ by broker, e.g. `XAUUSDm`, `GOLD`). Any chart timeframe works — the EA always uses M15 for signals.
2. Press **Ctrl+N** → Expert Advisors → MyEA → drag **GoldScalperM15** onto the chart. Use **one** chart only: since v1.51 a second copy on the same symbol refuses to start.
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
| 🔵 Holding position | A trade is open; the EA keeps its SL and closes it at 20:00 |
| 🟠 Paused | You pressed the pause button |
| 🔴 Halted: drawdown limit / losing streak / losing days | A risk guard paused the EA. Review the recent trades, then press **Resume** (panel or console key `P`). Resuming starts the peak and the streak count afresh |
| 🟠 News window | Inside the window before/after a high-impact event |
| 🟠 Daily loss limit reached | Today's loss hit the configured % — wait for tomorrow |
| 🟠 Max trades reached | Daily trade limit reached |
| 🟠 Outside trading hours | Outside the configured session |
| 🟠 Spread too wide | Spread is above the configured maximum |
| 🟠 Low volatility | Daily ATR is below `InpMinDailyATRPct` — the EA waits for a volatile day (normal in quiet markets) |

**Buttons**
- **Pause / Resume** — stops opening new trades (open trades are still managed). The setting is remembered across MT5 restarts.
- **Test** — system test: opens a real BUY of the minimum lot (with an SL), closes it after 0.1 s (`InpQuickTestHoldMs` = 100) and reports the open/close time and cost. It does not count as a trade of the day. Demo only unless `InpQuickTestReal = true`. Console key: `T`.
- **Close all** — closes only this EA's positions, after a confirmation dialog. Your manual trades are not affected.
> The panel, phone alerts and windows are in English by default; set `InpLanguage = Thai` for Thai.

**System test on demo** — set `InpTestMode = true` (demo accounts only; refused on a real account). The EA opens `InpTestTrades` real trades (default 3) one at a time, alternating BUY/SELL, holds each for `InpTestHoldMin` minutes and closes it, ignoring signals and trading hours. Use it to check order sending, SL, phone alerts, loss diagnosis, the loss cooldown and the journal. Set it back to false afterwards.

**PowerShell console** — open the "GoldScalper Console" shortcut on the Desktop or in the Start menu (create it once with `tools\Make-ConsoleShortcut.ps1`), or double-click `GS15_Console.bat` in the project folder. `A` runs the account check and shows the result. Commands are sent one at a time; the line under the buttons shows the EA's reply. It shows the EA's live status and a colour event log, newest first: opened, won, lost (with the reason), skipped (with the money at risk), news and warnings. Keys: `P` pause / resume, `A` account check, `T` test order, `C` close all (type CLOSE to confirm), `L` longer journal, `O` full log in Notepad, `Q` quit. Commands reach the EA within about a second. The EA works the same with the console closed. Files live in MT5's common `Files` folder (`GS15_<symbol>_<magic>_status/log/cmd.txt`); `InpConsole = false` turns this off.

**Console button on the chart** — top right of the chart: **▶ Open console** opens the console window, **■ Close console** closes it. MT5 does not let an EA start programs without DLL imports, so a small background helper does it: run `powershell -ExecutionPolicy Bypass -File tools\Install-ConsoleLauncher.ps1` once. It adds a hidden "GoldScalper Console Launcher" to the Windows Startup folder and starts it; the EA only writes a request file. If the helper is not running the button says **Console (set up)** and explains what to do. `-Remove` uninstalls it; `InpConsoleButton = false` hides the button. Start MT5 and the helper from your own Windows session (Start menu, Desktop shortcut, Startup folder): programs started from inside a sandboxed app can get a separate copy of `%APPDATA%`, and then the console cannot see the EA.

**Headlines** — under the event journal the console shows recent headlines from BBC, CNBC and InfoQuest RSS feeds, refreshed every 10 minutes in the background. They are for information only; the EA does not trade on them. `H` hides / shows them; the feed list is at the top of `tools\GS15_Console.ps1`.

## 4. Strategy and key settings

| Setting | Default | Meaning |
|---|---|---|
| `InpRangeStartHour` / `InpRangeEndHour` | 0 / 8 | Range window, server time |
| `InpMinDailyATRPct` | 1.6 | Trade only when daily ATR ≥ 1.6% of price |
| `InpSL_ATR` | 4.0 | Stop-loss = 4 × M15 ATR; no TP / breakeven / trailing |
| `InpMaxTradesPerDay` | 1 | One trade a day: the first breakout. Tested 2018–2026: more trades a day came after failed breakouts and lost more often |
| `InpStopEntry` | false | true = BUY STOP / SELL STOP orders at the range edges instead of waiting for an M15 close (the other side is cancelled on a fill). Tested better in 2024–2026 but with about twice the drawdown; off by default |
| `InpDailyCloseHour` | 20 | Close everything at 20:00 (avoids swap) |
| `InpSessionGuard` | true | Also close before gold stops trading: 10 min before the session end (`InpCloseBufferMin`), 22:50 in the weeks US and EU summer time differ, 18:00 on US holidays with an early close (`InpHolidayCloseHour`). Each close is logged (CLOSEAUDIT / CLOSEDONE in the Experts tab) |
| `InpLotMode` | Risk % | **Fixed lot** (`InpLots`) or **Risk %**: Lot = Balance × `InpRiskPct` ÷ SL points (XM GOLD: 1 point = $1 per lot), rounded down to 0.01 |
| `InpRiskPct` | 0.5 | Risk per trade when Risk % mode is on (must not exceed `InpMaxRiskPct`) |
| `InpStrictRisk` | true | Skip a trade if its real risk (SL + slippage + commission, vs equity) exceeds `InpRiskPct`; the skip is reported with the money at risk |
| `InpSlippagePts` | 30 | Slippage allowance at the SL (points), included in the real risk |
| `InpCommissionLot` | 0 | Round-turn commission per lot (0 on XM Standard) |
| `InpMaxRiskPct` | 5.0 | Hard cap: skip a trade if its stop would lose > 5% of equity |
| `InpMaxDDPct` | 20 | Halt (pause, phone alert) when equity falls 20% below its peak. 0 = off. Never reached in 2018–2026 (max DD 14.8%) |
| `InpMaxLossStreak` | 5 | Halt after 5 losing trades in a row. 0 = off. Would have fired 9 times in 2018–2026 (about once a year) |
| `InpMaxLosingDays` | 0 | Halt after N losing days in a row (days without trades do not count). 0 = off. Tested with a resume after 7 days: N = 2 halved the profit, N = 3 was better in 2018–2023 but worse in 2024–2026 |
| `InpNewsMinsBefore` / `InpNewsMinsAfter` | 15 / 15 | News window around high-impact USD events (minutes) |
| `InpMaxExposure` | 10 | Lot cap: position value ≤ 10 × equity (typical trades are 1–3 ×), against a bad ATR or a tiny stop. 0 = off |
| `InpMaxLot` | 0 | Optional fixed maximum lot per trade. 0 = off |
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

`InpLanguage` selects **English / Thai** for the panel, alerts and windows (English by default); `InpAccountCheck` turns the start-up check on or off. At start-up the check is printed to the **Experts** tab and needs no answer, so the EA keeps running when nobody is at the PC; set `InpAccountPopup = true` to get the popup instead (the EA waits until you answer). The panel button always opens the popup with choices. A switch to 1% risk lots made in the popup lasts for the session only — set `InpLotMode` in Inputs to make it permanent.

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
- a news window starts or ends
- the daily loss limit is reached or a risk guard halts the EA
- positions are closed before the Friday market close
- **daily summary** (v1.51, `InpDailySummary`): a few minutes after the daily close — trades, P/L, balance, drawdown, losses in a row, losing days in a row and the state
- **start / stop** (v1.51, `InpNotifyStartStop`): when the EA starts, with how long it was not running (worked out from the age of its status file, so it also covers a PC that was switched off or lost power); when MT5 closes or the EA is removed

Individual notification types can be turned off in the **Notifications** input group. A PC that is off cannot send anything; you learn about it from the start notice when it is back.

### PC watchdog (optional)

`tools\GS15_Watchdog.ps1` checks every 2 minutes during market hours (Mon 04:05 – Sat 03:50 Thai time) that the trading MT5 runs and that the EA status file is fresh, and shows a Windows notification once per problem (and when it is back to normal). It never starts, stops or trades anything. Run it by hand, or add it to the Windows Startup folder if you want it every time you log in. `D:\MT5_GoldScalper\_watchdog\PAUSE` pauses it; the log is `_watchdog\watchdog_log.txt`.

## 6. Backtesting

1. Press **Ctrl+R** to open the Strategy Tester.
2. Expert: `MyEA\GoldScalperM15` | Symbol: XAUUSD | Timeframe: M15.
3. Modelling: **Every tick based on real ticks** | Period: at least one year.
4. Inputs tab → **Load** a preset → **Start**.
5. Review Profit Factor (aim for > 1.3), Maximum Drawdown and number of trades.

> **News filter in the tester (v1.43+):** the MT5 calendar is not available in the Strategy Tester, so the live EA exports the USD calendar history (moderate + high, from Dec 2017) once a day to `Common\Files\GS15_news_USD.csv`, in GMT. In the tester the EA reads that file and converts each event to server time with the US daylight-saving rule (XM: GMT+2 in winter, GMT+3 in summer), so backtests skip the same news windows as live trading. Run the EA on a live or demo chart once before backtesting (or send `NEWSEXPORT` from the console). `InpNewsInTester = false` turns this off, e.g. to compare with older results, which did not include the news filter.
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
| Chart button says "Console (set up)" | Run `tools\Install-ConsoleLauncher.ps1` once, or sign out and in again so the Startup helper starts |
| Console shows "WAITING FOR THE EA" while the EA runs | The console and MT5 see different `Files` folders: start both from your own Windows session (see the Console button section) |
