# Changelog

All notable changes to GoldScalperM15. Backtests use XM Global `GOLD` unless noted. "1-min" = 1-minute OHLC model, "real ticks" = every tick based on real ticks.

## v1.43 — News filter in the Strategy Tester, chart Console button, headlines
- **News filter in backtests:** the MT5 calendar is not available in the Strategy Tester, so backtests used to include trades taken around news.
  - The live EA now exports the USD calendar history (moderate + high impact, Dec 2017 to 3 weeks ahead) to `Common\Files\GS15_news_USD.csv`: once at start and then daily, when the file is older than a day. The `NEWSEXPORT` console command forces it.
  - Times are stored in **GMT**. `CalendarValueHistory` reports every past event with *today's* server offset, which puts winter events one hour late; the export removes that offset and the tester adds the right one back per event with the US daylight-saving rule (`InpNewsServerUSDST`; XM is GMT+2 in winter, GMT+3 in summer). Checked: NFP 9 Jan 2026 and CPI 14 Oct 2026 at 15:30 server time, FOMC 10 Dec 2025 at 21:00.
  - In the tester the EA reads the file (`InpNewsFile`, default `GS15_news_USD.csv`) and applies the same before/after windows as live. `InpNewsInTester = false` turns it off, e.g. to compare with older results.
  - `tools/ExportNews.mq5` exports the history by hand.
- **Console button on the chart** (top right): **▶ Open console** / **■ Close console**. MT5 does not let an EA start programs without DLL imports, so the EA only writes a request file and a small hidden helper, `tools/GS15_ConsoleLauncher.ps1`, opens or closes the window.
  - `tools/Install-ConsoleLauncher.ps1` installs the helper in the Windows Startup folder and starts it; `-Remove` uninstalls it.
  - The helper writes a heartbeat; without it the button says **Console (set up)** and a click explains what to do. A second helper replaces one that has stopped responding.
  - The console announces its process id, so the button closes the right window at once. `InpConsoleButton = false` hides the button.
- **Headlines in the console:** recent headlines from BBC (world, business), CNBC (world, markets) and InfoQuest RSS, fetched in the background every 10 minutes. Information only: the EA never trades on them. `H` hides / shows them.
- **Portable MT5:** `install_to_MT5.bat` installs into a portable MT5 in `D:\MT5_GoldScalper` when there is one (`PORTABLE=` line), and `tools/backtest.ps1` runs it with `/portable`. A note in the guide explains why MT5 and the console must be started from your own Windows session.

## v1.42 — Test button, console redesign, review fixes
- **Test** button on the panel and `T` in the console: opens a real BUY of the minimum lot with an SL, holds it `InpQuickTestHoldMs` (100 ms), closes it, and reports how long the open, hold and close took and what it cost (the spread). Proves that orders really go through and nothing is stuck.
- The test trade uses its own magic number (`InpMagic` + 1), so it never counts as a trade of the day, a loss, a cooldown or a losing streak. It is refused while the EA has an open trade or Algo Trading is off. A test trade left by an MT5 restart is closed automatically.
- Demo accounts only, unless `InpQuickTestReal = true`.
- **Console redesign:**
  - A compact control panel in a dark / blue / navy theme, following Gravity UI design principles: semantic status colours, primary / normal / danger button views, a visible selected mode, 4-8-12-16-24 spacing. All colours are in one theme table at the top of `tools/GS15_Console.ps1`.
  - Sections: header with a DEMO / LIVE badge, status, today, mode & risk, market & news, controls, and the event journal.
  - The status is shown with a colour and a label: RUNNING, WAITING, NEWS WINDOW, IN TRADE, PAUSED, DAILY LIMIT, HALTED or ERROR.
  - Target risk and actual risk are shown separately.
  - The upcoming news event shows the time left.
- **Safer console commands:**
  - One command at a time: the buttons are disabled until the EA replies.
  - The result shown is the EA's own reply.
  - A command the EA does not pick up within 10 s is cancelled and reported.
- **`A` = account check:** new `ACCOUNT` command; the full result opens in the console.
- **Shortcuts:** `tools/Make-ConsoleShortcut.ps1` creates "GoldScalper Console" shortcuts on the Desktop and in the Start menu, opening a window sized for the whole panel.
- **The chart panel is optional:** `InpShowPanel = false` hides it; everything can be done from the console.
- **Fixes from a code review** (`docs/CODE_REVIEW.md`):
  - Risk-% sizing skips the trade when the tick value is not known yet (right after connecting). It no longer falls back to a fixed lot without risk checks.
  - A requote or price change gets one retry at the new price, with the same lot and stop distance. Before, the day's breakout was lost.
  - Deposits and withdrawals move the equity peak, so a withdrawal does not trigger the drawdown halt.
  - The daily loss limit uses the realized start-of-day balance.
- Evidence: the v1.41 baseline report and trade journal are in `reports/experiments/baseline_v141/`.
  - Across all 473 trades of 2018–2026, the real risk per trade never exceeded the 1% target (mean 0.79%).
  - `tools/analyze_journal.py` reproduces the analysis.

## v1.41 — Risk guards: drawdown halt, losing-streak halt, lot cap
- **Drawdown halt** (`InpMaxDDPct`, 20%): when equity falls this far below its peak, the EA pauses itself and sends an alert. Open trades keep their SL and the daily close.
- **Losing-streak halt** (`InpMaxLossStreak`, 5): the same after this many losing trades in a row.
- After a halt the EA waits for a person: review, then press **Resume** on the panel or `P` in the console. Resuming starts the peak and the streak afresh. The panel and console show `Halted: ...` with the reason. The peak, streak and halt survive an MT5 restart.
- **Lot cap:** position value ≤ `InpMaxExposure` × equity (10; typical trades are 1–3 ×), plus an optional fixed `InpMaxLot`. A bad ATR or an unusually close stop can no longer produce an oversized lot. The lot is reduced with a warning, or the trade is skipped if the cap is below the minimum lot. Based on the tick value, so it works the same on Standard, Micro and Cent accounts.
- In the tester nobody can press Resume, so halts are counted and the test carries on. 2018–2026, $3,000, mode 1: results identical to v1.40 (+$2,670.83, PF 1.45, DD 14.8%, 473 trades); the lot cap never triggered, the drawdown halt never fired, and the losing-streak halt would have fired 9 times.

## v1.40 — PowerShell console
- **`GS15_Console.bat`** opens a PowerShell window with:
  - the EA's live status: account, equity, mode, status, open trade, today's trades and P/L, spread/ATR, next news;
  - a colour event log, newest first. Opened (cyan), won (green), lost with the reason (red), skipped with the money at risk (yellow), news, warnings and the day's range.
- Keys: `1` / `2` switch mode (both explained first), `P` pause / resume, `C` close all (type CLOSE), `L` full log, `Q` quit.
- How it works: the EA writes `GS15_<symbol>_<magic>_status.txt` every second and appends to `..._log.txt` (MT5 common Files folder). It reads one command from `..._cmd.txt`. There are no DLL imports. `InpConsole = false` turns it off. Live and demo only, not in the tester.
- The installer (`install_to_MT5.bat`) is now in English. Shorter panel button label so it fits.

## v1.39 — Strict risk control, safety checks, English by default
- **Strict risk** (`InpStrictRisk`, on by default): the real risk of a trade must not exceed the current mode's % (1% in mode 1, 0.5% in mode 2).
  - Real risk = SL distance from the actual entry price + slippage allowance (`InpSlippagePts`) + commission (`InpCommissionLot`), measured against **equity**.
  - Lots are sized from equity the same way and rounded down.
  - If even the minimum lot would exceed the target, the trade is **skipped, never forced**. The phone alert gives the money at risk and the equity needed.
- **Daily loss budget:** a trade is skipped if its stop would push today's loss past `InpMaxDailyLossPct`. When the limit is reached, new trades stop; open trades keep their SL.
- **Verified closes:** daily, Friday, news and button closes confirm that the position is gone, retry up to 3 times, keep retrying every tick and alert on failure.
- **No duplicate orders:** a terminal-wide lock stops two charts (same symbol + magic) from sending orders together. Positions are re-checked before sending.
- **Restart-safe:** the loss cooldown survives an MT5 restart, like the pause and the trade mode already did.
- **Stale positions:** when the EA starts, any position left from while it was not running is reported and closed by the daily-close rule.
- **English by default** for the panel, phone alerts, windows, inputs and logs. `InpLanguage = Thai` switches to Thai.
- Regression: with the new checks off, results are identical to v1.38. Effect of the new defaults (2018–2026, mode 1):

  | Balance | Before (v1.38) | v1.39 |
  |---|---|---|
  | $3,000 | +105%, PF 1.46, DD 16.3%, 504 trades | **+89%, PF 1.45, DD 14.8%**, 473 trades |
  | $1,000 | trades at ~3% risk | +18%, PF 1.29, DD 12.6%, 151 trades (most skipped) |
  | $10,000 | — | +112%, PF 1.44, DD 16.2%, 503 trades |

  Real ticks Oct 2024 – Oct 2026, $3,000: +39%, PF 1.62, DD 10.1%.
- The daily budget skipped one trade in 2018–2026. On 30 Jan 2026 a single stop would have cost more than the whole 3% daily limit.
- Credits: the project is published under the name **Kla1524**.

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
